# Clinician-360 Data Quality Framework - Comprehensive Design Document
---

## 1. Executive Overview

### Business Purpose

Perform data quality validations on various dimensions across multiple layers (Bronze, Silver, and Gold) to ensure business users trust the data available on the Snowflake Platform.

### Summary

An **integrated, enterprise-grade data pipeline** with a **highly configurable and reusable Data Quality (DQ) framework** built using Snowflake native stored procedures. This project combines the proven Clinician-360 pipeline patterns (audit, reject handling, SCD Type-2, orchestration with retry/resume) with a new metadata-driven DQ engine that performs rule-based validation across all layers.

**Database:** `P360_DQ` (separate from the reference `P360_SP`)

**Key Differentiator:** DQ checks are **configuration-driven** — adding validation to any new table requires only inserting rows into metadata tables (DQ_FEED, DQ_RULE). No code changes needed.

---

## 2. Design Philosophy

| Principle | Implementation |
|-----------|---------------|
| **Medallion Architecture** | Bronze → Silver → Gold layered transformation |
| **Configuration-Driven DQ** | All rules, feeds, categories externalized to config tables |
| **Reusable DQ Engine** | Single generic procedure works across any table/layer/column |
| **Layer-Agnostic DQ** | DQ checks open to all layers (Bronze, Silver, Gold); primarily applied on Bronze and Silver |
| **Three-Outcome Model** | PASS / FAIL / PASS-SOFT based on rule criticality |
| **Incremental DQ Processing** | Delta-based checks using DQ_LOG timestamps (dq_start_ts / dq_end_ts) |
| **Circuit Breaker** | DQ threshold exceeds → blocks next layer execution |
| **Fault Tolerant** | Retry logic with resume-from-failure capability |
| **Observable** | Complete audit trail via DQ_LOG, DQ_LOG_HISTORY, DQ_RESULT |
| **Idempotent** | All procedures can be re-executed safely |
| **Healthcare Compliant** | HIPAA-aware schema separation, 365-day audit retention |
| **DMF Integration** | Snowflake Data Metric Functions for continuous monitoring |

---

## 3. Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                          ORCHESTRATION LAYER                                          │
│  SP_RUN_PACKAGE(mode) → Dependency Graph → DQ Gate → Retry → Notify → Audit         │
└────────────┬─────────────────────────────────────────────────────────────────────────┘
             │
    ┌────────┼─────────────────────────────────────────────────────────────────────┐
    │        ▼                                                                      │
    │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────┐   │
    │  │   BRONZE     │───▶│   SILVER     │───▶│    GOLD      │───▶│  AUDIT   │   │
    │  │   Layer      │    │   Layer      │    │   Layer      │    │  Layer   │   │
    │  └──────┬───────┘    └──────┬───────┘    └──────────────┘    └──────────┘   │
    │         │                   │                                                 │
    │         ▼                   ▼                                                 │
    │  ┌──────────────┐    ┌──────────────┐                                        │
    │  │  DQ CHECK    │    │  DQ CHECK    │       Gold receives ONLY records       │
    │  │  (Bronze)    │    │  (Silver)    │       with DQ_STATUS IN                │
    │  │              │    │              │       ('PASS','PASS-SOFT')              │
    │  │ PASS → Silver│    │ PASS → Gold  │                                        │
    │  │ FAIL → Block │    │ FAIL → Block │                                        │
    │  │ SOFT → Silver│    │ SOFT → Gold  │                                        │
    │  └──────────────┘    └──────────────┘                                        │
    │         │                   │                                                 │
    │         ▼                   ▼                                                 │
    │  ┌─────────────────────────────────────────────────────────────────────┐     │
    │  │                    DQ ENGINE (SP_RUN_DQ_CHECK)                       │     │
    │  │                                                                      │     │
    │  │  Reads: DQ_CATEGORIES → DQ_RULES → DQ_FEEDS                        │     │
    │  │  Writes: DQ_RESULTS + Updates DQ_STATUS on source table             │     │
    │  │  Notifies: DQ_EMAILS if threshold exceeded                          │     │
    │  │  Profiles: Column-level stats every execution                       │     │
    │  └─────────────────────────────────────────────────────────────────────┘     │
    │                                                                               │
    │  ┌─────────────────────────────────────────────────────────────────────┐     │
    │  │                    REJECT & AUDIT FRAMEWORK                          │     │
    │  │  REJECT_RECORDS │ REJECT_SUMMARY │ PKG_RUN_LOG │ STEP_RUN_LOG       │     │
    │  │  ERROR_LOG │ DQ_RUN_LOG │ NOTIFICATION_LOG │ SOURCE_ROW_COUNTS      │     │
    │  └─────────────────────────────────────────────────────────────────────┘     │
    └───────────────────────────────────────────────────────────────────────────────┘
             ▲
             │
    ┌────────┴─────────────────────────────────────────────────────────────────────┐
    │                         SOURCE / RAW LAYER                                    │
    │  P360_DQ.RAW_INGESTION                                                       │
    │  ├── RAW_NPI_REGISTRY          (NPI demographics + identifiers)              │
    │  └── RAW_SPECIALTY_TYPE        (Specialty taxonomy reference)                 │
    └───────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Database & Schema Layout

```
P360_DQ (Database)
├── CONFIG             - Package config, step registry, DQ metadata tables
│                        (DQ_CATEGORY, DQ_RULE, DQ_FEED, DQ_EMAIL)
├── RAW_INGESTION      - Immutable raw source data landing zone
├── BRONZE             - Staged/cleaned data with DQ_STATUS column
├── SILVER             - Unified dimension + SCD2 history (DQ validated)
├── GOLD               - Business-ready (only PASS/PASS-SOFT records)
├── AUDIT              - Run logs, step logs, DQ_LOG, DQ_LOG_HISTORY,
│                        DQ_RESULT, notification logs
├── REJECT             - Rejected records with full context
└── ORCHESTRATION      - Master procedures, tasks, monitoring
```

