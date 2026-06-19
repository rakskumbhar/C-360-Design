# Data Quality Engine — Workflow & Design Document

## 1. Overview

The Clinician-360 DQ Engine (`CONFIG.SP_RUN_DQ_CHECK`) is a **metadata-driven, token-substitution** data quality framework built entirely in Snowflake SQL. It evaluates configurable rules against any table/layer without hardcoded logic — adding a new rule requires only inserting rows into configuration tables.

---

## 2. Architecture Pattern

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ORCHESTRATOR (SP_RUN_PACKAGE)                        │
│  Calls pipeline steps sequentially: Stage → DQ Check → Load → DQ Check...  │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DQ ENGINE (CONFIG.SP_RUN_DQ_CHECK)                        │
│                                                                             │
│  Parameters: P_RUN_ID, P_TABLE_NM, P_LAYER, P_DQ_BATCH_ID                  │
│                                                                             │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │  Count   │──▶│ Iterate Feeds│──▶│ Token Replace│──▶│ Execute SQL    │  │
│  │  WHERE   │   │ (DQ_FEED +   │   │ on RULE_EXP  │   │ INSERT INTO    │  │
│  │  DQ_STATUS│   │  DQ_RULE)    │   │              │   │ DQ_RESULT      │  │
│  │  IS NULL │   └──────────────┘   └──────────────┘   └────────────────┘  │
│  └──────────┘                                                    │          │
│                                                                  ▼          │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────────────┐   │
│  │ Check        │◀──│ Log DQ_LOG + │◀──│ MERGE DQ_STATUS back to      │   │
│  │ Threshold    │   │ DQ_LOG_HIST  │   │ source table (FAIL/PASS-SOFT │   │
│  │              │   │              │   │ /PASS)                        │   │
│  └──────────────┘   └──────────────┘   └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Core Design Concepts

### 3.1 Token-Substitution Pattern

The engine **never hardcodes rule logic**. Instead, each rule stores a SQL expression template in `DQ_RULE.RULE_EXP` with placeholder tokens. At runtime, the engine replaces tokens with actual values from `DQ_FEED`:

```
RULE_EXP template:  CASE WHEN TRIM(COALESCE(${INPUT1},''))= '' THEN 'FAIL' ELSE 'PASS' END
                                       ▼ (token substitution)
Resolved SQL:       CASE WHEN TRIM(COALESCE(CAST(NPI_NUMBER AS VARCHAR),''))= '' THEN 'FAIL' ELSE 'PASS' END
```

### 3.2 Three-Outcome Model

Every record that goes through DQ evaluation receives one of three statuses:

| Status | Meaning | Trigger |
|--------|---------|---------|
| **PASS** | Record is clean | No rule violations detected |
| **PASS-SOFT** | Record has minor issues | Only non-critical rules failed (`CRITICALITY_IND = 'N'`) |
| **FAIL** | Record has serious issues | At least one critical rule failed (`CRITICALITY_IND = 'Y'`) |

**Priority:** FAIL > PASS-SOFT > PASS (worst status wins when multiple rules apply)

### 3.3 DQ_RESULT as Audit Trail

`DQ_RESULT` stores only records that **violated** a rule. The `RESULT` column reflects criticality:
- Critical violation → `RESULT = 'FAIL'`
- Non-critical violation → `RESULT = 'PASS-SOFT'`

Records that pass all rules are **never** inserted into DQ_RESULT (they get `DQ_STATUS = 'PASS'` directly on the source table).

### 3.4 Layer Gating

The Silver load only accepts Bronze records with `DQ_STATUS IN ('PASS', 'PASS-SOFT')`. Records with `FAIL` are blocked from flowing downstream:

```
Bronze (FAIL)      → Stays in Bronze, queryable for debugging
Bronze (PASS-SOFT) → Flows to Silver (minor issues tolerated)
Bronze (PASS)      → Flows to Silver (clean)
Silver (FAIL)      → Stays in Silver, blocks Gold load
Silver (PASS/SOFT) → Flows to Gold
```

---

## 4. Configuration Tables

### 4.1 DQ_RULE — Rule Definitions

Stores reusable rule templates. Each rule has a SQL expression with tokens.

