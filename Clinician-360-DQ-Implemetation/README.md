# Clinician-360 Data Quality Framework - Comprehensive Design Document
*Co-authored with CoCo*

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

### 5.2 Step Registry (PKG_STEP_REGISTRY)

Defines execution order and dependencies for the orchestrator.

| Column | Type | Description |
|--------|------|-------------|
| STEP_ID | NUMBER | Primary Key |
| STEP_NAME | VARCHAR(200) | Human-readable step name |
| STEP_LAYER | VARCHAR(20) | BRONZE, DQ_BRONZE, SILVER, DQ_SILVER, GOLD, AUDIT |
| STEP_PROCEDURE | VARCHAR(500) | Fully qualified procedure name |
| STEP_ORDER | NUMBER(5,1) | Execution sequence |
| DEPENDS_ON_STEP_ID | ARRAY | Dependency step IDs |
| IS_ACTIVE | BOOLEAN | Enable/disable |
| IS_RESTARTABLE | BOOLEAN | Can resume from here |
| RETRY_COUNT | NUMBER(2) | Max retry attempts |
| RETRY_DELAY_SECONDS | NUMBER | Wait between retries |
| TIMEOUT_MINUTES | NUMBER | Step timeout |
| DESCRIPTION | VARCHAR(500) | Step description |

**Step Execution Order:**

| Order | Step ID | Name | Layer | Dependencies |
|-------|---------|------|-------|--------------|
| 1.0 | 1 | STG_NPI_REGISTRY | BRONZE | None |
| 1.1 | 2 | STG_SPECIALTY_TYPE | BRONZE | None |
| 2.0 | 10 | DQ_CHECK_BRONZE | DQ_BRONZE | 1, 2 |
| 3.0 | 20 | LOAD_SILVER_PROVIDER | SILVER | 10 |
| 4.0 | 30 | DQ_CHECK_SILVER | DQ_SILVER | 20 |
| 5.0 | 40 | SCD2_PROVIDER_ATTRIBUTES | SILVER | 30 |
| 6.0 | 50 | LOAD_GOLD_DIM_PROVIDER | GOLD | 40 |
| 7.0 | 60 | AUDIT_REJECT_SUMMARY | AUDIT | 50 |

### 5.3 Environment Configuration (ENV_CONFIG)

| Column | Type | Description |
|--------|------|-------------|
| ENVIRONMENT | VARCHAR(20) | DEV / QA / PROD (PK) |
| SOURCE_DATABASE | VARCHAR(100) | Source database name |
| SOURCE_SCHEMA | VARCHAR(100) | Source schema |
| WAREHOUSE_NAME | VARCHAR(100) | Compute warehouse |
| MAX_PARALLEL_STEPS | NUMBER(2) | Parallel execution limit |
| DQ_REJECT_THRESHOLD | NUMBER(5,2) | DQ failure threshold % |
| ENABLE_NOTIFICATIONS | BOOLEAN | Notification toggle |
| IS_ACTIVE | BOOLEAN | Active environment flag |

---

## 6. Data Quality Framework — Configuration Tables

### 6.1 DQ_CATEGORIES

| Column | Type | Description |
|--------|------|-------------|
| CATEGORY_ID | INT | Primary Key |
| CATEGORY_NM | VARCHAR(100) | Dimension name |
| CATEGORY_DESC | VARCHAR(500) | Dimension description |

**Seed Data:**

| ID | Category | Description |
|----|----------|-------------|
| 1 | Accuracy | The degree to which data correctly reflects the real-world situation it represents |
| 2 | Completeness | The extent to which all required data is present |
| 3 | Consistency | The uniformity of data across different datasets or systems |
| 4 | Uniqueness | Ensuring that each record is distinct and not duplicated |
| 5 | Timeliness | The relevance of data in relation to the time it is needed |
| 6 | Validity | The degree to which data conforms to defined formats or standards |
| 7 | Integrity | The assurance that data is accurate, consistent, and reliable throughout its lifecycle and is not improperly modified |

### 6.2 DQ_RULES

| Column | Type | Description |
|--------|------|-------------|
| RULE_ID | INT | Primary Key (Sequence) |
| CATEGORY_ID | INT | FK → DQ_CATEGORIES.CATEGORY_ID |
| RULE_DESC | VARCHAR(500) | Human-readable description |
| RULE_EXP | VARCHAR(4000) | Reusable SQL expression with placeholders |
| ACTIVE_IND | VARCHAR(1) | Y = Active, N = Inactive |

**Seed Data:**

