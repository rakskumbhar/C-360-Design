-- Creates all configuration and DQ framework metadata tables for P360_DQ
/*=============================================================================
  CLINICIAN-360-DQ-IMPLEMENTATION
  00_CONFIG/002_configuration_tables.sql
  
  Purpose: Creates configuration tables that control package behavior,
           step definitions, DQ rules, feeds, and notification settings.
=============================================================================*/

USE DATABASE P360_DQ;
USE SCHEMA CONFIG;

-- ============================================================
-- PACKAGE CONFIGURATION (Key-Value Parameters)
-- ============================================================
CREATE OR REPLACE TABLE PKG_CONFIG (
    CONFIG_KEY          VARCHAR(100)    NOT NULL PRIMARY KEY,
    CONFIG_VALUE        VARCHAR(4000),
    CONFIG_DATA_TYPE    VARCHAR(20)     DEFAULT 'STRING',
    CONFIG_CATEGORY     VARCHAR(50)     NOT NULL,
    DESCRIPTION         VARCHAR(500),
    IS_ACTIVE           BOOLEAN         DEFAULT TRUE,
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_BY          VARCHAR(100)    DEFAULT CURRENT_USER()
);

-- ============================================================
-- STEP REGISTRY (Defines execution order and dependencies)
-- ============================================================
CREATE OR REPLACE TABLE PKG_STEP_REGISTRY (
    STEP_ID             NUMBER          NOT NULL PRIMARY KEY,
    STEP_NAME           VARCHAR(200)    NOT NULL,
    STEP_LAYER          VARCHAR(20)     NOT NULL,
    STEP_PROCEDURE      VARCHAR(500)    NOT NULL,
    STEP_ORDER          NUMBER(5,1)     NOT NULL,
    DEPENDS_ON_STEP_ID  ARRAY,
    IS_ACTIVE           BOOLEAN         DEFAULT TRUE,
    IS_RESTARTABLE      BOOLEAN         DEFAULT TRUE,
    RETRY_COUNT         NUMBER(2)       DEFAULT 3,
    RETRY_DELAY_SECONDS NUMBER          DEFAULT 60,
    TIMEOUT_MINUTES     NUMBER          DEFAULT 120,
    DESCRIPTION         VARCHAR(500),
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- ENVIRONMENT CONFIGURATION
-- ============================================================
CREATE OR REPLACE TABLE ENV_CONFIG (
    ENVIRONMENT         VARCHAR(20)     NOT NULL PRIMARY KEY,
    SOURCE_DATABASE     VARCHAR(100)    NOT NULL,
    SOURCE_SCHEMA       VARCHAR(100)    NOT NULL,
    WAREHOUSE_NAME      VARCHAR(100)    NOT NULL,
    MAX_PARALLEL_STEPS  NUMBER(2)       DEFAULT 4,
    DQ_REJECT_THRESHOLD NUMBER(5,2)     DEFAULT 5.00,
    ENABLE_NOTIFICATIONS BOOLEAN        DEFAULT FALSE,
    IS_ACTIVE           BOOLEAN         DEFAULT TRUE
);

-- ============================================================
-- NOTIFICATION CONFIGURATION
-- ============================================================
CREATE OR REPLACE TABLE NOTIFICATION_CONFIG (
    NOTIFICATION_ID     NUMBER          IDENTITY(1,1) PRIMARY KEY,
    NOTIFICATION_TYPE   VARCHAR(50)     NOT NULL,
    EVENT_TYPE          VARCHAR(50)     NOT NULL,
    RECIPIENTS          VARCHAR(2000)   NOT NULL,
    SUBJECT_TEMPLATE    VARCHAR(500),
    BODY_TEMPLATE       VARCHAR(4000),
    IS_ACTIVE           BOOLEAN         DEFAULT TRUE,
    INTEGRATION_NAME    VARCHAR(200),
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- DQ_CATEGORY (Data Quality Dimensions)
-- ============================================================
CREATE OR REPLACE TABLE DQ_CATEGORY (
    CATEGORY_ID     NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 NOORDER,
    CATEGORY_NM     STRING,
    CATEGORY_DESC   STRING,
    RECORD_INS_TS   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    RECORD_UPD_TS   TIMESTAMP_NTZ,
    RECORD_INS_BY   STRING DEFAULT CURRENT_USER(),
    RECORD_UPD_BY   STRING
);

-- ============================================================
-- DQ_RULE (Generalized reusable rule expressions)
-- ============================================================
CREATE OR REPLACE TABLE DQ_RULE (
    RULE_ID         NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 NOORDER,
    CATEGORY_ID     INTEGER,
    RULE_CODE       STRING,
    RULE_DESC       STRING,
    RULE_EXP        STRING,
    RULE_CATEGORY   STRING,
    RECORD_INS_TS   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    RECORD_UPD_TS   TIMESTAMP_NTZ,
    RECORD_INS_BY   STRING DEFAULT CURRENT_USER(),
    RECORD_UPD_BY   STRING
);

-- ============================================================
-- DQ_FEED (Column-level rule-to-table mapping)
-- ============================================================
CREATE OR REPLACE TABLE DQ_FEED (
    FEED_ID                     NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 NOORDER,
    LAYER                       VARCHAR(20),
    DOMAIN                      VARCHAR(50),
    RULE_ID                     NUMBER(38,0),
    TABLE_NM                    VARCHAR(100),
    RECORD_KEY_NM               VARCHAR(100),
    INCREMENTAL_DATE_COLUMN     VARCHAR(16777216),
    DQ_RULE_INPUT               VARCHAR(200),
    CRITICALITY_IND             VARCHAR(1),
    ACTIVE_IND                  VARCHAR(1),
    EXECUTION_GROUP             VARCHAR(50),
    DQ_RULE_INPUT_JOIN_TBL      VARCHAR(100),
    DQ_RULE_INPUT_JOIN_COL      VARCHAR(100),
    DQ_RULE_INPUT_WHERE_COL     VARCHAR(100),
    RECORD_INS_TS               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    RECORD_UPD_TS               TIMESTAMP_NTZ,
    RECORD_INS_BY               STRING DEFAULT CURRENT_USER(),
    RECORD_UPD_BY               STRING
);

-- ============================================================
-- DQ_EMAIL (Notification routing by domain)
-- ============================================================
CREATE OR REPLACE TABLE DQ_EMAIL (
    EMAIL_ID        INTEGER NOT NULL PRIMARY KEY,
    DOMAIN          STRING,
    EMAILS          STRING,
    RECORD_INS_TS   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    RECORD_UPD_TS   TIMESTAMP_NTZ,
    RECORD_INS_BY   STRING DEFAULT CURRENT_USER(),
    RECORD_UPD_BY   STRING
);
