select* from P360_DQ.CONFIG.DQ_CATEGORY;
select* from P360_DQ.CONFIG.DQ_RULE;
select* from P360_DQ.CONFIG.DQ_FEED;
select* from audit.DQ_LOG;
select* from audit.DQ_RESULT ;


--RAW
select* from P360_DQ.RAW_INGESTION.RAW_NPI_REGISTRY;
select* from P360_DQ.RAW_INGESTION.RAW_SPECIALTY_TYPE;

--Bronze
select* from P360_DQ.BRONZE.STG_NPI_REGISTRY
where npi_number= 12345
--where npi_number= 3333333333
;

select* from audit.DQ_RESULT 
where record_key=12

;

select* from P360_DQ.BRONZE.STG_SPECIALTY_TYPE;

select* from P360_DQ.BRONZE.STG_SPECIALTY_TYPE
where specialty_code is null
;
--end to end run script
--CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('FULL');


--silver
select* from P360_DQ.SILVER.DIM_PROVIDER;
select* from P360_DQ.SILVER.SCD2_PROVIDER_ATTRIBUTES;

--gold
select* from P360_DQ.GOLD.FCT_PROVIDER_360

;

select* from P360_DQ.CONFIG.DQ_FEED 
where table_nm='STG_NPI_REGISTRY'
;
select* from P360_DQ.CONFIG.DQ_RULE;


select* from audit.PKG_RUN_LOG ;
select* from audit.STEP_RUN_LOG ;