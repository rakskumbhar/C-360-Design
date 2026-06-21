-- ============================================================================
-- P360_SP END-TO-END VALIDATION & EXECUTION SCRIPTS
-- Database: P360_SP
-- Date: 2026-01-02
-- ============================================================================

-- ############################################################################
-- SECTION 1: PRE-VALIDATION SCRIPTS
-- Run these BEFORE executing any stored procedures to verify setup
-- ############################################################################

-- ============================================================================
-- 1.1 Verify CONFIG tables are populated
-- ============================================================================
SELECT '--- PKG_CONFIG ---' AS section;
SELECT * FROM P360_SP.CONFIG.PKG_CONFIG;

SELECT '--- PKG_STEP_REGISTRY ---' AS section;
SELECT STEP_ID, STEP_NAME, STEP_LAYER, STEP_PROCEDURE, STEP_ORDER, IS_ACTIVE 
FROM P360_SP.CONFIG.PKG_STEP_REGISTRY ORDER BY STEP_ORDER;

SELECT '--- DQ_RULES ---' AS section;
SELECT RULE_ID, RULE_NAME, SOURCE_TABLE, RULE_TYPE, SEVERITY, IS_ACTIVE 
FROM P360_SP.CONFIG.DQ_RULES ORDER BY SOURCE_TABLE, RULE_ID;

SELECT '--- NOTIFICATION_CONFIG ---' AS section;
SELECT * FROM P360_SP.CONFIG.NOTIFICATION_CONFIG;

SELECT '--- ENV_CONFIG ---' AS section;
SELECT * FROM P360_SP.CONFIG.ENV_CONFIG WHERE ENVIRONMENT = 'DEV';


-- redudnadnt value in P360_SP.CONFIG.ENV_CONFIG for DQ_REJECT_THRESHOLD , not useful. correct code
--update config
--update P360_SP.CONFIG.ENV_CONFIG
--set config_value=6.0
--WHERE ENVIRONMENT = 'DEV'
--and config_key='DQ_REJECT_THRESHOLD'
--;
--

--working below
update  P360_SP.CONFIG.PKG_CONFIG
 set config_value=60.0
where config_key='DQ_REJECT_THRESHOLD'
;



-- ============================================================================
-- 1.2 Verify RAW_INGESTION source tables have data (including new incremental)
-- ============================================================================
SELECT '--- SOURCE TABLE COUNTS ---' AS section;
SELECT 'NPI_RAW' AS TABLE_NAME, COUNT(*) AS TOTAL_ROWS, 
       SUM(CASE WHEN _LOADED_AT >= '2026-01-02' THEN 1 ELSE 0 END) AS NEW_INCREMENTAL_ROWS
FROM P360_SP.RAW_INGESTION.NPI_RAW
UNION ALL
SELECT 'PROVIDER_CREDENTIALS_RAW', COUNT(*), 
       SUM(CASE WHEN _LOADED_AT >= '2026-01-02' THEN 1 ELSE 0 END)
FROM P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
UNION ALL
SELECT 'PROVIDER_MASTER_RAW', COUNT(*), 
       SUM(CASE WHEN _LOADED_AT >= '2026-01-02' THEN 1 ELSE 0 END)
FROM P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
UNION ALL
SELECT 'CLAIMS_RAW', COUNT(*), 
       SUM(CASE WHEN _LOADED_AT >= '2026-01-02' THEN 1 ELSE 0 END)
FROM P360_SP.RAW_INGESTION.CLAIMS_RAW
UNION ALL
SELECT 'NETWORK_AFFILIATIONS_RAW', COUNT(*), 
       SUM(CASE WHEN _LOADED_AT >= '2026-01-02' THEN 1 ELSE 0 END)
FROM P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW;

-- ============================================================================
-- 1.3 Preview bad records that SHOULD be rejected by DQ rules
-- ============================================================================
SELECT '--- EXPECTED REJECTS: NPI_RAW ---' AS section;
SELECT NPI_NUMBER, PROVIDER_LAST_NAME_LEGAL, STATUS,
       CASE 
         WHEN NPI_NUMBER IS NULL THEN 'NULL NPI'
         WHEN LENGTH(NPI_NUMBER) != 10 THEN 'NPI LENGTH != 10'
         WHEN TRY_TO_NUMBER(NPI_NUMBER) IS NULL THEN 'NPI NOT NUMERIC'
         WHEN STATUS NOT IN ('A','D') THEN 'INVALID STATUS'
         WHEN PROVIDER_LAST_NAME_LEGAL IS NULL THEN 'NULL LAST NAME'
       END AS EXPECTED_REJECTION_REASON
FROM P360_SP.RAW_INGESTION.NPI_RAW
WHERE NPI_NUMBER IS NULL
   OR LENGTH(NPI_NUMBER) != 10
   OR TRY_TO_NUMBER(NPI_NUMBER) IS NULL
   OR STATUS NOT IN ('A','D')
   OR PROVIDER_LAST_NAME_LEGAL IS NULL;

SELECT '--- EXPECTED REJECTS: CLAIMS_RAW ---' AS section;
SELECT CLAIM_ID, NPI_NUMBER, ALLOWED_AMOUNT, PAID_AMOUNT, CLAIM_STATUS,
       CASE 
         WHEN NPI_NUMBER IS NULL THEN 'NULL NPI'
         WHEN LENGTH(NPI_NUMBER) != 10 THEN 'NPI LENGTH != 10'
         WHEN ALLOWED_AMOUNT < 0 THEN 'NEGATIVE AMOUNT'
         WHEN PAID_AMOUNT > ALLOWED_AMOUNT THEN 'PAID > ALLOWED'
         WHEN CLAIM_STATUS NOT IN ('PAID','DENIED','PENDING','ADJUSTED') THEN 'INVALID STATUS'
       END AS EXPECTED_REJECTION_REASON
FROM P360_SP.RAW_INGESTION.CLAIMS_RAW
WHERE NPI_NUMBER IS NULL
   OR LENGTH(NPI_NUMBER) != 10
   OR ALLOWED_AMOUNT < 0
   OR PAID_AMOUNT > ALLOWED_AMOUNT
   OR CLAIM_STATUS NOT IN ('PAID','DENIED','PENDING','ADJUSTED');

