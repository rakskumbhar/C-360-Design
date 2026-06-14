# Testing New Data

## Provider-360-by-snowflake-sp

---

### Testing Approach

Unlike dbt where tests are declarative YAML definitions, this project implements:

1. **Pre-load DQ validation** (inline in procedures)
2. **Post-load validation queries** (manual or automated)
3. **End-to-end pipeline tests**

---

### 1. Testing Bronze Layer (Data Quality)

#### Verify DQ Rules Are Working
```sql
-- Run a single bronze step
CALL P360_SP.BRONZE.SP_STG_NPI_REGISTRY(UUID_STRING(), 'FULL');

-- Check rejects
SELECT step_name, source_table, 
    r.value::VARCHAR AS reason, COUNT(*)
FROM P360_SP.REJECT.REJECT_RECORDS,
    LATERAL FLATTEN(reject_reasons) r
WHERE step_name = 'STG_NPI_REGISTRY'
GROUP BY 1, 2, 3 ORDER BY 4 DESC;
```

#### Add Test Data with Known Failures
```sql
-- Insert test record that should be rejected
INSERT INTO SNOWFLAKE_LEARNING_DB.RAW_INGESTION.NPI_RAW 
(npi_number, provider_first_name, provider_last_name_legal, status, _loaded_at)
VALUES ('123', NULL, 'TEST', 'X', CURRENT_TIMESTAMP());

-- Run pipeline
CALL P360_SP.BRONZE.SP_STG_NPI_REGISTRY(UUID_STRING(), 'INCREMENTAL');

-- Verify rejection with correct reasons
SELECT * FROM P360_SP.REJECT.REJECT_RECORDS
WHERE record_key = '123'
ORDER BY rejected_at DESC LIMIT 1;
-- Expected: reject_reasons = ['NPI_INVALID_LENGTH', 'FIRST_NAME_NULL', 'INVALID_NPI_STATUS']
```

---

### 2. Testing Silver Layer

#### Verify Unification Logic
```sql
-- Run silver unification
CALL P360_SP.SILVER.SP_INT_PROVIDERS_UNIFIED(UUID_STRING(), 'FULL');

-- Check join completeness
SELECT 
    COUNT(*) AS total_providers,
    COUNT(specialty_code) AS has_credentials,
    COUNT(facility_name) AS has_emr_data,
    ROUND(COUNT(specialty_code)::FLOAT / COUNT(*) * 100, 1) AS cred_coverage_pct,
    ROUND(COUNT(facility_name)::FLOAT / COUNT(*) * 100, 1) AS emr_coverage_pct
FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED;
```

#### Verify Deduplication
```sql
-- Check for remaining duplicates (should be 0)
SELECT npi_number, COUNT(*) AS cnt
FROM P360_SP.SILVER.INT_PROVIDERS_DEDUPED
GROUP BY npi_number HAVING COUNT(*) > 1;
```

---

### 3. Testing SCD2

```sql
-- Run SCD2
CALL P360_SP.SILVER.SP_SCD2_PROVIDER_ATTRIBUTES(UUID_STRING(), 'FULL');

-- Verify all current records have _is_current = TRUE
SELECT _is_current, COUNT(*) 
FROM P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES
GROUP BY _is_current;

-- Verify only one current version per NPI
SELECT npi_number, COUNT(*) 
FROM P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES
WHERE _is_current = TRUE
GROUP BY npi_number HAVING COUNT(*) > 1;
-- Should return 0 rows

-- Simulate a change and verify versioning
UPDATE P360_SP.SILVER.INT_PROVIDERS_UNIFIED
SET provider_status = 'INACTIVE' WHERE npi_number = (
    SELECT npi_number FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED LIMIT 1
);

CALL P360_SP.SILVER.SP_SCD2_PROVIDER_ATTRIBUTES(UUID_STRING(), 'INCREMENTAL');

-- Check history for that NPI
SELECT npi_number, provider_status, _valid_from, _valid_to, _is_current
FROM P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES
WHERE npi_number = '<test_npi>'
ORDER BY _valid_from;
```

---

### 4. Testing Gold Layer

#### Verify Provider 360 Summary
```sql
CALL P360_SP.GOLD.SP_PROVIDER_360_SUMMARY(UUID_STRING(), 'FULL');

-- Basic completeness
SELECT 
    COUNT(*) AS total_providers,
    SUM(CASE WHEN is_fully_active THEN 1 ELSE 0 END) AS active_providers,
    AVG(total_claims) AS avg_claims,
    AVG(denial_rate_pct) AS avg_denial_rate
FROM P360_SP.GOLD.PROVIDER_360_SUMMARY;

-- Verify no NULL NPI numbers
SELECT COUNT(*) FROM P360_SP.GOLD.PROVIDER_360_SUMMARY WHERE npi_number IS NULL;
-- Should be 0
```

---

### 5. End-to-End Pipeline Test

```sql
-- Full pipeline execution
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

-- Verify run completed
SELECT run_id, run_status, duration_seconds, 
    total_rows_read, total_rows_written, total_rows_rejected,
    completed_steps, total_steps
FROM P360_SP.AUDIT.PKG_RUN_LOG
ORDER BY start_timestamp DESC LIMIT 1;

-- Verify all steps completed
SELECT step_name, step_status, rows_read, rows_written, rows_rejected, duration_seconds
FROM P360_SP.AUDIT.STEP_RUN_LOG
WHERE run_id = (SELECT run_id FROM P360_SP.AUDIT.PKG_RUN_LOG ORDER BY start_timestamp DESC LIMIT 1)
ORDER BY start_timestamp;
```

---

### 6. DQ Threshold Test

```sql
-- Temporarily lower threshold to trigger failure
UPDATE P360_SP.CONFIG.PKG_CONFIG SET config_value = '0.1' WHERE config_key = 'DQ_REJECT_THRESHOLD';

-- Run - should fail if any rejects exist
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

-- Verify failure was captured
SELECT run_status, failed_step_id, error_message
FROM P360_SP.AUDIT.PKG_RUN_LOG ORDER BY start_timestamp DESC LIMIT 1;

-- Reset threshold
UPDATE P360_SP.CONFIG.PKG_CONFIG SET config_value = '5.0' WHERE config_key = 'DQ_REJECT_THRESHOLD';
```

---

### 7. Resume Test

```sql
-- Intentionally break a step (disable a source table reference)
-- Then run and observe failure
-- Then fix and resume:
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RESUME', '<failed_run_id>');

-- Verify it skipped previously completed steps
SELECT step_name, step_status FROM P360_SP.AUDIT.STEP_RUN_LOG
WHERE run_id = '<failed_run_id>' ORDER BY start_timestamp;
```