| Column | Purpose |
|--------|---------|
| RULE_ID | Auto-increment primary key |
| RULE_CODE | Human-readable identifier (e.g., `GN_NotNull`, `GN_InList`) |
| RULE_EXP | SQL expression template with `${TOKEN}` placeholders |
| RULE_CATEGORY | `SIMPLE`, `COMPLEX`, or `SQL_FEED` (determines execution pattern) |
| CATEGORY_ID | FK to DQ_CATEGORY (Completeness, Validity, etc.) |

### 4.2 DQ_FEED — Rule Assignments

Maps rules to specific columns on specific tables. This is where you configure *what* to check.

| Column | Purpose |
|--------|---------|
| FEED_ID | Auto-increment primary key |
| LAYER | `BRONZE`, `SILVER`, or `GOLD` |
| TABLE_NM | Target table name |
| RULE_ID | FK to DQ_RULE |
| DQ_RULE_INPUT | Column name to validate (replaces `${INPUT1}`) |
| DQ_RULE_INPUT_WHERE_COL | Parameter for IN-list or filter values (replaces `${INPUT2}`) |
| DQ_RULE_INPUT_JOIN_TBL | Reference table for LOOKUP rules |
| DQ_RULE_INPUT_JOIN_COL | Join column on reference table |
| RECORD_KEY_NM | Surrogate/business key column for identifying records |
| CRITICALITY_IND | `Y` = critical (FAIL), `N` = non-critical (PASS-SOFT) |
| ACTIVE_IND | `Y` = enabled, `N` = disabled |
| INCREMENTAL_DATE_COLUMN | Column used for incremental processing |

### 4.3 DQ_RESULT — Failure Audit Log

Stores every rule violation detected during a DQ run.

| Column | Purpose |
|--------|---------|
| DQ_BATCH_ID | Groups all results from one DQ check invocation |
| TABLE_NM | Which table was checked |
| FEED_ID | Which feed/rule combination triggered |
| RECORD_KEY | The surrogate key value of the failing record |
| RECORD_VALUE | The actual column value that failed |
| RESULT | `FAIL` or `PASS-SOFT` based on criticality |

---

## 5. Token Reference

Tokens in `DQ_RULE.RULE_EXP` are replaced at runtime:

| Token | Resolved From | Example |
|-------|---------------|---------|
| `${INPUT1}` | `CAST(DQ_FEED.DQ_RULE_INPUT AS VARCHAR)` | `CAST(NPI_NUMBER AS VARCHAR)` |
| `${INPUT2}` | `DQ_FEED.DQ_RULE_INPUT_WHERE_COL` | `'MD','DO','NP'` |
| `${INPUTN}` | `DQ_FEED.DQ_RULE_INPUT` (raw, no CAST) | `NPI_NUMBER` |
| `${TABLE_NAME}` | `P360_DQ.<schema>.<table>` | `P360_DQ.BRONZE.STG_NPI_REGISTRY` |
| `${JOINTBL1}` | Source table (same as TABLE_NAME) | `P360_DQ.BRONZE.STG_NPI_REGISTRY` |
| `${JOINTBL2}` | `DQ_FEED.DQ_RULE_INPUT_JOIN_TBL` | `P360_DQ.CONFIG.REF_STATE_CODES` |
| `${JOINCOL1}` | `DQ_FEED.DQ_RULE_INPUT` | `STATE` |
| `${JOINCOL2}` | `DQ_FEED.DQ_RULE_INPUT_JOIN_COL` | `STATE_CODE` |
| `${WHERECOL1}` | `DQ_FEED.DQ_RULE_INPUT_WHERE_COL` | `STATE_CODE` |
| `${INCREMENTAL_DATE_COLUMN}` | Hardcoded to `DQ_STATUS IS NULL` | Filters unprocessed records |

**Why `${INPUT1}` wraps in CAST:** The engine applies `CAST(column AS VARCHAR)` to `${INPUT1}` so that rules like `GN_NotNull` (which use `COALESCE(${INPUT1},'')`) work correctly on DATE, NUMBER, and TIMESTAMP columns without type errors.

**Why `${INPUTN}` does NOT wrap in CAST:** Used for PARTITION BY in duplicate detection where the original data type must be preserved for correct grouping.

---

## 6. Rule Category Execution Patterns

### 6.1 SIMPLE Rules

For per-row expression evaluation. The engine wraps the resolved expression in a SELECT and filters where the result equals `'FAIL'`:

