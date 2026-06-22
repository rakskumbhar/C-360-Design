-- Creates target tables for RAW, Bronze, Silver, Gold layers with test data
/*=============================================================================
  CLINICIAN-360-DQ-IMPLEMENTATION
  01_FRAMEWORK/003_target_tables.sql
  
  Purpose: Creates all layer tables (RAW, Bronze, Silver, Gold, SCD2)
           and inserts 15 test records per Bronze source table.
=============================================================================*/

USE DATABASE P360_DQ;

-- ============================================================
-- RAW LAYER TABLES
-- ============================================================
USE SCHEMA RAW_INGESTION;

CREATE OR REPLACE TABLE RAW_NPI_REGISTRY (
    NPI_NUMBER              VARCHAR(10),
    PROVIDER_FIRST_NAME     VARCHAR(100),
    PROVIDER_LAST_NAME      VARCHAR(100),
    PROVIDER_NAME           VARCHAR(200),
    CREDENTIAL              VARCHAR(50),
    GENDER                  VARCHAR(1),
    STATE                   VARCHAR(10),
    ZIP_CODE                VARCHAR(10),
    TAXONOMY_CODE           VARCHAR(20),
    PHONE                   VARCHAR(15),
    NPI_DEACTIVATION_FLAG   VARCHAR(1),
    ENUMERATION_DATE        DATE,
    SOURCE_SYSTEM           VARCHAR(50),
    ADDRESS_LINE_1          VARCHAR(200),
    CITY                    VARCHAR(100),
    PROVIDER_TIN            VARCHAR(11),
    _LOADED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW_SPECIALTY_TYPE (
    SPECIALTY_CODE          VARCHAR(20),
    SPECIALTY_NAME          VARCHAR(200),
    SPECIALTY_CATEGORY      VARCHAR(100),
    BOARD_CERTIFICATION_REQ VARCHAR(1),
    STATE                   VARCHAR(10),
    EFFECTIVE_DATE          DATE,
    EXPIRATION_DATE         DATE,
    SOURCE_SYSTEM           VARCHAR(50),
    _LOADED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- BRONZE LAYER TABLES
-- ============================================================
USE SCHEMA BRONZE;

CREATE OR REPLACE TABLE STG_NPI_REGISTRY (
    NPI_SK                  NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
    NPI_NUMBER              VARCHAR(10),
    PROVIDER_FIRST_NAME     VARCHAR(100),
    PROVIDER_LAST_NAME      VARCHAR(100),
    PROVIDER_NAME           VARCHAR(200),
    CREDENTIAL              VARCHAR(50),
    GENDER                  VARCHAR(1),
    STATE                   VARCHAR(50),
    ZIP_CODE                VARCHAR(10),
    TAXONOMY_CODE           VARCHAR(20),
    PHONE                   VARCHAR(15),
    NPI_DEACTIVATION_FLAG   VARCHAR(1),
    ENUMERATION_DATE        DATE,
    SOURCE_SYSTEM           VARCHAR(50),
    ADDRESS_LINE_1          VARCHAR(200),
    CITY                    VARCHAR(100),
    PROVIDER_TIN            VARCHAR(11),
    LOAD_DT                 TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATE_DT               TIMESTAMP_NTZ,
    ROW_STATUS              VARCHAR(20) DEFAULT 'ACTIVE',
    DQ_STATUS               VARCHAR(20),
    RECORD_HASH             VARCHAR(64),
    JOB_ID                  VARCHAR(36),
    _SOURCE_LOADED_AT       TIMESTAMP_NTZ,
    _RUN_ID                 VARCHAR(36)
);

CREATE OR REPLACE TABLE STG_SPECIALTY_TYPE (
    SPECIALTY_SK            NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
    SPECIALTY_CODE          VARCHAR(20),
    SPECIALTY_NAME          VARCHAR(200),
    SPECIALTY_CATEGORY      VARCHAR(100),
    BOARD_CERTIFICATION_REQ VARCHAR(1),
    STATE                   VARCHAR(50),
    EFFECTIVE_DATE          DATE,
    EXPIRATION_DATE         DATE,
    SOURCE_SYSTEM           VARCHAR(50),
    LOAD_DT                 TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATE_DT               TIMESTAMP_NTZ,
    ROW_STATUS              VARCHAR(20) DEFAULT 'ACTIVE',
    DQ_STATUS               VARCHAR(20),
    RECORD_HASH             VARCHAR(64),
    JOB_ID                  VARCHAR(36),
    _SOURCE_LOADED_AT       TIMESTAMP_NTZ,
    _RUN_ID                 VARCHAR(36)
);

-- ============================================================
-- SILVER LAYER TABLES
-- ============================================================
USE SCHEMA SILVER;

CREATE OR REPLACE TABLE DIM_PROVIDER (
    PROVIDER_SK             NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
    PROVIDER_BK             VARCHAR(10),
    PROVIDER_NAME           VARCHAR(200),
    PROVIDER_FIRST_NAME     VARCHAR(100),
    PROVIDER_LAST_NAME      VARCHAR(100),
    CREDENTIAL              VARCHAR(50),
    GENDER                  VARCHAR(1),
    PRIMARY_SPECIALTY       VARCHAR(200),
    SPECIALTY_CATEGORY      VARCHAR(100),
    STATE                   VARCHAR(50),
    ZIP_CODE                VARCHAR(10),
    PHONE                   VARCHAR(15),
    ADDRESS_LINE_1          VARCHAR(200),
    CITY                    VARCHAR(100),
    PROVIDER_TIN            VARCHAR(11),
    PROVIDER_NPI            VARCHAR(10),
    DELETION_FLAG           VARCHAR(1) DEFAULT 'N',
    SOURCE_SYSTEM           VARCHAR(50),
    LOAD_DT                 TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATE_DT               TIMESTAMP_NTZ,
    ROW_STATUS              VARCHAR(20) DEFAULT 'ACTIVE',
    DQ_STATUS               VARCHAR(20),
    RECORD_HASH             VARCHAR(64),
    JOB_ID                  VARCHAR(36),
    _RUN_ID                 VARCHAR(36)
);

CREATE OR REPLACE TABLE SCD2_PROVIDER_ATTRIBUTES (
    SCD_KEY                 VARCHAR(64) NOT NULL PRIMARY KEY,
    PROVIDER_BK             VARCHAR(10),
    PROVIDER_NAME           VARCHAR(200),
    CREDENTIAL              VARCHAR(50),
    STATE                   VARCHAR(50),
    ZIP_CODE                VARCHAR(10),
    PRIMARY_SPECIALTY       VARCHAR(200),
    PROVIDER_STATUS         VARCHAR(20),
    _VALID_FROM             TIMESTAMP_NTZ NOT NULL,
    _VALID_TO               TIMESTAMP_NTZ NOT NULL DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    _IS_CURRENT             BOOLEAN DEFAULT TRUE,
    _HASH_DIFF              VARCHAR(64),
    _RUN_ID                 VARCHAR(36)
);

-- ============================================================
-- GOLD LAYER TABLES
-- ============================================================
USE SCHEMA GOLD;

CREATE OR REPLACE TABLE FCT_PROVIDER_360 (
    PROVIDER_SK             NUMBER(38,0),
    PROVIDER_NPI            VARCHAR(10),
    PROVIDER_NAME           VARCHAR(200),
    CREDENTIAL              VARCHAR(50),
    GENDER_DESC             VARCHAR(10),
    PRIMARY_SPECIALTY       VARCHAR(200),
    SPECIALTY_CATEGORY      VARCHAR(100),
    STATE                   VARCHAR(50),
    ZIP_CODE                VARCHAR(10),
    ADDRESS_LINE_1          VARCHAR(200),
    CITY                    VARCHAR(100),
    PROVIDER_STATUS         VARCHAR(20),
    IS_CURRENT              BOOLEAN,
    VALID_FROM              TIMESTAMP_NTZ,
    VALID_TO                TIMESTAMP_NTZ,
    _LOADED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _RUN_ID                 VARCHAR(36)
);

-- ============================================================
-- INSERT TEST DATA INTO RAW TABLES (15 records each)
-- ============================================================

-- RAW_NPI_REGISTRY (Source: P360_DQ.RAW_INGESTION)
-- ============================================================
USE SCHEMA RAW_INGESTION;

INSERT INTO RAW_NPI_REGISTRY (NPI_NUMBER, PROVIDER_FIRST_NAME, PROVIDER_LAST_NAME, PROVIDER_NAME, CREDENTIAL, GENDER, STATE, ZIP_CODE, TAXONOMY_CODE, PHONE, NPI_DEACTIVATION_FLAG, ENUMERATION_DATE, SOURCE_SYSTEM, _LOADED_AT, ADDRESS_LINE_1, CITY, PROVIDER_TIN) VALUES
('1234567890', 'JOHN', 'SMITH', 'JOHN SMITH MD', 'MD', 'M', 'PA', '19101', '207Q00000X', '2155551001', 'N', '2010-01-15', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '123 Main Street', 'Philadelphia', '123-45-6789'),
('2345678901', 'JANE', 'DOE', 'JANE DOE DO', 'DO', 'F', 'NY', '10001', '208000000X', '2125551002', 'N', '2011-03-20', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '456 Oak Avenue', 'New York', '234-56-7890'),
('3456789012', 'ROBERT', 'WILSON', 'ROBERT WILSON NP', 'NP', 'M', 'CA', '90001', '363L00000X', '4155551003', 'N', '2012-06-10', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '789 Pine Blvd', 'Los Angeles', '345-67-8901'),
('4567890123', 'MARIA', 'GARCIA', 'MARIA GARCIA MD', 'MD', 'F', 'TX', '75001', '207R00000X', '2145551004', 'N', '2013-09-05', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '321 Elm Drive', 'Houston', '456-78-9012'),
('5678901234', 'DAVID', 'LEE', 'DAVID LEE DO', 'DO', 'M', 'FL', '33101', '208600000X', '3055551005', 'N', '2014-02-28', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '654 Maple Lane', 'Miami', '567-89-0123'),
('6789012345', 'SARAH', 'JOHNSON', 'SARAH JOHNSON MD', 'MD', 'F', 'IL', '60601', '207Q00000X', '3125551006', 'N', '2015-04-12', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '987 Cedar Court', 'Chicago', '678-90-1234'),
('7890123456', 'MICHAEL', 'BROWN', 'MICHAEL BROWN NP', 'NP', 'M', 'OH', '43001', '363A00000X', '6145551007', 'N', '2016-07-01', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '147 Birch Road', 'Columbus', '789-01-2345'),
('8901234567', 'LISA', 'ANDERSON', 'LISA ANDERSON MD', 'MD', 'F', 'WA', '98101', '207V00000X', '2065551008', 'N', '2017-11-18', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '258 Walnut Way', 'Seattle', '890-12-3456'),
('9012345678', 'JAMES', 'TAYLOR', 'JAMES TAYLOR DO', 'DO', 'M', 'MA', '02101', '208000000X', '6175551009', 'N', '2018-08-22', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '369 Cherry Parkway', 'Boston', '901-23-4567'),
('0123456789', 'EMILY', 'DAVIS', 'EMILY DAVIS MD', 'MD', 'F', 'CO', '80201', '207Q00000X', '3035551010', 'N', '2019-05-30', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '741 Aspen Circle', 'Denver', '012-34-5678'),
(NULL, NULL, NULL, NULL, 'MD', 'M', 'PA', '19102', '207Q00000X', '2155551011', 'N', '2020-01-01', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', NULL, NULL, NULL),
('12345', 'THOMAS', 'CLARK', 'THOMAS CLARK MD', 'MD', 'M', 'PENN', '19103', '207R00000X', '2155551012', 'N', '2020-02-01', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '285 Willow Drive', 'Pittsburgh', 'BADTIN'),
('1111111111', NULL, NULL, '', 'MD', 'M', 'NY', '10002', '208000000X', '2125551013', 'N', '2020-03-01', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '852 Spruce Terrace', 'Buffalo', '111-22-3333'),
('2222222222', 'KAREN', 'WHITE', 'KAREN WHITE NP', 'NP', 'F', 'NJ', '07001', '363L00000X', NULL, 'N', '2020-04-01', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '963 Hickory Path', 'Newark', '222-33-4444'),
('3333333333', 'PETER', 'HALL', 'PETER HALL MD', 'MD', 'M', 'CT', '06001', NULL, '2035551015', 'N', '2020-05-01', 'NPI_REGISTRY', '2026-06-17 21:52:17.950', '174 Poplar Street', 'Hartford', '333-44-5555');

-- ============================================================
-- RAW_SPECIALTY_TYPE (Source: P360_DQ.RAW_INGESTION)
-- ============================================================
INSERT INTO  RAW_SPECIALTY_TYPE (SPECIALTY_CODE, SPECIALTY_NAME, SPECIALTY_CATEGORY, BOARD_CERTIFICATION_REQ, STATE, EFFECTIVE_DATE, EXPIRATION_DATE, SOURCE_SYSTEM, _LOADED_AT) VALUES
('207Q00000X', 'FAMILY MEDICINE', 'Primary Care', 'Y', 'PA', '2010-01-01', '2030-12-31', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('208000000X', 'PEDIATRICS', 'Primary Care', 'Y', 'NY', '2010-01-01', '2030-06-30', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('207R00000X', 'INTERNAL MEDICINE', 'Primary Care', 'Y', 'TX', '2010-01-01', '2028-06-30', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('363L00000X', 'NURSE PRACTITIONER', 'Advanced Practice', 'N', 'CA', '2010-01-01', '2031-06-30', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('208600000X', 'SURGERY', 'Surgical', 'Y', 'FL', '2010-01-01', '2029-12-31', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('207V00000X', 'OBSTETRICS', 'Surgical', 'Y', 'WA', '2010-01-01', '2027-12-31', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('363A00000X', 'PHYSICIAN ASSISTANT', 'Advanced Practice', 'N', 'OH', '2010-01-01', '2030-03-31', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('2084N0400X', 'NEUROLOGY', 'Specialty', 'Y', 'IL', '2010-01-01', '2028-12-31', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('207X00000X', 'ORTHOPEDICS', 'Surgical', 'Y', 'MA', '2010-01-01', '2031-01-01', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('207Y00000X', 'OPHTHALMOLOGY', 'Specialty', 'Y', 'CO', '2010-01-01', '2029-09-30', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
(NULL, 'CARDIOLOGY', 'Specialty', 'Y', 'PA', '2015-01-01', NULL, 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('2086S0129X', 'VASCULAR SURGERY', 'Specialty', 'Y', 'NY', '2015-01-01', NULL, 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('207RC0000X', 'CARDIOVASCULAR', 'Specialty', 'Y', 'TX', '2015-01-01', NULL, 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('208C00000X', 'DERMATOLOGY', 'Specialty', 'Y', 'NJ', '2015-01-01', NULL, 'CMS_TAXONOMY', '2026-06-17 21:52:18.812'),
('207RI0200X', 'INFECTIOUS DISEASE', 'Specialty', 'Y', 'CT', '2015-01-01', '2029-03-15', 'CMS_TAXONOMY', '2026-06-17 21:52:18.812');
