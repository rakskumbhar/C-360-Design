-- Seeds all configuration data for DQ categories, rules, feeds, emails, pipeline settings, and raw ingestion tables
-- Co-authored with CoCo
/*=============================================================================
  CLINICIAN-360-DQ-IMPLEMENTATION
  00_CONFIG/003_seed_configuration.sql
  
  Purpose: Inserts seed data into all configuration tables.
=============================================================================*/

USE DATABASE P360_DQ;
USE SCHEMA CONFIG;

-- ============================================================
-- PKG_CONFIG (Pipeline Parameters)
-- ============================================================
INSERT INTO PKG_CONFIG (CONFIG_KEY, CONFIG_VALUE, CONFIG_DATA_TYPE, CONFIG_CATEGORY, DESCRIPTION) VALUES
('PKG_NAME', 'CLINICIAN_360_DQ', 'STRING', 'PIPELINE', 'Package identifier'),
('ENVIRONMENT', 'DEV', 'STRING', 'PIPELINE', 'Current environment'),
('SOURCE_DATABASE', 'P360_DQ', 'STRING', 'PIPELINE', 'Source database'),
('SOURCE_SCHEMA', 'RAW_INGESTION', 'STRING', 'PIPELINE', 'Source schema'),
('DQ_BRONZE_THRESHOLD', '90.00', 'NUMBER', 'DQ', 'Bronze layer DQ fail threshold %'),
('DQ_SILVER_THRESHOLD', '90.00', 'NUMBER', 'DQ', 'Silver layer DQ fail threshold %'),
('ENABLE_DQ_PROFILING', 'TRUE', 'BOOLEAN', 'DQ', 'Run profiling every execution'),
('ENABLE_SCD2', 'TRUE', 'BOOLEAN', 'PIPELINE', 'Enable SCD Type-2 tracking'),
('ENABLE_EMAIL_NOTIFY', 'FALSE', 'BOOLEAN', 'NOTIFICATION', 'Email notification toggle'),
('MAX_RETRY_COUNT', '3', 'NUMBER', 'PIPELINE', 'Default retry attempts'),
('RETRY_DELAY_SECONDS', '60', 'NUMBER', 'PIPELINE', 'Delay between retries');

-- ============================================================
-- PKG_STEP_REGISTRY (Execution Order)
-- ============================================================
--select* from PKG_STEP_REGISTRY

INSERT INTO PKG_STEP_REGISTRY (STEP_ID, STEP_NAME, STEP_LAYER, STEP_PROCEDURE, STEP_ORDER, DEPENDS_ON_STEP_ID, DESCRIPTION)
SELECT 1, 'STG_NPI_REGISTRY', 'BRONZE', 'P360_DQ.BRONZE.SP_STG_NPI_REGISTRY', 1.0, NULL, 'Stage NPI data from RAW to Bronze'
UNION ALL SELECT 2, 'STG_SPECIALTY_TYPE', 'BRONZE', 'P360_DQ.BRONZE.SP_STG_SPECIALTY_TYPE', 1.1, NULL, 'Stage Specialty data from RAW to Bronze'
UNION ALL SELECT 10, 'DQ_CHECK_BRONZE', 'DQ_BRONZE', 'P360_DQ.BRONZE.SP_RUN_DQ_BRONZE', 2.0, ARRAY_CONSTRUCT(1, 2), 'Run DQ checks on all Bronze tables'
UNION ALL SELECT 20, 'LOAD_DIM_PROVIDER', 'SILVER', 'P360_DQ.SILVER.SP_LOAD_DIM_PROVIDER', 3.0, ARRAY_CONSTRUCT(10), 'Load unified provider dimension'
UNION ALL SELECT 30, 'DQ_CHECK_SILVER', 'DQ_SILVER', 'P360_DQ.SILVER.SP_RUN_DQ_SILVER', 4.0, ARRAY_CONSTRUCT(20), 'Run DQ checks on Silver tables'
UNION ALL SELECT 40, 'SCD2_PROVIDER_ATTRIBUTES', 'SILVER', 'P360_DQ.SILVER.SP_SCD2_PROVIDER_ATTRIBUTES', 5.0, ARRAY_CONSTRUCT(30), 'SCD Type-2 tracking'
UNION ALL SELECT 50, 'LOAD_FCT_PROVIDER_360', 'GOLD', 'P360_DQ.GOLD.SP_LOAD_FCT_PROVIDER_360', 6.0, ARRAY_CONSTRUCT(40), 'Build Gold fact table'
UNION ALL SELECT 60, 'AUDIT_REJECT_SUMMARY', 'AUDIT', 'P360_DQ.AUDIT.SP_AUDIT_REJECT_SUMMARY', 7.0, ARRAY_CONSTRUCT(50), 'Aggregate DQ results and notify';

