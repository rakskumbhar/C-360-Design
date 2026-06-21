


--truncate audit and reject tables

truncate table P360_SP.AUDIT.DQ_RUN_LOG;
truncate table P360_SP.AUDIT.ERROR_LOG;
truncate table P360_SP.AUDIT.NOTIFICATION_LOG;
truncate table P360_SP.AUDIT.PKG_RUN_LOG;
truncate table P360_SP.AUDIT.SOURCE_ROW_COUNTS;
truncate table P360_SP.AUDIT.STEP_RUN_LOG;
truncate table P360_SP.REJECT.REJECT_RECORDS;
truncate table P360_SP.REJECT.REJECT_SUMMARY;


--truncate source data raw ingestion layer

truncate table  P360_SP.RAW_INGESTION.CLAIMS_RAW;
truncate table  P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW;
truncate table  P360_SP.RAW_INGESTION.NPI_RAW;
truncate table  P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW;
truncate table  P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW;


;--truncate bronze layer
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






--Load raw data--  first load at source raw layer
insert into P360_SP.RAW_INGESTION.CLAIMS_RAW
select* from p360_sp.test_data.CLAIMS_RAW_2026_06_01;

insert into P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
select* from p360_sp.test_data.NETWORK_AFFILIATIONS_RAW_2026_06_01;

insert into P360_SP.RAW_INGESTION.NPI_RAW
select* from p360_sp.test_data.NPI_RAW_2026_06_01;

insert into P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
select* from p360_sp.test_data.PROVIDER_CREDENTIALS_RAW_2026_06_01;

insert into P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
select* from p360_sp.test_data.PROVIDER_MASTER_RAW_2026_06_01;

-- Full refresh (initial load or reset)
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

--Raw ingestion tables-- source data pulled from EHR;

select* from P360_SP.RAW_INGESTION.CLAIMS_RAW;
select* from P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW;
select* from P360_SP.RAW_INGESTION.NPI_RAW;
select* from P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW;
select* from P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW;



--select audit log
select* from  P360_SP.AUDIT.PKG_RUN_LOG;
select* from  P360_SP.AUDIT.DQ_RUN_LOG;
select* from  P360_SP.AUDIT.SOURCE_ROW_COUNTS;
select* from  P360_SP.AUDIT.STEP_RUN_LOG;
select* from  P360_SP.REJECT.REJECT_RECORDS;
select* from  P360_SP.REJECT.REJECT_SUMMARY;
select* from  P360_SP.AUDIT.ERROR_LOG;
select* from  P360_SP.AUDIT.NOTIFICATION_LOG;--optional for email delivery



--Review summary views for audit and rejects
select* from P360_SP.ORCHESTRATION.VW_DQ_DASHBOARD;
select* from P360_SP.ORCHESTRATION.VW_ERROR_ANALYSIS;
select* from P360_SP.ORCHESTRATION.VW_REJECT_ANALYSIS;
select* from P360_SP.ORCHESTRATION.VW_RUN_HISTORY;
select* from P360_SP.ORCHESTRATION.VW_STEP_PERFORMANCE;



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

select* from P360_SP.GOLD.DIM_PROVIDER
--where npi_number='1234567890'
;

select* from P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES
--where npi_number='1234567890'
;
select* from P360_SP.GOLD.DIM_PROVIDER_NETWORK;
select* from P360_SP.GOLD.FCT_PROVIDER_VISITS;
select* from P360_SP.GOLD.PROVIDER_360_SUMMARY;





--Prepare for incremental data


-- incremental load
--load raw data -- incremental load (on top of already loaded data-- in append mode)
insert into P360_SP.RAW_INGESTION.CLAIMS_RAW
select* from p360_sp.test_data.CLAIMS_RAW_2026_06_10;

insert into P360_SP.RAW_INGESTION.NETWORK_AFFILIATIONS_RAW
select* from p360_sp.test_data.NETWORK_AFFILIATIONS_RAW_2026_06_10;

insert into P360_SP.RAW_INGESTION.NPI_RAW
select* from p360_sp.test_data.NPI_RAW_2026_06_10;

insert into P360_SP.RAW_INGESTION.PROVIDER_CREDENTIALS_RAW
select* from p360_sp.test_data.PROVIDER_CREDENTIALS_RAW_2026_06_10;

insert into P360_SP.RAW_INGESTION.PROVIDER_MASTER_RAW
select* from p360_sp.test_data.PROVIDER_MASTER_RAW_2026_06_10;
;



;


--Update DQ threshold

--Update DQ threshold to lower value so that package executions fails
update  P360_SP.CONFIG.PKG_CONFIG
 set config_value=10.0
where config_key='DQ_REJECT_THRESHOLD'
;

update  P360_SP.CONFIG.PKG_CONFIG
 set config_value=70.0
where config_key='DQ_REJECT_THRESHOLD'
;


-- Daily incremental processing
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('INCREMENTAL');







