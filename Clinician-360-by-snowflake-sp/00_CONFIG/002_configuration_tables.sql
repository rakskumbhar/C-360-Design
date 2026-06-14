/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  00_CONFIG/002_configuration_tables.sql
  
  Purpose: Creates configuration tables that control package behavior, 
           step definitions, data quality rules, and notification settings.
  
  Enterprise Features:
    - Package run parameters (batch size, parallelism, retry counts)
    - Step registry with dependency ordering
    - Data quality rule definitions
    - Email notification configuration
    - Environment-specific overrides
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA CONFIG;

-- ============================================================
-- PACKAGE CONFIGURATION (Key-Value Parameters)
-- ============================================================
CREATE TABLE IF NOT EXISTS PKG_CONFIG (
    config_key          VARCHAR(100)    NOT NULL PRIMARY KEY,
    config_value        VARCHAR(4000),
    config_data_type    VARCHAR(20)     DEFAULT 'STRING',
    config_category     VARCHAR(50)     NOT NULL,
    description         VARCHAR(500),
    is_active           BOOLEAN         DEFAULT TRUE,
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    updated_by          VARCHAR(100)    DEFAULT CURRENT_USER()
);

-- ============================================================
-- STEP REGISTRY (Defines execution order and dependencies)
-- ============================================================
CREATE TABLE IF NOT EXISTS PKG_STEP_REGISTRY (
    step_id             NUMBER          NOT NULL PRIMARY KEY,
    step_name           VARCHAR(200)    NOT NULL,
    step_layer          VARCHAR(20)     NOT NULL,  -- BRONZE, SILVER, GOLD, AUDIT
    step_procedure      VARCHAR(500)    NOT NULL,
    step_order          NUMBER(5,1)     NOT NULL,
    depends_on_step_id  ARRAY,
    is_active           BOOLEAN         DEFAULT TRUE,
    is_restartable      BOOLEAN         DEFAULT TRUE,
    retry_count         NUMBER(2)       DEFAULT 3,
    retry_delay_seconds NUMBER          DEFAULT 60,
    timeout_minutes     NUMBER          DEFAULT 120,
    description         VARCHAR(500),
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- DATA QUALITY RULES
-- ============================================================
CREATE TABLE IF NOT EXISTS DQ_RULES (
    rule_id             NUMBER          IDENTITY(1,1) PRIMARY KEY,
    rule_name           VARCHAR(200)    NOT NULL,
    source_table        VARCHAR(200)    NOT NULL,
    target_layer        VARCHAR(20)     NOT NULL,
    column_name         VARCHAR(100)    NOT NULL,
    rule_type           VARCHAR(50)     NOT NULL,  -- NOT_NULL, LENGTH, RANGE, PATTERN, REFERENTIAL, CUSTOM
    rule_expression     VARCHAR(4000)   NOT NULL,
    reject_reason_code  VARCHAR(100)    NOT NULL,
    severity            VARCHAR(10)     DEFAULT 'ERROR',  -- ERROR, WARNING, INFO
    is_active           BOOLEAN         DEFAULT TRUE,
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- NOTIFICATION CONFIGURATION
-- ============================================================
CREATE TABLE IF NOT EXISTS NOTIFICATION_CONFIG (
    notification_id     NUMBER          IDENTITY(1,1) PRIMARY KEY,
    notification_type   VARCHAR(50)     NOT NULL,  -- EMAIL, SLACK, WEBHOOK
    event_type          VARCHAR(50)     NOT NULL,  -- RUN_START, RUN_COMPLETE, RUN_FAILURE, DQ_THRESHOLD, STEP_FAILURE
    recipients          VARCHAR(2000)   NOT NULL,
    subject_template    VARCHAR(500),
    body_template       VARCHAR(4000),
    is_active           BOOLEAN         DEFAULT TRUE,
    integration_name    VARCHAR(200),
    created_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- ENVIRONMENT CONFIGURATION
-- ============================================================
CREATE TABLE IF NOT EXISTS ENV_CONFIG (
    environment         VARCHAR(20)     NOT NULL,  -- DEV, QA, PROD
    source_database     VARCHAR(100)    NOT NULL,
    source_schema       VARCHAR(100)    NOT NULL,
    warehouse_name      VARCHAR(100)    NOT NULL,
    max_parallel_steps  NUMBER(2)       DEFAULT 4,
    dq_reject_threshold NUMBER(5,2)     DEFAULT 5.00,
    enable_notifications BOOLEAN        DEFAULT FALSE,
    is_active           BOOLEAN         DEFAULT TRUE,
    PRIMARY KEY (environment)
);
