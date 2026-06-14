/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  02_BRONZE/005_sp_stg_network_affiliations.sql
  
  Source:  SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
  Target:  P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA BRONZE;

CREATE OR REPLACE PROCEDURE BRONZE.SP_STG_NETWORK_AFFILIATIONS(
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
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 5, 'STG_NETWORK_AFFILIATIONS', 'BRONZE', 1);

    IF (:P_MODE = 'INCREMENTAL') THEN
        SELECT COALESCE(MAX(_source_loaded_at), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
        FROM P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS;
    ELSE
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
        TRUNCATE TABLE P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS;
    END IF;

    SELECT COUNT(*) INTO v_total_count
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
    WHERE _loaded_at > :v_hwm;

    IF (v_total_count = 0) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', 0, 'rows_written', 0, 'rows_rejected', 0);
    END IF;

    INSERT INTO P360_SP.REJECT.REJECT_RECORDS (reject_id, run_id, step_name, source_table, reject_reasons, record_key, record_data, rejected_at)
    SELECT
        UUID_STRING(), :P_RUN_ID, 'STG_NETWORK_AFFILIATIONS', 'NETWORK_AFFILIATIONS_RAW',
        ARRAY_COMPACT(ARRAY_CONSTRUCT(
            CASE WHEN npi_number IS NULL THEN 'NPI_NUMBER_NULL' END,
            CASE WHEN LENGTH(npi_number) != 10 THEN 'NPI_INVALID_LENGTH' END,
            CASE WHEN effective_date IS NULL THEN 'EFFECTIVE_DATE_NULL' END
        )),
        npi_number,
        OBJECT_CONSTRUCT('npi_number', npi_number, 'network_affiliation_id', network_affiliation_id, 'network_name', network_name),
        CURRENT_TIMESTAMP()
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
    WHERE _loaded_at > :v_hwm
      AND (
          npi_number IS NULL
          OR LENGTH(npi_number) != 10
          OR effective_date IS NULL
      );

    v_reject_count := SQLROWCOUNT;
    CALL P360_SP.CONFIG.SP_CHECK_DQ_THRESHOLD(:P_RUN_ID, :v_step_run_id, 'NETWORK_AFFILIATIONS_RAW', :v_total_count, :v_reject_count);
    v_threshold_exceeded := (SELECT $1::BOOLEAN FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    IF (v_threshold_exceeded) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, :v_reject_count, 0, 'DQ threshold exceeded', 'DQ_FAIL', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'reason', 'DQ_THRESHOLD_EXCEEDED');
    END IF;

    INSERT INTO P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS (
        network_affiliation_id, npi_number, network_name, network_tier,
        participation_status, effective_date, termination_date, par_agreement_type,
        _source_loaded_at, _run_id
    )
    SELECT
        network_affiliation_id::VARCHAR,
        npi_number::VARCHAR(10),
        network_name::VARCHAR,
        network_tier::VARCHAR,
        participation_status::VARCHAR,
        effective_date::DATE,
        termination_date::DATE,
        par_agreement_type::VARCHAR,
        _loaded_at::TIMESTAMP_NTZ,
        :P_RUN_ID
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
    WHERE _loaded_at > :v_hwm
      AND NOT (
          npi_number IS NULL
          OR LENGTH(npi_number) != 10
          OR effective_date IS NULL
      );

    v_insert_count := SQLROWCOUNT;
    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_insert_count, :v_reject_count, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'rows_written', :v_insert_count, 'rows_rejected', :v_reject_count);

EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'STG_NETWORK_AFFILIATIONS', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, :v_reject_count, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