| Rule ID | Category | Description | Expression |
|---------|----------|-------------|------------|
| 1 | 2 (Completeness) | Validate if Nulls and blank values present | `CASE WHEN $input_value IS NULL OR $input_value = '' THEN 'FAIL' ELSE 'PASS' END` |
| 2 | 6 (Validity) | Validate string length is 2 chars | `CASE WHEN LENGTH(TRIM(TO_CHAR($input_value))) <> 2 THEN 'FAIL' ELSE 'PASS' END` |
| 3 | 6 (Validity) | Validate string length is 9 chars | `CASE WHEN LENGTH(TRIM(TO_CHAR($input_value))) <> 9 THEN 'FAIL' ELSE 'PASS' END` |
| 4 | 6 (Validity) | Validate string length is 10 chars | `CASE WHEN LENGTH(TRIM(TO_CHAR($input_value))) <> 10 THEN 'FAIL' ELSE 'PASS' END` |
| 5 | 6 (Validity) | Validate xxx-xx-xxxx format | `CASE WHEN SUBSTR($input_value,4,1)='-' AND SUBSTR($input_value,7,1)='-' AND LENGTH(REPLACE($input_value,'-',''))=9 THEN 'PASS' ELSE 'FAIL' END` |
| 6 | 4 (Uniqueness) | Validate no duplicate records | `GROUP BY $input_value HAVING COUNT(*) > 1` |
| 7 | 3 (Consistency) | Cross-column consistency validation | `CASE WHEN $input_value1 <> '0001-01-01' AND $input_value2 > 5000 THEN 'FAIL' ELSE 'PASS' END` |
| 8 | 7 (Integrity) | Cross-table referential integrity | `SELECT CASE WHEN A.COL1 <> B.COL2 THEN 'FAIL' ELSE 'PASS' END FROM TABLE_A A JOIN TABLE_B B ON A.KEY = B.KEY` |
| 9 | 1 (Accuracy) | Validate value exists in reference list | `CASE WHEN $input_value NOT IN (SELECT VALID_VALUE FROM REF_TABLE) THEN 'FAIL' ELSE 'PASS' END` |
| 10 | 5 (Timeliness) | Validate data is not stale (within N days) | `CASE WHEN DATEDIFF('DAY', $input_value, CURRENT_DATE()) > 365 THEN 'FAIL' ELSE 'PASS' END` |

### 6.3 DQ_FEEDS

| Column | Type | Description |
|--------|------|-------------|
| FEED_ID | INT | Primary Key (Sequence) |
| RULE_ID | INT | FK → DQ_RULES.RULE_ID |
| TABLE_NM | VARCHAR(200) | Source table name |
| LAYER | VARCHAR(20) | BRONZE or SILVER |
| DQ_RULE_INPUT | VARCHAR(4000) | Column name(s) or SQL expression |
| CRITICALITY_IND | VARCHAR(1) | Y = Critical (FAIL blocks), N = Non-critical (PASS-SOFT) |
| FEED_CATEGORY | VARCHAR(20) | Single / Multiple / Complex |
| DOMAIN | VARCHAR(100) | FK → DQ_EMAILS.DOMAIN (notification routing) |

**Feed Categories:**

| Category | Description | Example |
|----------|-------------|---------|
| **Single** | Rule applied on a single column | NULL check on STATE |
| **Multiple** | Rule applied on multiple columns of same table | EFFECTIVE_DATE + EXPIRATION_DATE cross-check |
| **Complex** | Rule applied across multiple tables via SQL | NPI exists in reference registry |

### 6.4 DQ_EMAILS

| Column | Type | Description |
|--------|------|-------------|
| EMAIL_ID | INT | Primary Key |
| DOMAIN | VARCHAR(100) | Domain grouping (PROVIDERS, CLAIMS, CLINICS) |
| EMAILS | VARCHAR(2000) | Comma-separated recipient list |

**Seed Data:**

| ID | Domain | Emails |
|----|--------|--------|
| 1 | PROVIDERS | abc@upmc.com,devang@citiustech.com,rakesh@citiustech.com |
| 2 | CLAIMS | selva@xyz.com |
| 3 | CLINICS | vekat@xyz.com,juan@xyz.com |

### 6.5 DQ_RESULTS (Audit Output)

| Column | Type | Description |
|--------|------|-------------|
| RESULT_ID | INT | Primary Key (auto-increment) |
| RULE_ID | INT | FK → DQ_RULES.RULE_ID |
| FEED_ID | INT | FK → DQ_FEEDS.FEED_ID |
| BUSINESS_DT | TIMESTAMP_NTZ | Business date of check |
| RESULT | VARCHAR(20) | PASS / FAIL / PASS-SOFT |
| SURROGATE_KEY | INT | Surrogate key of source record |
| BUSINESS_KEY | VARCHAR(500) | Natural key to identify source record |
| RUN_ID | VARCHAR(36) | FK → PKG_RUN_LOG.RUN_ID |
| ETL_LOAD_TS | TIMESTAMP_NTZ | When the result was inserted |

### 6.6 Relationships

```
DQ_CATEGORIES.CATEGORY_ID  ─────────►  DQ_RULES.CATEGORY_ID
DQ_RULES.RULE_ID           ─────────►  DQ_FEEDS.RULE_ID
DQ_FEEDS.FEED_ID           ─────────►  DQ_RESULTS.FEED_ID
DQ_RULES.RULE_ID           ─────────►  DQ_RESULTS.RULE_ID
DQ_FEEDS.DOMAIN            ─────────►  DQ_EMAILS.DOMAIN
PKG_RUN_LOG.RUN_ID         ─────────►  DQ_RESULTS.RUN_ID
PKG_STEP_REGISTRY.STEP_ID  ─────────►  STEP_RUN_LOG.STEP_ID
```