-- ============================================================================
-- 1.4 Verify prior run state (clean slate check)
-- ============================================================================
SELECT '--- PRIOR RUN STATUS ---' AS section;
SELECT RUN_ID, PACKAGE_NAME, RUN_STATUS, START_TIMESTAMP, TOTAL_ROWS_READ, TOTAL_ROWS_REJECTED
FROM P360_SP.AUDIT.PKG_RUN_LOG ORDER BY START_TIMESTAMP DESC LIMIT 5;

SELECT '--- REJECT TABLE STATE (BEFORE) ---' AS section;
SELECT COUNT(*) AS EXISTING_REJECTS FROM P360_SP.REJECT.REJECT_RECORDS;


-- ############################################################################
-- SECTION 2: STEP-BY-STEP SP EXECUTION
-- Execute these in order. Each step includes the individual SP call.
-- MASTER SP (if exists): CALL P360_SP.ORCHESTRATION.SP_RUN_PIPELINE('FULL');
-- ############################################################################

-- ============================================================================
-- 2.0 Initialize a new package run
-- ============================================================================
SET v_run_id = (SELECT UUID_STRING());

CALL P360_SP.CONFIG.SP_LOG_RUN_START($v_run_id, 'FULL', NULL);

-- Verify run started
SELECT * FROM P360_SP.AUDIT.PKG_RUN_LOG WHERE RUN_ID = $v_run_id;

-- ============================================================================
-- 2.1 BRONZE LAYER: Stage raw data with DQ validation
-- Master SP equivalent: SP_RUN_BRONZE_LAYER (if exists in ORCHESTRATION)
-- ============================================================================

-- Step 1: Stage NPI Registry
CALL P360_SP.BRONZE.SP_STG_NPI_REGISTRY($v_run_id, 'FULL');

-- Step 2: Stage Credentialed Providers
CALL P360_SP.BRONZE.SP_STG_CRED_PROVIDERS($v_run_id, 'FULL');

-- Step 3: Stage EMR Providers (Provider Master)
CALL P360_SP.BRONZE.SP_STG_EMR_PROVIDERS($v_run_id, 'FULL');

-- Step 4: Stage Claims Providers
CALL P360_SP.BRONZE.SP_STG_CLAIMS_PROVIDERS($v_run_id, 'FULL');

-- Step 5: Stage Network Affiliations
CALL P360_SP.BRONZE.SP_STG_NETWORK_AFFILIATIONS($v_run_id, 'FULL');

-- ============================================================================
-- 2.2 SILVER LAYER: Unify, deduplicate, enrich
-- Master SP equivalent: SP_RUN_SILVER_LAYER (if exists in ORCHESTRATION)
-- ============================================================================

-- Step 10: Unify providers from all sources
CALL P360_SP.SILVER.SP_INT_PROVIDERS_UNIFIED($v_run_id, 'FULL');

-- Step 11: Deduplicate unified providers
CALL P360_SP.SILVER.SP_INT_PROVIDERS_DEDUPED($v_run_id, 'FULL');

-- Step 12: Process network affiliations
CALL P360_SP.SILVER.SP_INT_NETWORK_AFFILIATIONS($v_run_id, 'FULL');

-- Step 13: SCD Type-2 provider attributes
CALL P360_SP.SILVER.SP_SCD2_PROVIDER_ATTRIBUTES($v_run_id, 'FULL');

-- ============================================================================
-- 2.3 GOLD LAYER: Build business-ready dimensions and facts
-- Master SP equivalent: SP_RUN_GOLD_LAYER (if exists in ORCHESTRATION)
-- ============================================================================

-- Step 20: Build DIM_PROVIDER
CALL P360_SP.GOLD.SP_DIM_PROVIDER($v_run_id, 'FULL');

-- Step 21: Build DIM_PROVIDER_NETWORK
CALL P360_SP.GOLD.SP_DIM_PROVIDER_NETWORK($v_run_id, 'FULL');

-- Step 22: Build FCT_PROVIDER_VISITS
CALL P360_SP.GOLD.SP_FCT_PROVIDER_VISITS($v_run_id, 'FULL');

-- Step 30: Build Provider 360 Summary (OBT)
CALL P360_SP.GOLD.SP_PROVIDER_360_SUMMARY($v_run_id, 'FULL');

-- ============================================================================
-- 2.4 Finalize the package run
-- ============================================================================
CALL P360_SP.CONFIG.SP_LOG_RUN_END($v_run_id, 'COMPLETED');


-- ############################################################################
-- SECTION 3: POST-VALIDATION SCRIPTS
-- Run these AFTER executing all SPs to verify results
-- ############################################################################

-- ============================================================================
-- 3.1 PKG_RUN_LOG - Verify package run completed successfully
-- ============================================================================
SELECT '--- PACKAGE RUN CHECK ---' AS section;
SELECT RUN_ID, PACKAGE_NAME, RUN_MODE, RUN_STATUS, 
       START_TIMESTAMP, END_TIMESTAMP, DURATION_SECONDS,
       TOTAL_ROWS_READ, TOTAL_ROWS_WRITTEN, TOTAL_ROWS_REJECTED,
       TOTAL_STEPS, COMPLETED_STEPS, FAILED_STEP_ID, ERROR_MESSAGE
FROM P360_SP.AUDIT.PKG_RUN_LOG 
WHERE RUN_ID = $v_run_id;

-- ============================================================================
-- 3.2 STEP_RUN_LOG - Verify all steps completed
-- ============================================================================
SELECT '--- STEP RUN LOG ---' AS section;
SELECT STEP_ID, STEP_NAME, STEP_LAYER, STEP_STATUS, 
       DURATION_SECONDS, ROWS_READ, ROWS_WRITTEN, ROWS_REJECTED, 
       REJECT_PERCENTAGE, DQ_PASSED, ERROR_MESSAGE
FROM P360_SP.AUDIT.STEP_RUN_LOG 
WHERE RUN_ID = $v_run_id
ORDER BY STEP_ID;

