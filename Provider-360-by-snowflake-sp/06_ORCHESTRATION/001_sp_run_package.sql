/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  06_ORCHESTRATION/001_sp_run_package.sql
  
  Purpose: Master orchestrator procedure that executes all pipeline steps 
           in dependency order with full error handling, retry logic, 
           failure/resume support, and notification dispatch.
  
  Run Modes:
    FULL        - Truncate and reload all layers
    INCREMENTAL - Process only new/changed records (default)
    RESUME      - Resume from the last failed step
    RERUN_STEP  - Re-execute a specific step by ID
  
  Enterprise Features:
    - Dependency-aware step execution
    - Configurable retry with exponential backoff
    - DQ threshold circuit breaker
    - Failure capture and resume capability
    - Notification on start/complete/failure
    - Full audit trail
    
  NOTE: Deployed via anonymous block (BEGIN...END) to work with the Snowsight
        worksheet parser. Uses single-quote body delimiter with ELSEIF (not
        ELSIF), FOR...END FOR (not LOOP...LEAVE), and WHILE...END WHILE.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA ORCHESTRATION;

BEGIN
    CREATE OR REPLACE PROCEDURE ORCHESTRATION.SP_RUN_PACKAGE(
        P_RUN_MODE      VARCHAR DEFAULT 'INCREMENTAL',
        P_RESUME_RUN_ID VARCHAR DEFAULT NULL,
        P_STEP_ID       NUMBER DEFAULT NULL
    )
    RETURNS VARIANT
    LANGUAGE SQL
    EXECUTE AS CALLER
    AS
    '
    DECLARE
        v_run_id VARCHAR;
        v_step_result VARIANT;
        v_step_status VARCHAR;
        v_retry_attempt NUMBER;
        v_max_retries NUMBER;
        v_retry_delay NUMBER;
        v_resume_from_step NUMBER DEFAULT 0;
        v_overall_status VARCHAR DEFAULT ''COMPLETED'';
        v_failed_step VARCHAR;
        v_error_msg VARCHAR;
        v_steps_completed NUMBER DEFAULT 0;
        v_steps_total NUMBER DEFAULT 0;
        v_retry_success BOOLEAN;
        
        cur_steps CURSOR FOR
            SELECT step_id, step_name, step_layer, step_procedure, retry_count, retry_delay_seconds
            FROM P360_SP.CONFIG.PKG_STEP_REGISTRY
            WHERE is_active = TRUE
              AND step_id >= :v_resume_from_step
              AND (step_id = :P_STEP_ID OR :P_STEP_ID IS NULL)
            ORDER BY step_order;
    BEGIN
        IF (:P_RUN_MODE = ''RESUME'' AND :P_RESUME_RUN_ID IS NOT NULL) THEN
            v_run_id := :P_RESUME_RUN_ID;
            SELECT COALESCE(failed_step_id, 0) INTO v_resume_from_step
            FROM P360_SP.AUDIT.PKG_RUN_LOG
            WHERE run_id = :v_run_id;
            
            UPDATE P360_SP.AUDIT.PKG_RUN_LOG
            SET run_status = ''RUNNING'',
                resume_from_step_id = :v_resume_from_step,
                error_message = NULL
            WHERE run_id = :v_run_id;
        ELSE
            v_run_id := UUID_STRING();
            CALL P360_SP.CONFIG.SP_LOG_RUN_START(:v_run_id, :P_RUN_MODE, NULL);
        END IF;

        CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, ''RUN_START'', NULL);

        SELECT COUNT(*) INTO v_steps_total
        FROM P360_SP.CONFIG.PKG_STEP_REGISTRY
        WHERE is_active = TRUE
          AND step_id >= :v_resume_from_step
          AND (step_id = :P_STEP_ID OR :P_STEP_ID IS NULL);

        FOR rec IN cur_steps DO
            v_retry_attempt := 0;
            v_max_retries := rec.retry_count;
            v_retry_delay := rec.retry_delay_seconds;
            v_retry_success := FALSE;

            WHILE (v_retry_attempt < v_max_retries AND v_retry_success = FALSE AND v_overall_status = ''COMPLETED'') DO
                v_retry_attempt := v_retry_attempt + 1;
                
                BEGIN
                    EXECUTE IMMEDIATE ''CALL '' || rec.step_procedure || ''('''''''''' || v_run_id || '''''''''', '''''''''' || P_RUN_MODE || '''''''''')'';
                    
                    v_step_result := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
                    v_step_status := v_step_result:status::VARCHAR;
                    
                    IF (v_step_status = ''COMPLETED'' OR v_step_status = ''SKIPPED'') THEN
                        v_steps_completed := v_steps_completed + 1;
                        v_retry_success := TRUE;
                    ELSEIF (v_step_status = ''FAILED'') THEN
                        IF (v_retry_attempt >= v_max_retries) THEN
                            v_overall_status := ''FAILED'';
                            v_failed_step := rec.step_name;
                            v_error_msg := COALESCE(v_step_result:error::VARCHAR, v_step_result:reason::VARCHAR, ''Unknown error'');
                            
                            UPDATE P360_SP.AUDIT.PKG_RUN_LOG
                            SET failed_step_id = rec.step_id
                            WHERE run_id = :v_run_id;
                            
                            CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, ''STEP_FAILURE'', NULL);
                        ELSE
                            CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, ''STEP_FAILURE'', NULL);
                            CALL SYSTEM$WAIT(:v_retry_delay, ''SECONDS'');
                        END IF;
                    END IF;
                EXCEPTION
                    WHEN OTHER THEN
                        IF (v_retry_attempt >= v_max_retries) THEN
                            v_overall_status := ''FAILED'';
                            v_failed_step := rec.step_name;
                            v_error_msg := SQLERRM;
                            
                            UPDATE P360_SP.AUDIT.PKG_RUN_LOG
                            SET failed_step_id = rec.step_id
                            WHERE run_id = :v_run_id;
                            
                            CALL P360_SP.CONFIG.SP_LOG_ERROR(:v_run_id, NULL, rec.step_name, SQLCODE, SQLSTATE, SQLERRM, rec.step_procedure, ''ERROR'');
                        ELSE
                            CALL SYSTEM$WAIT(:v_retry_delay, ''SECONDS'');
                        END IF;
                END;
            END WHILE;

            IF (v_overall_status = ''FAILED'') THEN
                CALL P360_SP.CONFIG.SP_LOG_RUN_END(:v_run_id, :v_overall_status, :v_error_msg);
                CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, ''RUN_FAILURE'', NULL);
                RETURN OBJECT_CONSTRUCT(
                    ''run_id'', :v_run_id,
                    ''status'', ''FAILED'',
                    ''mode'', :P_RUN_MODE,
                    ''steps_completed'', :v_steps_completed,
                    ''steps_total'', :v_steps_total,
                    ''failed_step'', :v_failed_step,
                    ''error'', :v_error_msg,
                    ''resume_command'', ''CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE(''''RESUME'''', '''''' || v_run_id || '''''')''
                );
            END IF;
        END FOR;

        CALL P360_SP.CONFIG.SP_LOG_RUN_END(:v_run_id, :v_overall_status, :v_error_msg);
        CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, ''RUN_COMPLETE'', NULL);

        RETURN OBJECT_CONSTRUCT(
            ''run_id'', :v_run_id,
            ''status'', :v_overall_status,
            ''mode'', :P_RUN_MODE,
            ''steps_completed'', :v_steps_completed,
            ''steps_total'', :v_steps_total,
            ''failed_step'', NULL,
            ''error'', NULL,
            ''resume_command'', NULL
        );

    EXCEPTION
        WHEN OTHER THEN
            CALL P360_SP.CONFIG.SP_LOG_RUN_END(:v_run_id, ''FAILED'', SQLERRM);
            CALL P360_SP.CONFIG.SP_SEND_NOTIFICATION(:v_run_id, ''RUN_FAILURE'', NULL);
            RETURN OBJECT_CONSTRUCT(''run_id'', :v_run_id, ''status'', ''FAILED'', ''error'', SQLERRM);
    END;
    ';
END;
