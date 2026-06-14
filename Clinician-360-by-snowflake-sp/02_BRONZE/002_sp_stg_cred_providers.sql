/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  02_BRONZE/002_sp_stg_cred_providers.sql
  
  Source:  SNOWFLAKE_LEARNING_DB.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
  Target:  P360_SP.BRONZE.STG_CRED_PROVIDERS
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA BRONZE;

CREATE OR REPLACE PROCEDURE BRONZE.SP_STG_CRED_PROVIDERS(
    P_RUN_ID    VARCHAR,
    P_MODE      VARCHAR DEFAULT 'INCREMENTAL'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_step_run_id VARCHAR;
    v_total_count NUMBER DEFAULT 0;
    v_reject_count NUMBER DEFAULT 0;
    v_insert_count NUMBER DEFAULT 0;
    v_threshold_exceeded BOOLEAN DEFAULT FALSE;
    v_hwm TIMESTAMP_NTZ;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 2, 'STG_CRED_PROVIDERS', 'BRONZE', 1);

    IF (:P_MODE = 'INCREMENTAL') THEN
        SELECT COALESCE(MAX(_source_loaded_at), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
        FROM P360_SP.BRONZE.STG_CRED_PROVIDERS;
    ELSE
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
        TRUNCATE TABLE P360_SP.BRONZE.STG_CRED_PROVIDERS;
    END IF;

    SELECT COUNT(*) INTO v_total_count
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
    WHERE _loaded_at > :v_hwm;

    IF (v_total_count = 0) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', 0, 'rows_written', 0, 'rows_rejected', 0);
    END IF;

    INSERT INTO P360_SP.REJECT.REJECT_RECORDS (reject_id, run_id, step_name, source_table, reject_reasons, record_key, record_data, rejected_at)
    SELECT
        UUID_STRING(), :P_RUN_ID, 'STG_CRED_PROVIDERS', 'PROVIDER_CREDENTIALS_RAW',
        ARRAY_COMPACT(ARRAY_CONSTRUCT(
            CASE WHEN npi_number IS NULL THEN 'NPI_NUMBER_NULL' END,
            CASE WHEN LENGTH(npi_number) != 10 THEN 'NPI_INVALID_LENGTH' END,
            CASE WHEN credential_status NOT IN ('ACTIVE','INACTIVE','EXPIRED','PENDING') AND credential_status IS NOT NULL THEN 'INVALID_CRED_STATUS' END
        )),
        npi_number,
        OBJECT_CONSTRUCT('npi_number', npi_number, 'provider_id', provider_id, 'credential_status', credential_status),
        CURRENT_TIMESTAMP()
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
    WHERE _loaded_at > :v_hwm
      AND (
          npi_number IS NULL
          OR LENGTH(npi_number) != 10
          OR (credential_status NOT IN ('ACTIVE','INACTIVE','EXPIRED','PENDING') AND credential_status IS NOT NULL)
      );

    v_reject_count := SQLROWCOUNT;
    CALL P360_SP.CONFIG.SP_CHECK_DQ_THRESHOLD(:P_RUN_ID, :v_step_run_id, 'PROVIDER_CREDENTIALS_RAW', :v_total_count, :v_reject_count);
    v_threshold_exceeded := (SELECT $1::BOOLEAN FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    IF (v_threshold_exceeded) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, :v_reject_count, 0, 'DQ threshold exceeded', 'DQ_FAIL', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'reason', 'DQ_THRESHOLD_EXCEEDED');
    END IF;

    INSERT INTO P360_SP.BRONZE.STG_CRED_PROVIDERS (
        credentialing_id, npi_number, specialty_code, specialty_description,
        board_certification, credential_status, credential_effective_date,
        credential_expiry_date, primary_taxonomy_code, _source_loaded_at, _run_id
    )
    SELECT
        provider_id::VARCHAR,
        npi_number::VARCHAR(10),
        specialty_code::VARCHAR,
        specialty_description::VARCHAR,
        board_certification::VARCHAR,
        credential_status::VARCHAR,
        credential_effective_date::DATE,
        credential_expiry_date::DATE,
        primary_taxonomy_code::VARCHAR,
        _loaded_at::TIMESTAMP_NTZ,
        :P_RUN_ID
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
    WHERE _loaded_at > :v_hwm
      AND NOT (
          npi_number IS NULL
          OR LENGTH(npi_number) != 10
          OR (credential_status NOT IN ('ACTIVE','INACTIVE','EXPIRED','PENDING') AND credential_status IS NOT NULL)
      );

    v_insert_count := SQLROWCOUNT;
    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_insert_count, :v_reject_count, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'rows_written', :v_insert_count, 'rows_rejected', :v_reject_count);

EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'STG_CRED_PROVIDERS', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, :v_reject_count, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