---

## 7. DQ Feeds Configuration (Rule-to-Table Mapping)

### 7.1 Bronze Layer Feeds

| Feed ID | Rule ID | Table | Layer | Column (DQ_RULE_INPUT) | Criticality | Category | Domain |
|---------|---------|-------|-------|------------------------|-------------|----------|--------|
| 1 | 1 | STG_NPI_REGISTRY | BRONZE | NPI_NUMBER | Y | Single | PROVIDERS |
| 2 | 1 | STG_NPI_REGISTRY | BRONZE | PROVIDER_NAME | Y | Single | PROVIDERS |
| 3 | 2 | STG_NPI_REGISTRY | BRONZE | STATE | Y | Single | PROVIDERS |
| 4 | 4 | STG_NPI_REGISTRY | BRONZE | NPI_NUMBER | Y | Single | PROVIDERS |
| 5 | 6 | STG_NPI_REGISTRY | BRONZE | NPI_NUMBER | Y | Single | PROVIDERS |
| 6 | 1 | STG_NPI_REGISTRY | BRONZE | PHONE | N | Single | PROVIDERS |
| 7 | 1 | STG_NPI_REGISTRY | BRONZE | TAXONOMY_CODE | N | Single | PROVIDERS |
| 8 | 1 | STG_SPECIALTY_TYPE | BRONZE | SPECIALTY_CODE | Y | Single | PROVIDERS |
| 9 | 1 | STG_SPECIALTY_TYPE | BRONZE | SPECIALTY_NAME | Y | Single | PROVIDERS |
| 10 | 2 | STG_SPECIALTY_TYPE | BRONZE | STATE | Y | Single | PROVIDERS |
| 11 | 1 | STG_SPECIALTY_TYPE | BRONZE | EXPIRATION_DATE | N | Single | PROVIDERS |
| 12 | 1 | STG_SPECIALTY_TYPE | BRONZE | BOARD_CERTIFICATION_REQ | N | Single | PROVIDERS |

### 7.2 Silver Layer Feeds

| Feed ID | Rule ID | Table | Layer | Column (DQ_RULE_INPUT) | Criticality | Category | Domain |
|---------|---------|-------|-------|------------------------|-------------|----------|--------|
| 13 | 1 | DIM_PROVIDER | SILVER | STATE | Y | Single | PROVIDERS |
| 14 | 1 | DIM_PROVIDER | SILVER | ZIP_CODE | Y | Single | PROVIDERS |
| 15 | 1 | DIM_PROVIDER | SILVER | PROVIDER_NPI | Y | Single | PROVIDERS |
| 16 | 1 | DIM_PROVIDER | SILVER | DELETION_FLAG | Y | Single | PROVIDERS |
| 17 | 1 | DIM_PROVIDER | SILVER | PROVIDER_NAME | Y | Single | PROVIDERS |
| 18 | 2 | DIM_PROVIDER | SILVER | STATE | Y | Single | PROVIDERS |
| 19 | 4 | DIM_PROVIDER | SILVER | PROVIDER_NPI | Y | Single | PROVIDERS |
| 20 | 3 | DIM_PROVIDER | SILVER | PROVIDER_TIN | Y | Single | PROVIDERS |
| 21 | 5 | DIM_PROVIDER | SILVER | PROVIDER_TIN | Y | Single | PROVIDERS |
| 22 | 6 | DIM_PROVIDER | SILVER | PROVIDER_NPI | Y | Single | PROVIDERS |

---

## 8. Source & Target Table Definitions

### 8.1 RAW Layer (RAW_INGESTION schema — immutable source)

#### RAW_NPI_REGISTRY

| Column | Type | Description |
|--------|------|-------------|
| NPI_NUMBER | VARCHAR(10) | 10-digit NPI identifier |
| PROVIDER_FIRST_NAME | VARCHAR(100) | First name |
| PROVIDER_LAST_NAME | VARCHAR(100) | Last name |
| PROVIDER_NAME | VARCHAR(200) | Full provider name |
| CREDENTIAL | VARCHAR(50) | Professional credential (MD, DO, NP) |
| GENDER | VARCHAR(1) | M/F |
| STATE | VARCHAR(10) | State code |
| ZIP_CODE | VARCHAR(10) | ZIP code |
| TAXONOMY_CODE | VARCHAR(20) | Provider taxonomy classification |
| PHONE | VARCHAR(15) | Phone number |
| NPI_DEACTIVATION_FLAG | VARCHAR(1) | Y/N deactivation indicator |
| ENUMERATION_DATE | DATE | NPI enumeration date |
| SOURCE_SYSTEM | VARCHAR(50) | Source system identifier |
| _LOADED_AT | TIMESTAMP_NTZ | Ingestion timestamp (immutable) |

#### RAW_SPECIALTY_TYPE

