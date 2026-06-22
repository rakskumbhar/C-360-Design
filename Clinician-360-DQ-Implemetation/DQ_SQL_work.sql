-- DQ Engine fix and Silver layer rule additions for Clinician-360 framework
-- Co-authored with CoCo

USE DATABASE P360_DQ;


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

truncate table P360_DQ.BRONZE.STG_NPI_REGISTRY;
truncate table P360_DQ.BRONZE.STG_SPECIALTY_TYPE;





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
select* from P360_DQ.CONFIG.DQ_RULE;
select* from P360_DQ.CONFIG.DQ_FEED;
select* from audit.DQ_LOG;
select* from audit.DQ_RESULT ;

--select* from audit.DQ_LOG_HISTORY;

--select* from P360_DQ.CONFIG.DQ_EMAIL;




select* from P360_DQ.CONFIG.ENV_CONFIG;
select* from P360_DQ.CONFIG.NOTIFICATION_CONFIG;
select* from P360_DQ.CONFIG.PKG_CONFIG;
select* from P360_DQ.CONFIG.PKG_STEP_REGISTRY;


--RAW
select* from P360_DQ.RAW_INGESTION.RAW_NPI_REGISTRY;
select* from P360_DQ.RAW_INGESTION.RAW_SPECIALTY_TYPE;

--Bronze
select* from P360_DQ.BRONZE.STG_NPI_REGISTRY
where npi_number= 12345
;


select* from audit.DQ_RESULT 
where record_key=12
;

select* from P360_DQ.BRONZE.STG_SPECIALTY_TYPE;



CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

--silver
select* from P360_DQ.SILVER.DIM_PROVIDER;
select* from P360_DQ.SILVER.SCD2_PROVIDER_ATTRIBUTES;

--gold
select* from P360_DQ.GOLD.FCT_PROVIDER_360

;
select* from P360_DQ.CONFIG.ENV_CONFIG

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



    select* from P360_DQ.BRONZE.STG_NPI_REGISTRY
    where npi_number ='1111111111'
    ;

select* from audit.dq_result
where record_key=943
;

select * from config.dq_feed
where feed_id in (1,2)

;
select* from config.dq_rule
where rule_id=2

;
    
select* from P360_DQ.BRONZE.STG_SPECIALTY_TYPE;

select* from P360_DQ.RAW_INGESTION.RAW_NPI_REGISTRY;
select* from P360_DQ.RAW_INGESTION.raw_specialty_type;



-- Reset DQ_STATUS so engine can re-evaluate all records
UPDATE P360_DQ.BRONZE.STG_NPI_REGISTRY SET DQ_STATUS = NULL;
UPDATE P360_DQ.BRONZE.STG_SPECIALTY_TYPE SET DQ_STATUS = NULL;
TRUNCATE TABLE P360_DQ.AUDIT.DQ_RESULT;
TRUNCATE TABLE P360_DQ.AUDIT.DQ_LOG;

CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('FULL');



-- Check DQ_STATUS populated in Bronze
SELECT DQ_STATUS, COUNT(*) AS cnt FROM P360_DQ.BRONZE.STG_NPI_REGISTRY GROUP BY DQ_STATUS;

SELECT DQ_STATUS, COUNT(*) AS cnt FROM P360_DQ.BRONZE.STG_SPECIALTY_TYPE GROUP BY DQ_STATUS;


-- Check DQ_RESULT has entries
SELECT TABLE_NM, RULE_ID, RESULT, COUNT(*) AS cnt
FROM P360_DQ.AUDIT.DQ_RESULT
GROUP BY TABLE_NM, RULE_ID, RESULT
ORDER BY TABLE_NM, RULE_ID;

-- Check step log for most recent run
SELECT STEP_NAME, STEP_STATUS, ROWS_READ, ROWS_WRITTEN, ERROR_CODE
FROM P360_DQ.AUDIT.STEP_RUN_LOG
WHERE RUN_ID = (SELECT MAX(RUN_ID) FROM P360_DQ.AUDIT.PKG_RUN_LOG)
ORDER BY START_TIMESTAMP;

-- Manually call Silver load to verify it picks up PASS records
TRUNCATE TABLE P360_DQ.SILVER.DIM_PROVIDER;
CALL P360_DQ.SILVER.SP_LOAD_DIM_PROVIDER('manual-test', 'FULL');

-- Check Silver DIM_PROVIDER is populated
SELECT COUNT(*) AS dim_provider_count FROM P360_DQ.SILVER.DIM_PROVIDER;

SELECT * FROM P360_DQ.SILVER.DIM_PROVIDER LIMIT 10;

-- Full DQ rules configuration
SELECT f.FEED_ID, f.LAYER, f.TABLE_NM, f.DQ_RULE_INPUT, f.DQ_RULE_INPUT_WHERE_COL, r.RULE_CODE, f.CRITICALITY_IND
FROM P360_DQ.CONFIG.DQ_FEED f
JOIN P360_DQ.CONFIG.DQ_RULE r ON f.RULE_ID = r.RULE_ID
WHERE f.ACTIVE_IND = 'Y'
ORDER BY f.LAYER, f.TABLE_NM, f.FEED_ID



-- Debug: Check DQ_LOG for any entries from the engine
SELECT * FROM P360_DQ.AUDIT.DQ_LOG ORDER BY DQ_START_TS DESC LIMIT 20;


SELECT 'STG_NPI_REGISTRY' AS TBL, DQ_STATUS, COUNT(*) AS CNT FROM P360_DQ.BRONZE.STG_NPI_REGISTRY GROUP BY DQ_STATUS
UNION ALL
SELECT 'STG_SPECIALTY_TYPE', DQ_STATUS, COUNT(*) FROM P360_DQ.BRONZE.STG_SPECIALTY_TYPE GROUP BY DQ_STATUS
ORDER BY TBL, DQ_STATUS;


SELECT NPI_NUMBER, PROVIDER_NAME, DQ_STATUS
FROM P360_DQ.BRONZE.STG_NPI_REGISTRY
WHERE DQ_STATUS IN ('PASS', 'PASS-SOFT')
LIMIT 15;


SELECT STEP_NAME, STEP_STATUS, ROWS_READ, ROWS_WRITTEN, ERROR_CODE
FROM P360_DQ.AUDIT.STEP_RUN_LOG
WHERE RUN_ID = (SELECT MAX(RUN_ID) FROM P360_DQ.AUDIT.PKG_RUN_LOG)
ORDER BY START_TIMESTAMP;
