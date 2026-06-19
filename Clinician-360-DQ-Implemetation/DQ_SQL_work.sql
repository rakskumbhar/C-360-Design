-- DQ Engine fix and Silver layer rule additions for Clinician-360 framework
-- Co-authored with CoCo

USE DATABASE P360_DQ;

/*=============================================================================
  FIX 1: Add new DQ rules - GN_InList for specific value validation
         and GN_Duplicate handling in the engine
=============================================================================*/

-- Add GN_InList rule (validates column value is in a specified list)
INSERT INTO CONFIG.DQ_RULE (CATEGORY_ID, RULE_CODE, RULE_DESC, RULE_EXP, RULE_CATEGORY)
SELECT 6, 'GN_InList', 'Validate value is in allowed list',
       'CASE WHEN ${INPUT1} NOT IN (${INPUT2}) THEN ''FAIL'' ELSE ''PASS'' END',
       'SIMPLE'
WHERE NOT EXISTS (SELECT 1 FROM CONFIG.DQ_RULE WHERE RULE_CODE = 'GN_InList');

-- Capture the new RULE_ID for GN_InList
SET v_inlist_rule_id = (SELECT RULE_ID FROM CONFIG.DQ_RULE WHERE RULE_CODE = 'GN_InList');

/*=============================================================================
  FIX 2: Add Bronze DQ_FEED entry for CREDENTIAL validation using GN_InList
=============================================================================*/

INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, DQ_RULE_INPUT_WHERE_COL,
    CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'BRONZE', 'PROVIDERS', $v_inlist_rule_id, 'STG_NPI_REGISTRY', 'NPI_SK',
       'LOAD_DT', 'CREDENTIAL', '''MD'',''DO'',''NP'',''PA'',''RN'',''APRN'',''DPM'',''DDS'',''PhD'',''PharmD'',''OD'',''DC''',
       'Y', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'STG_NPI_REGISTRY' AND DQ_RULE_INPUT = 'CREDENTIAL'
      AND LAYER = 'BRONZE'
);

/*=============================================================================
  FIX 3: Add richer Silver layer DQ rules
         - Credential validation (specific values)
         - Gender validation
         - Phone format
         - Deduplication check on PROVIDER_NPI
=============================================================================*/

-- Credential must be in valid list (Silver)
INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, DQ_RULE_INPUT_WHERE_COL,
    CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'SILVER', 'PROVIDERS', $v_inlist_rule_id, 'DIM_PROVIDER', 'PROVIDER_SK',
       'LOAD_DT', 'CREDENTIAL', '''MD'',''DO'',''NP'',''PA'',''RN'',''APRN'',''DPM'',''DDS'',''PhD'',''PharmD'',''OD'',''DC''',
       'Y', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'DIM_PROVIDER' AND DQ_RULE_INPUT = 'CREDENTIAL'
      AND LAYER = 'SILVER'
);

-- Gender must be M or F (Silver)
INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, DQ_RULE_INPUT_WHERE_COL,
    CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'SILVER', 'PROVIDERS', $v_inlist_rule_id, 'DIM_PROVIDER', 'PROVIDER_SK',
       'LOAD_DT', 'GENDER', '''M'',''F''',
       'N', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'DIM_PROVIDER' AND DQ_RULE_INPUT = 'GENDER'
      AND LAYER = 'SILVER'
);

-- Provider NPI must not be duplicate (Silver)
INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'SILVER', 'PROVIDERS', 1, 'DIM_PROVIDER', 'PROVIDER_SK',
       'LOAD_DT', 'PROVIDER_NPI', 'Y', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'DIM_PROVIDER' AND RULE_ID = 1
      AND LAYER = 'SILVER' AND DQ_RULE_INPUT = 'PROVIDER_NPI'
);

-- Provider phone not null (Silver - non-critical)
INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'SILVER', 'PROVIDERS', 2, 'DIM_PROVIDER', 'PROVIDER_SK',
       'LOAD_DT', 'PHONE', 'N', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'DIM_PROVIDER' AND RULE_ID = 2 AND DQ_RULE_INPUT = 'PHONE'
      AND LAYER = 'SILVER'
);


--Reset


truncate table audit.PKG_RUN_LOG ;
truncate table audit.STEP_RUN_LOG ;
truncate table audit.ERROR_LOG ;
truncate table audit.NOTIFICATION_LOG ;
truncate table audit.SOURCE_ROW_COUNTS;
truncate table audit.DQ_LOG;
truncate table audit.DQ_LOG_HISTORY;
truncate table audit.DQ_RESULT ;

