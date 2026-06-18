-- DQ check wrapper for all Bronze layer tables using the generic DQ engine
/*=============================================================================
  02_BRONZE/003_sp_run_dq_bronze.sql
=============================================================================*/

USE DATABASE P360_DQ;
USE SCHEMA BRONZE;

CREATE OR REPLACE PROCEDURE BRONZE.SP_RUN_DQ_BRONZE(
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
    v_result_npi VARIANT;
    v_result_spec VARIANT;
    v_threshold_exceeded BOOLEAN DEFAULT FALSE;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    v_batch_id := UUID_STRING();
    CALL P360_DQ.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 10, 'DQ_CHECK_BRONZE', 'DQ_BRONZE', 1);

    CALL P360_DQ.CONFIG.SP_RUN_DQ_CHECK(:P_RUN_ID, 'STG_NPI_REGISTRY', 'BRONZE', :v_batch_id);
    v_result_npi := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    CALL P360_DQ.CONFIG.SP_RUN_DQ_CHECK(:P_RUN_ID, 'STG_SPECIALTY_TYPE', 'BRONZE', :v_batch_id);
    v_result_spec := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    IF (v_result_npi:threshold_exceeded::BOOLEAN = TRUE OR v_result_spec:threshold_exceeded::BOOLEAN = TRUE) THEN
        v_threshold_exceeded := TRUE;
        CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, 'DQ threshold exceeded on Bronze', 'DQ_FAIL', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'reason', 'DQ_THRESHOLD_EXCEEDED', 'npi_result', :v_result_npi, 'spec_result', :v_result_spec);
    END IF;

    CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'npi_result', :v_result_npi, 'spec_result', :v_result_spec);
EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_DQ.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'DQ_CHECK_BRONZE', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