-- ============================================================================
-- 3.3 DQ_RUN_LOG - Verify DQ evaluations
-- ============================================================================
SELECT '--- DQ RUN LOG ---' AS section;
SELECT DQ_LOG_ID, SOURCE_TABLE, TOTAL_RECORDS, PASSED_RECORDS, REJECTED_RECORDS,
       REJECT_PERCENTAGE, THRESHOLD_EXCEEDED, THRESHOLD_VALUE, 
       RULES_EVALUATED, RULES_FAILED
FROM P360_SP.AUDIT.DQ_RUN_LOG 
WHERE RUN_ID = $v_run_id
ORDER BY EVALUATION_TIMESTAMP;

-- ============================================================================
-- 3.4 REJECT_RECORDS - Verify bad data was rejected
-- ============================================================================
SELECT '--- REJECT RECORDS ---' AS section;
SELECT REJECT_ID, STEP_NAME, SOURCE_TABLE, REJECT_REASONS, RECORD_KEY, SEVERITY
FROM P360_SP.REJECT.REJECT_RECORDS 
WHERE RUN_ID = $v_run_id
ORDER BY REJECTED_AT;

SELECT '--- REJECT SUMMARY ---' AS section;
SELECT * FROM P360_SP.REJECT.REJECT_SUMMARY 
WHERE RUN_ID = $v_run_id;

-- ============================================================================
-- 3.5 SOURCE_ROW_COUNTS - Verify source counts captured
-- ============================================================================
SELECT '--- SOURCE ROW COUNTS ---' AS section;
SELECT COUNT_ID, SOURCE_TABLE, TOTAL_COUNT, INCREMENTAL_COUNT, COUNTED_AT
FROM P360_SP.AUDIT.SOURCE_ROW_COUNTS 
WHERE RUN_ID = $v_run_id
ORDER BY COUNTED_AT;

-- ============================================================================
-- 3.6 ERROR_LOG - Check for any errors
-- ============================================================================
SELECT '--- ERROR LOG ---' AS section;
SELECT * FROM P360_SP.AUDIT.ERROR_LOG 
WHERE RUN_ID = $v_run_id;

-- ============================================================================
-- 3.7 NOTIFICATION_LOG - Check notifications sent
-- ============================================================================
SELECT '--- NOTIFICATION LOG ---' AS section;
SELECT * FROM P360_SP.AUDIT.NOTIFICATION_LOG 
WHERE RUN_ID = $v_run_id;

-- ============================================================================
-- 3.8 Layer-by-layer row count validation
-- ============================================================================
SELECT '--- LAYER ROW COUNTS ---' AS section;
SELECT 'BRONZE' AS LAYER, 'STG_NPI_REGISTRY' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM P360_SP.BRONZE.STG_NPI_REGISTRY
UNION ALL SELECT 'BRONZE', 'STG_CRED_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_CRED_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_EMR_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_EMR_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_CLAIMS_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_CLAIMS_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_NETWORK_AFFILIATIONS', COUNT(*) FROM P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS
UNION ALL SELECT 'SILVER', 'INT_PROVIDERS_UNIFIED', COUNT(*) FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED
UNION ALL SELECT 'SILVER', 'INT_PROVIDERS_DEDUPED', COUNT(*) FROM P360_SP.SILVER.INT_PROVIDERS_DEDUPED
UNION ALL SELECT 'SILVER', 'INT_NETWORK_AFFILIATIONS', COUNT(*) FROM P360_SP.SILVER.INT_NETWORK_AFFILIATIONS
UNION ALL SELECT 'SNAPSHOTS', 'SCD2_PROVIDER_ATTRIBUTES', COUNT(*) FROM P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES
UNION ALL SELECT 'GOLD', 'DIM_PROVIDER', COUNT(*) FROM P360_SP.GOLD.DIM_PROVIDER
UNION ALL SELECT 'GOLD', 'DIM_PROVIDER_NETWORK', COUNT(*) FROM P360_SP.GOLD.DIM_PROVIDER_NETWORK
UNION ALL SELECT 'GOLD', 'FCT_PROVIDER_VISITS', COUNT(*) FROM P360_SP.GOLD.FCT_PROVIDER_VISITS
UNION ALL SELECT 'GOLD', 'PROVIDER_360_SUMMARY', COUNT(*) FROM P360_SP.GOLD.PROVIDER_360_SUMMARY;

-- ============================================================================
-- 3.9 Config tables data validation (confirm all are populated)
-- ============================================================================
SELECT '--- CONFIG TABLE COUNTS ---' AS section;
SELECT 'PKG_CONFIG' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM P360_SP.CONFIG.PKG_CONFIG
UNION ALL SELECT 'PKG_STEP_REGISTRY', COUNT(*) FROM P360_SP.CONFIG.PKG_STEP_REGISTRY
UNION ALL SELECT 'DQ_RULES', COUNT(*) FROM P360_SP.CONFIG.DQ_RULES
UNION ALL SELECT 'NOTIFICATION_CONFIG', COUNT(*) FROM P360_SP.CONFIG.NOTIFICATION_CONFIG
UNION ALL SELECT 'ENV_CONFIG', COUNT(*) FROM P360_SP.CONFIG.ENV_CONFIG;

-- ============================================================================
-- 3.10 Data Quality Summary - Compare expected vs actual rejects
-- ============================================================================
SELECT '--- DQ VALIDATION SUMMARY ---' AS section;
SELECT 
    SOURCE_TABLE,
    TOTAL_RECORDS,
    PASSED_RECORDS,
    REJECTED_RECORDS,
    REJECT_PERCENTAGE,
    THRESHOLD_VALUE,
    CASE WHEN THRESHOLD_EXCEEDED THEN 'BREACHED' ELSE 'WITHIN LIMITS' END AS THRESHOLD_STATUS
FROM P360_SP.AUDIT.DQ_RUN_LOG
WHERE RUN_ID = $v_run_id
ORDER BY SOURCE_TABLE;


-- ############################################################################
-- SECTION 4: INCREMENTAL MODE TEST
-- Run AFTER a successful FULL mode run. Only new records (loaded after the
-- high-water mark from the FULL run) will be picked up.
-- ############################################################################

