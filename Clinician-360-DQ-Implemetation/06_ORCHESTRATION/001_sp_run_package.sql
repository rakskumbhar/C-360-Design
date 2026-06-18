-- Master orchestrator with dependency execution, DQ gates, and resume capability
-- Co-authored with CoCo
USE DATABASE P360_DQ;
USE SCHEMA ORCHESTRATION;

CREATE OR REPLACE PROCEDURE ORCHESTRATION.SP_RUN_PACKAGE(
    P_RUN_MODE VARCHAR DEFAULT 'INCREMENTAL',
    P_RESUME_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_run_id VARCHAR;
    v_step_result VARIANT;
    v_step_status VARCHAR;
    v_overall_status VARCHAR DEFAULT 'COMPLETED';
    v_error_msg VARCHAR;
    v_steps_completed NUMBER DEFAULT 0;
    v_steps_total NUMBER DEFAULT 0;
    v_resume_from_step NUMBER DEFAULT 0;
    v_cur_step_id NUMBER;
    v_cur_step_name VARCHAR;
    v_cur_step_procedure VARCHAR;
BEGIN
    IF (:P_RUN_MODE = 'RESUME' AND :P_RESUME_RUN_ID IS NOT NULL) THEN
        v_run_id := :P_RESUME_RUN_ID;
        SELECT COALESCE(FAILED_STEP_ID, 0) INTO v_resume_from_step
        FROM P360_DQ.AUDIT.PKG_RUN_LOG WHERE RUN_ID = :v_run_id;
        UPDATE P360_DQ.AUDIT.PKG_RUN_LOG SET RUN_STATUS = 'RUNNING', ERROR_MESSAGE = NULL WHERE RUN_ID = :v_run_id;
    ELSE
        v_run_id := UUID_STRING();
        CALL P360_DQ.CONFIG.SP_LOG_RUN_START(:v_run_id, :P_RUN_MODE, NULL);
    END IF;

    CALL P360_DQ.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'RUN_START', NULL);

    SELECT COUNT(*) INTO v_steps_total FROM P360_DQ.CONFIG.PKG_STEP_REGISTRY
    WHERE IS_ACTIVE = TRUE AND STEP_ID >= :v_resume_from_step;

    LET v_rs RESULTSET := (
        SELECT STEP_ID, STEP_NAME, STEP_PROCEDURE
        FROM P360_DQ.CONFIG.PKG_STEP_REGISTRY
        WHERE IS_ACTIVE = TRUE AND STEP_ID >= :v_resume_from_step
        ORDER BY STEP_ORDER
    );
    LET cur_steps CURSOR FOR v_rs;

    FOR rec IN cur_steps DO
        v_cur_step_id := rec.STEP_ID;
        v_cur_step_name := rec.STEP_NAME;
        v_cur_step_procedure := rec.STEP_PROCEDURE;

        BEGIN
            LET v_call_sql VARCHAR := 'CALL ' || :v_cur_step_procedure || '(''' || :v_run_id || ''', ''' || :P_RUN_MODE || ''')';
            EXECUTE IMMEDIATE :v_call_sql;
            v_step_result := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
            v_step_status := v_step_result:status::VARCHAR;

            IF (v_step_status = 'COMPLETED') THEN
                v_steps_completed := v_steps_completed + 1;
            ELSEIF (v_step_status = 'FAILED') THEN
                v_overall_status := 'FAILED';
                v_error_msg := COALESCE(v_step_result:error::VARCHAR, v_step_result:reason::VARCHAR, 'Step failed');
                UPDATE P360_DQ.AUDIT.PKG_RUN_LOG SET FAILED_STEP_ID = :v_cur_step_id WHERE RUN_ID = :v_run_id;
                CALL P360_DQ.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'STEP_FAILURE', NULL);
            END IF;
        EXCEPTION
            WHEN OTHER THEN
                v_error_msg := SQLERRM;
                v_overall_status := 'FAILED';
                UPDATE P360_DQ.AUDIT.PKG_RUN_LOG SET FAILED_STEP_ID = :v_cur_step_id WHERE RUN_ID = :v_run_id;
                CALL P360_DQ.CONFIG.SP_LOG_ERROR(:v_run_id, NULL, :v_cur_step_name, '', '', :v_error_msg, :v_cur_step_procedure, 'ERROR');
        END;

        IF (v_overall_status = 'FAILED') THEN
            CALL P360_DQ.CONFIG.SP_LOG_RUN_END(:v_run_id, 'FAILED', :v_error_msg);
            CALL P360_DQ.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'RUN_FAILURE', NULL);
            RETURN OBJECT_CONSTRUCT('run_id', :v_run_id, 'status', 'FAILED', 'failed_step', :v_cur_step_name, 'error', :v_error_msg,
                'resume_command', 'CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE(''RESUME'', ''' || v_run_id || ''')');
        END IF;
    END FOR;

    CALL P360_DQ.CONFIG.SP_LOG_RUN_END(:v_run_id, 'COMPLETED', NULL);
    CALL P360_DQ.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'RUN_COMPLETE', NULL);
    RETURN OBJECT_CONSTRUCT('run_id', :v_run_id, 'status', 'COMPLETED', 'steps_completed', :v_steps_completed, 'steps_total', :v_steps_total);
EXCEPTION
    WHEN OTHER THEN
        v_error_msg := SQLERRM;
        CALL P360_DQ.CONFIG.SP_LOG_RUN_END(:v_run_id, 'FAILED', :v_error_msg);
        RETURN OBJECT_CONSTRUCT('run_id', :v_run_id, 'status', 'FAILED', 'error', :v_error_msg);
END;
$$;
