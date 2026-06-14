# Architecture

## Provider-360-by-snowflake-sp

### Overview

Enterprise-grade Provider 360 data pipeline implemented entirely using Snowflake native stored procedures. This project replaces the dbt-based Provider_360 pipeline with a framework that provides superior control over execution flow, error handling, and operational monitoring.

### Design Philosophy

| Principle | Implementation |
|-----------|---------------|
| **Medallion Architecture** | Bronze → Silver → Gold layered transformation |
| **Configuration-Driven** | All parameters externalized to config tables |
| **Fault Tolerant** | Retry logic with resume-from-failure capability |
| **Observable** | Complete audit trail for every run and step |
| **Healthcare Compliant** | HIPAA-aware schema separation, audit retention |
| **Idempotent** | All procedures can be re-executed safely |

---

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        ORCHESTRATION LAYER                                    │
│  SP_RUN_PACKAGE(mode) → Dependency Graph → Retry → Notify → Audit           │
└────────────┬─────────────────────────────────────────────────────────────────┘
             │
    ┌────────┼────────────────────────────────────────────────────────┐
    │        ▼                                                         │
    │  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
    │  │  BRONZE  │───▶│  SILVER  │───▶│   GOLD   │───▶│  AUDIT   │  │
    │  │  Layer   │    │  Layer   │    │  Layer   │    │  Layer   │  │
    │  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
    │       │               │               │               │         │
    │       ▼               ▼               ▼               ▼         │
    │  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐     │
    │  │STG_NPI  │    │UNIFIED  │    │DIM_PROV │    │REJECT   │     │
    │  │STG_CRED │    │DEDUPED  │    │DIM_NET  │    │SUMMARY  │     │
    │  │STG_EMR  │    │NETWORK  │    │FCT_VISIT│    │RUN_META │     │
    │  │STG_CLM  │    │SCD2     │    │OBT_360  │    │DQ_LOG   │     │
    │  │STG_NET  │    └─────────┘    └─────────┘    └─────────┘     │
    │  └─────────┘                                                    │
    │       ▲                                                         │
    │       │                                                         │
    │  ┌─────────────────────────────────────────┐                   │
    │  │         DATA QUALITY ENGINE             │                   │
    │  │  DQ Rules → Validate → Reject/Pass     │                   │
    │  └─────────────────────────────────────────┘                   │
    └─────────────────────────────────────────────────────────────────┘
             ▲
             │
    ┌────────┴────────────────────────────────────────────────────────┐
    │                    SOURCE LAYER                                   │
    │  SNOWFLAKE_LEARNING_DB.RAW_INGESTION                            │
    │  ├── NPI_RAW                                                     │
    │  ├── PROVIDER_CREDENTIALS_RAW                                    │
    │  ├── PROVIDER_MASTER_RAW                                         │
    │  ├── CLAIMS_RAW                                                  │
    │  └── NETWORK_AFFILIATIONS_RAW                                    │
    └──────────────────────────────────────────────────────────────────┘
```

---

### Database Schema Layout

```
P360_SP (Database)
├── CONFIG          - Package configuration, step registry, DQ rules, notifications
├── RAW_INGESTION   - (Reference only - source lives in SNOWFLAKE_LEARNING_DB)
├── BRONZE          - Staged/cleaned data with DQ validation
├── SILVER          - Unified, deduplicated, enriched transformations
├── GOLD            - Business-ready dimensions, facts, OBT
├── AUDIT           - Run logs, step logs, error logs, DQ metrics
├── REJECT          - Rejected records and rejection summaries
├── SNAPSHOTS       - SCD Type-2 history tables
└── ORCHESTRATION   - Master procedures, tasks, monitoring views
```

---

### Step Execution Flow

| Order | Step ID | Name | Layer | Dependencies |
|-------|---------|------|-------|--------------|
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

### Key Differences from dbt Implementation

| Feature | dbt Project | Snowflake SP Project |
|---------|------------|---------------------|
| Execution Control | dbt CLI / scheduler | Native stored procedure orchestrator |
| Error Handling | dbt hooks (limited) | Full try/catch with retry & resume |
| Data Quality | dbt tests (post-execution) | Inline DQ with reject-before-load |
| Incremental | `is_incremental()` macro | High-water-mark with explicit MERGE |
| SCD2 | dbt snapshots | Custom hash-diff SCD2 procedure |
| Audit Trail | Limited run artifacts | Full run/step/error/DQ log tables |
| Notifications | External (Slack hooks) | Built-in email integration support |
| Resume | Not supported | Resume from exact failure point |
| Configuration | YAML files | Database tables (runtime modifiable) |
| Scheduling | External scheduler | Native Snowflake Tasks |

---

### Enterprise Healthcare Standards Implemented

1. **HIPAA Compliance**: Schema-level data isolation, 365-day audit retention
2. **Data Lineage**: Complete run_id tracking through all layers
3. **Reject Handling**: Records failing DQ are captured with full context, never lost
4. **Circuit Breaker**: Configurable DQ threshold stops pipeline before bad data propagates
5. **Change Data Capture**: SCD Type-2 for provider attribute history
6. **Idempotency**: MERGE-based operations ensure re-runnability
7. **Least Privilege**: Procedures execute as caller for security context preservation