| Column | Type | Description |
|--------|------|-------------|
| SPECIALTY_CODE | VARCHAR(20) | Specialty taxonomy code |
| SPECIALTY_NAME | VARCHAR(200) | Specialty description |
| SPECIALTY_CATEGORY | VARCHAR(100) | Grouping (Primary Care, Surgical, etc.) |
| BOARD_CERTIFICATION_REQ | VARCHAR(1) | Y/N required flag |
| STATE | VARCHAR(10) | State registered |
| EFFECTIVE_DATE | DATE | When active |
| EXPIRATION_DATE | DATE | When expires (NULL if active) |
| SOURCE_SYSTEM | VARCHAR(50) | Source identifier |
| _LOADED_AT | TIMESTAMP_NTZ | Ingestion timestamp |

### 8.2 Bronze Layer (BRONZE schema — staged, DQ-validated)

#### STG_NPI_REGISTRY

| Column | Type | Description |
|--------|------|-------------|
| NPI_SK | INT (AUTOINCREMENT) | Surrogate key |
| NPI_NUMBER | VARCHAR(10) | 10-digit NPI |
| PROVIDER_FIRST_NAME | VARCHAR(100) | First name |
| PROVIDER_LAST_NAME | VARCHAR(100) | Last name |
| PROVIDER_NAME | VARCHAR(200) | Full name |
| CREDENTIAL | VARCHAR(50) | Credential |
| GENDER | VARCHAR(1) | Gender code |
| STATE | VARCHAR(2) | 2-char state code |
| ZIP_CODE | VARCHAR(10) | ZIP code |
| TAXONOMY_CODE | VARCHAR(20) | Taxonomy code |
| PHONE | VARCHAR(15) | Phone number |
| NPI_DEACTIVATION_FLAG | VARCHAR(1) | Deactivation indicator |
| ENUMERATION_DATE | DATE | NPI enumeration date |
| SOURCE_SYSTEM | VARCHAR(50) | Source system |
| LOAD_DT | TIMESTAMP_NTZ | Load timestamp |
| UPDATE_DT | TIMESTAMP_NTZ | Last update |
| ROW_STATUS | VARCHAR(20) | ACTIVE / INACTIVE |
| DQ_STATUS | VARCHAR(20) | **PASS / FAIL / PASS-SOFT** |
| RECORD_HASH | VARCHAR(64) | SHA-256 hash for CDC |
| JOB_ID | VARCHAR(36) | Job/run identifier |
| _SOURCE_LOADED_AT | TIMESTAMP_NTZ | Source ingestion time (HWM) |
| _RUN_ID | VARCHAR(36) | Pipeline run ID |

#### STG_SPECIALTY_TYPE

| Column | Type | Description |
|--------|------|-------------|
| SPECIALTY_SK | INT (AUTOINCREMENT) | Surrogate key |
| SPECIALTY_CODE | VARCHAR(20) | Specialty code |
| SPECIALTY_NAME | VARCHAR(200) | Specialty name |
| SPECIALTY_CATEGORY | VARCHAR(100) | Category grouping |
| BOARD_CERTIFICATION_REQ | VARCHAR(1) | Y/N |
| STATE | VARCHAR(2) | 2-char state code |
| EFFECTIVE_DATE | DATE | Effective from |
| EXPIRATION_DATE | DATE | Expires on |
| SOURCE_SYSTEM | VARCHAR(50) | Source system |
| LOAD_DT | TIMESTAMP_NTZ | Load timestamp |
| UPDATE_DT | TIMESTAMP_NTZ | Last update |
| ROW_STATUS | VARCHAR(20) | ACTIVE / INACTIVE |
| DQ_STATUS | VARCHAR(20) | **PASS / FAIL / PASS-SOFT** |
| RECORD_HASH | VARCHAR(64) | SHA-256 hash for CDC |
| JOB_ID | VARCHAR(36) | Job identifier |
| _SOURCE_LOADED_AT | TIMESTAMP_NTZ | Source ingestion time |
| _RUN_ID | VARCHAR(36) | Pipeline run ID |

### 8.3 Silver Layer (SILVER schema — unified, deduplicated)

#### DIM_PROVIDER (Unified Provider Dimension)

| Column | Type | Description |
|--------|------|-------------|
| PROVIDER_SK | INT | Surrogate key |
| PROVIDER_BK | VARCHAR(10) | Business key (NPI_NUMBER) |
| PROVIDER_NAME | VARCHAR(200) | Full provider name |
| PROVIDER_FIRST_NAME | VARCHAR(100) | First name |
| PROVIDER_LAST_NAME | VARCHAR(100) | Last name |
| CREDENTIAL | VARCHAR(50) | Credential |
| GENDER | VARCHAR(1) | Gender code |
| PRIMARY_SPECIALTY | VARCHAR(200) | Primary specialty name |
| SPECIALTY_CATEGORY | VARCHAR(100) | Specialty grouping |
| STATE | VARCHAR(2) | State code |
| ZIP_CODE | VARCHAR(10) | ZIP |
| PHONE | VARCHAR(15) | Phone |
| PROVIDER_TIN | VARCHAR(11) | Tax ID (xxx-xx-xxxx format) |
| PROVIDER_NPI | VARCHAR(10) | NPI number |
| DELETION_FLAG | VARCHAR(1) | Y/N soft-delete flag |
| SOURCE_SYSTEM | VARCHAR(50) | Source |
| LOAD_DT | TIMESTAMP_NTZ | Initial load date |
| UPDATE_DT | TIMESTAMP_NTZ | Last update timestamp |
| ROW_STATUS | VARCHAR(20) | ACTIVE / INACTIVE |
| DQ_STATUS | VARCHAR(20) | **PASS / FAIL / PASS-SOFT** |
| RECORD_HASH | VARCHAR(64) | Hash for CDC |
| JOB_ID | VARCHAR(36) | Job ID |
| _RUN_ID | VARCHAR(36) | Pipeline run ID |

