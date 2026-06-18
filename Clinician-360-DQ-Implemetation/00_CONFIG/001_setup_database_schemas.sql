-- Creates P360_DQ database and all schemas for the Clinician-360 DQ framework
/*=============================================================================
  CLINICIAN-360-DQ-IMPLEMENTATION
  00_CONFIG/001_setup_database_schemas.sql
  
  Purpose: Creates the database and schemas for the Provider 360 Data Quality
           Framework implementation.
  
  Database: P360_DQ
  Schemas:  CONFIG, RAW_INGESTION, BRONZE, SILVER, GOLD, AUDIT, REJECT, ORCHESTRATION
=============================================================================*/

-- ============================================================
-- DATABASE CREATION
-- ============================================================
CREATE DATABASE IF NOT EXISTS P360_DQ
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 90 in prod
    COMMENT = 'Clinician 360 - Data Quality Framework Implementation';

USE DATABASE P360_DQ;

-- ============================================================
-- SCHEMA CREATION
-- ============================================================

-- Configuration & DQ Framework Metadata
CREATE SCHEMA IF NOT EXISTS CONFIG
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 90 in prod
    COMMENT = 'Package configuration, DQ rules, DQ feeds, DQ categories, notification config';

-- Raw Ingestion (Source - immutable landing zone)
CREATE SCHEMA IF NOT EXISTS RAW_INGESTION
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 90 in prod
    COMMENT = 'Raw source data landing zone - immutable raw records';

-- Bronze Layer (Staging - near replica of RAW, no DQ filtering)
CREATE SCHEMA IF NOT EXISTS BRONZE
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 30 in prod
    COMMENT = 'Staged data with type casting and column rename. DQ_STATUS updated by DQ engine.';

-- Silver Layer (Unified dimensions + SCD2)
CREATE SCHEMA IF NOT EXISTS SILVER
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 30 in prod
    COMMENT = 'Unified, deduplicated provider dimension and SCD2 history tables';

-- Gold Layer (Business-ready - only PASS/PASS-SOFT records)
CREATE SCHEMA IF NOT EXISTS GOLD
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 90 in prod
    COMMENT = 'Business-ready facts and summaries - only DQ-validated records';

-- Audit & DQ Results
CREATE SCHEMA IF NOT EXISTS AUDIT
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 365 in prod
    COMMENT = 'Run logs, DQ results, DQ logs, error logs, notification logs';

-- Reject Layer
CREATE SCHEMA IF NOT EXISTS REJECT
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 365 in prod
    COMMENT = 'Rejected records and rejection summaries';

-- Orchestration
CREATE SCHEMA IF NOT EXISTS ORCHESTRATION
    DATA_RETENTION_TIME_IN_DAYS = 01-- set it to 90 in prod
    COMMENT = 'Package orchestration, scheduling, and flow control';