**Note:** No separate SNAPSHOTS schema — SCD2 tables reside in SILVER.

---

## 5. DQ Status Updates in Bronze Layer

### Two Scenarios

**1. Insert Records (New Data)**

When new records come into the Bronze layer from the ingestion framework, the `DQ_STATUS` column will be `NULL`. Later during DQ checks, this attribute will be updated to FAIL / PASS / PASS-SOFT.

**2. Update Records (UPSERT Logic)**

When bronze table records are updated as part of the UPSERT logic, along with the business-related attributes, the `DQ_STATUS` field will be reset to `NULL`. This signals that a change occurred and DQ checks have not yet been applied. Later during DQ checks, this attribute will be updated to FAIL / PASS / PASS-SOFT.

```
NEW RECORD (INSERT)      → DQ_STATUS = NULL → DQ Engine → PASS / FAIL / PASS-SOFT
UPDATED RECORD (UPSERT)  → DQ_STATUS = NULL → DQ Engine → PASS / FAIL / PASS-SOFT
```

---

## 6. Data Quality Framework — Configuration Tables

### 6.1 Table Relationships

```
DQ_CATEGORY.CATEGORY_ID  ──────►  DQ_RULE.CATEGORY_ID
DQ_RULE.RULE_ID           ──────►  DQ_FEED.RULE_ID
DQ_FEED.FEED_ID           ──────►  DQ_RESULT.FEED_ID
DQ_RULE.RULE_ID           ──────►  DQ_RESULT.RULE_ID
DQ_FEED.DOMAIN            ──────►  DQ_EMAIL.DOMAIN
DQ_RESULT.TABLE_NM        ──────►  Target Table (logical link)
DQ_RESULT.RECORD_KEY      ──────►  Business/Surrogate Key in target table
```

### 6.2 DQ_CATEGORY

```sql
CREATE OR REPLACE TABLE DQ_CATEGORY (
    CATEGORY_ID     NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 NOORDER,
    CATEGORY_NM     STRING,
    CATEGORY_DESC   STRING,
    RECORD_INS_TS   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    RECORD_UPD_TS   TIMESTAMP_NTZ,
    RECORD_INS_BY   STRING,
    RECORD_UPD_BY   STRING
);
```

### 6.3 DQ_RULE

```sql
CREATE OR REPLACE TABLE DQ_RULE (
    RULE_ID         NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 NOORDER,
    CATEGORY_ID     INTEGER,
    RULE_CODE       STRING,
    RULE_DESC       STRING,
    RULE_EXP        STRING,
    RULE_CATEGORY   STRING,    -- SIMPLE / MULTIPLE / COMPLEX / SQL FEED
    RECORD_INS_TS   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    RECORD_UPD_TS   TIMESTAMP_NTZ,
    RECORD_INS_BY   STRING,
    RECORD_UPD_BY   STRING
);
```

**Rule Categories:** SIMPLE (one column), MULTIPLE (multiple columns same table), COMPLEX (joins/duplicates), SQL FEED (custom query)

**Sample Rules:**

| RULE_ID | CAT_ID | RULE_CODE | RULE_DESC | RULE_CATEGORY |
|---------|--------|-----------|-----------|---------------|
| 1 | 4 | GN_Duplicate | Check columns has no duplicates | COMPLEX |
| 2 | 2 | GN_NotNull | Check mandatory fields are not null | SIMPLE |
| 3 | 2 | GN_LOOKUP | Check code exists in reference table | COMPLEX |
| 4 | 6 | GN_Length2 | Validate string length is 2 chars | SIMPLE |
| 5 | 6 | GN_Length9 | Validate string length is 9 chars | SIMPLE |
| 6 | 6 | GN_Length10 | Validate string length is 10 chars | SIMPLE |
| 7 | 6 | GN_FormatTIN | Validate xxx-xx-xxxx format | SIMPLE |
| 8 | 1 | GN_UpperCase | Check field is in upper case | SIMPLE |
| 9 | 5 | GN_Timeliness | Validate data not stale | SIMPLE |
| 10 | 7 | GN_RefIntegrity | Referential integrity cross-table | COMPLEX |

### 6.4 DQ_FEED

```sql
CREATE OR REPLACE TABLE DQ_FEED (
    FEED_ID                     NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 NOORDER,
    LAYER                       VARCHAR(20),
    DOMAIN                      VARCHAR(50),
    RULE_ID                     NUMBER(38,0),
    TABLE_NM                    VARCHAR(100),
    RECORD_KEY_NM               VARCHAR(100),
    INCREMENTAL_DATE_COLUMN     VARCHAR(16777216),
    DQ_RULE_INPUT               VARCHAR(200),
    CRITICALITY_IND             VARCHAR(1),
    ACTIVE_IND                  VARCHAR(1),
    EXECUTION_GROUP             VARCHAR(50),
    DQ_RULE_INPUT_JOIN_TBL      VARCHAR(100),
    DQ_RULE_INPUT_JOIN_COL      VARCHAR(100),
    DQ_RULE_INPUT_WHERE_COL     VARCHAR(100),
    RECORD_INS_TS               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    RECORD_UPD_TS               TIMESTAMP_NTZ,
    RECORD_INS_BY               STRING,
    RECORD_UPD_BY               STRING
);
```

**Flag Behavior:** ACTIVE_IND=Y → include; CRITICALITY_IND=Y + FAIL → 'FAIL'; CRITICALITY_IND=N + FAIL → 'PASS-SOFT'

**EXECUTION_GROUP:** Enables parallel batch execution of DQ checks. Tables in the same group run together. At 80-table scale, assign groups (e.g., GROUP_A, GROUP_B, GROUP_C) so Snowflake Tasks can process groups in parallel rather than sequentially looping through all tables.

### 6.5 DQ_LOG + DQ_LOG_HISTORY