```sql
INSERT INTO DQ_RESULT (...)
SELECT <batch_id>, <layer>, <domain>, <table>, <rule_id>, <feed_id>,
       CAST(<key_col> AS VARCHAR),
       CAST(<input_col> AS VARCHAR),
       'FAIL' or 'PASS-SOFT',    -- based on CRITICALITY_IND
       CURRENT_USER()
FROM <source_table>
WHERE DQ_STATUS IS NULL
  AND (<resolved_expression>) = 'FAIL'
```

**Examples:** GN_NotNull, GN_Length2, GN_Length10, GN_FormatTIN, GN_UpperCase, GN_Timeliness, GN_InList

### 6.2 COMPLEX Rules

For rules requiring window functions or multi-table joins. Currently handles `GN_Duplicate` with an explicit QUALIFY pattern:

```sql
INSERT INTO DQ_RESULT (...)
SELECT <batch_id>, <layer>, <domain>, <table>, <rule_id>, <feed_id>,
       CAST(a.<key_col> AS VARCHAR),
       CAST(a.<input_col> AS VARCHAR),
       'FAIL' or 'PASS-SOFT',
       CURRENT_USER()
FROM <source_table> a
WHERE DQ_STATUS IS NULL
QUALIFY (ROW_NUMBER() OVER(PARTITION BY <input_col> ORDER BY <incr_col> DESC)) > 1
```

**Examples:** GN_Duplicate, GN_LOOKUP, GN_RefIntegrity

### 6.3 SQL_FEED Rules

For fully custom SQL. The entire resolved expression is treated as a subquery:

```sql
INSERT INTO DQ_RESULT (...)
SELECT <batch_id>, <layer>, <domain>, <table>, <rule_id>, <feed_id>,
       CAST(<key_col> AS VARCHAR),
       CAST(<input_col> AS VARCHAR),
       'FAIL' or 'PASS-SOFT',
       CURRENT_USER()
FROM (<resolved_expression>) sub
WHERE sub.RESULT = 'FAIL'
```

---

## 7. Stored Procedure Step-by-Step Walkthrough

### SP_RUN_DQ_CHECK(P_RUN_ID, P_TABLE_NM, P_LAYER, P_DQ_BATCH_ID)

#### Step 1: Initialize & Count

```
1. Set v_dq_start_ts = CURRENT_TIMESTAMP()
2. Resolve schema from layer: BRONZE/SILVER/GOLD
3. Build fully qualified table name: P360_DQ.<schema>.<table>
4. Execute: SELECT COUNT(*) FROM <table> WHERE DQ_STATUS IS NULL
5. If count = 0 → log success with 0 counts → RETURN early
```

**Why DQ_STATUS IS NULL?** This is the incremental processing filter. Only new/unprocessed records (NULL status) are evaluated. Records already marked PASS/FAIL/PASS-SOFT from a previous run are skipped.

#### Step 2: Fetch Feeds & Iterate

```
1. Get RECORD_KEY_NM from DQ_FEED (identifies which column is the record's key)
2. Open cursor over: DQ_FEED JOIN DQ_RULE WHERE table + layer + ACTIVE_IND='Y'
3. For each feed:
   a. Assign cursor fields to local variables
   b. Perform token substitution on RULE_EXP
   c. Build dynamic INSERT-SELECT based on RULE_CATEGORY
   d. EXECUTE IMMEDIATE the dynamic SQL
   e. On exception: log error to DQ_LOG but CONTINUE to next feed
```

**Key design choice:** Per-feed exception handling ensures one bad rule doesn't abort the entire DQ check. Failed feeds are logged individually.

#### Step 3: Count Critical Failures

```sql
SELECT COUNT(DISTINCT RECORD_KEY) INTO v_fail_count
FROM DQ_RESULT
WHERE DQ_BATCH_ID = :batch AND TABLE_NM = :table AND RESULT = 'FAIL'
```

**Why DISTINCT RECORD_KEY?** A single record can fail multiple rules, producing multiple DQ_RESULT rows. The threshold should be based on how many *records* failed critically, not how many *rule violations* occurred.

**Why only RESULT = 'FAIL'?** Non-critical violations (PASS-SOFT) should not count toward the threshold that blocks pipeline progression.

#### Step 4: MERGE DQ_STATUS Back to Source Table

