/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  01_FRAMEWORK/001_audit_tables.sql
  
  Purpose: Creates the audit/logging tables that form the backbone of the 
           enterprise observability framework.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA AUDIT;

-- ============================================================
-- PACKAGE RUN LOG (Master run record)
-- ============================================================
CREATE TABLE IF NOT EXISTS PKG_RUN_LOG (
    run_id              VARCHAR(36)     NOT NULL PRIMARY KEY,
    package_name        VARCHAR(100)    NOT NULL,
    run_mode            VARCHAR(20)     NOT NULL,  -- FULL, INCREMENTAL, RESUME, RERUN_STEP
    environment         VARCHAR(20)     NOT NULL,
    run_status          VARCHAR(20)     NOT NULL DEFAULT 'RUNNING',  -- RUNNING, COMPLETED, FAILED, CANCELLED
    initiated_by        VARCHAR(100)    NOT NULL DEFAULT CURRENT_USER(),
    start_timestamp     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    end_timestamp       TIMESTAMP_NTZ,
    duration_seconds    NUMBER,
    total_rows_read     NUMBER          DEFAULT 0,
    total_rows_written  NUMBER          DEFAULT 0,
    total_rows_rejected NUMBER          DEFAULT 0,
    total_steps         NUMBER          DEFAULT 0,
    completed_steps     NUMBER          DEFAULT 0,
    failed_step_id      NUMBER,
    error_message       VARCHAR(4000),
    error_state         VARCHAR(10),
    resume_from_step_id NUMBER,
    run_parameters      VARIANT,
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- STEP RUN LOG (Per-step execution details)
-- ============================================================
CREATE TABLE IF NOT EXISTS STEP_RUN_LOG (
    step_run_id         VARCHAR(36)     NOT NULL PRIMARY KEY,
    run_id              VARCHAR(36)     NOT NULL,
    step_id             NUMBER          NOT NULL,
    step_name           VARCHAR(200)    NOT NULL,
    step_layer          VARCHAR(20)     NOT NULL,
    step_status         VARCHAR(20)     NOT NULL DEFAULT 'RUNNING',  -- RUNNING, COMPLETED, FAILED, SKIPPED, RETRYING
    attempt_number      NUMBER(3)       DEFAULT 1,
    start_timestamp     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    end_timestamp       TIMESTAMP_NTZ,
    duration_seconds    NUMBER,
    rows_read           NUMBER          DEFAULT 0,
    rows_written        NUMBER          DEFAULT 0,
    rows_rejected       NUMBER          DEFAULT 0,
    rows_updated        NUMBER          DEFAULT 0,
    rows_deleted        NUMBER          DEFAULT 0,
    reject_percentage   NUMBER(5,2)     DEFAULT 0,
    dq_passed           BOOLEAN         DEFAULT TRUE,
    error_message       VARCHAR(4000),
    error_code          VARCHAR(20),
    error_state         VARCHAR(10),
    sql_query_id        VARCHAR(200),
    metadata            VARIANT,
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT fk_step_run_log FOREIGN KEY (run_id) REFERENCES PKG_RUN_LOG(run_id)
);

-- ============================================================
-- ERROR LOG (Detailed error capture)
-- ============================================================
CREATE TABLE IF NOT EXISTS ERROR_LOG (
    error_log_id        VARCHAR(36)     NOT NULL PRIMARY KEY,
    run_id              VARCHAR(36)     NOT NULL,
    step_run_id         VARCHAR(36),
    step_name           VARCHAR(200),
    error_timestamp     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    error_code          VARCHAR(20),
    error_state         VARCHAR(10),
    error_message       VARCHAR(4000),
    error_stack_trace   VARCHAR(8000),
    sql_statement       VARCHAR(8000),
    sql_query_id        VARCHAR(200),
    severity            VARCHAR(10)     DEFAULT 'ERROR',
    is_retryable        BOOLEAN         DEFAULT TRUE,
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- DATA QUALITY LOG (Per-run DQ metrics)
-- ============================================================
CREATE TABLE IF NOT EXISTS DQ_RUN_LOG (
    dq_log_id           VARCHAR(36)     NOT NULL PRIMARY KEY,
    run_id              VARCHAR(36)     NOT NULL,
    step_run_id         VARCHAR(36),
    source_table        VARCHAR(200)    NOT NULL,
    total_records       NUMBER          NOT NULL DEFAULT 0,
    passed_records      NUMBER          NOT NULL DEFAULT 0,
    rejected_records    NUMBER          NOT NULL DEFAULT 0,
    reject_percentage   NUMBER(5,2)     DEFAULT 0,
    threshold_exceeded  BOOLEAN         DEFAULT FALSE,
    threshold_value     NUMBER(5,2),
    rules_evaluated     NUMBER          DEFAULT 0,
    rules_failed        NUMBER          DEFAULT 0,
    evaluation_timestamp TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    rule_details        VARIANT,
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- NOTIFICATION LOG
-- ============================================================
CREATE TABLE IF NOT EXISTS NOTIFICATION_LOG (
    notification_log_id VARCHAR(36)     NOT NULL PRIMARY KEY,
    run_id              VARCHAR(36),
    notification_type   VARCHAR(50)     NOT NULL,
    event_type          VARCHAR(50)     NOT NULL,
    recipients          VARCHAR(2000),
    subject             VARCHAR(500),
    body                VARCHAR(4000),
    send_status         VARCHAR(20)     DEFAULT 'PENDING',  -- PENDING, SENT, FAILED
    error_message       VARCHAR(1000),
    sent_at             TIMESTAMP_NTZ,
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- REJECT RECORDS TABLE (Universal reject store)
-- ============================================================
CREATE TABLE IF NOT EXISTS REJECT.REJECT_RECORDS (
    reject_id           VARCHAR(36)     NOT NULL,
    run_id              VARCHAR(36)     NOT NULL,
    step_name           VARCHAR(200)    NOT NULL,
    source_table        VARCHAR(200)    NOT NULL,
    reject_reasons      ARRAY           NOT NULL,
    record_key          VARCHAR(500),
    record_data         VARIANT,
    severity            VARCHAR(10)     DEFAULT 'ERROR',
    rejected_at         TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (reject_id, run_id)
);

-- ============================================================
-- REJECT SUMMARY TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS REJECT.REJECT_SUMMARY (
    summary_id          VARCHAR(36)     NOT NULL,
    run_id              VARCHAR(36)     NOT NULL,
    step_name           VARCHAR(200)    NOT NULL,
    source_table        VARCHAR(200)    NOT NULL,
    reject_reason       VARCHAR(200)    NOT NULL,
    reject_count        NUMBER          NOT NULL,
    first_rejected_at   TIMESTAMP_NTZ,
    last_rejected_at    TIMESTAMP_NTZ,
    summarized_at       TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (summary_id, run_id)
);

-- ============================================================
-- SOURCE ROW COUNTS (Track source volumes per run)
-- ============================================================
CREATE TABLE IF NOT EXISTS SOURCE_ROW_COUNTS (
    count_id            VARCHAR(36)     NOT NULL PRIMARY KEY,
    run_id              VARCHAR(36)     NOT NULL,
    source_table        VARCHAR(200)    NOT NULL,
    total_count         NUMBER          NOT NULL DEFAULT 0,
    incremental_count   NUMBER          DEFAULT 0,
    counted_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);
