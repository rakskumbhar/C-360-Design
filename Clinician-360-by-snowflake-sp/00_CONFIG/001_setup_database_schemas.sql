/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  00_CONFIG/001_setup_database_schemas.sql
  
  Purpose: Creates the database, schemas, and foundational objects for the 
           Provider 360 Stored Procedure project.
  
  Healthcare Standard: HIPAA-compliant schema separation with least-privilege 
                       access patterns.
=============================================================================*/

-- ============================================================
-- DATABASE CREATION
-- ============================================================
CREATE DATABASE IF NOT EXISTS P360_SP
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Provider 360 - Snowflake Stored Procedure Implementation';

USE DATABASE P360_SP;

-- ============================================================
-- SCHEMA CREATION (Medallion Architecture)
-- ============================================================

-- Configuration & Framework
CREATE SCHEMA IF NOT EXISTS CONFIG
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Package configuration, run control, and framework metadata';

-- Raw Ingestion (Source)
CREATE SCHEMA IF NOT EXISTS RAW_INGESTION
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Raw source data landing zone - immutable raw records';

-- Bronze Layer (Staging)
CREATE SCHEMA IF NOT EXISTS BRONZE
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Staged/cleaned data with column renaming and type casting';

-- Silver Layer (Intermediate Transforms)
CREATE SCHEMA IF NOT EXISTS SILVER
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Unified, deduplicated, enriched provider data';

-- Gold Layer (Business/Consumption)
CREATE SCHEMA IF NOT EXISTS GOLD
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Business-ready dimensions, facts, and OBT tables';

-- Audit & Compliance
CREATE SCHEMA IF NOT EXISTS AUDIT
    DATA_RETENTION_TIME_IN_DAYS = 365
    COMMENT = 'Run logs, data quality metrics, reject records, audit trails';

-- Reject Layer
CREATE SCHEMA IF NOT EXISTS REJECT
    DATA_RETENTION_TIME_IN_DAYS = 365
    COMMENT = 'Rejected records from data quality validation';

-- Snapshot/SCD2 Layer
CREATE SCHEMA IF NOT EXISTS SNAPSHOTS
    DATA_RETENTION_TIME_IN_DAYS = 365
    COMMENT = 'Slowly Changing Dimension Type-2 history tables';

-- Orchestration
CREATE SCHEMA IF NOT EXISTS ORCHESTRATION
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Package orchestration, scheduling, and flow control';