```sql
MERGE INTO <source_table> tgt
USING (
    SELECT RECORD_KEY,
        CASE WHEN MAX(CASE WHEN RESULT = 'FAIL' THEN 1 ELSE 0 END) > 0
             THEN 'FAIL'
             ELSE 'PASS-SOFT'
        END AS COMPUTED_STATUS
    FROM DQ_RESULT
    WHERE DQ_BATCH_ID = :batch AND TABLE_NM = :table
    GROUP BY RECORD_KEY
) src
ON CAST(tgt.<key_col> AS VARCHAR) = src.RECORD_KEY
WHEN MATCHED AND tgt.DQ_STATUS IS NULL
THEN UPDATE SET DQ_STATUS = src.COMPUTED_STATUS;

-- Then: all remaining NULLs = PASS
UPDATE <source_table> SET DQ_STATUS = 'PASS' WHERE DQ_STATUS IS NULL;
```

**Logic:**
- If a record has ANY `RESULT = 'FAIL'` entry in DQ_RESULT → `DQ_STATUS = 'FAIL'`
- If a record has ONLY `RESULT = 'PASS-SOFT'` entries → `DQ_STATUS = 'PASS-SOFT'`
- If a record has NO entries in DQ_RESULT → `DQ_STATUS = 'PASS'`

#### Step 5: Log Results

Insert summary row into both `DQ_LOG` (current state) and `DQ_LOG_HISTORY` (immutable archive):
- `OVERALL_COUNT`: Total records evaluated
- `FAILED_COUNT`: Distinct records with critical failures
- `STATUS`: 'Success' (DQ check completed, regardless of failures found)

#### Step 6: Check Threshold

```
1. Call SP_CHECK_DQ_THRESHOLD(run_id, NULL, table, overall_count, fail_count)
2. Threshold = fail_count / overall_count * 100
3. If threshold exceeded → v_threshold_exceeded = TRUE
4. Return result object with status, counts, and threshold_exceeded flag
```

The orchestrator reads `threshold_exceeded` from the return value and decides whether to block downstream processing.

---

## 8. End-to-End Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ SP_RUN_PACKAGE('FULL')                                                      │
│                                                                             │
│  Step 1: SP_STG_NPI_REGISTRY        → Bronze staging (RAW → Bronze)        │
│  Step 2: SP_STG_SPECIALTY_TYPE      → Bronze staging (RAW → Bronze)        │
│                                                                             │
│  Step 3: SP_RUN_DQ_BRONZE                                                   │
│      └─ SP_RUN_DQ_CHECK(run_id, 'STG_NPI_REGISTRY', 'BRONZE', batch_id)   │
│      └─ SP_RUN_DQ_CHECK(run_id, 'STG_SPECIALTY_TYPE', 'BRONZE', batch_id) │
│           ┌─────────────────────────────────────────────────────┐          │
│           │ DQ_STATUS updated on Bronze tables:                  │          │
│           │   PASS → eligible for Silver                        │          │
│           │   PASS-SOFT → eligible for Silver (minor issues)    │          │
│           │   FAIL → blocked from Silver                        │          │
│           └─────────────────────────────────────────────────────┘          │
│      └─ If threshold exceeded → STOP pipeline                              │
│                                                                             │
│  Step 4: SP_LOAD_DIM_PROVIDER       → Silver load                          │
│      └─ MERGE from Bronze WHERE DQ_STATUS IN ('PASS','PASS-SOFT')          │
│                                                                             │
│  Step 5: SP_RUN_DQ_SILVER                                                   │
│      └─ SP_RUN_DQ_CHECK(run_id, 'DIM_PROVIDER', 'SILVER', batch_id)       │
│           ┌─────────────────────────────────────────────────────┐          │
│           │ DQ_STATUS updated on Silver table                    │          │
│           └─────────────────────────────────────────────────────┘          │
│      └─ If threshold exceeded → STOP pipeline                              │
│                                                                             │
│  Step 6: SP_SCD2_PROVIDER_ATTRIBUTES → SCD2 history tracking               │
│      └─ Only processes DIM_PROVIDER WHERE DQ_STATUS IN ('PASS','PASS-SOFT')│
│                                                                             │
│  Step 7: SP_LOAD_FCT_PROVIDER_360   → Gold fact table                      │
│      └─ Joins DIM_PROVIDER + SCD2 for business-ready view                  │
│                                                                             │
│  Step 8: SP_AUDIT_REJECT_SUMMARY    → Aggregates failures for reporting    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Adding a New DQ Rule (Zero Code Changes)