-- ============================================================================
-- 4.1 PRE-INCREMENTAL: Capture current state (before inserting new data)
-- ============================================================================
SELECT '--- PRE-INCREMENTAL STATE ---' AS section;
SELECT 'BRONZE' AS LAYER, 'STG_NPI_REGISTRY' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM P360_SP.BRONZE.STG_NPI_REGISTRY
UNION ALL SELECT 'BRONZE', 'STG_CRED_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_CRED_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_EMR_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_EMR_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_CLAIMS_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_CLAIMS_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_NETWORK_AFFILIATIONS', COUNT(*) FROM P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS
UNION ALL SELECT 'SILVER', 'INT_PROVIDERS_UNIFIED', COUNT(*) FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED
UNION ALL SELECT 'SILVER', 'INT_PROVIDERS_DEDUPED', COUNT(*) FROM P360_SP.SILVER.INT_PROVIDERS_DEDUPED
UNION ALL SELECT 'SILVER', 'INT_NETWORK_AFFILIATIONS', COUNT(*) FROM P360_SP.SILVER.INT_NETWORK_AFFILIATIONS
UNION ALL SELECT 'GOLD', 'DIM_PROVIDER', COUNT(*) FROM P360_SP.GOLD.DIM_PROVIDER
UNION ALL SELECT 'GOLD', 'DIM_PROVIDER_NETWORK', COUNT(*) FROM P360_SP.GOLD.DIM_PROVIDER_NETWORK
UNION ALL SELECT 'GOLD', 'FCT_PROVIDER_VISITS', COUNT(*) FROM P360_SP.GOLD.FCT_PROVIDER_VISITS
UNION ALL SELECT 'GOLD', 'PROVIDER_360_SUMMARY', COUNT(*) FROM P360_SP.GOLD.PROVIDER_360_SUMMARY;

-- ============================================================================
-- 4.2 Insert NEW incremental records (simulating a fresh data load)
--     _LOADED_AT = '2026-06-11 08:00:00' to be AFTER the FULL run's HWM
--     Mix of good records + bad records for DQ rejection testing
-- ============================================================================

-- NPI_RAW: 3 good + 2 bad
INSERT INTO P360_SP.RAW_INGESTION.NPI_RAW (NPI_NUMBER, PROVIDER_FIRST_NAME, PROVIDER_LAST_NAME_LEGAL, PROVIDER_CREDENTIAL_TEXT, PROVIDER_GENDER_CODE, ENTITY_TYPE_CODE, SOLE_PROPRIETOR, ENUMERATION_DATE, LAST_UPDATE_DATE, NPI_DEACTIVATION_DATE, NPI_REACTIVATION_DATE, STATUS, _LOADED_AT)
SELECT '6611223344', 'Thomas', 'Wilson', 'MD', 'M', '1', 'N', '2023-02-14', '2026-06-11', NULL, NULL, 'A', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT '7722334455', 'Angela', 'Garcia', 'DO', 'F', '1', 'N', '2021-08-10', '2026-06-11', NULL, NULL, 'A', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT '8833445566', 'Kevin', 'Lee', 'PA', 'M', '1', 'Y', '2019-12-01', '2026-06-11', NULL, NULL, 'A', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT NULL, 'NoNPI', 'Incremental', 'MD', 'F', '1', 'N', '2024-01-01', '2026-06-11', NULL, NULL, 'A', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT '99001122XX', 'BadFormat', 'Incremental', 'DO', 'M', '1', 'N', '2024-03-01', '2026-06-11', NULL, NULL, 'Z', '2026-06-11 08:00:00'::TIMESTAMP_NTZ;

-- PROVIDER_CREDENTIALS_RAW: 3 good + 2 bad
INSERT INTO P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW (PROVIDER_ID, NPI_NUMBER, SPECIALTY_CODE, SPECIALTY_DESCRIPTION, BOARD_CERTIFICATION, CREDENTIAL_STATUS, CREDENTIAL_EFFECTIVE_DATE, CREDENTIAL_EXPIRY_DATE, PRIMARY_TAXONOMY_CODE, _LOADED_AT)
SELECT 'CRED-021', '6611223344', '208D00000X', 'General Practice', 'ABIM Board Certified', 'ACTIVE', '2024-01-01', '2027-01-01', '208D00000X', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'CRED-022', '7722334455', '207R00000X', 'Internal Medicine', 'ABIM Board Certified', 'ACTIVE', '2023-06-01', '2026-06-01', '207R00000X', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'CRED-023', '8833445566', '363A00000X', 'Physician Assistant', 'NCCPA Certified', 'ACTIVE', '2024-03-01', '2027-03-01', '363A00000X', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'CRED-024', NULL, '208D00000X', 'General Practice', 'None', 'ACTIVE', '2024-01-01', '2027-01-01', '208D00000X', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'CRED-025', '9900112233', '207Q00000X', 'Family Medicine', 'ABFM', 'ACTIVE', '2026-01-01', '2024-01-01', '207Q00000X', '2026-06-11 08:00:00'::TIMESTAMP_NTZ;

-- PROVIDER_MASTER_RAW: 3 good + 2 bad
INSERT INTO P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW (PROVIDER_ID, NPI_NUMBER, FACILITY_NAME, ADDRESS_LINE_1, ADDRESS_LINE_2, CITY, STATE_CODE, ZIP_CODE, PHONE_NUMBER, ACCEPTING_NEW_PATIENTS, PROVIDER_STATUS, UPDATED_AT, _LOADED_AT)
SELECT 'EMR-021', '6611223344', 'Wilson Family Practice', '111 Oak Ln', 'Suite 1', 'Nashville', 'TN', '37201', '615-555-1111', TRUE, 'ACTIVE', '2026-06-11 09:00:00'::TIMESTAMP_NTZ, '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'EMR-022', '7722334455', 'Garcia Internal Med', '222 Maple Dr', NULL, 'Charlotte', 'NC', '28201', '704-555-2222', TRUE, 'ACTIVE', '2026-06-11 10:00:00'::TIMESTAMP_NTZ, '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'EMR-023', '8833445566', 'Lee PA Group', '333 Pine St', NULL, 'Richmond', 'VA', '23219', '804-555-3333', TRUE, 'ACTIVE', '2026-06-11 11:00:00'::TIMESTAMP_NTZ, '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'EMR-024', NULL, 'Null NPI Clinic Incr', '444 Null Ave', NULL, 'Tampa', 'FL', '33601', '813-555-4444', TRUE, 'ACTIVE', '2026-06-11 08:00:00'::TIMESTAMP_NTZ, '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'EMR-025', '9900112233', 'Terminated Provider', '555 End Rd', NULL, 'Reno', 'NV', '89501', '775-555-5555', FALSE, 'TERMINATED', '2026-06-11 08:00:00'::TIMESTAMP_NTZ, '2026-06-11 08:00:00'::TIMESTAMP_NTZ;

