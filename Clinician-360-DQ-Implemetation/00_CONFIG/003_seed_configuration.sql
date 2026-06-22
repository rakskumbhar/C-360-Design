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
INSERT INTO RAW_SPECIALTY_TYPE (SPECIALTY_CODE, SPECIALTY_NAME, SPECIALTY_CATEGORY, BOARD_CERTIFICATION_REQ, STATE, EFFECTIVE_DATE, EXPIRATION_DATE, SOURCE_SYSTEM, _LOADED_AT) VALUES
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