### Example: Add a "Valid Email Format" rule

**Step 1:** Insert rule definition
```sql
INSERT INTO P360_DQ.CONFIG.DQ_RULE (CATEGORY_ID, RULE_CODE, RULE_DESC, RULE_EXP, RULE_CATEGORY)
VALUES (6, 'GN_EmailFormat', 'Validate email format contains @',
        'CASE WHEN ${INPUT1} NOT LIKE ''%@%.%'' THEN ''FAIL'' ELSE ''PASS'' END',
        'SIMPLE');
```

**Step 2:** Assign rule to a table/column
```sql
INSERT INTO P360_DQ.CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
VALUES ('SILVER', 'PROVIDERS',
    (SELECT RULE_ID FROM DQ_RULE WHERE RULE_CODE = 'GN_EmailFormat'),
    'DIM_PROVIDER', 'PROVIDER_SK', 'LOAD_DT', 'EMAIL', 'N', 'Y', 'GROUP_A');
```

**Step 3:** Done. The engine picks it up automatically on next run.

---

## 10. Existing Rules Catalog

| Rule ID | Code | Category | Expression Pattern | Use Case |
|---------|------|----------|-------------------|----------|
| 1 | GN_Duplicate | COMPLEX | ROW_NUMBER PARTITION BY → QUALIFY > 1 | Detect duplicate records |
| 2 | GN_NotNull | SIMPLE | `COALESCE(col,'') = ''` | Mandatory field check |
| 3 | GN_LOOKUP | COMPLEX | LEFT JOIN + WHERE ref IS NULL | Referential lookup |
| 4 | GN_Length2 | SIMPLE | `LENGTH(col) <> 2` | State code validation |
| 5 | GN_Length9 | SIMPLE | `LENGTH(col) <> 9` | SSN-style field |
| 6 | GN_Length10 | SIMPLE | `LENGTH(col) <> 10` | NPI number validation |
| 7 | GN_FormatTIN | SIMPLE | `SUBSTR` pattern check `xxx-xx-xxxx` | TIN format |
| 8 | GN_UpperCase | SIMPLE | `col <> UPPER(col)` | Case standardization |
| 9 | GN_Timeliness | SIMPLE | `DATEDIFF > 365` | Stale data detection |
| 10 | GN_RefIntegrity | COMPLEX | LEFT JOIN + WHERE ref IS NULL | Cross-table integrity |
| 101 | GN_InList | SIMPLE | `col NOT IN (values)` | Allowed values validation |

---

## 11. Error Handling Strategy

1. **Per-feed exception handling:** If one feed's dynamic SQL fails (e.g., bad column name), the error is logged to `DQ_LOG` with the `FEED_ID` and error message, then processing continues with the next feed.

2. **Procedure-level exception:** If the entire procedure fails (e.g., can't count source rows), a final `DQ_LOG` entry is written with `STATUS = 'Fail'` and the error message is returned in the JSON result.

3. **Orchestrator handling:** The orchestrator (`SP_RUN_PACKAGE`) reads the return value. If `status = 'THRESHOLD_EXCEEDED'` or an exception occurred, it marks the step as failed, logs the error, and either stops or allows resume.

---

## 12. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| DQ_RESULT stores only failures | Avoids storing millions of PASS rows; source table DQ_STATUS is the PASS indicator |
| RESULT = 'FAIL' vs 'PASS-SOFT' in DQ_RESULT | Enables single-table audit queries without joining back to DQ_FEED for criticality |
| COUNT(DISTINCT RECORD_KEY) for threshold | A record failing 5 rules is still 1 bad record, not 5 |
| Only RESULT='FAIL' counts toward threshold | Non-critical issues shouldn't block pipeline progression |
| CAST(column AS VARCHAR) in ${INPUT1} | Prevents type errors when NotNull/Length rules run on DATE/NUMBER columns |
| Separate ${INPUTN} without CAST | Preserves original type for PARTITION BY in duplicate detection |
| Per-feed exception handling | One bad rule config shouldn't abort the entire DQ check for a table |
| DQ_STATUS IS NULL as incremental filter | Enables re-processing only new/updated records; already-evaluated records are skipped |