### 8.4 Gold Layer (GOLD schema — business-ready, cleansed)

#### FCT_PROVIDER_360 (One Big Table / Summary View)

| Column | Type | Description |
|--------|------|-------------|
| PROVIDER_SK | INT | Surrogate key |
| PROVIDER_NPI | VARCHAR(10) | NPI number |
| PROVIDER_NAME | VARCHAR(200) | Full name |
| CREDENTIAL | VARCHAR(50) | Credential |
| GENDER_DESC | VARCHAR(10) | Male / Female / Unknown |
| PRIMARY_SPECIALTY | VARCHAR(200) | Specialty |
| SPECIALTY_CATEGORY | VARCHAR(100) | Specialty group |
| STATE | VARCHAR(2) | State |
| ZIP_CODE | VARCHAR(10) | ZIP |
| PROVIDER_STATUS | VARCHAR(20) | ACTIVE / INACTIVE |
| IS_CURRENT | BOOLEAN | Current SCD2 version flag |
| VALID_FROM | TIMESTAMP_NTZ | SCD2 valid-from |
| VALID_TO | TIMESTAMP_NTZ | SCD2 valid-to |
| _LOADED_AT | TIMESTAMP_NTZ | Gold load timestamp |
| _RUN_ID | VARCHAR(36) | Pipeline run ID |

**Gold layer filter:** `WHERE DQ_STATUS IN ('PASS', 'PASS-SOFT')` from Silver.

### 8.5 Snapshots (SCD Type-2)

#### SCD2_PROVIDER_ATTRIBUTES

| Column | Type | Description |
|--------|------|-------------|
| SCD_KEY | VARCHAR(64) | MD5 hash key |
| PROVIDER_BK | VARCHAR(10) | Business key (NPI) |
| PROVIDER_NAME | VARCHAR(200) | Full name |
| CREDENTIAL | VARCHAR(50) | Credential |
| STATE | VARCHAR(2) | State |
| ZIP_CODE | VARCHAR(10) | ZIP |
| PRIMARY_SPECIALTY | VARCHAR(200) | Specialty |
| PROVIDER_STATUS | VARCHAR(20) | Status |
| _VALID_FROM | TIMESTAMP_NTZ | Version start |
| _VALID_TO | TIMESTAMP_NTZ | Version end (9999-12-31 if current) |
| _IS_CURRENT | BOOLEAN | Current version flag |
| _HASH_DIFF | VARCHAR(64) | Change detection hash |
| _RUN_ID | VARCHAR(36) | Pipeline run ID |

---

## 9. Audit & Observability Tables

### 9.1 PKG_RUN_LOG (Master Run Record)

| Column | Type | Description |
|--------|------|-------------|
| RUN_ID | VARCHAR(36) | UUID Primary Key |
| PACKAGE_NAME | VARCHAR(100) | Package identifier |
| RUN_MODE | VARCHAR(20) | FULL / INCREMENTAL / RESUME / RERUN_STEP |
| ENVIRONMENT | VARCHAR(20) | DEV / QA / PROD |
| RUN_STATUS | VARCHAR(20) | RUNNING / COMPLETED / FAILED / CANCELLED |
| INITIATED_BY | VARCHAR(100) | User who started run |
| START_TIMESTAMP | TIMESTAMP_NTZ | Run start time |
| END_TIMESTAMP | TIMESTAMP_NTZ | Run end time |
| DURATION_SECONDS | NUMBER | Total duration |
| TOTAL_ROWS_READ | NUMBER | Aggregate rows read |
| TOTAL_ROWS_WRITTEN | NUMBER | Aggregate rows written |
| TOTAL_ROWS_REJECTED | NUMBER | Aggregate rejects |
| TOTAL_STEPS | NUMBER | Steps attempted |
| COMPLETED_STEPS | NUMBER | Steps completed |
| FAILED_STEP_ID | NUMBER | Which step failed |
| ERROR_MESSAGE | VARCHAR(4000) | Failure detail |
| RESUME_FROM_STEP_ID | NUMBER | Resume point |
| RUN_PARAMETERS | VARIANT | Input parameters JSON |

### 9.2 STEP_RUN_LOG (Per-Step Details)

