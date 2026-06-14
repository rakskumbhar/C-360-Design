select* from P360_SP.BRONZE.STG_CLAIMS_PROVIDERS;

select* from P360_SP.AUDIT.DQ_RUN_LOG;
select* from P360_SP.AUDIT.ERROR_LOG;
select* from P360_SP.AUDIT.NOTIFICATION_LOG;
select* from P360_SP.AUDIT.PKG_RUN_LOG;
select* from P360_SP.AUDIT.SOURCE_ROW_COUNTS;
select* from P360_SP.AUDIT.STEP_RUN_LOG;



USE DATABASE P360_SP;
USE SCHEMA CONFIG;
select* from PKG_CONFIG;

select* from PKG_STEP_REGISTRY;--table empty and no records

select* from DQ_RULES;--table does not exists 

select* from NOTIFICATION_CONFIG-- table empty and no records

select* from ENV_CONFIG; -- table empty and no records



USE DATABASE P360_SP;
USE SCHEMA AUDIT;

select* from PKG_RUN_LOG;
select* from STEP_RUN_LOG
where run_id='73cb690e-f596-4e0e-bae9-21d10d5f6443'
;

select* from ERROR_LOG;
select* from DQ_RUN_LOG;

select * from REJECT.REJECT_RECORDS;

select* from REJECT.REJECT_SUMMARY;
select* from SOURCE_ROW_COUNTS;-- table is empty. no records are loaded


--Raw ingestion tables
select* from P360_SP.RAW _INGESTION.CLAIMS_RAW;
select* from P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW;
select* from P360_SP.RAW_INGESTION.NPI_RAW;
select* from P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW;
select* from P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW;



-- Data operations
select* from P360_SP.RAW_INGESTION.CLAIMS_RAW
where _loaded_at::date='2024-01-15'
;

select* from P360_SP.RAW_INGESTION.CLAIMS_RAW
where _loaded_at::date='2026-06-10'
;


-- update _loaded_at
update P360_SP.RAW_INGESTION.CLAIMS_RAW
set _loaded_at='2026-01-01'
where _loaded_at::date='2024-01-15'
;

--select* from TEST_DATA.CLAIMS_RAW_2026_06_10;
create table TEST_DATA.CLAIMS_RAW_2026_06_10 as

select* from P360_SP.RAW_INGESTION.CLAIMS_RAW
where _loaded_at::date='2026-06-10'
;


delete from P360_SP.RAW_INGESTION.CLAIMS_RAW
where _loaded_at::date='2026-06-10'
;




select* from TEST_DATA.CLAIMS_RAW_2026_06_10;


create schema TEST_DATA;


-- ============================================================================
-- NETWORK_AFFILIATIONS_RAW — Same pattern as CLAIMS_RAW
-- ============================================================================

select* from P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
where _loaded_at::date='2024-01-15'
;

select* from P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
where _loaded_at::date='2026-06-10'
;

-- update _loaded_at
update P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
set _loaded_at='2026-01-01'
where _loaded_at::date='2024-01-15'
;

create table TEST_DATA.NETWORK_AFFILIATIONS_RAW_2026_06_10 as
select* from P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
where _loaded_at::date='2026-06-10'
;

delete from P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
where _loaded_at::date='2026-06-10'
;

select* from TEST_DATA.NETWORK_AFFILIATIONS_RAW_2026_06_10;


-- ============================================================================
-- NPI_RAW — Same pattern as CLAIMS_RAW
-- ============================================================================

select* from P360_SP.RAW_INGESTION.NPI_RAW
where _loaded_at::date='2024-01-15'
;

select* from P360_SP.RAW_INGESTION.NPI_RAW
where _loaded_at::date='2026-06-10'
;

-- update _loaded_at
update P360_SP.RAW_INGESTION.NPI_RAW
set _loaded_at='2026-01-01'
where _loaded_at::date='2024-01-15'
;

create table TEST_DATA.NPI_RAW_2026_06_10 as
select* from P360_SP.RAW_INGESTION.NPI_RAW
where _loaded_at::date='2026-06-10'
;

delete from P360_SP.RAW_INGESTION.NPI_RAW
where _loaded_at::date='2026-06-10'
;

select* from TEST_DATA.NPI_RAW_2026_06_10;


-- ============================================================================
-- PROVIDER_CREDENTIALS_RAW — Same pattern as CLAIMS_RAW
-- ============================================================================

select* from P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
where _loaded_at::date='2024-01-15'
;

select* from P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
where _loaded_at::date='2026-06-10'
;

-- update _loaded_at
update P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
set _loaded_at='2026-01-01'
where _loaded_at::date='2024-01-15'
;

create table TEST_DATA.PROVIDER_CREDENTIALS_RAW_2026_06_10 as
select* from P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
where _loaded_at::date='2026-06-10'
;

delete from P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
where _loaded_at::date='2026-06-10'
;

select* from TEST_DATA.PROVIDER_CREDENTIALS_RAW_2026_06_10;


-- ============================================================================
-- PROVIDER_MASTER_RAW — Same pattern as CLAIMS_RAW
-- ============================================================================

select* from P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
where _loaded_at::date='2024-01-15'
;

select* from P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
where _loaded_at::date='2026-06-10'
;

-- update _loaded_at
update P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
set _loaded_at='2026-01-01'
where _loaded_at::date='2024-01-15'
;

create table TEST_DATA.PROVIDER_MASTER_RAW_2026_06_10 as
select* from P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
where _loaded_at::date='2026-06-10'
;

delete from P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
where _loaded_at::date='2026-06-10'
;

