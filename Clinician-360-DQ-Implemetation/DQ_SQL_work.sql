-- Full ordered deployment script for Clinician-360 DQ Framework

/*=============================================================================
  07_DEPLOY/001_deploy_all.sql
  
  Purpose: Execute all scripts in correct dependency order.
  Usage:   Run each referenced script sequentially to deploy P360_DQ framework.
=============================================================================*/

-- Step 1: Database & Schemas
-- EXECUTE: 00_CONFIG/001_setup_database_schemas.sql

-- Step 2: Configuration Tables
-- EXECUTE: 00_CONFIG/002_configuration_tables.sql

-- Step 3: Seed Configuration
-- EXECUTE: 00_CONFIG/003_seed_configuration.sql

-- Step 4: Audit & DQ Tables
-- EXECUTE: 01_FRAMEWORK/001_audit_tables.sql

-- Step 5: Utility Procedures
-- EXECUTE: 01_FRAMEWORK/002_utility_procedures.sql

-- Step 6: Target Tables + Test Data
-- EXECUTE: 01_FRAMEWORK/003_target_tables.sql

-- Step 7: DQ Engine
-- EXECUTE: 01_FRAMEWORK/004_dq_engine_procedure.sql

-- Step 8: Bronze Staging
-- EXECUTE: 02_BRONZE/001_sp_stg_npi_registry.sql
-- EXECUTE: 02_BRONZE/002_sp_stg_specialty_type.sql
-- EXECUTE: 02_BRONZE/003_sp_run_dq_bronze.sql

-- Step 9: Silver
-- EXECUTE: 03_SILVER/001_sp_load_dim_provider.sql
-- EXECUTE: 03_SILVER/002_sp_run_dq_silver.sql
-- EXECUTE: 03_SILVER/003_sp_scd2_provider_attributes.sql

-- Step 10: Gold
-- EXECUTE: 04_GOLD/001_sp_load_fct_provider_360.sql

-- Step 11: Audit Summary
-- EXECUTE: 05_AUDIT/001_sp_reject_summary.sql

-- Step 12: Orchestrator
-- EXECUTE: 06_ORCHESTRATION/001_sp_run_package.sql

-- ============================================================
-- DEMO EXECUTION (run after all above are deployed)
-- ============================================================-- Full pipeline run:
CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

-- Incremental run:
-- CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('INCREMENTAL');

-- Resume from failure:
-- CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('RESUME', '<run_id>');