| Column | Type | Description |
|--------|------|-------------|
| STEP_RUN_ID | VARCHAR(36) | UUID Primary Key |
| RUN_ID | VARCHAR(36) | FK → PKG_RUN_LOG |
| STEP_ID | NUMBER | Step identifier |
| STEP_NAME | VARCHAR(200) | Step name |
| STEP_LAYER | VARCHAR(20) | Layer |
| STEP_STATUS | VARCHAR(20) | RUNNING / COMPLETED / FAILED / SKIPPED / RETRYING |
| ATTEMPT_NUMBER | NUMBER(3) | Retry attempt count |
| START_TIMESTAMP | TIMESTAMP_NTZ | Step start |
| END_TIMESTAMP | TIMESTAMP_NTZ | Step end |
| DURATION_SECONDS | NUMBER | Step duration |
| ROWS_READ | NUMBER | Rows processed |
| ROWS_WRITTEN | NUMBER | Rows inserted/merged |
| ROWS_REJECTED | NUMBER | Rows rejected |
| ROWS_UPDATED | NUMBER | Rows updated |
| REJECT_PERCENTAGE | NUMBER(5,2) | Reject % |
| DQ_PASSED | BOOLEAN | DQ threshold respected |
| ERROR_MESSAGE | VARCHAR(4000) | Error details |
| SQL_QUERY_ID | VARCHAR(200) | Snowflake query ID |
| METADATA | VARIANT | Additional context |

### 9.3 ERROR_LOG

| Column | Type | Description |
|--------|------|-------------|
| ERROR_LOG_ID | VARCHAR(36) | UUID PK |
| RUN_ID | VARCHAR(36) | FK → PKG_RUN_LOG |
| STEP_RUN_ID | VARCHAR(36) | FK → STEP_RUN_LOG |
| STEP_NAME | VARCHAR(200) | Step name |
| ERROR_TIMESTAMP | TIMESTAMP_NTZ | When error occurred |
| ERROR_CODE | VARCHAR(20) | Snowflake error code |
| ERROR_STATE | VARCHAR(10) | SQL state |
| ERROR_MESSAGE | VARCHAR(4000) | Error description |
| ERROR_STACK_TRACE | VARCHAR(8000) | Stack trace |
| SQL_STATEMENT | VARCHAR(8000) | Failing SQL |
| SEVERITY | VARCHAR(10) | ERROR / WARNING / INFO |
| IS_RETRYABLE | BOOLEAN | Can retry flag |

### 9.4 DQ_RUN_LOG (DQ Metrics Per Run)

| Column | Type | Description |
|--------|------|-------------|
| DQ_LOG_ID | VARCHAR(36) | UUID PK |
| RUN_ID | VARCHAR(36) | FK → PKG_RUN_LOG |
| STEP_RUN_ID | VARCHAR(36) | FK → STEP_RUN_LOG |
| SOURCE_TABLE | VARCHAR(200) | Table checked |
| TOTAL_RECORDS | NUMBER | Total records evaluated |
| PASSED_RECORDS | NUMBER | Records passed |
| FAILED_RECORDS | NUMBER | Records failed (hard) |
| SOFT_PASS_RECORDS | NUMBER | Records soft-passed |
| REJECT_PERCENTAGE | NUMBER(5,2) | Fail % |
| THRESHOLD_EXCEEDED | BOOLEAN | Circuit breaker triggered |
| THRESHOLD_VALUE | NUMBER(5,2) | Configured threshold |
| RULES_EVALUATED | NUMBER | Number of rules run |
| RULES_FAILED | NUMBER | Rules with failures |

### 9.5 NOTIFICATION_LOG

| Column | Type | Description |
|--------|------|-------------|
| NOTIFICATION_LOG_ID | VARCHAR(36) | UUID PK |
| RUN_ID | VARCHAR(36) | FK → PKG_RUN_LOG |
| NOTIFICATION_TYPE | VARCHAR(50) | EMAIL |
| EVENT_TYPE | VARCHAR(50) | RUN_START / RUN_COMPLETE / RUN_FAILURE / DQ_THRESHOLD |
| RECIPIENTS | VARCHAR(2000) | Email addresses |
| SUBJECT | VARCHAR(500) | Email subject |
| BODY | VARCHAR(4000) | Email body |
| SEND_STATUS | VARCHAR(20) | PENDING / SENT / FAILED |
| SENT_AT | TIMESTAMP_NTZ | Send timestamp |

### 9.6 Reject Tables

#### REJECT.REJECT_RECORDS

| Column | Type | Description |
|--------|------|-------------|
| REJECT_ID | VARCHAR(36) | UUID |
| RUN_ID | VARCHAR(36) | FK → PKG_RUN_LOG |
| STEP_NAME | VARCHAR(200) | Which step rejected |
| SOURCE_TABLE | VARCHAR(200) | Source table |
| REJECT_REASONS | ARRAY | Array of reason codes |
| RECORD_KEY | VARCHAR(500) | Business key of rejected record |
| RECORD_DATA | VARIANT | Full record as JSON |
| SEVERITY | VARCHAR(10) | ERROR / WARNING |
| REJECTED_AT | TIMESTAMP_NTZ | Rejection timestamp |

#### REJECT.REJECT_SUMMARY