```sql
CREATE OR REPLACE TABLE DQ_LOG (
    DQ_BATCH_ID     VARCHAR(16777216),
    LAYER           VARCHAR(16777216),
    DOMAIN          VARCHAR(16777216),
    TABLE_NM        VARCHAR(16777216) NOT NULL,
    FEED_ID         NUMBER(38,0),
    DQ_START_TS     TIMESTAMP_NTZ(9),
    DQ_END_TS       TIMESTAMP_NTZ(9),
    ERROR_MESSAGE   VARCHAR(16777216),
    OVERALL_COUNT   NUMBER(38,0),
    FAILED_COUNT    NUMBER(38,0),
    STATUS          VARCHAR(16777216),
    UPDATED_TS      TIMESTAMP_NTZ(9)
);
-- DQ_LOG_HISTORY has identical structure for archival
```

**Incremental Logic:** dq_start_ts = previous dq_end_ts; dq_end_ts = CURRENT_TIMESTAMP

### 6.6 DQ_RESULT

```sql
CREATE OR REPLACE TABLE DQ_RESULT (
    DQ_BATCH_ID         VARCHAR(16777216),
    LAYER               VARCHAR(100),
    DOMAIN              VARCHAR(100),
    TABLE_NM            VARCHAR(500),
    RULE_ID             NUMBER(38,0),
    FEED_ID             NUMBER(38,0),
    RECORD_KEY          VARCHAR(500),
    RECORD_VALUE        VARCHAR(16777216),
    RECORD_UPDATED_TS   VARCHAR(16777216),
    RESULT              VARCHAR(100),
    RECORD_INS_TS       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    RECORD_UPD_TS       TIMESTAMP_NTZ,
    RECORD_INS_BY       STRING,
    RECORD_UPD_BY       STRING
);
```

### 6.7 DQ_EMAIL

```sql
CREATE OR REPLACE TABLE DQ_EMAIL (
    EMAIL_ID        INTEGER,
    DOMAIN          STRING,
    EMAILS          STRING,
    RECORD_INS_TS   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    RECORD_UPD_TS   TIMESTAMP_NTZ,
    RECORD_INS_BY   STRING,
    RECORD_UPD_BY   STRING
);
```

---

## 7. DQ Rule Expression Placeholders

| Placeholder | Source | Description |
|-------------|--------|-------------|
| `${INPUT1}` | DQ_FEED.DQ_RULE_INPUT | Single column for SIMPLE rules |
| `${INPUTN}` | DQ_FEED.DQ_RULE_INPUT | Column(s) for COMPLEX duplicates |
| `${TABLE_NAME}` | DQ_FEED.TABLE_NM | Source table |
| `${INCREMENTAL_DATE_COLUMN}` | DQ_FEED.INCREMENTAL_DATE_COLUMN | Delta filter |
| `${JOINTBL1}` | DQ_FEED.TABLE_NM | Primary table |
| `${JOINTBL2}` | DQ_FEED.DQ_RULE_INPUT_JOIN_TBL | Reference table |
| `${JOINCOL1}` | DQ_FEED.DQ_RULE_INPUT | Join column (primary) |
| `${JOINCOL2}` | DQ_FEED.DQ_RULE_INPUT_JOIN_COL | Join column (reference) |
| `${WHERECOL1}` | DQ_FEED.DQ_RULE_INPUT_WHERE_COL | Where-clause column |

---

## 8. Sample Business Rules

| Rule ID | Layer | Entity | Critical? | Attribute | Rule Description | Category |
|---------|-------|--------|-----------|-----------|------------------|----------|
| PRV-1 | Silver | Provider | Yes | Provider ID | Cannot be blank | Uniqueness |
| PRV-2 | Silver | Provider | Yes | First Name | Must be in upper case | Accuracy |
| PRV-3 | Silver | Provider | Yes | Last Name | Must be in upper case | Accuracy |
| PRV-4 | Silver | Provider | Yes | Address | Requires Address Line 1 | Accuracy |
| PRV-5 | Silver | Provider | Yes | City | Cannot be empty | Accuracy |
| PRV-6 | Silver | Provider | Yes | State | Must contain valid name or abbreviation | Validity |

---

## 9. Pipeline Configuration (PKG_CONFIG)

Key-value store for runtime parameters — inherited from reference framework.

| Column | Type | Description |
|--------|------|-------------|
| CONFIG_KEY | VARCHAR(100) | Primary Key |
| CONFIG_VALUE | VARCHAR(4000) | Parameter value |
| CONFIG_DATA_TYPE | VARCHAR(20) | STRING, NUMBER, BOOLEAN |
| CONFIG_CATEGORY | VARCHAR(50) | Grouping (DQ, PIPELINE, NOTIFICATION, etc.) |
| DESCRIPTION | VARCHAR(500) | Human-readable description |
| IS_ACTIVE | BOOLEAN | Enable/disable flag |
| CREATED_AT | TIMESTAMP_NTZ | Record creation timestamp |
| UPDATED_AT | TIMESTAMP_NTZ | Last modification timestamp |

**Key Config Entries:**

| Key | Value | Category | Description |
|-----|-------|----------|-------------|
| PKG_NAME | CLINICIAN_360_DQ | PIPELINE | Package identifier |
| ENVIRONMENT | DEV | PIPELINE | Current environment |
| SOURCE_DATABASE | P360_DQ | PIPELINE | Source database |
| SOURCE_SCHEMA | RAW_INGESTION | PIPELINE | Source schema |
| DQ_REJECT_THRESHOLD | 5.00 | DQ | Max reject % before circuit breaker |
| DQ_BRONZE_THRESHOLD | 10.00 | DQ | Bronze-specific threshold |
| DQ_SILVER_THRESHOLD | 5.00 | DQ | Silver-specific threshold |
| ENABLE_DQ_PROFILING | TRUE | DQ | Run profiling every execution |
| ENABLE_SCD2 | TRUE | PIPELINE | Enable SCD Type-2 tracking |
| ENABLE_EMAIL_NOTIFY | FALSE | NOTIFICATION | Email notification toggle |
| MAX_RETRY_COUNT | 3 | PIPELINE | Default retry attempts |
| RETRY_DELAY_SECONDS | 60 | PIPELINE | Delay between retries |

