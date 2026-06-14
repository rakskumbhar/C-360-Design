USE DATABASE P360_SP;
USE SCHEMA ORCHESTRATION;

CREATE OR REPLACE PROCEDURE ORCHESTRATION.SP_RUN_PACKAGE(
    P_RUN_MODE      VARCHAR DEFAULT 'INCREMENTAL',
    P_RESUME_RUN_ID VARCHAR DEFAULT NULL,
    P_STEP_ID       NUMBER DEFAULT NULL
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
    v_retry_attempt NUMBER;
    v_max_retries NUMBER;
    v_retry_delay NUMBER;
    v_resume_from_step NUMBER DEFAULT 0;
    v_overall_status VARCHAR DEFAULT 'COMPLETED';
    v_failed_step VARCHAR;
    v_error_msg VARCHAR;
    v_steps_completed NUMBER DEFAULT 0;
    v_steps_total NUMBER DEFAULT 0;
    v_err_message VARCHAR;
    
    cur_steps CURSOR FOR
        SELECT step_id, step_name, step_layer, step_procedure, retry_count, retry_delay_seconds
        FROM P360_SP.CONFIG.PKG_STEP_REGISTRY
        WHERE is_active = TRUE
          AND step_id >= :v_resume_from_step
          AND (step_id = :P_STEP_ID OR :P_STEP_ID IS NULL)
        ORDER BY step_order;
    
    v_cur_step_id NUMBER;
    v_cur_step_name VARCHAR;
    v_cur_step_layer VARCHAR;
    v_cur_step_procedure VARCHAR;
    v_cur_retry_count NUMBER;
    v_cur_retry_delay NUMBER;
BEGIN
    IF (:P_RUN_MODE = 'RESUME' AND :P_RESUME_RUN_ID IS NOT NULL) THEN
        v_run_id := :P_RESUME_RUN_ID;
        SELECT COALESCE(failed_step_id, 0) INTO v_resume_from_step
        FROM P360_SP.AUDIT.PKG_RUN_LOG
        WHERE run_id = :v_run_id;
        
        UPDATE P360_SP.AUDIT.PKG_RUN_LOG
        SET run_status = 'RUNNING',
            resume_from_step_id = :v_resume_from_step,
            error_message = NULL
        WHERE run_id = :v_run_id;
    ELSE
        v_run_id := UUID_STRING();
        CALL P360_SP.CONFIG.SP_LOG_RUN_START(:v_run_id, :P_RUN_MODE, NULL);
    END IF;

    CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'RUN_START', NULL);

    SELECT COUNT(*) INTO v_steps_total
    FROM P360_SP.CONFIG.PKG_STEP_REGISTRY
    WHERE is_active = TRUE
      AND step_id >= :v_resume_from_step
      AND (step_id = :P_STEP_ID OR :P_STEP_ID IS NULL);

    OPEN cur_steps;
    LOOP
        FETCH cur_steps INTO v_cur_step_id, v_cur_step_name, v_cur_step_layer, v_cur_step_procedure, v_cur_retry_count, v_cur_retry_delay;
        
        IF (NOT FOUND) THEN
            LEAVE;
        END IF;

        v_retry_attempt := 0;
        v_max_retries := v_cur_retry_count;
        v_retry_delay := v_cur_retry_delay;

        LOOP
            v_retry_attempt := v_retry_attempt + 1;
            
            BEGIN
                EXECUTE IMMEDIATE 'CALL ' || v_cur_step_procedure || '(''' || v_run_id || ''', ''' || P_RUN_MODE || ''')';
                
                v_step_result := (SELECT $1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
                v_step_status := v_step_result:status::VARCHAR;
                
                IF (v_step_status = 'COMPLETED' OR v_step_status = 'SKIPPED') THEN
                    v_steps_completed := v_steps_completed + 1;
                    LEAVE;
                ELSIF (v_step_status = 'FAILED') THEN
                    IF (v_retry_attempt >= v_max_retries) THEN
                        v_overall_status := 'FAILED';
                        v_failed_step := v_cur_step_name;
                        v_error_msg := COALESCE(v_step_result:error::VARCHAR, v_step_result:reason::VARCHAR, 'Unknown error');
                        
                        UPDATE P360_SP.AUDIT.PKG_RUN_LOG
                        SET failed_step_id = :v_cur_step_id
                        WHERE run_id = :v_run_id;
                        
                        CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'STEP_FAILURE', NULL);
                        LEAVE;
                    ELSE
                        CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'STEP_FAILURE', NULL);
                        CALL SYSTEM$WAIT(60, 'SECONDS');
                    END IF;
                END IF;
            EXCEPTION
                WHEN OTHER THEN
                    LET v_err_message := SQLERRM;
                    IF (v_retry_attempt >= v_max_retries) THEN
                        v_overall_status := 'FAILED';
                        v_failed_step := v_cur_step_name;
                        v_error_msg := :v_err_message;
                        
                        UPDATE P360_SP.AUDIT.PKG_RUN_LOG
                        SET failed_step_id = :v_cur_step_id
                        WHERE run_id = :v_run_id;
                        
                        CALL P360_SP.CONFIG.SP_LOG_ERROR(:v_run_id, NULL, :v_cur_step_name, '', '', :v_err_message, :v_cur_step_procedure, 'ERROR');
                        LEAVE;
                    ELSE
                        CALL SYSTEM$WAIT(60, 'SECONDS');
                    END IF;
            END;
        END LOOP;

        IF (v_overall_status = 'FAILED') THEN
            LEAVE;
        END IF;
    END LOOP;
    CLOSE cur_steps;

    CALL P360_SP.CONFIG.SP_LOG_RUN_END(:v_run_id, :v_overall_status, :v_error_msg);

    IF (v_overall_status = 'COMPLETED') THEN
        CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'RUN_COMPLETE', NULL);
    ELSE
        CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'RUN_FAILURE', NULL);
    END IF;

    RETURN OBJECT_CONSTRUCT(
        'run_id', :v_run_id,
        'status', :v_overall_status,
        'mode', :P_RUN_MODE,
        'steps_completed', :v_steps_completed,
        'steps_total', :v_steps_total,
        'failed_step', :v_failed_step,
        'error', :v_error_msg,
        'resume_command', CASE WHEN v_overall_status = 'FAILED' 
            THEN 'CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE(''RESUME'', ''' || v_run_id || ''')' 
            ELSE NULL END
    );

EXCEPTION
    WHEN OTHER THEN
        LET v_err_message := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_RUN_END(:v_run_id, 'FAILED', :v_err_message);
        CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, 'RUN_FAILURE', NULL);
        RETURN OBJECT_CONSTRUCT('run_id', :v_run_id, 'status', 'FAILED', 'error', :v_err_message);
END;
$$;


-- ============================================================
-- MONITORING VIEW: Run History Dashboard
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_RUN_HISTORY AS
SELECT
    run_id,
    package_name,
    run_mode,
    environment,
    run_status,
    initiated_by,
    start_timestamp,
    end_timestamp,
    duration_seconds,
    ROUND(duration_seconds / 60.0, 1) AS duration_minutes,
    total_rows_read,
    total_rows_written,
    total_rows_rejected,
    total_steps,
    completed_steps,
    failed_step_id,
    error_message,
    resume_from_step_id
FROM P360_SP.AUDIT.PKG_RUN_LOG
ORDER BY start_timestamp DESC;

-- ============================================================
-- MONITORING VIEW: Step Performance
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_STEP_PERFORMANCE AS
SELECT
    s.run_id,
    r.run_mode,
    s.step_name,
    s.step_layer,
    s.step_status,
    s.attempt_number,
    s.start_timestamp,
    s.end_timestamp,
    s.duration_seconds,
    s.rows_read,
    s.rows_written,
    s.rows_rejected,
    s.reject_percentage,
    s.error_message,
    r.start_timestamp AS run_start
FROM P360_SP.AUDIT.STEP_RUN_LOG s
JOIN P360_SP.AUDIT.PKG_RUN_LOG r ON s.run_id = r.run_id
ORDER BY r.start_timestamp DESC, s.start_timestamp;

-- ============================================================
-- MONITORING VIEW: Data Quality Dashboard
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_DQ_DASHBOARD AS
SELECT
    d.run_id,
    r.run_mode,
    r.start_timestamp AS run_date,
    d.source_table,
    d.total_records,
    d.passed_records,
    d.rejected_records,
    d.reject_percentage,
    d.threshold_exceeded,
    d.threshold_value,
    d.evaluation_timestamp
FROM P360_SP.AUDIT.DQ_RUN_LOG d
JOIN P360_SP.AUDIT.PKG_RUN_LOG r ON d.run_id = r.run_id
ORDER BY d.evaluation_timestamp DESC;

-- ============================================================
-- MONITORING VIEW: Error Analysis
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_ERROR_ANALYSIS AS
SELECT
    e.run_id,
    e.step_name,
    e.error_code,
    e.error_state,
    e.error_message,
    e.severity,
    e.error_timestamp,
    r.run_mode,
    r.environment
FROM P360_SP.AUDIT.ERROR_LOG e
JOIN P360_SP.AUDIT.PKG_RUN_LOG r ON e.run_id = r.run_id
ORDER BY e.error_timestamp DESC;

-- ============================================================
-- MONITORING VIEW: Reject Analysis
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_REJECT_ANALYSIS AS
SELECT
    rs.run_id,
    r.start_timestamp AS run_date,
    rs.step_name,
    rs.source_table,
    rs.reject_reason,
    rs.reject_count,
    rs.first_rejected_at,
    rs.last_rejected_at
FROM P360_SP.REJECT.REJECT_SUMMARY rs
JOIN P360_SP.AUDIT.PKG_RUN_LOG r ON rs.run_id = r.run_id
ORDER BY r.start_timestamp DESC, rs.reject_count DESC;
