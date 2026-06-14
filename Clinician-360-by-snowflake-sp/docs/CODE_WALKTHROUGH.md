# Code Walkthrough

## Provider-360-by-snowflake-sp

---

### Project Structure

```
Provider-360-by-snowflake-sp/
├── 00_CONFIG/
│   ├── 001_setup_database_schemas.sql    # Database and schema DDL
│   ├── 002_configuration_tables.sql      # Config, step registry, DQ rules, notifications
│   └── 003_seed_configuration.sql        # Default configuration data
├── 01_FRAMEWORK/
│   ├── 001_audit_tables.sql              # Run logs, step logs, error logs, DQ logs
│   ├── 002_utility_procedures.sql        # Logging, error handling, notifications
│   └── 003_target_tables.sql             # All Bronze/Silver/Gold/Snapshot DDL
├── 02_BRONZE/
│   ├── 001_sp_stg_npi_registry.sql       # NPI staging with DQ
│   ├── 002_sp_stg_cred_providers.sql     # Credentialing staging with DQ
│   ├── 003_sp_stg_emr_providers.sql      # EMR staging with DQ
│   ├── 004_sp_stg_claims_providers.sql   # Claims staging with DQ
│   └── 005_sp_stg_network_affiliations.sql # Network staging with DQ
├── 03_SILVER/
│   ├── 001_sp_int_providers_unified.sql  # Multi-source unification
│   ├── 002_sp_int_providers_deduped.sql  # Deduplication by NPI
│   ├── 003_sp_int_network_affiliations.sql # Network enrichment
│   └── 004_sp_scd2_provider_attributes.sql # SCD Type-2 history
├── 04_GOLD/
│   ├── 001_sp_dim_provider.sql           # Provider dimension (SCD2-sourced)
│   ├── 002_sp_dim_provider_network.sql   # Network dimension
│   ├── 003_sp_fct_provider_visits.sql    # Visits fact (incremental)
│   └── 004_sp_provider_360_summary.sql   # One Big Table summary
├── 05_AUDIT/
│   └── 001_sp_reject_summary.sql         # Reject summary + run metadata
├── 06_ORCHESTRATION/
│   ├── 001_sp_run_package.sql            # Master orchestrator
│   └── 002_scheduling_and_tasks.sql      # Tasks + monitoring views
├── 07_DEPLOY/
│   └── 001_deploy_all.sql                # Deployment guide
└── docs/
    ├── ARCHITECTURE.md                    # Architecture documentation
    ├── OPERATIONS.md                      # Operations guide
    └── CODE_WALKTHROUGH.md               # This file
```

---

### Procedure Patterns

#### Standard Bronze Procedure Pattern

Every Bronze layer procedure follows this template:

```sql
CREATE OR REPLACE PROCEDURE BRONZE.SP_STG_<SOURCE>(P_RUN_ID VARCHAR, P_MODE VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_step_run_id VARCHAR;
    v_hwm TIMESTAMP_NTZ;         -- High-water mark for incremental
    v_total_count NUMBER;
    v_reject_count NUMBER;
    v_insert_count NUMBER;
BEGIN
    -- 1. Initialize step logging
    v_step_run_id := UUID_STRING();
    CALL SP_LOG_STEP_START(...);

    -- 2. Determine high-water mark (INCREMENTAL vs FULL)
    IF (P_MODE = 'INCREMENTAL') THEN
        SELECT MAX(_source_loaded_at) INTO v_hwm FROM target_table;
    ELSE
        TRUNCATE TABLE target_table;
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
    END IF;

    -- 3. Count incoming records
    SELECT COUNT(*) INTO v_total_count FROM source WHERE _loaded_at > v_hwm;

    -- 4. Insert rejected records (DQ failures)
    INSERT INTO REJECT.REJECT_RECORDS
    SELECT ... WHERE <dq_rules_fail> AND _loaded_at > v_hwm;
    v_reject_count := SQLROWCOUNT;

    -- 5. Check DQ threshold (circuit breaker)
    CALL SP_CHECK_DQ_THRESHOLD(...)  -- Returns TRUE if threshold exceeded

    -- 6. Insert valid records
    INSERT INTO target_table
    SELECT ... WHERE NOT <dq_rules_fail> AND _loaded_at > v_hwm;
    v_insert_count := SQLROWCOUNT;

    -- 7. Log step completion
    CALL SP_LOG_STEP_END(...);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', ...);

EXCEPTION
    WHEN OTHER THEN
        CALL SP_LOG_ERROR(...);
        CALL SP_LOG_STEP_END(..., 'FAILED');
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', SQLERRM);
END;
$$;
```