| Column | Type | Description |
|--------|------|-------------|
| SUMMARY_ID | VARCHAR(36) | UUID |
| RUN_ID | VARCHAR(36) | FK → PKG_RUN_LOG |
| STEP_NAME | VARCHAR(200) | Step name |
| SOURCE_TABLE | VARCHAR(200) | Table |
| REJECT_REASON | VARCHAR(200) | Reason code |
| REJECT_COUNT | NUMBER | Count of rejects for this reason |
| FIRST_REJECTED_AT | TIMESTAMP_NTZ | First occurrence |
| LAST_REJECTED_AT | TIMESTAMP_NTZ | Last occurrence |

---

## 10. DQ Engine Procedure Design

### 10.1 SP_RUN_DQ_CHECK (Core Generic Engine)

```
Signature:
  SP_RUN_DQ_CHECK(
    P_RUN_ID     VARCHAR,    -- Pipeline run identifier
    P_TABLE_NM   VARCHAR,    -- Table to check (e.g., 'STG_NPI_REGISTRY')
    P_LAYER      VARCHAR,    -- Layer (e.g., 'BRONZE')
    P_JOB_ID     VARCHAR     -- Job execution identifier
  )

Returns: VARIANT (status, counts, threshold info)

Logic:
  1. INITIALIZE
     - Log step start
     - Get configured threshold for this layer

  2. FETCH FEEDS
     - Query DQ_FEEDS WHERE TABLE_NM = P_TABLE_NM AND LAYER = P_LAYER
     - Join DQ_RULES to get RULE_EXP, CATEGORY_ID
     - Only process where ACTIVE_IND = 'Y'

  3. FOR EACH FEED (cursor loop):
     a. Determine FEED_CATEGORY (Single / Multiple / Complex)
     
     b. BUILD DYNAMIC SQL:
        - Single:  Replace $input_value with column name
        - Multiple: Replace $input_value1, $input_value2 with respective columns
        - Complex: Use RULE_EXP as-is (full SQL)
     
     c. EXECUTE against source table:
        - Evaluate RULE_EXP for each record
        - Capture SURROGATE_KEY and BUSINESS_KEY per record
     
     d. DETERMINE OUTCOME per record:
        - If RULE_EXP = 'PASS' → record result = PASS
        - If RULE_EXP = 'FAIL' AND CRITICALITY_IND = 'Y' → record result = FAIL
        - If RULE_EXP = 'FAIL' AND CRITICALITY_IND = 'N' → record result = PASS-SOFT
     
     e. INSERT results into AUDIT.DQ_RESULTS

  4. AGGREGATE DQ_STATUS per record (worst-case wins):
     - Priority: FAIL > PASS-SOFT > PASS
     - If any critical rule fails → overall DQ_STATUS = 'FAIL'
     - If only non-critical rules fail → overall DQ_STATUS = 'PASS-SOFT'
     - If all rules pass → DQ_STATUS = 'PASS'

  5. UPDATE source table:
     - SET DQ_STATUS = aggregated result per surrogate key

  6. CHECK THRESHOLD (Circuit Breaker):
     - Calculate: fail_pct = (FAIL_COUNT / TOTAL_COUNT) * 100
     - If fail_pct > configured threshold → return THRESHOLD_EXCEEDED = TRUE
     - Log to DQ_RUN_LOG

  7. NOTIFY (if threshold exceeded):
     - Lookup DQ_EMAILS by DOMAIN from DQ_FEEDS
     - Log notification to NOTIFICATION_LOG
     - (Production: SYSTEM$SEND_EMAIL)

  8. RETURN result object
```

### 10.2 SP_RUN_DQ_BRONZE (Bronze Layer Wrapper)

```
Calls SP_RUN_DQ_CHECK for each bronze table:
  - SP_RUN_DQ_CHECK(run_id, 'STG_NPI_REGISTRY', 'BRONZE', job_id)
  - SP_RUN_DQ_CHECK(run_id, 'STG_SPECIALTY_TYPE', 'BRONZE', job_id)

If ANY table exceeds threshold → return FAILED (blocks Silver)
```

### 10.3 SP_RUN_DQ_SILVER (Silver Layer Wrapper)

```
Calls SP_RUN_DQ_CHECK for silver tables:
  - SP_RUN_DQ_CHECK(run_id, 'DIM_PROVIDER', 'SILVER', job_id)

If threshold exceeded → return FAILED (blocks Gold)
```

---

## 11. DQ Rule Expression Patterns

### 11.1 Placeholder Reference

| Placeholder | Used In | Description |
|-------------|---------|-------------|
| `$input_value` | Single category | Replaced with column value reference |
| `$input_value1`, `$input_value2` | Multiple category | Replaced with respective column values |
| Full SQL statement | Complex category | Executed as-is against the database |

### 11.2 Expression Examples

