/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  02_BRONZE/001_sp_stg_npi_registry.sql
  
  Purpose: Stages NPI registry data from raw source with data quality 
           validation and reject handling.
  
  Source:  SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NPI_RAW
  Target:  P360_SP.BRONZE.STG_NPI_REGISTRY
  Rejects: P360_SP.REJECT.REJECT_RECORDS
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA BRONZE;

CREATE OR REPLACE PROCEDURE BRONZE.SP_STG_NPI_REGISTRY(
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
    v_source_db VARCHAR;
    v_source_schema VARCHAR;
    v_total_count NUMBER DEFAULT 0;
    v_reject_count NUMBER DEFAULT 0;
    v_insert_count NUMBER DEFAULT 0;
    v_threshold_exceeded BOOLEAN DEFAULT FALSE;
    v_hwm TIMESTAMP_NTZ;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id :=  UUID_STRING();
    
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 1, 'STG_NPI_REGISTRY', 'BRONZE', 1);
    
    SELECT config_value INTO v_source_db FROM P360_SP.CONFIG.PKG_CONFIG WHERE config_key = 'SOURCE_DATABASE';
    SELECT config_value INTO v_source_schema FROM P360_SP.CONFIG.PKG_CONFIG WHERE config_key = 'SOURCE_SCHEMA';

    IF (:P_MODE = 'INCREMENTAL') THEN
        SELECT COALESCE(MAX(_source_loaded_at), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
        FROM P360_SP.BRONZE.STG_NPI_REGISTRY;
    ELSE
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
        TRUNCATE TABLE P360_SP.BRONZE.STG_NPI_REGISTRY;
    END IF;

    SELECT COUNT(*) INTO v_total_count
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NPI_RAW
    WHERE _loaded_at > :v_hwm;

    IF (v_total_count = 0) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', 0, 'rows_written', 0, 'rows_rejected', 0);
    END IF;

    INSERT INTO P360_SP.REJECT.REJECT_RECORDS (reject_id, run_id, step_name, source_table, reject_reasons, record_key, record_data, rejected_at)
    SELECT
        UUID_STRING(),
        :P_RUN_ID,
        'STG_NPI_REGISTRY',
        'NPI_RAW',
        ARRAY_COMPACT(ARRAY_CONSTRUCT(
            CASE WHEN npi_number IS NULL THEN 'NPI_NUMBER_NULL' END,
            CASE WHEN LENGTH(npi_number) != 10 THEN 'NPI_INVALID_LENGTH' END,
            CASE WHEN TRY_TO_NUMBER(npi_number) IS NULL AND npi_number IS NOT NULL THEN 'NPI_NON_NUMERIC' END,
            CASE WHEN provider_first_name IS NULL THEN 'FIRST_NAME_NULL' END,
            CASE WHEN provider_last_name_legal IS NULL THEN 'LAST_NAME_NULL' END,
            CASE WHEN status NOT IN ('A','D','R') AND status IS NOT NULL THEN 'INVALID_NPI_STATUS' END
        )),
        npi_number,
        OBJECT_CONSTRUCT('npi_number', npi_number, 'first_name', provider_first_name, 'last_name', provider_last_name_legal, 'status', status),
        CURRENT_TIMESTAMP()
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NPI_RAW
    WHERE _loaded_at > :v_hwm
      AND (
          npi_number IS NULL
          OR LENGTH(npi_number) != 10
          OR (TRY_TO_NUMBER(npi_number) IS NULL AND npi_number IS NOT NULL)
          OR provider_first_name IS NULL
          OR provider_last_name_legal IS NULL
          OR (status NOT IN ('A','D','R') AND status IS NOT NULL)
      );

    v_reject_count := SQLROWCOUNT;

    CALL P360_SP.CONFIG.SP_CHECK_DQ_THRESHOLD(:P_RUN_ID, :v_step_run_id, 'NPI_RAW', :v_total_count, :v_reject_count);
    v_threshold_exceeded := (SELECT $1::BOOLEAN FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    IF (v_threshold_exceeded) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, :v_reject_count, 0, 'DQ threshold exceeded', 'DQ_FAIL', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'reason', 'DQ_THRESHOLD_EXCEEDED', 'reject_pct', ROUND((:v_reject_count::FLOAT / :v_total_count) * 100, 2));
    END IF;

    INSERT INTO P360_SP.BRONZE.STG_NPI_REGISTRY (
        npi_number, first_name, last_name, credentials, gender_code,
        entity_type_code, is_sole_proprietor, enumeration_date, last_update_date,
        deactivation_date, reactivation_date, npi_status, _source_loaded_at, _run_id
    )
    SELECT
        npi_number::VARCHAR(10),
        provider_first_name::VARCHAR,
        provider_last_name_legal::VARCHAR,
        provider_credential_text::VARCHAR,
        provider_gender_code::VARCHAR(1),
        entity_type_code::VARCHAR(1),
        sole_proprietor::VARCHAR(1),
        enumeration_date::DATE,
        last_update_date::DATE,
        npi_deactivation_date::DATE,
        npi_reactivation_date::DATE,
        status::VARCHAR(1),
        _loaded_at::TIMESTAMP_NTZ,
        :P_RUN_ID
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NPI_RAW
    WHERE _loaded_at > :v_hwm
      AND NOT (
          npi_number IS NULL
          OR LENGTH(npi_number) != 10
          OR (TRY_TO_NUMBER(npi_number) IS NULL AND npi_number IS NOT NULL)
          OR provider_first_name IS NULL
          OR provider_last_name_legal IS NULL
          OR (status NOT IN ('A','D','R') AND status IS NOT NULL)
      );

    v_insert_count := SQLROWCOUNT;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_insert_count, :v_reject_count, 0, NULL, NULL, NULL);
    
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'rows_written', :v_insert_count, 'rows_rejected', :v_reject_count);

EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'STG_NPI_REGISTRY', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, :v_reject_count, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
