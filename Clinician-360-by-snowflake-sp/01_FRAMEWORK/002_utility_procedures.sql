/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  01_FRAMEWORK/002_utility_procedures.sql
  
  Purpose: Core utility procedures for logging, error handling, config access,
           notification dispatch, and surrogate key generation.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA CONFIG;

-- ============================================================
-- GET CONFIG VALUE
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_GET_CONFIG(
    P_CONFIG_KEY VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_value VARCHAR;
BEGIN
    SELECT config_value INTO v_value
    FROM P360_SP.CONFIG.PKG_CONFIG
    WHERE config_key = :P_CONFIG_KEY AND is_active = TRUE;
    
    RETURN v_value;
EXCEPTION
    WHEN OTHER THEN
        RETURN NULL;
END;
$$;

-- ============================================================
-- GENERATE UUID
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_GENERATE_UUID()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    RETURN UUID_STRING();
END;
$$;

-- ============================================================
-- LOG RUN START
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_RUN_START(
    P_RUN_ID        VARCHAR,
    P_RUN_MODE      VARCHAR,
    P_PARAMETERS    VARIANT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_pkg_name VARCHAR;
    v_env VARCHAR;
BEGIN
    SELECT config_value INTO v_pkg_name FROM P360_SP.CONFIG.PKG_CONFIG WHERE config_key = 'PKG_NAME';
    SELECT config_value INTO v_env FROM P360_SP.CONFIG.PKG_CONFIG WHERE config_key = 'ENVIRONMENT';
    
    INSERT INTO P360_SP.AUDIT.PKG_RUN_LOG (
        run_id, package_name, run_mode, environment, run_status, 
        initiated_by, start_timestamp, run_parameters
    ) VALUES (
        :P_RUN_ID, :v_pkg_name, :P_RUN_MODE, :v_env, 'RUNNING',
        CURRENT_USER(), CURRENT_TIMESTAMP(), :P_PARAMETERS
    );
    
    RETURN 'RUN_STARTED';
END;
$$;

-- ============================================================
-- LOG RUN END
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_RUN_END(
    P_RUN_ID    VARCHAR,
    P_STATUS    VARCHAR,
    P_ERROR_MSG VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_rows_read NUMBER;
    v_rows_written NUMBER;
    v_rows_rejected NUMBER;
    v_total_steps NUMBER;
    v_completed_steps NUMBER;
BEGIN
    SELECT 
        COALESCE(SUM(rows_read), 0),
        COALESCE(SUM(rows_written), 0),
        COALESCE(SUM(rows_rejected), 0),
        COUNT(*),
        SUM(CASE WHEN step_status = 'COMPLETED' THEN 1 ELSE 0 END)
    INTO v_rows_read, v_rows_written, v_rows_rejected, v_total_steps, v_completed_steps
    FROM P360_SP.AUDIT.STEP_RUN_LOG
    WHERE run_id = :P_RUN_ID;

    UPDATE P360_SP.AUDIT.PKG_RUN_LOG
    SET run_status = :P_STATUS,
        end_timestamp = CURRENT_TIMESTAMP(),
        duration_seconds = TIMESTAMPDIFF('SECOND', start_timestamp, CURRENT_TIMESTAMP()),
        total_rows_read = :v_rows_read,
        total_rows_written = :v_rows_written,
        total_rows_rejected = :v_rows_rejected,
        total_steps = :v_total_steps,
        completed_steps = :v_completed_steps,
        error_message = :P_ERROR_MSG
    WHERE run_id = :P_RUN_ID;
    
    RETURN :P_STATUS;
END;
$$;

-- ============================================================
-- LOG STEP START
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_STEP_START(
    P_STEP_RUN_ID   VARCHAR,
    P_RUN_ID        VARCHAR,
    P_STEP_ID       NUMBER,
    P_STEP_NAME     VARCHAR,
    P_STEP_LAYER    VARCHAR,
    P_ATTEMPT       NUMBER DEFAULT 1
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    INSERT INTO P360_SP.AUDIT.STEP_RUN_LOG (
        step_run_id, run_id, step_id, step_name, step_layer, 
        step_status, attempt_number, start_timestamp
    ) VALUES (
        :P_STEP_RUN_ID, :P_RUN_ID, :P_STEP_ID, :P_STEP_NAME, :P_STEP_LAYER,
        'RUNNING', :P_ATTEMPT, CURRENT_TIMESTAMP()
    );
    
    RETURN 'STEP_STARTED';
END;
$$;

-- ============================================================
-- LOG STEP END
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_STEP_END(
    P_STEP_RUN_ID       VARCHAR,
    P_STATUS            VARCHAR,
    P_ROWS_READ         NUMBER DEFAULT 0,
    P_ROWS_WRITTEN      NUMBER DEFAULT 0,
    P_ROWS_REJECTED     NUMBER DEFAULT 0,
    P_ROWS_UPDATED      NUMBER DEFAULT 0,
    P_ERROR_MESSAGE     VARCHAR DEFAULT NULL,
    P_ERROR_CODE        VARCHAR DEFAULT NULL,
    P_METADATA          VARIANT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_reject_pct NUMBER(5,2) DEFAULT 0;
    v_dq_passed BOOLEAN DEFAULT TRUE;
    v_threshold NUMBER(5,2);
BEGIN
    IF (:P_ROWS_READ > 0) THEN
        v_reject_pct := ROUND((:P_ROWS_REJECTED::FLOAT / :P_ROWS_READ) * 100, 2);
    END IF;

    SELECT config_value::NUMBER INTO v_threshold 
    FROM P360_SP.CONFIG.PKG_CONFIG WHERE config_key = 'DQ_REJECT_THRESHOLD';

    IF (v_reject_pct > v_threshold) THEN
        v_dq_passed := FALSE;
    END IF;

    UPDATE P360_SP.AUDIT.STEP_RUN_LOG
    SET step_status = :P_STATUS,
        end_timestamp = CURRENT_TIMESTAMP(),
        duration_seconds = TIMESTAMPDIFF('SECOND', start_timestamp, CURRENT_TIMESTAMP()),
        rows_read = :P_ROWS_READ,
        rows_written = :P_ROWS_WRITTEN,
        rows_rejected = :P_ROWS_REJECTED,
        rows_updated = :P_ROWS_UPDATED,
        reject_percentage = :v_reject_pct,
        dq_passed = :v_dq_passed,
        error_message = :P_ERROR_MESSAGE,
        error_code = :P_ERROR_CODE,
        metadata = :P_METADATA
    WHERE step_run_id = :P_STEP_RUN_ID;
    
    RETURN :P_STATUS;
END;
$$;

-- ============================================================
-- LOG ERROR
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_ERROR(
    P_RUN_ID        VARCHAR,
    P_STEP_RUN_ID   VARCHAR,
    P_STEP_NAME     VARCHAR,
    P_ERROR_CODE    VARCHAR,
    P_ERROR_STATE   VARCHAR,
    P_ERROR_MESSAGE VARCHAR,
    P_SQL_STATEMENT VARCHAR DEFAULT NULL,
    P_SEVERITY      VARCHAR DEFAULT 'ERROR'
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_id VARCHAR DEFAULT UUID_STRING();
BEGIN
    INSERT INTO P360_SP.AUDIT.ERROR_LOG (
        error_log_id, run_id, step_run_id, step_name,
        error_code, error_state, error_message, sql_statement, severity
    ) VALUES (
        :v_id, :P_RUN_ID, :P_STEP_RUN_ID, :P_STEP_NAME,
        :P_ERROR_CODE, :P_ERROR_STATE, :P_ERROR_MESSAGE, :P_SQL_STATEMENT, :P_SEVERITY
    );
    
    RETURN 'ERROR_LOGGED';
END;
$$;

-- ============================================================
-- SEND NOTIFICATION (Placeholder - requires email integration)
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_SEND_NOTIFICATION(
    P_RUN_ID        VARCHAR,
    P_EVENT_TYPE    VARCHAR,
    P_PARAMS        VARIANT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_enabled VARCHAR;
    v_recipients VARCHAR;
    v_subject VARCHAR;
    v_body VARCHAR;
    v_integration VARCHAR;
    v_notification_id VARCHAR DEFAULT UUID_STRING();
BEGIN
    SELECT config_value INTO v_enabled FROM P360_SP.CONFIG.PKG_CONFIG WHERE config_key = 'ENABLE_EMAIL_NOTIFY';
    
    IF (v_enabled != 'TRUE') THEN
        RETURN 'NOTIFICATIONS_DISABLED';
    END IF;
    
    SELECT recipients, subject_template, body_template, integration_name
    INTO v_recipients, v_subject, v_body, v_integration
    FROM P360_SP.CONFIG.NOTIFICATION_CONFIG
    WHERE event_type = :P_EVENT_TYPE AND is_active = TRUE
    LIMIT 1;
    
    INSERT INTO P360_SP.AUDIT.NOTIFICATION_LOG (
        notification_log_id, run_id, notification_type, event_type,
        recipients, subject, body, send_status, sent_at
    ) VALUES (
        :v_notification_id, :P_RUN_ID, 'EMAIL', :P_EVENT_TYPE,
        :v_recipients, :v_subject, :v_body, 'LOGGED', CURRENT_TIMESTAMP()
    );
    
    -- NOTE: Actual email sending requires:
    -- CALL SYSTEM$SEND_EMAIL(:v_integration, :v_recipients, :v_subject, :v_body);
    -- Enable when email integration is configured in production
    
    RETURN 'NOTIFICATION_LOGGED';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'NOTIFICATION_FAILED: ' || SQLERRM;
END;
$$;

-- ============================================================
-- CHECK DQ THRESHOLD
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_CHECK_DQ_THRESHOLD(
    P_RUN_ID        VARCHAR,
    P_STEP_RUN_ID   VARCHAR,
    P_SOURCE_TABLE  VARCHAR,
    P_TOTAL_RECORDS NUMBER,
    P_REJECT_COUNT  NUMBER
)
RETURNS BOOLEAN
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_threshold NUMBER(5,2);
    v_reject_pct NUMBER(5,2);
    v_exceeded BOOLEAN DEFAULT FALSE;
    v_dq_log_id VARCHAR DEFAULT UUID_STRING();
BEGIN
    SELECT config_value::NUMBER INTO v_threshold 
    FROM P360_SP.CONFIG.PKG_CONFIG WHERE config_key = 'DQ_REJECT_THRESHOLD';
    
    IF (:P_TOTAL_RECORDS > 0) THEN
        v_reject_pct := ROUND((:P_REJECT_COUNT::FLOAT / :P_TOTAL_RECORDS) * 100, 2);
    ELSE
        v_reject_pct := 0;
    END IF;
    
    IF (v_reject_pct > v_threshold) THEN
        v_exceeded := TRUE;
    END IF;
    
    INSERT INTO P360_SP.AUDIT.DQ_RUN_LOG (
        dq_log_id, run_id, step_run_id, source_table,
        total_records, passed_records, rejected_records,
        reject_percentage, threshold_exceeded, threshold_value
    ) VALUES (
        :v_dq_log_id, :P_RUN_ID, :P_STEP_RUN_ID, :P_SOURCE_TABLE,
        :P_TOTAL_RECORDS, :P_TOTAL_RECORDS - :P_REJECT_COUNT, :P_REJECT_COUNT,
        :v_reject_pct, :v_exceeded, :v_threshold
    );
    
    IF (v_exceeded) THEN
        CALL CONFIG.SP_SEND_NOTIFICATION(:P_RUN_ID, 'DQ_THRESHOLD', NULL);
    END IF;
    
    RETURN v_exceeded;
END;
$$;