```sql
-- COMPLETENESS: Null/blank check (Rule 1)
CASE WHEN $input_value IS NULL OR $input_value = '' THEN 'FAIL' ELSE 'PASS' END

-- VALIDITY: Length = 2 chars (Rule 2, e.g., STATE)
CASE WHEN LENGTH(TRIM(TO_CHAR($input_value))) <> 2 THEN 'FAIL' ELSE 'PASS' END

-- VALIDITY: Length = 10 chars (Rule 4, e.g., NPI)
CASE WHEN LENGTH(TRIM(TO_CHAR($input_value))) <> 10 THEN 'FAIL' ELSE 'PASS' END

-- VALIDITY: Format xxx-xx-xxxx (Rule 5, e.g., TIN)
CASE WHEN SUBSTR($input_value,4,1) = '-' AND SUBSTR($input_value,7,1) = '-'
     AND LENGTH(REPLACE($input_value,'-','')) = 9 THEN 'PASS' ELSE 'FAIL' END

-- UNIQUENESS: Duplicate detection (Rule 6)
GROUP BY $input_value HAVING COUNT(*) > 1

-- CONSISTENCY: Multi-column validation (Rule 7)
CASE WHEN $input_value1 <> '0001-01-01' AND $input_value2 > 5000
     THEN 'FAIL' ELSE 'PASS' END

-- INTEGRITY: Cross-table join validation (Rule 8)
SELECT CASE WHEN A.CLAIM_DT <> B.PROCEDURE_DT AND A.CLAIM_AMT <> 0
       THEN 'FAIL' ELSE 'PASS' END
FROM CLAIMS A JOIN PROCEDURE B ON A.CLAIM_ID = B.PROCEDURE_ID
```

---

## 12. Pipeline Execution Flow (End-to-End)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  SP_RUN_PACKAGE('INCREMENTAL')                                                   │
│                                                                                   │
│  Step 1: BRONZE STAGING                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_STG_NPI_REGISTRY(run_id, mode)                                      │    │
│  │    → Read from RAW_INGESTION.RAW_NPI_REGISTRY                           │    │
│  │    → Apply inline reject (NULL NPI, invalid format, etc.)               │    │
│  │    → Insert passing records into BRONZE.STG_NPI_REGISTRY                │    │
│  │    → Rejected records → REJECT.REJECT_RECORDS                           │    │
│  │                                                                          │    │
│  │  SP_STG_SPECIALTY_TYPE(run_id, mode)                                    │    │
│  │    → Read from RAW_INGESTION.RAW_SPECIALTY_TYPE                         │    │
│  │    → Insert into BRONZE.STG_SPECIALTY_TYPE                              │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                                     ▼                                            │
│  Step 2: DQ CHECK — BRONZE                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_RUN_DQ_BRONZE(run_id)                                               │    │
│  │    → SP_RUN_DQ_CHECK(run_id, 'STG_NPI_REGISTRY', 'BRONZE', job_id)     │    │
│  │    → SP_RUN_DQ_CHECK(run_id, 'STG_SPECIALTY_TYPE', 'BRONZE', job_id)   │    │
│  │    → Updates DQ_STATUS on each Bronze table record                      │    │
│  │    → Inserts detailed results into AUDIT.DQ_RESULTS                     │    │
│  │    → If threshold exceeded → PIPELINE STOPS HERE (circuit breaker)      │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                          (Only if DQ passed)                                     │
│                                     ▼                                            │
│  Step 3: SILVER LOAD                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_LOAD_SILVER_PROVIDER(run_id, mode)                                  │    │
│  │    → SELECT from Bronze WHERE DQ_STATUS IN ('PASS', 'PASS-SOFT')        │    │
│  │    → Unify NPI + Specialty into DIM_PROVIDER                            │    │
│  │    → MERGE into SILVER.DIM_PROVIDER                                     │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                                     ▼                                            │
│  Step 4: DQ CHECK — SILVER                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_RUN_DQ_SILVER(run_id)                                               │    │
│  │    → SP_RUN_DQ_CHECK(run_id, 'DIM_PROVIDER', 'SILVER', job_id)         │    │
│  │    → Updates DQ_STATUS on DIM_PROVIDER                                  │    │
│  │    → If threshold exceeded → PIPELINE STOPS HERE                        │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                          (Only if DQ passed)                                     │
│                                     ▼                                            │
│  Step 5: SCD TYPE-2                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_SCD2_PROVIDER_ATTRIBUTES(run_id, mode)                              │    │
│  │    → Hash-diff comparison against SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES    │    │
│  │    → Close expired versions (_IS_CURRENT = FALSE)                       │    │
│  │    → Insert new versions                                                 │    │
│  │    → Only processes DQ_STATUS IN ('PASS', 'PASS-SOFT')                  │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                                     ▼                                            │
│  Step 6: GOLD LOAD                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_LOAD_GOLD_PROVIDER(run_id, mode)                                    │    │
│  │    → Build FCT_PROVIDER_360 from SCD2 snapshot                          │    │
│  │    → Only current versions with DQ_STATUS IN ('PASS','PASS-SOFT')       │    │
│  │    → Derive business attributes (gender_desc, status_desc, etc.)        │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                     │                                            │
│                                     ▼                                            │
│  Step 7: AUDIT & REPORTING                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  SP_AUDIT_REJECT_SUMMARY(run_id)                                        │    │
│  │    → Aggregate reject reasons into REJECT.REJECT_SUMMARY                │    │
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
- **Location:** `SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES`

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