truncate table reject.REJECT_RECORDS;
truncate table reject.REJECT_SUMMARY ;



/*=============================================================================
  FIX 5: Reset Bronze DQ_STATUS and re-run full pipeline
=============================================================================*/

-- Reset DQ_STATUS so engine can re-evaluate
UPDATE P360_DQ.BRONZE.STG_NPI_REGISTRY SET DQ_STATUS = NULL;
UPDATE P360_DQ.BRONZE.STG_SPECIALTY_TYPE SET DQ_STATUS = NULL;


-- Run full pipeline
CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

/*=============================================================================
  VALIDATION QUERIES (run after pipeline completes)
=============================================================================*/

-- Check DQ_STATUS populated in Bronze
SELECT DQ_STATUS, COUNT(*) AS cnt FROM P360_DQ.BRONZE.STG_NPI_REGISTRY GROUP BY DQ_STATUS;
SELECT DQ_STATUS, COUNT(*) AS cnt FROM P360_DQ.BRONZE.STG_SPECIALTY_TYPE GROUP BY DQ_STATUS;

-- Check DQ_RESULT has entries
SELECT TABLE_NM, RULE_ID, RESULT, COUNT(*) FROM P360_DQ.AUDIT.DQ_RESULT GROUP BY TABLE_NM, RULE_ID, RESULT ORDER BY TABLE_NM, RULE_ID;

-- Check Silver DIM_PROVIDER is populated
SELECT COUNT(*) AS dim_provider_count FROM P360_DQ.SILVER.DIM_PROVIDER;
SELECT * FROM P360_DQ.SILVER.DIM_PROVIDER LIMIT 10;

-- Check DQ rules configuration
SELECT f.FEED_ID, f.LAYER, f.TABLE_NM, f.DQ_RULE_INPUT, f.DQ_RULE_INPUT_WHERE_COL, r.RULE_CODE, f.CRITICALITY_IND
FROM P360_DQ.CONFIG.DQ_FEED f
JOIN P360_DQ.CONFIG.DQ_RULE r ON f.RULE_ID = r.RULE_ID
WHERE f.ACTIVE_IND = 'Y'
ORDER BY f.LAYER, f.TABLE_NM, f.FEED_ID;

SELECT * FROM P360_DQ.BRONZE.STG_NPI_REGISTRY 
WHERE  (CASE WHEN TRIM(COALESCE(CAST(NPI_NUMBER AS VARCHAR),''))= '' THEN 'FAIL' ELSE 'PASS' END) = 'FAIL'

;
use p360_dq;

select* from audit.PKG_RUN_LOG ;
select* from audit.STEP_RUN_LOG ;
select* from audit.SOURCE_ROW_COUNTS;
select* from audit.DQ_LOG;
select* from audit.DQ_LOG_HISTORY;
select* from audit.DQ_RESULT ;
select* from audit.ERROR_LOG ;
select* from audit.NOTIFICATION_LOG ;

select* from reject.REJECT_RECORDS;
select* from reject.REJECT_SUMMARY ;



select* from P360_DQ.CONFIG.DQ_CATEGORY;
select* from P360_DQ.CONFIG.DQ_EMAIL;
select* from P360_DQ.CONFIG.DQ_FEED;
select* from P360_DQ.CONFIG.DQ_RULE;
select* from P360_DQ.CONFIG.DQ_log;

select* from P360_DQ.CONFIG.ENV_CONFIG;
select* from P360_DQ.CONFIG.NOTIFICATION_CONFIG;
select* from P360_DQ.CONFIG.PKG_CONFIG;
select* from P360_DQ.CONFIG.PKG_STEP_REGISTRY;


select* from P360_DQ.BRONZE.STG_NPI_REGISTRY;
select* from P360_DQ.BRONZE.STG_SPECIALTY_TYPE

CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

select* from P360_DQ.BRONZE.STG_NPI_REGISTRY;
select* from P360_DQ.BRONZE.STG_SPECIALTY_TYPE;
select* from P360_DQ.SILVER.DIM_PROVIDER;
select* from P360_DQ.SILVER.SCD2_PROVIDER_ATTRIBUTES;
select* from P360_DQ.GOLD.FCT_PROVIDER_360

;

update P360_DQ.CONFIG.ENV_CONFIG
set dq_reject_threshold='90.00'
where environment='DEV'
;
update P360_DQ.CONFIG.PKG_CONFIG
set config_value='90.00'
where config_category='DQ' and config_data_type='NUMBER'
;