### 9.2 Step Registry (PKG_STEP_REGISTRY)

| Order | Step ID | Name | Layer | Dependencies |
|-------|---------|------|-------|--------------|
| 1.0 | 1 | STG_NPI_REGISTRY | BRONZE | None |
| 1.1 | 2 | STG_SPECIALTY_TYPE | BRONZE | None |
| 2.0 | 10 | DQ_CHECK_BRONZE | DQ_BRONZE | 1, 2 |
| 3.0 | 20 | LOAD_DIM_PROVIDER | SILVER | 10 |
| 4.0 | 30 | DQ_CHECK_SILVER | DQ_SILVER | 20 |
| 5.0 | 40 | SCD2_PROVIDER_ATTRIBUTES | SILVER | 30 |
| 6.0 | 50 | LOAD_FCT_PROVIDER_360 | GOLD | 40 |
| 7.0 | 60 | AUDIT_REJECT_SUMMARY | AUDIT | 50 |

---

## 10. DQ Engine Procedure Design (SP_RUN_DQ_CHECK)

### Process Flow

```
1. SP reads DQ_FEED for given TABLE_NM + LAYER (ACTIVE_IND = 'Y')
2. Joins with DQ_RULE & DQ_CATEGORY tables
3. DQ checks performed based on logic in DQ_RULE.RULE_EXP
4. Failed records → DQ_STATUS updated as 'FAIL' on source table
5. Passed records → DQ_STATUS updated as 'PASS'
6. Non-critical fails → DQ_STATUS updated as 'PASS-SOFT'
7. Results inserted in DQ_RESULT table
8. Execution logged in DQ_LOG + DQ_LOG_HISTORY
9. Email notifications sent with details of failed records
```

### Procedure Signature

```
SP_RUN_DQ_CHECK(P_RUN_ID VARCHAR, P_TABLE_NM VARCHAR, P_LAYER VARCHAR, P_DQ_BATCH_ID VARCHAR)
```

### Logic

```
1. INITIALIZE
   - Read DQ_LOG for last dq_end_ts (incremental window)
   - Set dq_start_ts = last dq_end_ts; dq_end_ts = CURRENT_TIMESTAMP

2. FETCH FEEDS
   - SELECT from DQ_FEED WHERE TABLE_NM AND LAYER AND ACTIVE_IND = 'Y'
   - JOIN DQ_RULE + DQ_CATEGORY

3. FOR EACH FEED:
   a. Read RULE_CATEGORY (SIMPLE/MULTIPLE/COMPLEX/SQL FEED)
   b. BUILD DYNAMIC SQL replacing ${INPUT1}, ${TABLE_NAME}, etc.
   c. APPLY FILTER: WHERE DQ_STATUS IS NULL (new/changed records)
   d. EXECUTE and capture results
   e. INSERT failed records into DQ_RESULT
   f. DETERMINE DQ_STATUS:
      CRITICALITY_IND='Y' + FAIL → 'FAIL'
      CRITICALITY_IND='N' + FAIL → 'PASS-SOFT'
      PASS → 'PASS'

4. AGGREGATE per record (worst wins: FAIL > PASS-SOFT > PASS)
5. UPDATE source table SET DQ_STATUS
6. LOG to DQ_LOG + DQ_LOG_HISTORY
7. CHECK THRESHOLD → if exceeded, notify + return FAILED
8. RETURN result object
```

---

## 11. Source & Target Tables (Summary)

### Bronze (STG_ prefix)
- **STG_NPI_REGISTRY** — NPI_SK, NPI_NUMBER, PROVIDER_NAME, STATE, etc. + DQ_STATUS
- **STG_SPECIALTY_TYPE** — SPECIALTY_SK, SPECIALTY_CODE, SPECIALTY_NAME, STATE, etc. + DQ_STATUS

### Silver (DIM_ prefix)
- **DIM_PROVIDER** — PROVIDER_SK, PROVIDER_NPI, PROVIDER_NAME, STATE, ADDRESS, etc. + DQ_STATUS
- **SCD2_PROVIDER_ATTRIBUTES** — SCD_KEY, PROVIDER_BK, _VALID_FROM, _VALID_TO, _IS_CURRENT, _HASH_DIFF

### Gold (FCT_ prefix)
- **FCT_PROVIDER_360** — PROVIDER_SK, PROVIDER_NPI, PROVIDER_NAME, business-derived columns
- Gold filter: `WHERE DQ_STATUS IN ('PASS','PASS-SOFT')` from Silver

---

## 12. Pipeline Execution Flow (End-to-End)

### Design Decision: No Inline Rejects at Bronze

Bronze layer is a **near-replica of RAW** with minimal transformation (type casting, column renaming) but **no DQ-based filtering**. All records — including bad data — land in Bronze with `DQ_STATUS = NULL`. The DQ engine evaluates them in Step 2.

**Pros:**
- Bronze is a faithful copy of source — nothing is silently dropped
- DQ logic is centralized in the DQ engine (single place to maintain rules)
- Bad records remain visible and queryable in Bronze for debugging
- Rule changes don't require re-ingestion — just re-run DQ engine
- Clear separation of concerns: ingestion vs. validation

**Cons:**
- Bronze tables are larger (include bad records that will never reach Silver)
- DQ engine must process all records including obviously bad ones
- Slightly more compute spent evaluating records that are clearly invalid