-- ============================================================
-- ENV_CONFIG -- select* from ENV_CONFIG
-- ============================================================
INSERT INTO ENV_CONFIG (ENVIRONMENT, SOURCE_DATABASE, SOURCE_SCHEMA, WAREHOUSE_NAME, MAX_PARALLEL_STEPS, DQ_REJECT_THRESHOLD, ENABLE_NOTIFICATIONS) VALUES
('DEV', 'P360_DQ', 'RAW_INGESTION', 'COMPUTE_WH', 4, 80.00, FALSE),
('QA', 'P360_DQ', 'RAW_INGESTION', 'COMPUTE_WH', 4, 5.00, TRUE),
('PROD', 'P360_DQ', 'RAW_INGESTION', 'COMPUTE_WH', 8, 5.00, TRUE);

--select* from ENV_CONFIG

-- ============================================================
-- DQ_CATEGORY (7 Data Quality Dimensions)
-- ============================================================
INSERT INTO DQ_CATEGORY (CATEGORY_ID, CATEGORY_NM, CATEGORY_DESC) VALUES
(1, 'Accuracy', 'The degree to which data correctly reflects the real-world situation it represents.'),
(2, 'Completeness', 'The extent to which all required data is present.'),
(3, 'Consistency', 'The uniformity of data across different datasets or systems.'),
(4, 'Uniqueness', 'Ensuring that each record is distinct and not duplicated.'),
(5, 'Timeliness', 'The relevance of data in relation to the time it is needed.'),
(6, 'Validity', 'The degree to which data conforms to defined formats or standards.'),
(7, 'Integrity', 'The assurance that data is accurate, consistent, and reliable throughout its lifecycle and is not improperly modified.');

-- ============================================================
-- DQ_RULE (Generic reusable rules)
-- ============================================================
INSERT INTO   DQ_RULE (RULE_ID, CATEGORY_ID, RULE_CODE, RULE_DESC, RULE_EXP, RULE_CATEGORY) VALUES
(1, 4, 'GN_Duplicate', 'Check columns has no duplicates',
 'CASE WHEN (ROW_NUMBER() OVER(PARTITION BY ${INPUTN} ORDER BY 1))>1 THEN ''FAIL'' ELSE ''PASS'' END AS RESULT FROM ${TABLE_NAME} a WHERE ${INCREMENTAL_DATE_COLUMN} QUALIFY RESULT = ''FAIL''',
 'COMPLEX'),
(2, 2, 'GN_NotNull', 'Check mandatory fields are not null',
 'CASE WHEN TRIM(COALESCE(${INPUT1},''''))= '''' THEN ''FAIL'' ELSE ''PASS'' END',
 'SIMPLE'),
(3, 2, 'GN_LOOKUP', 'Check code exists in reference table',
 '''FAIL'' AS RESULT FROM ${JOINTBL1} a LEFT JOIN ${JOINTBL2} b ON a.${JOINCOL1} = b.${JOINCOL2} WHERE ${INCREMENTAL_DATE_COLUMN} AND b.${WHERECOL1} IS NULL',
 'COMPLEX'),
(4, 6, 'GN_Length2', 'Validate string length is 2 chars',
 'CASE WHEN LENGTH(TRIM(TO_CHAR(${INPUT1}))) <> 2 THEN ''FAIL'' ELSE ''PASS'' END',
 'SIMPLE'),
(5, 6, 'GN_Length9', 'Validate string length is 9 chars',
 'CASE WHEN LENGTH(TRIM(TO_CHAR(${INPUT1}))) <> 9 THEN ''FAIL'' ELSE ''PASS'' END',
 'SIMPLE'),
(6, 6, 'GN_Length10', 'Validate string length is 10 chars',
 'CASE WHEN LENGTH(TRIM(TO_CHAR(${INPUT1}))) <> 10 THEN ''FAIL'' ELSE ''PASS'' END',
 'SIMPLE'),
(7, 6, 'GN_FormatTIN', 'Validate xxx-xx-xxxx format',
 'CASE WHEN SUBSTR(${INPUT1},4,1)=''-'' AND SUBSTR(${INPUT1},7,1)=''-'' AND LENGTH(REPLACE(${INPUT1},''-'',''''))=9 THEN ''PASS'' ELSE ''FAIL'' END',
 'SIMPLE'),