-- CLAIMS_RAW: 3 good + 2 bad
INSERT INTO P360_SP.RAW_INGESTION.CLAIMS_RAW (CLAIM_ID, NPI_NUMBER, PATIENT_ID, SERVICE_DATE, PROCEDURE_CODE, DIAGNOSIS_CODE, ALLOWED_AMOUNT, PAID_AMOUNT, CLAIM_STATUS, NETWORK_STATUS, _LOADED_AT)
SELECT 'CLM-024', '6611223344', 'PAT-301', '2026-01-02', '99213', 'Z00.00', 175.00, 140.00, 'PAID', 'IN_NETWORK', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'CLM-025', '7722334455', 'PAT-302', '2026-01-02', '99214', 'I10', 225.00, 180.00, 'PAID', 'IN_NETWORK', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'CLM-026', '8833445566', 'PAT-303', '2026-06-11', '99215', 'M54.5', 300.00, 240.00, 'PENDING', 'IN_NETWORK', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'CLM-027', NULL, 'PAT-304', '2026-06-11', '99213', 'J06.9', 150.00, 120.00, 'PAID', 'IN_NETWORK', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'CLM-028', '9900112233', 'PAT-305', '2026-06-11', '99214', 'E11.9', 200.00, 350.00, 'PAID', 'IN_NETWORK', '2026-06-11 08:00:00'::TIMESTAMP_NTZ;

-- NETWORK_AFFILIATIONS_RAW: 3 good + 2 bad
INSERT INTO P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW (NETWORK_AFFILIATION_ID, NPI_NUMBER, NETWORK_NAME, NETWORK_TIER, PARTICIPATION_STATUS, EFFECTIVE_DATE, TERMINATION_DATE, PAR_AGREEMENT_TYPE, _LOADED_AT)
SELECT 'NET-021', '6611223344', 'Humana PPO', 'TIER_1', 'PARTICIPATING', '2026-01-01', NULL, 'FULL', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'NET-022', '7722334455', 'Kaiser HMO', 'TIER_2', 'PARTICIPATING', '2025-06-01', NULL, 'FULL', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'NET-023', '8833445566', 'Tricare', 'TIER_1', 'PARTICIPATING', '2025-09-01', NULL, 'PARTIAL', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'NET-024', NULL, 'No NPI Network Incr', 'TIER_1', 'PARTICIPATING', '2025-01-01', NULL, 'FULL', '2026-06-11 08:00:00'::TIMESTAMP_NTZ
UNION ALL SELECT 'NET-025', '9900112233', 'Bad Status Incr', 'TIER_1', 'EXPIRED', '2025-01-01', NULL, 'FULL', '2026-06-11 08:00:00'::TIMESTAMP_NTZ;

-- ============================================================================
-- 4.3 INCREMENTAL RUN: Execute pipeline in INCREMENTAL mode
--     Only records with _LOADED_AT > HWM (from FULL run) will be processed
-- ============================================================================
SET v_run_id_incr = (SELECT UUID_STRING());

CALL P360_SP.CONFIG.SP_LOG_RUN_START($v_run_id_incr, 'INCREMENTAL', NULL);

-- Verify incremental run started
SELECT * FROM P360_SP.AUDIT.PKG_RUN_LOG WHERE RUN_ID = $v_run_id_incr;

-- ============================================================================
-- 4.3.1 BRONZE LAYER (INCREMENTAL)
-- Master SP equivalent: SP_RUN_BRONZE_LAYER (if exists in ORCHESTRATION)
-- ============================================================================

-- Step 1: Stage NPI Registry (incremental)
CALL P360_SP.BRONZE.SP_STG_NPI_REGISTRY($v_run_id_incr, 'INCREMENTAL');

-- Step 2: Stage Credentialed Providers (incremental)
CALL P360_SP.BRONZE.SP_STG_CRED_PROVIDERS($v_run_id_incr, 'INCREMENTAL');

-- Step 3: Stage EMR Providers (incremental)
CALL P360_SP.BRONZE.SP_STG_EMR_PROVIDERS($v_run_id_incr, 'INCREMENTAL');

-- Step 4: Stage Claims Providers (incremental)
CALL P360_SP.BRONZE.SP_STG_CLAIMS_PROVIDERS($v_run_id_incr, 'INCREMENTAL');

-- Step 5: Stage Network Affiliations (incremental)
CALL P360_SP.BRONZE.SP_STG_NETWORK_AFFILIATIONS($v_run_id_incr, 'INCREMENTAL');

-- ============================================================================
-- 4.3.2 SILVER LAYER (INCREMENTAL)
-- Master SP equivalent: SP_RUN_SILVER_LAYER (if exists in ORCHESTRATION)
-- ============================================================================

-- Step 10: Unify providers (incremental)
CALL P360_SP.SILVER.SP_INT_PROVIDERS_UNIFIED($v_run_id_incr, 'INCREMENTAL');

-- Step 11: Deduplicate providers (incremental)
CALL P360_SP.SILVER.SP_INT_PROVIDERS_DEDUPED($v_run_id_incr, 'INCREMENTAL');

-- Step 12: Process network affiliations (incremental)
CALL P360_SP.SILVER.SP_INT_NETWORK_AFFILIATIONS($v_run_id_incr, 'INCREMENTAL');

-- Step 13: SCD2 provider attributes (incremental - merges new changes)
CALL P360_SP.SILVER.SP_SCD2_PROVIDER_ATTRIBUTES($v_run_id_incr, 'INCREMENTAL');