**Mitigation:** The incremental DQ processing (via DQ_LOG timestamps and DQ_STATUS IS NULL filter) ensures only new/changed records are evaluated, keeping compute manageable.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  SP_RUN_PACKAGE('INCREMENTAL')                                                   │
│                                                                                   │
│  Step 1: BRONZE STAGING (near-replica of RAW, no DQ filtering)                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_STG_NPI_REGISTRY(run_id, mode)                                      │    │
│  │    → Read from RAW_INGESTION.RAW_NPI_REGISTRY (HWM-based)              │    │
│  │    → Minimal transform: type casting, column rename                     │    │
│  │    → Insert ALL records into BRONZE.STG_NPI_REGISTRY (DQ_STATUS=NULL)  │    │
│  │    → No inline reject — bad records included for DQ evaluation later   │    │
│  │                                                                          │    │
│  │  SP_STG_SPECIALTY_TYPE(run_id, mode)                                    │    │
│  │    → Read from RAW_INGESTION.RAW_SPECIALTY_TYPE (HWM-based)            │    │
│  │    → Insert ALL records into BRONZE.STG_SPECIALTY_TYPE (DQ_STATUS=NULL) │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                                     ▼                                            │
│  Step 2: DQ CHECK — BRONZE                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_RUN_DQ_BRONZE(run_id)                                               │    │
│  │    → SP_RUN_DQ_CHECK(run_id, 'STG_NPI_REGISTRY', 'BRONZE', batch_id)   │    │
│  │    → SP_RUN_DQ_CHECK(run_id, 'STG_SPECIALTY_TYPE', 'BRONZE', batch_id) │    │
│  │    → Evaluates all records WHERE DQ_STATUS IS NULL                      │    │
│  │    → Updates DQ_STATUS (PASS / FAIL / PASS-SOFT) on each record         │    │
│  │    → Inserts results into AUDIT.DQ_RESULT                               │    │
│  │    → Logs to AUDIT.DQ_LOG + DQ_LOG_HISTORY                             │    │
│  │    → If threshold exceeded → PIPELINE STOPS (circuit breaker)           │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                          (Only if DQ passed threshold)                            │
│                                     ▼                                            │
│  Step 3: SILVER LOAD                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_LOAD_DIM_PROVIDER(run_id, mode)                                     │    │
│  │    → SELECT from Bronze WHERE DQ_STATUS IN ('PASS', 'PASS-SOFT')        │    │
│  │    → Unify NPI + Specialty into DIM_PROVIDER                            │    │
│  │    → MERGE into SILVER.DIM_PROVIDER (DQ_STATUS = NULL on new/changed)   │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                                     ▼                                            │
│  Step 4: DQ CHECK — SILVER                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_RUN_DQ_SILVER(run_id)                                               │    │
│  │    → SP_RUN_DQ_CHECK(run_id, 'DIM_PROVIDER', 'SILVER', batch_id)       │    │
│  │    → Evaluates records WHERE DQ_STATUS IS NULL                          │    │
│  │    → Updates DQ_STATUS on DIM_PROVIDER                                  │    │
│  │    → If threshold exceeded → PIPELINE STOPS                             │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                          (Only if DQ passed threshold)                            │
│                                     ▼                                            │
│  Step 5: SCD TYPE-2 (in SILVER schema)                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_SCD2_PROVIDER_ATTRIBUTES(run_id, mode)                              │    │
│  │    → Hash-diff comparison on SILVER.SCD2_PROVIDER_ATTRIBUTES            │    │
│  │    → Close expired versions (_IS_CURRENT = FALSE)                       │    │
│  │    → Insert new versions                                                 │    │
│  │    → Only processes DQ_STATUS IN ('PASS', 'PASS-SOFT')                  │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                                     ▼                                            │
│  Step 6: GOLD LOAD                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_LOAD_FCT_PROVIDER_360(run_id, mode)                                 │    │
│  │    → Build from SCD2 snapshot (current versions only)                   │    │
│  │    → Only WHERE DQ_STATUS IN ('PASS','PASS-SOFT') from Silver           │    │
│  │    → Derive business attributes (gender_desc, status_desc, etc.)        │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                                     ▼                                            │
│  Step 7: AUDIT & REPORTING                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_AUDIT_REJECT_SUMMARY(run_id)                                        │    │
│  │    → Aggregate DQ failures from DQ_RESULT into summaries                │    │
│  │    → Log DQ metrics to AUDIT.DQ_RUN_LOG                                 │    │
│  │    → Send completion notification                                        │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 13. Circuit Breaker (DQ Threshold Blocking)

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────────────────┐
│  DQ Check    │────►│  Calculate       │────►│  fail_pct > threshold?       │
│  Completes   │     │  fail_pct =      │     │                              │
│              │     │  FAIL / TOTAL    │     │  YES → Block next layer     │
│              │     │  × 100           │     │         Log DQ_RUN_LOG       │
│              │     │                  │     │         Send notification    │
│              │     │                  │     │         Return FAILED        │
│              │     │                  │     │                              │
│              │     │                  │     │  NO  → Continue pipeline    │
└──────────────┘     └──────────────────┘     └──────────────────────────────┘

Configured Thresholds:
  Bronze: 10% (DQ_BRONZE_THRESHOLD)
  Silver: 5%  (DQ_SILVER_THRESHOLD)
