-- DQ check wrapper for Silver layer tables and SCD2 procedure
-- Co-authored with CoCo
/*=============================================================================
  03_SILVER/002_sp_run_dq_silver.sql
=============================================================================*/

USE DATABASE P360_DQ;
USE SCHEMA SILVER;

CREATE OR REPLACE PROCEDURE SILVER.SP_RUN_DQ_SILVER(
    P_RUN_ID VARCHAR, P_MODE VARCHAR DEFAULT 'INCREMENTAL'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_step_run_id VARCHAR;
    v_batch_id VARCHAR;
    v_result VARIANT;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    v_batch_id := UUID_STRING();
    CALL P360_DQ.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 30, 'DQ_CHECK_SILVER', 'DQ_SILVER', 1);

    CALL P360_DQ.CONFIG.SP_RUN_DQ_CHECK(:P_RUN_ID, 'DIM_PROVIDER', 'SILVER', :v_batch_id);
    v_result := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    IF (v_result:threshold_exceeded::BOOLEAN = TRUE) THEN
        CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, 'DQ threshold exceeded on Silver', 'DQ_FAIL', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'reason', 'DQ_THRESHOLD_EXCEEDED', 'result', :v_result);
    END IF;

    CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'result', :v_result);
EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_DQ.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'DQ_CHECK_SILVER', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
