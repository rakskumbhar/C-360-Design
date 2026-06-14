# Clinician-360-by-Snowflake-SP

**Enterprise Healthcare Provider 360 Data Pipeline — Snowflake Native Stored Procedures**

[![Snowflake](https://img.shields.io/badge/Platform-Snowflake-29B5E8?logo=snowflake&logoColor=white)](https://www.snowflake.com/)
[![SQL](https://img.shields.io/badge/Language-SQL-orange)](https://docs.snowflake.com/en/sql-reference)
[![License](https://img.shields.io/badge/License-Proprietary-red)]()
[![HIPAA](https://img.shields.io/badge/Compliance-HIPAA-green)]()

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Data Flow](#data-flow)
- [Project Structure](#project-structure)
- [Pipeline Execution](#pipeline-execution)
- [Data Quality Engine](#data-quality-engine)
- [Incremental Processing](#incremental-processing)
- [Monitoring and Observability](#monitoring-and-observability)
- [Healthcare Compliance](#healthcare-compliance)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Scheduling](#scheduling)
- [Data Retention](#data-retention)
- [Documentation](#documentation)
- [Contributing](#contributing)

---

## Overview

**Clinician-360-by-Snowflake-SP** (C-360-Design) is an enterprise-grade Provider 360 data pipeline implemented entirely using Snowflake native stored procedures. It delivers a comprehensive healthcare provider analytics solution using the **Medallion Architecture** (Bronze → Silver → Gold), providing superior control over execution flow, error handling, and operational monitoring compared to traditional dbt-based pipelines.

The pipeline ingests healthcare provider data from multiple authoritative sources — NPI Registry, Credentialing Systems, EMR, Claims, and Network Affiliations — applies rigorous data quality validation, deduplicates and unifies provider records, maintains historical changes via SCD Type-2, and produces a comprehensive **Provider 360 Summary** (One Big Table) for downstream analytics and reporting.

### Why Snowflake Native Stored Procedures?

| Capability | dbt-based Pipeline | This Project (SP-based) |
|---|---|---|
| Execution Control | External CLI / scheduler | Native stored procedure orchestrator |
| Error Handling | dbt hooks (limited) | Full try/catch with retry and resume |
| Data Quality | Post-execution tests | Inline DQ with reject-before-load |
| Incremental | `is_incremental()` macro | High-water-mark with explicit MERGE |
| SCD Type-2 | dbt snapshots | Custom hash-diff SCD2 procedure |
| Audit Trail | Limited run artifacts | Full run/step/error/DQ log tables |
| Resume | Not supported | Resume from exact failure point |
| Configuration | Static YAML files | Database tables (runtime modifiable) |
| Scheduling | External scheduler | Native Snowflake Tasks |

---

## Key Features

- **Medallion Architecture** — Bronze → Silver → Gold layered transformation with clear data contracts
- **Configuration-Driven** — All parameters externalized to database config tables; no code changes for environment switching
- **Fault Tolerant** — Retry logic with resume-from-failure capability at individual step granularity
- **Observable** — Complete audit trail for every run and step with built-in monitoring views
- **Healthcare Compliant** — HIPAA-aware schema separation, 365-day audit retention, least-privilege execution
- **Idempotent** — All procedures can be re-executed safely using MERGE-based operations
- **Inline Data Quality** — Validate-before-load pattern with reject capture and circuit breaker
- **SCD Type-2** — Full provider attribute history tracking via hash comparison
- **Native Scheduling** — Snowflake Tasks for automated daily incremental runs
- **Email Notifications** — Built-in alerting for pipeline events (start, complete, failure, DQ threshold)

---

## Architecture

### High-Level Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                          ORCHESTRATION LAYER                                      │
│    SP_RUN_PACKAGE(mode) → Dependency Graph → Retry → Notify → Audit              │
└──────────────┬───────────────────────────────────────────────────────────────────┘
               │
      ┌────────┼──────────────────────────────────────────────────────────┐
      │        ▼                                                           │
      │  ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌──────────┐ │
      │  │  BRONZE   │───▶│  SILVER   │───▶│   GOLD    │───▶│  AUDIT   │ │
      │  │  Layer    │    │  Layer    │    │  Layer    │    │  Layer   │ │
      │  └───────────┘    └───────────┘    └───────────┘    └──────────┘ │
      │       │                │                │                │        │
      │       ▼                ▼                ▼                ▼        │
      │  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐   │
      │  │STG_NPI   │    │UNIFIED   │    │DIM_PROV  │    │REJECT    │   │
      │  │STG_CRED  │    │DEDUPED   │    │DIM_NET   │    │SUMMARY   │   │
      │  │STG_EMR   │    │NETWORK   │    │FCT_VISIT │    │RUN_META  │   │
      │  │STG_CLM   │    │SCD2      │    │OBT_360   │    │DQ_LOG    │   │
      │  │STG_NET   │    └──────────┘    └──────────┘    └──────────┘   │
      │  └──────────┘                                                     │
      │       ▲                                                           │
      │       │                                                           │
      │  ┌─────────────────────────────────────────────┐                 │
      │  │           DATA QUALITY ENGINE               │                 │
      │  │    DQ Rules → Validate → Reject/Pass        │                 │
      │  └─────────────────────────────────────────────┘                 │
      └───────────────────────────────────────────────────────────────────┘
               ▲
               │
      ┌────────┴──────────────────────────────────────────────────────────┐
      │                      SOURCE LAYER                                  │
      │    SNOWFLAKE_LEARNING_DB.RAW_INGESTION                            │
      │    ├── NPI_RAW                                                     │
      │    ├── PROVIDER_CREDENTIALS_RAW                                    │
      │    ├── PROVIDER_MASTER_RAW                                         │
      │    ├── CLAIMS_RAW                                                  │
      │    └── NETWORK_AFFILIATIONS_RAW                                    │
      └────────────────────────────────────────────────────────────────────┘
```

### Database Schema Layout

```
P360_SP (Database)
├── CONFIG          → Package configuration, step registry, DQ rules, notifications
├── BRONZE          → Staged/cleaned data with DQ validation applied
├── SILVER          → Unified, deduplicated, enriched transformations
├── GOLD            → Business-ready dimensions, facts, Provider 360 OBT
├── AUDIT           → Run logs, step logs, error logs, DQ metrics
├── REJECT          → Rejected records and rejection summaries
├── SNAPSHOTS       → SCD Type-2 history tables
└── ORCHESTRATION   → Master procedures, tasks, monitoring views
```

---

## Data Flow

### Provider Master Data Flow (NPI → 360 Summary)

```
NPI_RAW ─────────────┐
                      │
CREDENTIALS_RAW ─────┼──▶ [DQ Validate] ──▶ BRONZE ──▶ INT_PROVIDERS_UNIFIED
                      │                                         │
EMR_MASTER_RAW ──────┘                                         ▼
                                                    INT_PROVIDERS_DEDUPED
                                                              │
                                                              ▼
                                                  SCD2_PROVIDER_ATTRIBUTES
                                                              │
                                                              ▼
                                                       DIM_PROVIDER ─────────┐
                                                                             │
CLAIMS_RAW ──▶ [DQ] ──▶ STG_CLAIMS ──▶ FCT_PROVIDER_VISITS ────────────────┼──▶ PROVIDER_360_SUMMARY
                                                                             │
NETWORK_RAW ──▶ [DQ] ──▶ STG_NETWORK ──▶ INT_NETWORK ──▶ DIM_NETWORK ──────┘
```

### Step Execution Order and Dependencies

| Order | Step ID | Step Name | Layer | Dependencies |
|-------|---------|-----------|-------|--------------|
| 1.0 | 1 | STG_NPI_REGISTRY | BRONZE | None |
| 1.1 | 2 | STG_CRED_PROVIDERS | BRONZE | None |
| 1.2 | 3 | STG_EMR_PROVIDERS | BRONZE | None |
| 1.3 | 4 | STG_CLAIMS_PROVIDERS | BRONZE | None |
| 1.4 | 5 | STG_NETWORK_AFFILIATIONS | BRONZE | None |
| 2.0 | 10 | INT_PROVIDERS_UNIFIED | SILVER | 1, 2, 3 |
| 2.1 | 11 | INT_PROVIDERS_DEDUPED | SILVER | 10 |
| 2.2 | 12 | INT_NETWORK_AFFILIATIONS | SILVER | 5 |
| 3.0 | 20 | SCD2_PROVIDER_ATTRIBUTES | SILVER | 10 |
| 4.0 | 30 | DIM_PROVIDER | GOLD | 20 |
| 4.1 | 31 | DIM_PROVIDER_NETWORK | GOLD | 12 |
| 4.2 | 32 | FCT_PROVIDER_VISITS | GOLD | 4 |
| 4.3 | 33 | PROVIDER_360_SUMMARY | GOLD | 30, 31, 32 |
| 5.0 | 40 | AUDIT_REJECT_SUMMARY | AUDIT | 33 |
| 5.1 | 41 | AUDIT_RUN_METADATA | AUDIT | 40 |

---

## Project Structure

```
Clinician-360-by-snowflake-sp/
├── 00_CONFIG/
│   ├── 001_setup_database_schemas.sql        # Database and schema DDL
│   ├── 002_configuration_tables.sql          # Config, step registry, DQ rules, notifications
│   └── 003_seed_configuration.sql            # Default configuration data
├── 01_FRAMEWORK/
│   ├── 001_audit_tables.sql                  # Run logs, step logs, error logs, DQ logs
│   ├── 002_utility_procedures.sql            # Logging, error handling, notifications
│   └── 003_target_tables.sql                 # All Bronze/Silver/Gold/Snapshot table DDL
├── 02_BRONZE/
│   ├── 001_sp_stg_npi_registry.sql           # NPI staging with DQ validation
│   ├── 002_sp_stg_cred_providers.sql         # Credentialing staging with DQ
│   ├── 003_sp_stg_emr_providers.sql          # EMR staging with DQ
│   ├── 004_sp_stg_claims_providers.sql       # Claims staging with DQ
│   └── 005_sp_stg_network_affiliations.sql   # Network staging with DQ
├── 03_SILVER/
│   ├── 001_sp_int_providers_unified.sql      # Multi-source provider unification
│   ├── 002_sp_int_providers_deduped.sql      # Deduplication by NPI
│   ├── 003_sp_int_network_affiliations.sql   # Network enrichment
│   └── 004_sp_scd2_provider_attributes.sql   # SCD Type-2 history tracking
├── 04_GOLD/
│   ├── 001_sp_dim_provider.sql               # Provider dimension (SCD2-sourced)
│   ├── 002_sp_dim_provider_network.sql       # Network dimension
│   ├── 003_sp_fct_provider_visits.sql        # Visits fact table (incremental)
│   └── 004_sp_provider_360_summary.sql       # One Big Table (OBT) summary
├── 05_AUDIT/
│   └── 001_sp_reject_summary.sql             # Reject summary + run metadata
├── 06_ORCHESTRATION/
│   ├── 001_sp_run_package.sql                # Master orchestrator procedure
│   └── 002_scheduling_and_tasks.sql          # Snowflake Tasks + monitoring views
├── 07_DEPLOY/
│   └── 001_deploy_all.sql                    # Deployment execution guide
├── docs/                                      # Detailed documentation
│   ├── ARCHITECTURE.md
│   ├── CODE_WALKTHROUGH.md
│   ├── INCREMENTAL_PROCESSING.md
│   ├── OPERATIONS.md
│   ├── Snowflake_SETUP.md
│   └── TESTING_NEW_DATA.md
└── README.md                                  # This file
```

---

## Pipeline Execution

### Execution Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `FULL` | Truncates all targets, processes all source data | Initial load, data fixes, weekly full refresh |
| `INCREMENTAL` | Uses high-water-mark, processes only new/changed records | Daily automated runs |
| `RESUME` | Resumes from last failed step of a specified run | Recovery after transient failures |
| `RERUN_STEP` | Re-executes a single step by ID | Targeted re-processing |

### Usage Examples

```sql
-- Full refresh (initial load or reset)
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

-- Daily incremental processing
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('INCREMENTAL');

-- Resume a failed run from its failure point
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RESUME', '<run_id>');

-- Re-run a specific step (e.g., step 10: INT_PROVIDERS_UNIFIED)
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RERUN_STEP', NULL, 10);
```

### Return Value Convention

All procedures return a structured VARIANT object:

```json
// Success
{"status": "COMPLETED", "rows_read": 1000, "rows_written": 985, "rows_rejected": 15}

// Failure
{"status": "FAILED", "error": "Division by zero", "reason": "DQ_THRESHOLD_EXCEEDED"}

// Skipped (disabled step)
{"status": "SKIPPED", "reason": "SCD2_DISABLED"}
```

---

## Data Quality Engine

The pipeline implements a **validate-before-load** pattern — a fundamental departure from post-execution test approaches:

```
┌─────────────┐     ┌──────────────┐     ┌───────────────────┐     ┌──────────────┐
│ Source Data  │────▶│  DQ Rules    │────▶│  Pass/Fail Split  │────▶│ Target Table │
└─────────────┘     │  Evaluation  │     │                   │     └──────────────┘
                    └──────────────┘     │   ┌───────────┐   │
                                         │   │  REJECT   │   │
                                         └──▶│  TABLE    │───┘
                                             └───────────┘
                                                  │
                                             ┌────▼─────┐
                                             │ CIRCUIT  │
                                             │ BREAKER  │
                                             └──────────┘
```

### Key DQ Capabilities

1. **Pre-load validation** — Records are validated BEFORE loading into target tables
2. **Reject capture** — Invalid records are routed to the REJECT schema with full context (reject reasons, source record, timestamp)
3. **Circuit breaker** — If reject percentage exceeds the configurable threshold (default 5%), the step FAILS immediately
4. **Configuration-driven rules** — DQ rules are stored in `CONFIG.DQ_RULES` table and can be modified at runtime
5. **No partial bad data** — Pipeline halts before bad data propagates downstream

---

## Incremental Processing

### High-Water Mark (HWM) Strategy

Each procedure uses a high-water mark pattern based on `_source_loaded_at` timestamps:

```sql
-- INCREMENTAL: Process only new records
SELECT * FROM source_table WHERE _loaded_at > v_high_water_mark;

-- FULL: Process all records (HWM reset to epoch)
TRUNCATE TABLE target_table;
SELECT * FROM source_table WHERE _loaded_at > '1900-01-01';
```

### MERGE-Based Idempotency

Silver and Gold layers use MERGE to ensure safe re-execution:
- Same data processed twice does not create duplicates
- Late-arriving data updates previous records
- Partial runs can be resumed without data corruption

### SCD Type-2 Change Detection

```
Source Change → Hash Mismatch → Close Old Version → Insert New Version
No Change    → Hash Match    → Skip (no action)
New Record   → No Existing   → Insert First Version
```

---

## Monitoring and Observability

### Built-in Monitoring Views

```sql
-- Run history (all pipeline executions)
SELECT * FROM P360_SP.ORCHESTRATION.VW_RUN_HISTORY;

-- Step-level performance metrics
SELECT * FROM P360_SP.ORCHESTRATION.VW_STEP_PERFORMANCE WHERE run_id = '<run_id>';

-- Data quality dashboard
SELECT * FROM P360_SP.ORCHESTRATION.VW_DQ_DASHBOARD WHERE run_id = '<run_id>';

-- Error investigation
SELECT * FROM P360_SP.ORCHESTRATION.VW_ERROR_ANALYSIS WHERE run_id = '<run_id>';

-- Reject analysis
SELECT * FROM P360_SP.ORCHESTRATION.VW_REJECT_ANALYSIS WHERE run_id = '<run_id>';
```

### Notification Events

| Event | Trigger | Recipients |
|-------|---------|------------|
| RUN_START | Pipeline begins | data-engineering |
| RUN_COMPLETE | Pipeline succeeds | data-engineering |
| RUN_FAILURE | Pipeline fails (after all retries) | data-engineering + on-call |
| DQ_THRESHOLD | Reject rate exceeds threshold | data-quality |
| STEP_FAILURE | Individual step fails (retrying) | data-engineering |

---

## Healthcare Compliance

This project implements the following enterprise healthcare standards:

| Standard | Implementation |
|----------|---------------|
| **HIPAA Compliance** | Schema-level data isolation, 365-day audit retention |
| **Data Lineage** | Complete `run_id` tracking through all layers |
| **Reject Handling** | Records failing DQ are captured with full context, never silently dropped |
| **Circuit Breaker** | Configurable DQ threshold stops pipeline before bad data propagates |
| **Change Data Capture** | SCD Type-2 for full provider attribute history |
| **Idempotency** | MERGE-based operations ensure safe re-runnability |
| **Least Privilege** | Procedures execute as caller for security context preservation |
| **Role-Based Access** | Three-tier RBAC: P360_ADMIN, P360_OPERATOR, P360_READER |

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Snowflake Account | Enterprise Edition or higher (required for Tasks) |
| Role | `ACCOUNTADMIN` for initial setup |
| Warehouse | `COMPUTE_WH` (or any available warehouse) |
| Source Data | `SNOWFLAKE_LEARNING_DB.RAW_INGESTION` with populated tables |

### Required Source Tables

| Table | Key Column | Description |
|-------|-----------|-------------|
| `NPI_RAW` | npi_number | CMS National Provider Identifier registry |
| `PROVIDER_CREDENTIALS_RAW` | npi_number | Provider credentialing records |
| `PROVIDER_MASTER_RAW` | npi_number | EMR provider master file |
| `CLAIMS_RAW` | claim_id, npi_number | Medical claims data |
| `NETWORK_AFFILIATIONS_RAW` | npi_number | Network participation records |

All source tables must include a `_loaded_at TIMESTAMP_NTZ` column for incremental processing.

---

## Quick Start

```sql
-- Step 1: Deploy infrastructure (schemas, tables, procedures)
-- Execute files in order from 00_CONFIG through 06_ORCHESTRATION
-- See docs/Snowflake_SETUP.md for detailed step-by-step instructions

-- Step 2: Seed configuration with defaults
-- Execute: 00_CONFIG/003_seed_configuration.sql

-- Step 3: Run initial full load
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

-- Step 4: Enable daily automated schedule
ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL RESUME;

-- Step 5: Monitor execution
SELECT * FROM P360_SP.ORCHESTRATION.VW_RUN_HISTORY;
```

---

## Configuration

All pipeline behavior is controlled via database configuration tables — no code changes required.

### View Current Configuration

```sql
SELECT config_key, config_value, config_category, description
FROM P360_SP.CONFIG.PKG_CONFIG
WHERE is_active = TRUE
ORDER BY config_category, config_key;
```

### Common Configuration Changes

```sql
-- Adjust DQ reject threshold (default: 5%)
UPDATE P360_SP.CONFIG.PKG_CONFIG
SET config_value = '3.0' WHERE config_key = 'DQ_REJECT_THRESHOLD';

-- Enable email notifications
UPDATE P360_SP.CONFIG.PKG_CONFIG
SET config_value = 'TRUE' WHERE config_key = 'ENABLE_EMAIL_NOTIFY';

-- Disable a specific step (e.g., SCD2)
UPDATE P360_SP.CONFIG.PKG_STEP_REGISTRY
SET is_active = FALSE WHERE step_id = 20;

-- Switch source environment
UPDATE P360_SP.CONFIG.PKG_CONFIG
SET config_value = 'PROD_DB' WHERE config_key = 'SOURCE_DATABASE';
```

---

## Scheduling

### Enable Automated Daily Incremental

```sql
ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL RESUME;
```

### Suspend Scheduling

```sql
ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL SUSPEND;
```

### Check Task Status

```sql
SHOW TASKS IN SCHEMA P360_SP.ORCHESTRATION;
```

---

## Data Retention

| Schema | Retention | Purpose |
|--------|-----------|---------|
| CONFIG | 90 days | Configuration time-travel |
| BRONZE | 30 days | Staged data recovery |
| SILVER | 30 days | Intermediate recovery |
| GOLD | 90 days | Business data recovery |
| AUDIT | 365 days | Compliance / audit trail |
| REJECT | 365 days | DQ investigation |
| SNAPSHOTS | 365 days | Historical SCD2 data |

---

## Documentation

Detailed documentation is available in the [`docs/`](docs/) folder:

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture, schema layout, design philosophy, step execution flow, dbt comparison |
| [CODE_WALKTHROUGH.md](docs/CODE_WALKTHROUGH.md) | Project structure, procedure patterns, key design decisions, data flow per source |
| [INCREMENTAL_PROCESSING.md](docs/INCREMENTAL_PROCESSING.md) | HWM strategy, MERGE idempotency, SCD2 logic, edge cases, monitoring queries |
| [OPERATIONS.md](docs/OPERATIONS.md) | Deployment, pipeline execution, monitoring views, configuration, scheduling, troubleshooting |
| [Snowflake_SETUP.md](docs/Snowflake_SETUP.md) | Prerequisites, step-by-step setup, RBAC configuration, environment setup |
| [TESTING_NEW_DATA.md](docs/TESTING_NEW_DATA.md) | Testing approach per layer, E2E pipeline tests, DQ threshold tests, resume tests |

---

## Contributing

### Deployment Order

When deploying changes, execute scripts in numerical order:

```
00_CONFIG  → 01_FRAMEWORK → 02_BRONZE → 03_SILVER → 04_GOLD → 05_AUDIT → 06_ORCHESTRATION → 07_DEPLOY
```

### Design Principles

1. All procedures must be **idempotent** (safe to re-run)
2. All procedures must return a **VARIANT** status object
3. DQ validation happens **before** loading, never after
4. Configuration changes must **not** require code changes
5. Every run and step must have a complete **audit trail**
6. Procedures execute as **CALLER** (least privilege)

---

## License

Proprietary. Internal use only.

---

**Project:** C-360-Design (Clinician-360-by-Snowflake-SP)  
**Platform:** Snowflake  
**Author:** RAKSKUMBHAR  