select* from P360_DQ.CONFIG.DQ_FEED 
where table_nm='STG_NPI_REGISTRY'
;
select* from P360_DQ.CONFIG.DQ_RULE;

;
SELECT f.FEED_ID, f.RULE_ID, f.DQ_RULE_INPUT, f.RECORD_KEY_NM,
               f.INCREMENTAL_DATE_COLUMN, f.CRITICALITY_IND, f.DOMAIN,
               r.RULE_EXP, r.RULE_CATEGORY, r.RULE_CODE
        FROM P360_DQ.CONFIG.DQ_FEED f
        JOIN P360_DQ.CONFIG.DQ_RULE r ON f.RULE_ID = r.RULE_ID
        WHERE f.ACTIVE_IND = 'Y' AND table_nm='STG_NPI_REGISTRY'
        ORDER BY f.FEED_ID
        ;





      SELECT f.FEED_ID AS F_FEED_ID, f.RULE_ID AS F_RULE_ID,
               f.DQ_RULE_INPUT AS F_DQ_RULE_INPUT, f.RECORD_KEY_NM AS F_RECORD_KEY_NM,
               f.INCREMENTAL_DATE_COLUMN AS F_INCR_COL, f.CRITICALITY_IND AS F_CRIT,
               f.DOMAIN AS F_DOMAIN,
               f.DQ_RULE_INPUT_JOIN_TBL AS F_JOIN_TBL,
               f.DQ_RULE_INPUT_JOIN_COL AS F_JOIN_COL,
               f.DQ_RULE_INPUT_WHERE_COL AS F_WHERE_COL,
               r.RULE_EXP AS R_RULE_EXP, r.RULE_CATEGORY AS R_RULE_CATEGORY,
               r.RULE_CODE AS R_RULE_CODE
        FROM P360_DQ.CONFIG.DQ_FEED f
        JOIN P360_DQ.CONFIG.DQ_RULE r ON f.RULE_ID = r.RULE_ID
        WHERE f.TABLE_NM = 'STG_NPI_REGISTRY'
          AND f.LAYER = 'BRONZE'
          AND f.ACTIVE_IND = 'Y'
        ORDER BY f.FEED_ID

;
        CASE WHEN (ROW_NUMBER() OVER(PARTITION BY PROVIDERID ORDER BY 1))>1 THEN 'FAIL' ELSE 'PASS' END AS RESULT FROM PROVIDER a WHERE ${INCREMENTAL_DATE_COLUMN} QUALIFY RESULT = 'FAIL'

        --AFTER EXECUTION, DQ_STATUS COLUMNS IN BRONZE TABLES LIKE STG_NPI_REGISTRY NOT UPDATED, ALSO IN SILVER LAYER TABLE DIM_PROVIDER IS NOT EVEN POPULATED WITH ANY DATA.
        -- IN THE P360_DQ.CONFIG.DQ_FEED TABLE for some columns data VALUES ARE NULL, here are these columns - DQ_RULE_INPUT_JOIN_TBL,DQ_RULE_INPUT_JOIN_COL AND DQ_RULE_INPUT_WHERE_COL. 
there is no provision of de-deplication handling, if there are duplciate records of npi coming from source and how we can limit to have latest record in silver layer, could you please let me know how this can be handled.
Also there are not data quality rules defined for silver layer, I am expecting some rules to be defined in silver layer
        
        Also in P360_DQ.CONFIG.DQ_FEED table for example provider credential in specific values like ('MD','DO','NP') etc.

        what is use of batch_id?


  ;

-- After a fresh execution of DQ framework by resetting DQ_status to null in bronze and silver layer and after executiong  this command to Run full pipeline
CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

I see audit.DQ_LOG tables has some errors in error_message columns and also its logging against bornze and silver layer against 2 domain values- Providers and null, and hence silver dim_provider tables overall_count = 12 hpwever it mentions failed_count as 37 which is not possible. this behavior seen in table audit.DQ_LOG. due to this silver table is failing as it exceeding 90.00 of set DQ threshold. could you please check on this and fix this.

before running this I also observer audit.DQ_RESULT tables has result column with all records populated as 'FAIL' however I am expecting FAIL, PASS-SOFT and PASS values over there. could you please check and fix this;


;
   SELECT RECORD_KEY_NM 
   
    FROM P360_DQ.CONFIG.DQ_FEED
    WHERE TABLE_NM = 'STG_NPI_REGISTRY' AND LAYER = 'BRONZE' AND ACTIVE_IND = 'Y'
    LIMIT 1;