-- Utility stored procedures for logging, error handling, and notifications
-- Co-authored with CoCo
/*=============================================================================
  CLINICIAN-360-DQ-IMPLEMENTATION
  01_FRAMEWORK/002_utility_procedures.sql
  
  Purpose: Utility procedures for run/step logging, error capture, 
           notification dispatch, and DQ threshold checking.
=============================================================================*/

USE DATABASE P360_DQ;
USE SCHEMA CONFIG;

-- ============================================================
-- SP_LOG_RUN_START
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_RUN_START(
    P_RUN_ID VARCHAR, P_RUN_MODE VARCHAR, P_PARAMS VARIANT
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    INSERT INTO P360_DQ.AUDIT.PKG_RUN_LOG (RUN_ID, PACKAGE_NAME, RUN_MODE, ENVIRONMENT, RUN_STATUS, RUN_PARAMETERS)
    SELECT :P_RUN_ID, 'CLINICIAN_360_DQ', :P_RUN_MODE,
           (SELECT CONFIG_VALUE FROM P360_DQ.CONFIG.PKG_CONFIG WHERE CONFIG_KEY = 'ENVIRONMENT'),
           'RUNNING', :P_PARAMS;
    RETURN 'OK';
END;
$$;

-- ============================================================
-- SP_LOG_RUN_END
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_RUN_END(
    P_RUN_ID VARCHAR, P_STATUS VARCHAR, P_ERROR_MSG VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    UPDATE P360_DQ.AUDIT.PKG_RUN_LOG
    SET RUN_STATUS = :P_STATUS,
        END_TIMESTAMP = CURRENT_TIMESTAMP(),
        DURATION_SECONDS = DATEDIFF('SECOND', START_TIMESTAMP, CURRENT_TIMESTAMP()),
        ERROR_MESSAGE = :P_ERROR_MSG
    WHERE RUN_ID = :P_RUN_ID;
    RETURN 'OK';
END;
$$;

-- ============================================================
-- SP_LOG_STEP_START
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_STEP_START(
    P_STEP_RUN_ID VARCHAR, P_RUN_ID VARCHAR, P_STEP_ID NUMBER, P_STEP_NAME VARCHAR, P_STEP_LAYER VARCHAR, P_ATTEMPT NUMBER
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    INSERT INTO P360_DQ.AUDIT.STEP_RUN_LOG (STEP_RUN_ID, RUN_ID, STEP_ID, STEP_NAME, STEP_LAYER, STEP_STATUS, ATTEMPT_NUMBER)
    VALUES (:P_STEP_RUN_ID, :P_RUN_ID, :P_STEP_ID, :P_STEP_NAME, :P_STEP_LAYER, 'RUNNING', :P_ATTEMPT);
    RETURN 'OK';
END;
$$;

-- ============================================================
-- SP_LOG_STEP_END
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_STEP_END(
    P_STEP_RUN_ID VARCHAR, P_STATUS VARCHAR, P_ROWS_READ NUMBER, P_ROWS_WRITTEN NUMBER, P_ROWS_REJECTED NUMBER, P_ROWS_UPDATED NUMBER, P_ERROR_MSG VARCHAR, P_ERROR_CODE VARCHAR, P_QUERY_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_reject_pct NUMBER(5,2) DEFAULT 0;
BEGIN
    IF (:P_ROWS_READ > 0) THEN
        v_reject_pct := ROUND((:P_ROWS_REJECTED::FLOAT / :P_ROWS_READ) * 100, 2);
    END IF;
    UPDATE P360_DQ.AUDIT.STEP_RUN_LOG
    SET STEP_STATUS = :P_STATUS,
        END_TIMESTAMP = CURRENT_TIMESTAMP(),
        DURATION_SECONDS = DATEDIFF('SECOND', START_TIMESTAMP, CURRENT_TIMESTAMP()),
        ROWS_READ = :P_ROWS_READ,
        ROWS_WRITTEN = :P_ROWS_WRITTEN,
        ROWS_REJECTED = :P_ROWS_REJECTED,
        ROWS_UPDATED = :P_ROWS_UPDATED,
        REJECT_PERCENTAGE = :v_reject_pct,
        ERROR_MESSAGE = :P_ERROR_MSG,
        ERROR_CODE = :P_ERROR_CODE,
        SQL_QUERY_ID = :P_QUERY_ID
    WHERE STEP_RUN_ID = :P_STEP_RUN_ID;
    RETURN 'OK';
END;
$$;

-- ============================================================
-- SP_LOG_ERROR
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_LOG_ERROR(
    P_RUN_ID VARCHAR, P_STEP_RUN_ID VARCHAR, P_STEP_NAME VARCHAR, P_ERROR_CODE VARCHAR, P_ERROR_STATE VARCHAR, P_ERROR_MSG VARCHAR, P_SQL VARCHAR, P_SEVERITY VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_error_log_id VARCHAR DEFAULT UUID_STRING();
BEGIN
    INSERT INTO P360_DQ.AUDIT.ERROR_LOG (ERROR_LOG_ID, RUN_ID, STEP_RUN_ID, STEP_NAME, ERROR_CODE, ERROR_STATE, ERROR_MESSAGE, SQL_STATEMENT, SEVERITY)
    VALUES (:v_error_log_id, :P_RUN_ID, :P_STEP_RUN_ID, :P_STEP_NAME, :P_ERROR_CODE, :P_ERROR_STATE, :P_ERROR_MSG, :P_SQL, :P_SEVERITY);
    RETURN 'OK';
END;
$$;

-- ============================================================
-- SP_CHECK_DQ_THRESHOLD
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_CHECK_DQ_THRESHOLD(
    P_RUN_ID VARCHAR, P_STEP_RUN_ID VARCHAR, P_TABLE_NM VARCHAR, P_TOTAL_COUNT NUMBER, P_FAIL_COUNT NUMBER
)
RETURNS BOOLEAN
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_threshold NUMBER(5,2);
    v_fail_pct NUMBER(5,2);
    v_exceeded BOOLEAN DEFAULT FALSE;
BEGIN
    SELECT COALESCE(CONFIG_VALUE::NUMBER, 10.00) INTO v_threshold
    FROM P360_DQ.CONFIG.PKG_CONFIG
    WHERE CONFIG_KEY = 'DQ_BRONZE_THRESHOLD';

    IF (:P_TOTAL_COUNT > 0) THEN
        v_fail_pct := ROUND((:P_FAIL_COUNT::FLOAT / :P_TOTAL_COUNT) * 100, 2);
    ELSE
        v_fail_pct := 0;
    END IF;

    IF (v_fail_pct > v_threshold) THEN
        v_exceeded := TRUE;
    END IF;

    RETURN :v_exceeded;
END;
$$;

-- ============================================================
-- SP_SEND_NOTIFICATION (Stub - logs notification intent)
-- ============================================================
CREATE OR REPLACE PROCEDURE CONFIG.SP_SEND_NOTIFICATION(
    P_RUN_ID VARCHAR, P_EVENT_TYPE VARCHAR, P_DETAILS VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_enabled VARCHAR;
    v_notification_id VARCHAR DEFAULT UUID_STRING();
BEGIN
    SELECT CONFIG_VALUE INTO v_enabled FROM P360_DQ.CONFIG.PKG_CONFIG WHERE CONFIG_KEY = 'ENABLE_EMAIL_NOTIFY';
    IF (v_enabled = 'TRUE') THEN
        INSERT INTO P360_DQ.AUDIT.NOTIFICATION_LOG (NOTIFICATION_LOG_ID, RUN_ID, NOTIFICATION_TYPE, EVENT_TYPE, SEND_STATUS)
        VALUES (:v_notification_id, :P_RUN_ID, 'EMAIL', :P_EVENT_TYPE, 'PENDING');
    END IF;
    RETURN 'OK';
END;
$$;