```

---

## 14. Snowflake DMF (Data Metric Functions) Integration

### 14.1 Overview

Snowflake DMFs provide **system-level, scheduled data quality monitoring** that runs automatically on tables. We integrate DMFs alongside our custom DQ engine for defense-in-depth.

### 14.2 Planned DMFs

| DMF | Applied To | Purpose |
|-----|-----------|---------|
| SNOWFLAKE.CORE.NULL_COUNT | STG_NPI_REGISTRY.NPI_NUMBER | System-level null monitoring |
| SNOWFLAKE.CORE.NULL_COUNT | STG_NPI_REGISTRY.STATE | System-level null monitoring |
| SNOWFLAKE.CORE.DUPLICATE_COUNT | STG_NPI_REGISTRY.NPI_NUMBER | Uniqueness monitoring |
| SNOWFLAKE.CORE.NULL_COUNT | DIM_PROVIDER.PROVIDER_NPI | Silver null check |
| Custom DMF: DMF_VALID_STATE_LENGTH | STG_NPI_REGISTRY.STATE | Count records where LENGTH != 2 |
| Custom DMF: DMF_VALID_NPI_LENGTH | STG_NPI_REGISTRY.NPI_NUMBER | Count records where LENGTH != 10 |

### 14.3 Cost Considerations

| Factor | Detail |
|--------|--------|
| **Compute** | DMFs execute on a Snowflake-managed internal compute pool (serverless). No dedicated warehouse needed. |
| **Billing** | Charged per Snowflake credit consumed during DMF execution. Cost depends on table size and DMF complexity. |
| **Schedule** | By default DMFs run on table change (DML trigger). Can be set to TRIGGER_ON_CHANGES or at a fixed CRON schedule. |
| **Estimate** | For 2 small tables (~15 rows each), cost is negligible (<0.001 credits/execution). At production scale, monitor via ACCOUNT_USAGE.DATA_QUALITY_MONITORING_USAGE_HISTORY. |
| **Optimization** | Use CRON schedule (e.g., every hour) instead of trigger-on-changes for high-frequency insert tables to control costs. |

### 14.4 Monitoring DMF Results

```sql
-- View DMF results
SELECT * FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE TABLE_NAME = 'STG_NPI_REGISTRY'
ORDER BY MEASUREMENT_TIME DESC;
```

---

## 15. Test Data Strategy

### 15.1 RAW_NPI_REGISTRY (15 Test Records)

| # | NPI_NUMBER | PROVIDER_NAME | STATE | PHONE | TAXONOMY | Expected DQ_STATUS | Violation |
|---|-----------|---------------|-------|-------|----------|-------------------|-----------|
| 1 | 1234567890 | John Smith MD | PA | 2155551001 | 207Q00000X | PASS | None |
| 2 | 2345678901 | Jane Doe DO | NY | 2125551002 | 208000000X | PASS | None |
| 3 | 3456789012 | Robert Wilson NP | CA | 4155551003 | 363L00000X | PASS | None |
| 4 | 4567890123 | Maria Garcia MD | TX | 2145551004 | 207R00000X | PASS | None |
| 5 | 5678901234 | David Lee DO | FL | 3055551005 | 208600000X | PASS | None |
| 6 | 6789012345 | Sarah Johnson MD | IL | 3125551006 | 207Q00000X | PASS | None |
| 7 | 7890123456 | Michael Brown NP | OH | 6145551007 | 363A00000X | PASS | None |
| 8 | 8901234567 | Lisa Anderson MD | WA | 2065551008 | 207V00000X | PASS | None |
| 9 | 9012345678 | James Taylor DO | MA | 6175551009 | 208000000X | PASS | None |
| 10 | 0123456789 | Emily Davis MD | CO | 3035551010 | 207Q00000X | PASS | None |
| 11 | NULL | NULL | PA | 2155551011 | 207Q00000X | **FAIL** | NULL NPI + NULL NAME (critical) |
| 12 | 12345 | Thomas Clark MD | PENN | 2155551012 | 207R00000X | **FAIL** | NPI len!=10, STATE len!=2 (critical) |
| 13 | 1111111111 | | NY | 2125551013 | 208000000X | **FAIL** | Blank NAME (critical) |
| 14 | 2222222222 | Karen White NP | NJ | NULL | 363L00000X | **PASS-SOFT** | NULL PHONE (non-critical) |
| 15 | 3333333333 | Peter Hall MD | CT | 2035551015 | NULL | **PASS-SOFT** | NULL TAXONOMY (non-critical) |

### 15.2 RAW_SPECIALTY_TYPE (15 Test Records)

| # | SPECIALTY_CODE | SPECIALTY_NAME | STATE | BOARD_CERT | EXPIRATION_DATE | Expected DQ_STATUS | Violation |
|---|---------------|----------------|-------|-----------|-----------------|-------------------|-----------|
| 1 | 207Q00000X | Family Medicine | PA | Y | NULL | PASS | None |
| 2 | 208000000X | Pediatrics | NY | Y | NULL | PASS | None |
| 3 | 207R00000X | Internal Medicine | TX | Y | NULL | PASS | None |
| 4 | 363L00000X | Nurse Practitioner | CA | N | NULL | PASS | None |
| 5 | 208600000X | Surgery | FL | Y | NULL | PASS | None |
| 6 | 207V00000X | Obstetrics | WA | Y | NULL | PASS | None |
| 7 | 363A00000X | Physician Assistant | OH | N | NULL | PASS | None |
| 8 | 2084N0400X | Neurology | IL | Y | NULL | PASS | None |
| 9 | 207X00000X | Orthopedics | MA | Y | NULL | PASS | None |
| 10 | 207Y00000X | Ophthalmology | CO | Y | NULL | PASS | None |
| 11 | NULL | Cardiology | PA | Y | NULL | **FAIL** | NULL SPECIALTY_CODE (critical) |
| 12 | 2086S0129X | NULL | NY | Y | NULL | **FAIL** | NULL SPECIALTY_NAME (critical) |
| 13 | 207RC0000X | Cardiovascular | TEXAS | Y | NULL | **FAIL** | STATE len!=2 (critical) |
| 14 | 208C00000X | Dermatology | NJ | NULL | NULL | **PASS-SOFT** | NULL BOARD_CERT (non-critical) |
| 15 | 207RI0200X | Infectious Disease | CT | Y | NULL | **PASS-SOFT** | NULL EXPIRATION_DATE (non-critical) |

---

## 16. Orchestrator Design (SP_RUN_PACKAGE)

### 16.1 Run Modes

| Mode | Behavior |
|------|----------|
| **FULL** | Truncate and reload all layers from raw |
| **INCREMENTAL** | Process only new/changed records (high-water-mark) |
| **RESUME** | Resume from last failed step |
| **RERUN_STEP** | Re-execute a specific step by ID |

### 16.2 Enterprise Features

- **Dependency-aware execution** — Steps respect DEPENDS_ON_STEP_ID
- **Configurable retry** — Exponential backoff with max attempts
- **DQ Gate** — Bronze DQ blocks Silver; Silver DQ blocks Gold
- **Circuit Breaker** — Threshold-based pipeline halt
- **Resume capability** — Exact failure point restart
- **Notification dispatch** — On start, complete, failure, DQ threshold
- **Full audit trail** — Every step logged with row counts and timing

### 16.3 Pseudo-code

```
PROCEDURE SP_RUN_PACKAGE(P_RUN_MODE, P_RESUME_RUN_ID, P_STEP_ID):
  
  1. Initialize run (generate UUID or resume existing)
  2. Log run start → PKG_RUN_LOG
  3. Send RUN_START notification
  
  4. FOR each step in PKG_STEP_REGISTRY (ordered by STEP_ORDER):
     - Skip if step_id < resume_from_step_id
     - Check dependencies are COMPLETED
     
     5. RETRY LOOP (max = retry_count):
        - Log step start → STEP_RUN_LOG
        - CALL step procedure dynamically
        - Evaluate result:
          * COMPLETED/SKIPPED → mark success, break
          * FAILED → 
            - If DQ_THRESHOLD step → halt pipeline
            - If retries remaining → wait, retry
            - If max retries → mark FAILED, halt
        
     6. If step FAILED:
        - Update PKG_RUN_LOG.failed_step_id
        - Send STEP_FAILURE notification
        - RETURN with resume_command
  
  7. Log run end (COMPLETED)
  8. Send RUN_COMPLETE notification
  9. RETURN summary object
