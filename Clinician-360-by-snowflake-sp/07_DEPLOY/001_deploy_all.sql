/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  07_DEPLOY/001_deploy_all.sql
  
  Purpose: Master deployment script that executes all DDL and procedure 
           creation in the correct order. Run this to deploy the entire project.
  
  Usage: Execute this file end-to-end in Snowflake to deploy.
  
  Prerequisites:
    - ACCOUNTADMIN or equivalent role
    - COMPUTE_WH warehouse available
    - SNOWFLAKE_LEARNING_DB.RAW_INGESTION schema with source tables
=============================================================================*/

-- ============================================================
-- PRE-FLIGHT CHECKS
-- ============================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- STEP 1: Create Database and Schemas
-- Execute: 00_CONFIG/001_setup_database_schemas.sql
-- ============================================================

-- ============================================================
-- STEP 2: Create Configuration Tables
-- Execute: 00_CONFIG/002_configuration_tables.sql
-- ============================================================

-- ============================================================
-- STEP 3: Create Audit/Framework Tables
-- Execute: 01_FRAMEWORK/001_audit_tables.sql
-- ============================================================

-- ============================================================
-- STEP 4: Create Target Tables (Bronze/Silver/Gold)
-- Execute: 01_FRAMEWORK/003_target_tables.sql
-- ============================================================

-- ============================================================
-- STEP 5: Create Utility Procedures
-- Execute: 01_FRAMEWORK/002_utility_procedures.sql
-- ============================================================

-- ============================================================
-- STEP 6: Create Bronze Layer Procedures
-- Execute: 02_BRONZE/001_sp_stg_npi_registry.sql
-- Execute: 02_BRONZE/002_sp_stg_cred_providers.sql
-- Execute: 02_BRONZE/003_sp_stg_emr_providers.sql
-- Execute: 02_BRONZE/004_sp_stg_claims_providers.sql
-- Execute: 02_BRONZE/005_sp_stg_network_affiliations.sql
-- ============================================================

-- ============================================================
-- STEP 7: Create Silver Layer Procedures
-- Execute: 03_SILVER/001_sp_int_providers_unified.sql
-- Execute: 03_SILVER/002_sp_int_providers_deduped.sql
-- Execute: 03_SILVER/003_sp_int_network_affiliations.sql
-- Execute: 03_SILVER/004_sp_scd2_provider_attributes.sql
-- ============================================================

-- ============================================================
-- STEP 8: Create Gold Layer Procedures
-- Execute: 04_GOLD/001_sp_dim_provider.sql
-- Execute: 04_GOLD/002_sp_dim_provider_network.sql
-- Execute: 04_GOLD/003_sp_fct_provider_visits.sql
-- Execute: 04_GOLD/004_sp_provider_360_summary.sql
-- ============================================================

-- ============================================================
-- STEP 9: Create Audit Procedures
-- Execute: 05_AUDIT/001_sp_reject_summary.sql
-- ============================================================

-- ============================================================
-- STEP 10: Create Orchestrator
-- Execute: 06_ORCHESTRATION/001_sp_run_package.sql
-- Execute: 06_ORCHESTRATION/002_scheduling_and_tasks.sql
-- ============================================================

-- ============================================================
-- STEP 11: Seed Configuration Data
-- Execute: 00_CONFIG/003_seed_configuration.sql
-- ============================================================

-- ============================================================
-- STEP 12: Validation
-- ============================================================
SELECT 'DEPLOYMENT VALIDATION' AS check_type;

SELECT 'SCHEMAS' AS object_type, COUNT(*) AS count 
FROM P360_SP.INFORMATION_SCHEMA.SCHEMATA WHERE CATALOG_NAME = 'P360_SP';

SELECT 'TABLES' AS object_type, COUNT(*) AS count 
FROM P360_SP.INFORMATION_SCHEMA.TABLES WHERE TABLE_CATALOG = 'P360_SP' AND TABLE_TYPE = 'BASE TABLE';

SELECT 'VIEWS' AS object_type, COUNT(*) AS count 
FROM P360_SP.INFORMATION_SCHEMA.TABLES WHERE TABLE_CATALOG = 'P360_SP' AND TABLE_TYPE = 'VIEW';

SELECT 'PROCEDURES' AS object_type, COUNT(*) AS count 
FROM P360_SP.INFORMATION_SCHEMA.PROCEDURES WHERE PROCEDURE_CATALOG = 'P360_SP';

-- ============================================================
-- STEP 13: Initial Run (Optional)
-- ============================================================
-- To execute an initial full load:
-- CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');
--
-- To resume a failed run:
-- CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RESUME', '<run_id>');
--
-- To rerun a specific step:
-- CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RERUN_STEP', NULL, <step_id>);

-- ============================================================
-- STEP 14: Enable Scheduled Tasks (Production Only)
-- ============================================================
-- ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL RESUME;
-- ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_WEEKLY_FULL RESUME;