select* from TEST_DATA.PROVIDER_MASTER_RAW_2026_06_10;

;

--truncate audit and reject tables

truncate table P360_SP.AUDIT.DQ_RUN_LOG;
truncate table P360_SP.AUDIT.ERROR_LOG;
truncate table P360_SP.AUDIT.NOTIFICATION_LOG;
truncate table P360_SP.AUDIT.PKG_RUN_LOG;
truncate table P360_SP.AUDIT.SOURCE_ROW_COUNTS;
truncate table P360_SP.AUDIT.STEP_RUN_LOG;
truncate table P360_SP.REJECT.REJECT_RECORDS;
truncate table P360_SP.REJECT.REJECT_SUMMARY;

select* from P360_SP.ORCHESTRATION.VW_DQ_DASHBOARD;
select* from P360_SP.ORCHESTRATION.VW_ERROR_ANALYSIS;
select* from P360_SP.ORCHESTRATION.VW_REJECT_ANALYSIS;
select* from P360_SP.ORCHESTRATION.VW_RUN_HISTORY;
select* from P360_SP.ORCHESTRATION.VW_STEP_PERFORMANCE;



--truncate bronze layer
truncate table P360_SP.BRONZE.STG_CLAIMS_PROVIDERS;
truncate table P360_SP.BRONZE.STG_CRED_PROVIDERS;
truncate table P360_SP.BRONZE.STG_EMR_PROVIDERS;
truncate table P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS;
truncate table P360_SP.BRONZE.STG_NPI_REGISTRY;


--truncate silver layer

truncate table P360_SP.SILVER.INT_NETWORK_AFFILIATIONS;
truncate table P360_SP.SILVER.INT_PROVIDERS_DEDUPED;
truncate table P360_SP.SILVER.INT_PROVIDERS_UNIFIED;

--truncate gold layer

truncate table P360_SP.GOLD.DIM_PROVIDER;
truncate table P360_SP.GOLD.DIM_PROVIDER_NETWORK;
truncate table P360_SP.GOLD.FCT_PROVIDER_VISITS;
truncate table P360_SP.GOLD.PROVIDER_360_SUMMARY;













    SELECT step_id, step_name, step_layer, step_procedure, retry_count, retry_delay_seconds
        FROM P360_SP.CONFIG.PKG_STEP_REGISTRY
        WHERE is_active = TRUE;

select*   FROM P360_SP.CONFIG.PKG_STEP_REGISTRY;

--select audit log
select* from  P360_SP.AUDIT.PKG_RUN_LOG;
select* from  P360_SP.AUDIT.DQ_RUN_LOG;
select* from  P360_SP.AUDIT.SOURCE_ROW_COUNTS;
select* from  P360_SP.AUDIT.STEP_RUN_LOG;
select* from  P360_SP.REJECT.REJECT_RECORDS;
select* from  P360_SP.REJECT.REJECT_SUMMARY;
select* from  P360_SP.AUDIT.ERROR_LOG;
select* from  P360_SP.AUDIT.NOTIFICATION_LOG;--optional for email delivery


P360_SP.ORCHESTRATION.VW_DQ_DASHBOARD



--select bronze layer
select* from  P360_SP.BRONZE.STG_CLAIMS_PROVIDERS;
select* from  P360_SP.BRONZE.STG_CRED_PROVIDERS;
select* from  P360_SP.BRONZE.STG_EMR_PROVIDERS;
select* from  P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS;
select* from  P360_SP.BRONZE.STG_NPI_REGISTRY;


--select silver layer

select* from  P360_SP.SILVER.INT_NETWORK_AFFILIATIONS;
select* from  P360_SP.SILVER.INT_PROVIDERS_DEDUPED;
select* from  P360_SP.SILVER.INT_PROVIDERS_UNIFIED;

--select gold layer

select* from P360_SP.GOLD.DIM_PROVIDER;
select* from P360_SP.GOLD.DIM_PROVIDER_NETWORK;
select* from P360_SP.GOLD.FCT_PROVIDER_VISITS;
select* from P360_SP.GOLD.PROVIDER_360_SUMMARY;

--incremental data 

select* from P360_SP.RAW_INGESTION.CLAIMS_RAW;
select* from P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW;
select* from P360_SP.RAW_INGESTION.NPI_RAW;
select* from P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW;
select* from P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW;


select* from P360_SP.TEST_DATA.CLAIMS_RAW_2026_06_10;
select* from P360_SP.TEST_DATA.NETWORK_AFFILIATIONS_RAW_2026_06_10;
select* from P360_SP.TEST_DATA.NPI_RAW_2026_06_10;
select* from P360_SP.TEST_DATA.PROVIDER_CREDENTIALS_RAW_2026_06_10;
select* from P360_SP.TEST_DATA.PROVIDER_MASTER_RAW_2026_06_10;


insert into P360_SP.RAW_INGESTION.CLAIMS_RAW
select* from P360_SP.TEST_DATA.CLAIMS_RAW_2026_06_10;

insert into P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
select* from P360_SP.TEST_DATA.NETWORK_AFFILIATIONS_RAW_2026_06_10;

insert into P360_SP.RAW_INGESTION.NPI_RAW
select* from P360_SP.TEST_DATA.NPI_RAW_2026_06_10;

insert into P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
select* from P360_SP.TEST_DATA.PROVIDER_CREDENTIALS_RAW_2026_06_10;

insert into P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
select* from P360_SP.TEST_DATA.PROVIDER_MASTER_RAW_2026_06_10;


--delete threshold -- 1 record
