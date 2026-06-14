/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  05_AUDIT/001_sp_reject_summary.sql
  
  Purpose: Summarizes reject records for the current run by step and reason.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA AUDIT;

CREATE OR REPLACE PROCEDURE AUDIT.SP_REJECT_SUMMARY(
    P_RUN_ID    VARCHAR,
    P_MODE      VARCHAR DEFAULT 'FULL'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_step_run_id VARCHAR;
    v_insert_count NUMBER DEFAULT 0;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 40, 'AUDIT_REJECT_SUMMARY', 'AUDIT', 1);

    INSERT INTO P360_SP.REJECT.REJECT_SUMMARY (
        summary_id, run_id, step_name, source_table, reject_reason,
        reject_count, first_rejected_at, last_rejected_at, summarized_at
    )
    SELECT
        UUID_STRING(),
        :P_RUN_ID,
        step_name,
        source_table,
        r.value::VARCHAR AS reject_reason,
        COUNT(*) AS reject_count,
        MIN(rejected_at) AS first_rejected_at,
        MAX(rejected_at) AS last_rejected_at,
        CURRENT_TIMESTAMP()
    FROM P360_SP.REJECT.REJECT_RECORDS,
        LATERAL FLATTEN(input => reject_reasons) r
    WHERE run_id = :P_RUN_ID
    GROUP BY step_name, source_table, r.value::VARCHAR;

    v_insert_count := SQLROWCOUNT;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_insert_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'summary_records', :v_insert_count);

EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'AUDIT_REJECT_SUMMARY', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;

-- ============================================================
-- RUN METADATA PROCEDURE
-- ============================================================
CREATE OR REPLACE PROCEDURE AUDIT.SP_RUN_METADATA(
    P_RUN_ID    VARCHAR,
    P_MODE      VARCHAR DEFAULT 'FULL'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_step_run_id VARCHAR;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 41, 'AUDIT_RUN_METADATA', 'AUDIT', 1);

    INSERT INTO P360_SP.AUDIT.SOURCE_ROW_COUNTS (count_id, run_id, source_table, total_count, incremental_count, counted_at)
    SELECT UUID_STRING(), :P_RUN_ID, 'NPI_RAW', COUNT(*), 0, CURRENT_TIMESTAMP()
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NPI_RAW
    UNION ALL
    SELECT UUID_STRING(), :P_RUN_ID, 'PROVIDER_CREDENTIALS_RAW', COUNT(*), 0, CURRENT_TIMESTAMP()
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
    UNION ALL
    SELECT UUID_STRING(), :P_RUN_ID, 'PROVIDER_MASTER_RAW', COUNT(*), 0, CURRENT_TIMESTAMP()
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.PROVIDER_MASTER_RAW
    UNION ALL
    SELECT UUID_STRING(), :P_RUN_ID, 'CLAIMS_RAW', COUNT(*), 0, CURRENT_TIMESTAMP()
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.CLAIMS_RAW
    UNION ALL
    SELECT UUID_STRING(), :P_RUN_ID, 'NETWORK_AFFILIATIONS_RAW', COUNT(*), 0, CURRENT_TIMESTAMP()
    FROM SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 5, 5, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'sources_counted', 5);

EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'AUDIT_RUN_METADATA', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