---

### Key Design Decisions

#### 1. MERGE vs INSERT for Incremental

Silver and Gold layers use MERGE to ensure idempotency:
- If a run partially completes and is re-executed, MERGE prevents duplicates
- Uses surrogate keys (MD5 hash) as merge keys

#### 2. SCD2 via Hash Comparison

The SCD2 procedure:
1. Computes a hash of all tracked attributes
2. Compares with current version's hash
3. If different: closes current version (_valid_to = now, _is_current = FALSE)
4. Inserts new version (_valid_from = now, _is_current = TRUE)

#### 3. DQ as Gate, Not Post-Check

Unlike dbt where tests run AFTER loading:
- SP approach validates BEFORE loading
- Invalid records go to REJECT table
- Valid records proceed to target
- If reject % exceeds threshold, step FAILS (no partial bad data)

#### 4. Configuration-Driven Execution

All parameters live in CONFIG tables:
- Step ordering and dependencies in PKG_STEP_REGISTRY
- DQ thresholds in PKG_CONFIG
- No code changes needed for:
  - Adjusting retry counts
  - Changing thresholds
  - Enabling/disabling steps
  - Switching environments

#### 5. Resume-from-Failure

When a run fails:
1. PKG_RUN_LOG records `failed_step_id`
2. Resume mode skips all completed steps
3. Starts from the exact step that failed
4. Maintains the same `run_id` for lineage continuity

---

### Execution Modes

| Mode | Behavior |
|------|----------|
| `FULL` | Truncates all targets, processes all source data |
| `INCREMENTAL` | Uses high-water-mark, processes only new records |
| `RESUME` | Resumes from last failed step of specified run |
| `RERUN_STEP` | Re-executes a single step by ID |

---

### Data Flow Per Source

#### NPI Registry Flow
```
NPI_RAW → [DQ Validate] → STG_NPI_REGISTRY → INT_PROVIDERS_UNIFIED 
    → INT_PROVIDERS_DEDUPED → SCD2_PROVIDER_ATTRIBUTES → DIM_PROVIDER
    → PROVIDER_360_SUMMARY
```

#### Claims Flow
```
CLAIMS_RAW → [DQ Validate] → STG_CLAIMS_PROVIDERS → FCT_PROVIDER_VISITS
    → PROVIDER_360_SUMMARY (aggregated)
```

#### Network Flow
```
NETWORK_AFFILIATIONS_RAW → [DQ Validate] → STG_NETWORK_AFFILIATIONS 
    → INT_NETWORK_AFFILIATIONS → DIM_PROVIDER_NETWORK
    → PROVIDER_360_SUMMARY (aggregated)
```

---

### Return Value Convention

All procedures return a VARIANT object:

```json
// Success
{"status": "COMPLETED", "rows_read": 1000, "rows_written": 985, "rows_rejected": 15}

// Failure  
{"status": "FAILED", "error": "Division by zero", "reason": "DQ_THRESHOLD_EXCEEDED"}

// Skipped
{"status": "SKIPPED", "reason": "SCD2_DISABLED"}
```

The orchestrator uses `status` field to determine next action (continue, retry, or abort).