-- ============================================================================
-- 4.3.3 GOLD LAYER (INCREMENTAL)
-- Master SP equivalent: SP_RUN_GOLD_LAYER (if exists in ORCHESTRATION)
-- ============================================================================

-- Step 20: Build DIM_PROVIDER (incremental)
CALL P360_SP.GOLD.SP_DIM_PROVIDER($v_run_id_incr, 'INCREMENTAL');

-- Step 21: Build DIM_PROVIDER_NETWORK (incremental)
CALL P360_SP.GOLD.SP_DIM_PROVIDER_NETWORK($v_run_id_incr, 'INCREMENTAL');

-- Step 22: Build FCT_PROVIDER_VISITS (incremental)
CALL P360_SP.GOLD.SP_FCT_PROVIDER_VISITS($v_run_id_incr, 'INCREMENTAL');

-- Step 30: Build Provider 360 Summary (incremental)
CALL P360_SP.GOLD.SP_PROVIDER_360_SUMMARY($v_run_id_incr, 'INCREMENTAL');

-- ============================================================================
-- 4.3.4 Finalize incremental run
-- ============================================================================
CALL P360_SP.CONFIG.SP_LOG_RUN_END($v_run_id_incr, 'COMPLETED');

-- ============================================================================
-- 4.4 POST-INCREMENTAL VALIDATION
-- ============================================================================

-- 4.4.1 Verify incremental run completed
SELECT '--- INCREMENTAL RUN STATUS ---' AS section;
SELECT RUN_ID, PACKAGE_NAME, RUN_MODE, RUN_STATUS, 
       START_TIMESTAMP, END_TIMESTAMP, DURATION_SECONDS,
       TOTAL_ROWS_READ, TOTAL_ROWS_WRITTEN, TOTAL_ROWS_REJECTED,
       TOTAL_STEPS, COMPLETED_STEPS
FROM P360_SP.AUDIT.PKG_RUN_LOG 
WHERE RUN_ID = $v_run_id_incr;

-- 4.4.2 Verify step-level results (should show only incremental counts)
SELECT '--- INCREMENTAL STEP LOG ---' AS section;
SELECT STEP_ID, STEP_NAME, STEP_LAYER, STEP_STATUS, 
       ROWS_READ, ROWS_WRITTEN, ROWS_REJECTED, 
       REJECT_PERCENTAGE, DQ_PASSED
FROM P360_SP.AUDIT.STEP_RUN_LOG 
WHERE RUN_ID = $v_run_id_incr
ORDER BY STEP_ID;

-- 4.4.3 Verify DQ caught bad records in incremental batch
SELECT '--- INCREMENTAL DQ LOG ---' AS section;
SELECT SOURCE_TABLE, TOTAL_RECORDS, PASSED_RECORDS, REJECTED_RECORDS,
       REJECT_PERCENTAGE, THRESHOLD_EXCEEDED
FROM P360_SP.AUDIT.DQ_RUN_LOG 
WHERE RUN_ID = $v_run_id_incr
ORDER BY SOURCE_TABLE;

-- 4.4.4 Check rejects from incremental run
SELECT '--- INCREMENTAL REJECTS ---' AS section;
SELECT STEP_NAME, SOURCE_TABLE, REJECT_REASONS, RECORD_KEY, SEVERITY
FROM P360_SP.REJECT.REJECT_RECORDS 
WHERE RUN_ID = $v_run_id_incr
ORDER BY REJECTED_AT;

-- 4.4.5 Compare row counts BEFORE vs AFTER incremental
SELECT '--- POST-INCREMENTAL ROW COUNTS ---' AS section;
SELECT 'BRONZE' AS LAYER, 'STG_NPI_REGISTRY' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM P360_SP.BRONZE.STG_NPI_REGISTRY
UNION ALL SELECT 'BRONZE', 'STG_CRED_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_CRED_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_EMR_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_EMR_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_CLAIMS_PROVIDERS', COUNT(*) FROM P360_SP.BRONZE.STG_CLAIMS_PROVIDERS
UNION ALL SELECT 'BRONZE', 'STG_NETWORK_AFFILIATIONS', COUNT(*) FROM P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS
UNION ALL SELECT 'SILVER', 'INT_PROVIDERS_UNIFIED', COUNT(*) FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED
UNION ALL SELECT 'SILVER', 'INT_PROVIDERS_DEDUPED', COUNT(*) FROM P360_SP.SILVER.INT_PROVIDERS_DEDUPED
UNION ALL SELECT 'SILVER', 'INT_NETWORK_AFFILIATIONS', COUNT(*) FROM P360_SP.SILVER.INT_NETWORK_AFFILIATIONS
UNION ALL SELECT 'GOLD', 'DIM_PROVIDER', COUNT(*) FROM P360_SP.GOLD.DIM_PROVIDER
UNION ALL SELECT 'GOLD', 'DIM_PROVIDER_NETWORK', COUNT(*) FROM P360_SP.GOLD.DIM_PROVIDER_NETWORK
UNION ALL SELECT 'GOLD', 'FCT_PROVIDER_VISITS', COUNT(*) FROM P360_SP.GOLD.FCT_PROVIDER_VISITS
UNION ALL SELECT 'GOLD', 'PROVIDER_360_SUMMARY', COUNT(*) FROM P360_SP.GOLD.PROVIDER_360_SUMMARY;

-- 4.4.6 SOURCE_ROW_COUNTS for incremental run
SELECT '--- INCREMENTAL SOURCE COUNTS ---' AS section;
SELECT SOURCE_TABLE, TOTAL_COUNT, INCREMENTAL_COUNT, COUNTED_AT
FROM P360_SP.AUDIT.SOURCE_ROW_COUNTS 
WHERE RUN_ID = $v_run_id_incr
ORDER BY COUNTED_AT;

-- 4.4.7 Compare FULL vs INCREMENTAL runs side-by-side
SELECT '--- FULL vs INCREMENTAL COMPARISON ---' AS section;
SELECT RUN_MODE, RUN_STATUS, TOTAL_ROWS_READ, TOTAL_ROWS_WRITTEN, 
       TOTAL_ROWS_REJECTED, DURATION_SECONDS, COMPLETED_STEPS,*
