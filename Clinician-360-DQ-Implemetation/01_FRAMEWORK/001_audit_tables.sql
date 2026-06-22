-- Creates audit, DQ logging, reject, and observability tables for the DQ framework
/*=============================================================================
  CLINICIAN-360-DQ-IMPLEMENTATION
  01_FRAMEWORK/001_audit_tables.sql
  
  Purpose: Creates audit/logging tables and DQ result tables.
=============================================================================*/

USE DATABASE P360_DQ;

-- ============================================================
-- PKG_RUN_LOG (Master run record)
-- ============================================================
USE SCHEMA AUDIT;

CREATE OR REPLACE TABLE PKG_RUN_LOG (
    RUN_ID              VARCHAR(36)     NOT NULL PRIMARY KEY,
    PACKAGE_NAME        VARCHAR(100)    NOT NULL,
    RUN_MODE            VARCHAR(20)     NOT NULL,
    ENVIRONMENT         VARCHAR(20)     NOT NULL,
    RUN_STATUS          VARCHAR(20)     NOT NULL DEFAULT 'RUNNING',
    INITIATED_BY        VARCHAR(100)    NOT NULL DEFAULT CURRENT_USER(),
    START_TIMESTAMP     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    END_TIMESTAMP       TIMESTAMP_NTZ,
    DURATION_SECONDS    NUMBER,
    TOTAL_ROWS_READ     NUMBER          DEFAULT 0,
    TOTAL_ROWS_WRITTEN  NUMBER          DEFAULT 0,
    TOTAL_ROWS_REJECTED NUMBER          DEFAULT 0,
    TOTAL_STEPS         NUMBER          DEFAULT 0,
    COMPLETED_STEPS     NUMBER          DEFAULT 0,
    FAILED_STEP_ID      NUMBER,
    ERROR_MESSAGE       VARCHAR(4000),
    ERROR_STATE         VARCHAR(10),
    RESUME_FROM_STEP_ID NUMBER,
    RUN_PARAMETERS      VARIANT,
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- STEP_RUN_LOG (Per-step execution details)
-- ============================================================
CREATE OR REPLACE TABLE STEP_RUN_LOG (
    STEP_RUN_ID         VARCHAR(36)     NOT NULL PRIMARY KEY,
    RUN_ID              VARCHAR(36)     NOT NULL,
    STEP_ID             NUMBER          NOT NULL,
    STEP_NAME           VARCHAR(200)    NOT NULL,
    STEP_LAYER          VARCHAR(20)     NOT NULL,
    STEP_STATUS         VARCHAR(20)     NOT NULL DEFAULT 'RUNNING',
    ATTEMPT_NUMBER      NUMBER(3)       DEFAULT 1,
    START_TIMESTAMP     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    END_TIMESTAMP       TIMESTAMP_NTZ,
    DURATION_SECONDS    NUMBER,
    ROWS_READ           NUMBER          DEFAULT 0,
    ROWS_WRITTEN        NUMBER          DEFAULT 0,
    ROWS_REJECTED       NUMBER          DEFAULT 0,
    ROWS_UPDATED        NUMBER          DEFAULT 0,
    REJECT_PERCENTAGE   NUMBER(5,2)     DEFAULT 0,
    DQ_PASSED           BOOLEAN         DEFAULT TRUE,
    ERROR_MESSAGE       VARCHAR(4000),
    ERROR_CODE          VARCHAR(20),
    SQL_QUERY_ID        VARCHAR(200),
    METADATA            VARIANT,
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- ERROR_LOG (Detailed error capture)
-- ============================================================
CREATE OR REPLACE TABLE ERROR_LOG (
    ERROR_LOG_ID        VARCHAR(36)     NOT NULL PRIMARY KEY,
    RUN_ID              VARCHAR(36)     NOT NULL,
    STEP_RUN_ID         VARCHAR(36),
    STEP_NAME           VARCHAR(200),
    ERROR_TIMESTAMP     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ERROR_CODE          VARCHAR(20),
    ERROR_STATE         VARCHAR(10),
    ERROR_MESSAGE       VARCHAR(4000),
    ERROR_STACK_TRACE   VARCHAR(8000),
    SQL_STATEMENT       VARCHAR(8000),
    SQL_QUERY_ID        VARCHAR(200),
    SEVERITY            VARCHAR(10)     DEFAULT 'ERROR',
    IS_RETRYABLE        BOOLEAN         DEFAULT TRUE,
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- NOTIFICATION_LOG
-- ============================================================
CREATE OR REPLACE TABLE NOTIFICATION_LOG (
    NOTIFICATION_LOG_ID VARCHAR(36)     NOT NULL PRIMARY KEY,
    RUN_ID              VARCHAR(36),
    NOTIFICATION_TYPE   VARCHAR(50)     NOT NULL,
    EVENT_TYPE          VARCHAR(50)     NOT NULL,
    RECIPIENTS          VARCHAR(2000),
    SUBJECT             VARCHAR(500),
    BODY                VARCHAR(4000),
    SEND_STATUS         VARCHAR(20)     DEFAULT 'PENDING',
    ERROR_MESSAGE       VARCHAR(1000),
    SENT_AT             TIMESTAMP_NTZ,
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- SOURCE_ROW_COUNTS
-- ============================================================
CREATE OR REPLACE TABLE SOURCE_ROW_COUNTS (
    COUNT_ID            VARCHAR(36)     NOT NULL PRIMARY KEY,
    RUN_ID              VARCHAR(36)     NOT NULL,
    SOURCE_TABLE        VARCHAR(200)    NOT NULL,
    TOTAL_COUNT         NUMBER          NOT NULL DEFAULT 0,
    INCREMENTAL_COUNT   NUMBER          DEFAULT 0,
    COUNTED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- DQ_LOG (Current run DQ audit - per feed execution)
-- ============================================================
CREATE OR REPLACE TABLE DQ_LOG (
    DQ_BATCH_ID     VARCHAR(16777216),
    LAYER           VARCHAR(16777216),
    DOMAIN          VARCHAR(16777216),
    TABLE_NM        VARCHAR(16777216) NOT NULL,
    FEED_ID         NUMBER(38,0),
    DQ_START_TS     TIMESTAMP_NTZ(9),
    DQ_END_TS       TIMESTAMP_NTZ(9),
    ERROR_MESSAGE   VARCHAR(16777216),
    OVERALL_COUNT   NUMBER(38,0),
    FAILED_COUNT    NUMBER(38,0),
    STATUS          VARCHAR(16777216),
    UPDATED_TS      TIMESTAMP_NTZ(9)
);

-- ============================================================
-- DQ_LOG_HISTORY (Archival of all DQ executions)
-- ============================================================
CREATE OR REPLACE TABLE DQ_LOG_HISTORY (
    DQ_BATCH_ID     VARCHAR(16777216),
    LAYER           VARCHAR(16777216),
    DOMAIN          VARCHAR(16777216),
    TABLE_NM        VARCHAR(16777216) NOT NULL,
    FEED_ID         NUMBER(38,0),
    DQ_START_TS     TIMESTAMP_NTZ(9),
    DQ_END_TS       TIMESTAMP_NTZ(9),
    ERROR_MESSAGE   VARCHAR(16777216),
    OVERALL_COUNT   NUMBER(38,0),
    FAILED_COUNT    NUMBER(38,0),
    STATUS          VARCHAR(16777216),
    UPDATED_TS      TIMESTAMP_NTZ(9)
);

-- ============================================================
-- DQ_RESULT (Record-level DQ outcomes)
-- ============================================================


create or replace TABLE P360_DQ.AUDIT.DQ_RESULT (
	DQ_BATCH_ID VARCHAR(16777216),
	LAYER VARCHAR(100),
	DOMAIN VARCHAR(100),
	TABLE_NM VARCHAR(500),
	RULE_ID NUMBER(38,0),
	FEED_ID NUMBER(38,0),
	RECORD_KEY VARCHAR(500),
	RECORD_VALUE VARCHAR(16777216),
	RECORD_UPDATED_TS VARCHAR(16777216),
	RESULT VARCHAR(100),
	RECORD_INS_TS TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP(),
	RECORD_UPD_TS TIMESTAMP_NTZ(9),
	RECORD_INS_BY VARCHAR(16777216) DEFAULT CURRENT_USER(),
	RECORD_UPD_BY VARCHAR(16777216),
	DQ_CHECK_SQL_DYN VARCHAR(16777216)
);



-- ============================================================
-- REJECT RECORDS (Full rejected record store)
-- ============================================================
USE SCHEMA REJECT;

CREATE OR REPLACE TABLE REJECT_RECORDS (
    REJECT_ID           VARCHAR(36)     NOT NULL,
    RUN_ID              VARCHAR(36)     NOT NULL,
    STEP_NAME           VARCHAR(200)    NOT NULL,
    SOURCE_TABLE        VARCHAR(200)    NOT NULL,
    REJECT_REASONS      ARRAY           NOT NULL,
    RECORD_KEY          VARCHAR(500),
    RECORD_DATA         VARIANT,
    SEVERITY            VARCHAR(10)     DEFAULT 'ERROR',
    REJECTED_AT         TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (REJECT_ID, RUN_ID)
);

-- ============================================================
-- REJECT SUMMARY
-- ============================================================
CREATE OR REPLACE TABLE REJECT_SUMMARY (
    SUMMARY_ID          VARCHAR(36)     NOT NULL,
    RUN_ID              VARCHAR(36)     NOT NULL,
    STEP_NAME           VARCHAR(200)    NOT NULL,
    SOURCE_TABLE        VARCHAR(200)    NOT NULL,
    REJECT_REASON       VARCHAR(200)    NOT NULL,
    REJECT_COUNT        NUMBER          NOT NULL,
    FIRST_REJECTED_AT   TIMESTAMP_NTZ,
    LAST_REJECTED_AT    TIMESTAMP_NTZ,
    SUMMARIZED_AT       TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (SUMMARY_ID, RUN_ID)
);