(8, 1, 'GN_UpperCase', 'Check field is in upper case',
 'CASE WHEN ${INPUT1} <> UPPER(${INPUT1}) THEN ''FAIL'' ELSE ''PASS'' END',
 'SIMPLE'),
(9, 5, 'GN_Timeliness', 'Validate data not stale (within 365 days)',
 'CASE WHEN DATEDIFF(''DAY'', ${INPUT1}, CURRENT_DATE()) > 365 THEN ''FAIL'' ELSE ''PASS'' END',
 'SIMPLE'),
(10, 7, 'GN_RefIntegrity', 'Referential integrity cross-table check',
 '''FAIL'' AS RESULT FROM ${JOINTBL1} a LEFT JOIN ${JOINTBL2} b ON a.${JOINCOL1} = b.${JOINCOL2} WHERE ${INCREMENTAL_DATE_COLUMN} AND b.${WHERECOL1} IS NULL',
 'COMPLEX'),
(101, 6, 'GN_InList', 'Validate value is in allowed list',
 'CASE WHEN ${INPUT1} NOT IN (${INPUT2}) THEN ''FAIL'' ELSE ''PASS'' END',
 'SIMPLE');

-- ============================================================
-- DQ_FEED (Bronze Layer)
-- ============================================================
INSERT INTO DQ_FEED (FEED_ID, LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM, INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP) VALUES
(1, 'BRONZE', 'PROVIDERS', 2, 'STG_NPI_REGISTRY', 'NPI_SK', 'LOAD_DT', 'NPI_NUMBER', 'Y', 'Y', 'GROUP_A'),
(2, 'BRONZE', 'PROVIDERS', 2, 'STG_NPI_REGISTRY', 'NPI_SK', 'LOAD_DT', 'PROVIDER_NAME', 'Y', 'Y', 'GROUP_A'),
(3, 'BRONZE', 'PROVIDERS', 4, 'STG_NPI_REGISTRY', 'NPI_SK', 'LOAD_DT', 'STATE', 'Y', 'Y', 'GROUP_A'),
(4, 'BRONZE', 'PROVIDERS', 6, 'STG_NPI_REGISTRY', 'NPI_SK', 'LOAD_DT', 'NPI_NUMBER', 'Y', 'Y', 'GROUP_A'),
(5, 'BRONZE', 'PROVIDERS', 1, 'STG_NPI_REGISTRY', 'NPI_SK', 'LOAD_DT', 'NPI_NUMBER', 'Y', 'Y', 'GROUP_A'),
(6, 'BRONZE', 'PROVIDERS', 2, 'STG_NPI_REGISTRY', 'NPI_SK', 'LOAD_DT', 'PHONE', 'N', 'Y', 'GROUP_A'),
(7, 'BRONZE', 'PROVIDERS', 2, 'STG_NPI_REGISTRY', 'NPI_SK', 'LOAD_DT', 'TAXONOMY_CODE', 'N', 'Y', 'GROUP_A'),
(8, 'BRONZE', 'PROVIDERS', 2, 'STG_SPECIALTY_TYPE', 'SPECIALTY_SK', 'LOAD_DT', 'SPECIALTY_CODE', 'Y', 'Y', 'GROUP_A'),
(9, 'BRONZE', 'PROVIDERS', 2, 'STG_SPECIALTY_TYPE', 'SPECIALTY_SK', 'LOAD_DT', 'SPECIALTY_NAME', 'Y', 'Y', 'GROUP_A'),
(10, 'BRONZE', 'PROVIDERS', 4, 'STG_SPECIALTY_TYPE', 'SPECIALTY_SK', 'LOAD_DT', 'STATE', 'Y', 'Y', 'GROUP_A'),
(11, 'BRONZE', 'PROVIDERS', 2, 'STG_SPECIALTY_TYPE', 'SPECIALTY_SK', 'LOAD_DT', 'EXPIRATION_DATE', 'N', 'Y', 'GROUP_A'),
(12, 'BRONZE', 'PROVIDERS', 2, 'STG_SPECIALTY_TYPE', 'SPECIALTY_SK', 'LOAD_DT', 'BOARD_CERTIFICATION_REQ', 'N', 'Y', 'GROUP_A');

-- ============================================================
-- DQ_FEED (Silver Layer)
-- ============================================================
INSERT INTO DQ_FEED (FEED_ID, LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM, INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP) VALUES
(101, 'SILVER', 'PROVIDERS', 2, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'PROVIDER_NPI', 'Y', 'Y', 'GROUP_A'),
(102, 'SILVER', 'PROVIDERS', 8, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'PROVIDER_FIRST_NAME', 'Y', 'Y', 'GROUP_A'),
(103, 'SILVER', 'PROVIDERS', 8, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'PROVIDER_LAST_NAME', 'Y', 'Y', 'GROUP_A'),
(104, 'SILVER', 'PROVIDERS', 2, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'ADDRESS_LINE_1', 'Y', 'Y', 'GROUP_A'),
(105, 'SILVER', 'PROVIDERS', 2, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'CITY', 'Y', 'Y', 'GROUP_A'),
(106, 'SILVER', 'PROVIDERS', 4, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'STATE', 'Y', 'Y', 'GROUP_A'),
(107, 'SILVER', 'PROVIDERS', 6, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'PROVIDER_NPI', 'Y', 'Y', 'GROUP_A'),
(108, 'SILVER', 'PROVIDERS', 5, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'PROVIDER_TIN', 'Y', 'N', 'GROUP_A'),
(109, 'SILVER', 'PROVIDERS', 7, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'PROVIDER_TIN', 'Y', 'Y', 'GROUP_A'),
(110, 'SILVER', 'PROVIDERS', 1, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'PROVIDER_NPI', 'Y', 'Y', 'GROUP_A'),
(203, 'SILVER', 'PROVIDERS', 2, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'PHONE', 'N', 'Y', 'GROUP_A');

-- ============================================================
-- DQ_FEED (GN_InList rules - Bronze & Silver)
-- ============================================================
INSERT INTO DQ_FEED (FEED_ID, LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM, INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, DQ_RULE_INPUT_WHERE_COL, CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP) VALUES
(201, 'BRONZE', 'PROVIDERS', 101, 'STG_NPI_REGISTRY', 'NPI_SK', 'LOAD_DT', 'CREDENTIAL', '''MD'',''DO'',''NP'',''PA'',''RN'',''APRN'',''DPM'',''DDS'',''PhD'',''PharmD'',''OD'',''DC''', 'Y', 'Y', 'GROUP_A'),
(202, 'SILVER', 'PROVIDERS', 101, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'CREDENTIAL', '''MD'',''DO'',''NP'',''PA'',''RN'',''APRN'',''DPM'',''DDS'',''PhD'',''PharmD'',''OD'',''DC''', 'Y', 'Y', 'GROUP_A'),
(301, 'SILVER', 'PROVIDERS', 101, 'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'GENDER', '''M'',''F''', 'N', 'Y', 'GROUP_A');

-- ============================================================
-- DQ_EMAIL (Notification recipients by domain)
-- ============================================================
INSERT INTO  DQ_EMAIL (EMAIL_ID, DOMAIN, EMAILS) VALUES
(1, 'PROVIDERS', 'abc@upmc.com,devang@citiustech.com,rakesh@citiustech.com'),
(2, 'CLAIMS', 'selva@xyz.com'),
(3, 'CLINICS', 'vekat@xyz.com,juan@xyz.com');