FROM P360_SP.AUDIT.PKG_RUN_LOG 
ORDER BY START_TIMESTAMP DESC 
LIMIT 5;

-- ############################################################################
-- END OF SCRIPTS
-- ############################################################################


-- ############################################################################
-- SECTION 5: MASTER SP REFERENCE & ARCHITECTURE NOTES
-- ############################################################################

-- ============================================================================
-- 5.1 MASTER STORED PROCEDURE: SP_RUN_PACKAGE
-- ============================================================================
--
-- Location: P360_SP.ORCHESTRATION.SP_RUN_PACKAGE
-- This is the SINGLE entry point to run the entire pipeline end-to-end.
-- It reads PKG_STEP_REGISTRY and executes all 13 child SPs in dependency order.
--
-- PARAMETERS:
-- +-----------------+----------+---------------+------------------------------------------+
-- | Parameter       | Type     | Default       | Description                              |
-- +-----------------+----------+---------------+------------------------------------------+
-- | P_RUN_MODE      | VARCHAR  | 'INCREMENTAL' | FULL / INCREMENTAL / RESUME / RERUN_STEP |
-- | P_RESUME_RUN_ID | VARCHAR  | NULL          | Required for RESUME - pass failed run_id |
-- | P_STEP_ID       | NUMBER   | NULL          | Required for RERUN_STEP - step ID only   |
-- +-----------------+----------+---------------+------------------------------------------+
--
-- USAGE EXAMPLES:
--
--   -- 1. FULL REFRESH (truncate + reload all layers)
--   CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');
--
--   -- 2. INCREMENTAL (default - processes only new records after HWM)
--   CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('INCREMENTAL');
--   -- or simply:
--   CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE();
--
--   -- 3. RESUME from failure (pass the failed run_id)
--   CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RESUME', '<failed-run-id>');
--
--   -- 4. RE-RUN a specific step only (e.g. step 11 = INT_PROVIDERS_DEDUPED)
--   CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RERUN_STEP', NULL, 11);
--

-- ============================================================================
-- 5.2 FAILURE & RESUME BEHAVIOR
-- ============================================================================
--
-- ON FAILURE:
--   1. Records failed_step_id in PKG_RUN_LOG
--   2. Logs error details to ERROR_LOG
--   3. Sends failure notification (if configured)
--   4. STOPS execution immediately (no further steps run)
--   5. Returns JSON with ready-to-copy resume_command:
--      {
--        "run_id": "abc-123...",
--        "status": "FAILED",
--        "failed_step": "INT_PROVIDERS_DEDUPED",
--        "resume_command": "CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RESUME', 'abc-123...')"
--      }
--
-- RESUME MODE:
--   - Reads the failed_step_id from PKG_RUN_LOG for the given run_id
--   - Skips all prior completed steps
--   - Re-executes from the failed step onward
--   - Updates run_status back to RUNNING, then COMPLETED/FAILED
--
-- RETRY LOGIC (built-in per step):
--   - Each step retries up to RETRY_COUNT (default 3) times
--   - Waits RETRY_DELAY_SECONDS between attempts
--   - Only after all retries exhausted does it mark the step as FAILED
--

-- ============================================================================
-- 5.3 AUTOMATED SCHEDULING (via Snowflake Tasks)
-- ============================================================================
--
-- +-------------------------------+----------------------------+-------------+
-- | Task Name                     | Schedule                   | Mode        |
-- +-------------------------------+----------------------------+-------------+
-- | TSK_P360_DAILY_INCREMENTAL    | 6 AM ET daily (Mon-Sat)    | INCREMENTAL |
-- | TSK_P360_WEEKLY_FULL          | 2 AM ET Sunday             | FULL        |
-- +-------------------------------+----------------------------+-------------+
--
-- Tasks are created SUSPENDED by default. Activate with:
--   ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL RESUME;
--   ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_WEEKLY_FULL RESUME;
--

-- ============================================================================
-- 5.4 PIPELINE EXECUTION ORDER (13 Steps)
-- ============================================================================
--
-- +------+---------------------------+--------+-----------------------------------------------+
-- | Step | Name                      | Layer  | Depends On                                    |
-- +------+---------------------------+--------+-----------------------------------------------+
-- |  1   | STG_NPI_REGISTRY          | BRONZE | None                                          |
-- |  2   | STG_CRED_PROVIDERS        | BRONZE | Step 1                                        |
-- |  3   | STG_EMR_PROVIDERS         | BRONZE | Step 1                                        |
-- |  4   | STG_CLAIMS_PROVIDERS      | BRONZE | Step 1                                        |
-- |  5   | STG_NETWORK_AFFILIATIONS  | BRONZE | Step 1                                        |
-- | 10   | INT_PROVIDERS_UNIFIED     | SILVER | Steps 1, 2, 3                                 |
-- | 11   | INT_PROVIDERS_DEDUPED     | SILVER | Step 10                                       |
-- | 12   | INT_NETWORK_AFFILIATIONS  | SILVER | Steps 5, 11                                   |
-- | 13   | SCD2_PROVIDER_ATTRIBUTES  | SILVER | Step 11                                       |
-- | 20   | DIM_PROVIDER              | GOLD   | Steps 11, 13                                  |
-- | 21   | DIM_PROVIDER_NETWORK      | GOLD   | Step 12                                       |
-- | 22   | FCT_PROVIDER_VISITS       | GOLD   | Steps 4, 20                                   |
-- | 30   | PROVIDER_360_SUMMARY      | GOLD   | Steps 20, 21, 22                              |
-- +------+---------------------------+--------+-----------------------------------------------+
--

-- ============================================================================
-- 5.5 MONITORING VIEWS (available in ORCHESTRATION schema)
-- ============================================================================
--
-- VW_RUN_HISTORY       - Run history dashboard (status, duration, row counts)
-- VW_STEP_PERFORMANCE  - Step-level metrics (per-step timing, rows, errors)
-- VW_DQ_DASHBOARD      - Data quality trends (reject rates, threshold breaches)
-- VW_ERROR_ANALYSIS    - Error investigation (codes, states, messages)
-- VW_REJECT_ANALYSIS   - Reject record analysis (reasons, counts, tables)
--