```

---

## 17. SCD Type-2 Implementation

### 17.1 Design

- **Tracked columns:** Provider attributes that change over time (status, specialty, address, credential)
- **Hash-diff:** MD5 of all tracked columns for change detection
- **Versioning:** `_VALID_FROM`, `_VALID_TO`, `_IS_CURRENT`
- **Location:** `SILVER.SCD2_PROVIDER_ATTRIBUTES`

### 17.2 Logic

```
1. Create temp table from SILVER.DIM_PROVIDER with computed _HASH_DIFF
   (Only records WHERE DQ_STATUS IN ('PASS', 'PASS-SOFT'))
2. CLOSE existing versions where hash has changed:
   UPDATE SET _VALID_TO = NOW(), _IS_CURRENT = FALSE
3. INSERT new versions for changed + new records:
   _VALID_FROM = NOW(), _VALID_TO = '9999-12-31', _IS_CURRENT = TRUE
```

---

## 18. Notification Configuration

### 18.1 NOTIFICATION_CONFIG Table

| Column | Type | Description |
|--------|------|-------------|
| NOTIFICATION_ID | NUMBER | Primary Key |
| NOTIFICATION_TYPE | VARCHAR(50) | EMAIL |
| EVENT_TYPE | VARCHAR(50) | Event trigger |
| RECIPIENTS | VARCHAR(2000) | Recipient list |
| SUBJECT_TEMPLATE | VARCHAR(500) | Subject with placeholders |
| BODY_TEMPLATE | VARCHAR(4000) | Body with placeholders |
| IS_ACTIVE | BOOLEAN | Active flag |
| INTEGRATION_NAME | VARCHAR(200) | Snowflake email integration |

### 18.2 Supported Events

| Event | Trigger | Recipients Source |
|-------|---------|-------------------|
| RUN_START | Pipeline begins | NOTIFICATION_CONFIG |
| RUN_COMPLETE | Pipeline finishes | NOTIFICATION_CONFIG |
| RUN_FAILURE | Pipeline fails | NOTIFICATION_CONFIG |
| DQ_THRESHOLD | DQ threshold exceeded | DQ_EMAILS (by DOMAIN) |
| STEP_FAILURE | Individual step fails | NOTIFICATION_CONFIG |

---

## 19. Project Directory Structure

```
Clinician-360-DQ-Implemetation/
├── 00_CONFIG/
│   ├── 001_setup_database_schemas.sql        -- P360_DQ database + all schemas
│   ├── 002_configuration_tables.sql          -- PKG_CONFIG, PKG_STEP_REGISTRY, ENV_CONFIG,
│   │                                            NOTIFICATION_CONFIG
│   └── 003_seed_configuration.sql            -- All config inserts (pkg params, steps,
│                                                DQ categories, rules, feeds, emails)
│
├── 01_FRAMEWORK/
│   ├── 001_audit_tables.sql                  -- PKG_RUN_LOG, STEP_RUN_LOG, ERROR_LOG,
│   │                                            DQ_RUN_LOG, NOTIFICATION_LOG,
│   │                                            REJECT_RECORDS, REJECT_SUMMARY,
│   │                                            DQ_RESULTS, SOURCE_ROW_COUNTS
│   ├── 002_utility_procedures.sql            -- SP_GET_CONFIG, SP_GENERATE_UUID,
│   │                                            SP_LOG_RUN_START/END, SP_LOG_STEP_START/END,
│   │                                            SP_LOG_ERROR, SP_SEND_NOTIFICATION,
│   │                                            SP_CHECK_DQ_THRESHOLD
│   ├── 003_target_tables.sql                 -- Bronze, Silver, Gold, Snapshot table DDLs
│   └── 004_dq_engine_procedure.sql           -- SP_RUN_DQ_CHECK (core generic DQ engine)
│
├── 02_BRONZE/
│   ├── 001_sp_stg_npi_registry.sql           -- Stage NPI from RAW with inline reject
│   ├── 002_sp_stg_specialty_type.sql         -- Stage Specialty from RAW with inline reject
│   └── 003_sp_run_dq_bronze.sql              -- DQ check wrapper for all bronze tables
│
├── 03_SILVER/
│   ├── 001_sp_load_dim_provider.sql          -- Unify Bronze → Silver (PASS/PASS-SOFT only)
│   ├── 002_sp_run_dq_silver.sql              -- DQ check wrapper for silver tables
│   └── 003_sp_scd2_provider_attributes.sql   -- SCD Type-2 hash-diff tracking
│
├── 04_GOLD/
│   └── 001_sp_load_fct_provider_360.sql      -- Build Gold from SCD2 (PASS/PASS-SOFT only)
│
├── 05_AUDIT/
│   ├── 001_sp_reject_summary.sql             -- Aggregate reject reasons
│   └── 002_dq_monitoring_views.sql           -- Summary views for DQ metrics
│
├── 06_ORCHESTRATION/
│   ├── 001_sp_run_package.sql                -- Master orchestrator (retry/resume/gate)
│   └── 002_scheduling_and_tasks.sql          -- Snowflake Task scheduling
│
├── 07_DEPLOY/
│   └── 001_deploy_all.sql                    -- Full ordered deployment script
│
└── docs/
    └── README.md                             -- This document
```

---

## 20. Deployment Order

| # | Script | Purpose |
|---|--------|---------|
| 1 | 00_CONFIG/001_setup_database_schemas.sql | Create P360_DQ database + schemas |
| 2 | 00_CONFIG/002_configuration_tables.sql | Create config/DQ metadata tables |
| 3 | 00_CONFIG/003_seed_configuration.sql | Seed all configuration data |
| 4 | 01_FRAMEWORK/001_audit_tables.sql | Create audit/reject/DQ results tables |
| 5 | 01_FRAMEWORK/002_utility_procedures.sql | Deploy utility stored procedures |
| 6 | 01_FRAMEWORK/003_target_tables.sql | Create Bronze/Silver/Gold/Snapshot tables |
| 7 | 01_FRAMEWORK/004_dq_engine_procedure.sql | Deploy core DQ engine |
| 8 | 02_BRONZE/001_sp_stg_npi_registry.sql | Deploy NPI staging procedure |
| 9 | 02_BRONZE/002_sp_stg_specialty_type.sql | Deploy Specialty staging procedure |
| 10 | 02_BRONZE/003_sp_run_dq_bronze.sql | Deploy Bronze DQ wrapper |
| 11 | 03_SILVER/001_sp_load_dim_provider.sql | Deploy Silver load procedure |
| 12 | 03_SILVER/002_sp_run_dq_silver.sql | Deploy Silver DQ wrapper |
| 13 | 03_SILVER/003_sp_scd2_provider_attributes.sql | Deploy SCD2 procedure |
| 14 | 04_GOLD/001_sp_load_fct_provider_360.sql | Deploy Gold load procedure |
| 15 | 05_AUDIT/001_sp_reject_summary.sql | Deploy reject summary procedure |
| 16 | 05_AUDIT/002_dq_monitoring_views.sql | Deploy monitoring views |
| 17 | 06_ORCHESTRATION/001_sp_run_package.sql | Deploy master orchestrator |
| 18 | 06_ORCHESTRATION/002_scheduling_and_tasks.sql | Configure tasks |
| 19 | 07_DEPLOY/001_deploy_all.sql | Calls all scripts in order |

---

## 21. Key Design Decisions Summary

| Decision | Rationale |
|----------|-----------|
| Separate database (P360_DQ) | Isolation from reference project, independent lifecycle |
| DQ on Bronze + Silver only | Gold receives only cleansed data; DQ at source layers catches issues early |
| Gold filtered by DQ_STATUS | `WHERE DQ_STATUS IN ('PASS','PASS-SOFT')` ensures business-ready data |
| Three-outcome model (PASS/FAIL/PASS-SOFT) | Balances strictness with business pragmatism |
| Worst-case DQ_STATUS wins | If any critical rule fails, record is FAIL regardless of other passes |
| Circuit breaker per layer | Bronze threshold blocks Silver; Silver threshold blocks Gold |
| Profiling every execution | Continuous visibility into data shape changes |
| DQ_STATUS on source table | In-place update enables simple downstream filtering |
| Reusable DQ engine | Adding new tables/rules = only config inserts, no code changes |
| SCD2 after Silver DQ | Only quality-checked records enter historical tracking |
| DMF as supplementary | System-level monitoring alongside custom business rules |
| Enterprise naming conventions | RAW_ prefix for raw, STG_ for bronze, DIM_/FCT_ for silver/gold |

---

## 22. Naming Conventions

| Layer | Prefix | Example |
|-------|--------|---------|
| RAW (Ingestion) | RAW_ | RAW_NPI_REGISTRY, RAW_SPECIALTY_TYPE |
| BRONZE (Staging) | STG_ | STG_NPI_REGISTRY, STG_SPECIALTY_TYPE |
| SILVER (Dimension/Intermediate) | DIM_ / INT_ | DIM_PROVIDER, INT_PROVIDER_SPECIALTY |
| GOLD (Fact/Summary) | FCT_ / OBT_ | FCT_PROVIDER_360 |
| SNAPSHOT (SCD2) | SCD2_ | SCD2_PROVIDER_ATTRIBUTES |
| CONFIG tables | DQ_ / PKG_ / ENV_ | DQ_RULES, PKG_CONFIG, ENV_CONFIG |
| Procedures | SP_ | SP_RUN_DQ_CHECK, SP_STG_NPI_REGISTRY |
| Audit tables | (descriptive) | PKG_RUN_LOG, STEP_RUN_LOG, DQ_RESULTS |

---

## 23. Future Extensibility

Adding DQ to a new table requires **zero code changes**:

1. Insert rule into `DQ_RULES` (if new validation type)
2. Insert feed into `DQ_FEEDS` (maps rule → table → column → layer)
3. Add `DQ_STATUS VARCHAR(20)` column to the new table
4. The existing `SP_RUN_DQ_CHECK` engine handles it automatically

---