-- ############################################################################
-- SECTION 6: IMPROVEMENT SUGGESTIONS & PRODUCTION RECOMMENDATIONS
-- ############################################################################

-- ============================================================================
-- 6.1 CURRENT STRENGTHS
-- ============================================================================
--
-- [+] Registry-driven execution (PKG_STEP_REGISTRY) - new SPs auto-discovered
-- [+] Full/Incremental/Resume/RerunStep modes cover all operational scenarios
-- [+] Retry with configurable count and delay per step
-- [+] Full audit trail (PKG_RUN_LOG, STEP_RUN_LOG, DQ_RUN_LOG, ERROR_LOG)
-- [+] DQ threshold circuit breaker
-- [+] Notification framework
-- [+] Clean separation: RAW_INGESTION -> BRONZE -> SILVER -> GOLD
-- [+] Reject records captured with full context
--

-- ============================================================================
-- 6.2 RECOMMENDED IMPROVEMENTS
-- ============================================================================
--
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | #  | Area                          | Suggestion                                    | Priority |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 1  | Dependency Resolution         | DEPENDS_ON_STEP_ID is stored but not enforced | HIGH     |
-- |    |                               | at runtime. Add logic to verify all           |          |
-- |    |                               | dependency steps completed before executing.  |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 2  | Parallel Execution            | Convert to Snowflake Task DAG where each step | MEDIUM   |
-- |    |                               | is a child task with predecessor deps. Bronze |          |
-- |    |                               | steps 2-5 can run in parallel (all depend on  |          |
-- |    |                               | step 1 only).                                 |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 3  | Idempotency on Resume         | RESUME re-runs a step that may have partially | HIGH     |
-- |    |                               | written data. Add TRUNCATE-before-reinsert    |          |
-- |    |                               | pattern or use MERGE for all writes.          |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 4  | Dynamic DQ Rules              | DQ_RULES table exists but SPs use inline DQ   | HIGH     |
-- |    |                               | logic. Refactor SPs to dynamically read rules |          |
-- |    |                               | from DQ_RULES and evaluate generically.       |          |
-- |    |                               | New rules become config-only changes.         |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 5  | Per-Table DQ Thresholds       | Single global DQ_REJECT_THRESHOLD (5%).       | MEDIUM   |
-- |    |                               | Add per-table thresholds in DQ_RULES or       |          |
-- |    |                               | PKG_STEP_REGISTRY.                            |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 6  | Version Tracking              | No deployment versioning. Add PKG_VERSION     | LOW      |
-- |    |                               | table to track which SP version is deployed.  |          |
-- |    |                               | Helps with rollback scenarios.                |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 7  | Dry-Run Mode                  | Add P_DRY_RUN BOOLEAN DEFAULT FALSE that      | MEDIUM   |
-- |    |                               | logs what WOULD execute without running.      |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 8  | Concurrency Control           | Tasks have ALLOW_OVERLAPPING=FALSE, but       | HIGH     |
-- |    |                               | manual CALL can overlap. Add a run-level      |          |
-- |    |                               | lock check (is another run RUNNING in         |          |
-- |    |                               | PKG_RUN_LOG?) to prevent manual overlap.      |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 9  | Step Timeout Enforcement      | TIMEOUT_MINUTES stored but not enforced.      | LOW      |
-- |    |                               | Use SYSTEM$CANCEL_QUERY() or watchdog pattern |          |
-- |    |                               | if step exceeds configured timeout.           |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 10 | Layer-Level Execution         | Can't run just one layer today. Add           | MEDIUM   |
-- |    |                               | P_LAYER VARCHAR DEFAULT NULL to filter        |          |
-- |    |                               | PKG_STEP_REGISTRY by layer (BRONZE/SILVER/    |          |
-- |    |                               | GOLD only).                                   |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 11 | Metadata-Driven Source Config | Source table names hardcoded in SPs. Create   | LOW      |
-- |    |                               | SOURCE_TABLE_REGISTRY mapping raw->bronze->   |          |
-- |    |                               | silver->gold with column mappings. New tables |          |
-- |    |                               | become config-only additions.                 |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 12 | Rollback Capability           | No rollback on failure. Use Time Travel       | MEDIUM   |
-- |    |                               | (AT TIMESTAMP => pre-run) to revert tables    |          |
-- |    |                               | on catastrophic failure.                      |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
-- | 13 | Trend-Based Alerting          | Views exist but no alerting on trends. Add    | LOW      |
-- |    |                               | detection if reject rate increases 2x over    |          |
-- |    |                               | last 5 runs -> raise WARNING notification.    |          |
-- +----+-------------------------------+-----------------------------------------------+----------+
--

-- ============================================================================
-- 6.3 NEW TABLE/SP ADDITION WORKFLOW (Current Design)
-- ============================================================================
--
-- To add a new source table to the pipeline:
--
--   1. Create raw table in RAW_INGESTION schema
--   2. Create target staged table in BRONZE schema
--   3. Write staging SP in BRONZE following existing pattern
--   4. Add DQ rules to CONFIG.DQ_RULES table
--   5. INSERT row into CONFIG.PKG_STEP_REGISTRY with appropriate:
--      - STEP_ID (pick next available in layer range)
--      - STEP_ORDER (controls execution sequence)
--      - DEPENDS_ON_STEP_ID (array of prerequisite steps)
--   6. Done - SP_RUN_PACKAGE picks it up automatically on next run
--
-- NO CODE CHANGES to SP_RUN_PACKAGE required.
--

-- ============================================================================
-- 6.4 PRODUCTION EVOLUTION PATH
-- ============================================================================
--
-- Phase 1 (Current): Sequential SP execution with registry + audit
-- Phase 2 (Next):    Enforce dependency resolution + concurrency locks
-- Phase 3 (Future):  Convert to Snowflake Task DAG for native parallelism
-- Phase 4 (Target):  Fully metadata-driven generic SPs (config-only changes)
--

-- ############################################################################
-- END OF DOCUMENT
-- ############################################################################


