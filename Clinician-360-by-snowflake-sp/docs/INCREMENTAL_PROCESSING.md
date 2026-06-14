# Incremental Processing

## Provider-360-by-snowflake-sp

---

### Overview

The Provider 360 SP pipeline supports two processing modes:

| Mode | Description | Use Case |
|------|------------|----------|
| **FULL** | Truncates targets, processes all source data | Initial load, data fixes, weekly refresh |
| **INCREMENTAL** | Processes only new/changed records | Daily runs, near-real-time updates |

---

### High-Water Mark (HWM) Strategy

Each procedure uses a **high-water mark** pattern based on `_source_loaded_at` timestamp:

```sql
-- Determine HWM
IF (P_MODE = 'INCREMENTAL') THEN
    SELECT COALESCE(MAX(_source_loaded_at), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
    FROM target_table;
ELSE
    v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
    TRUNCATE TABLE target_table;
END IF;

-- Process only records after HWM
SELECT * FROM source_table WHERE _loaded_at > v_hwm;
```

#### Benefits
- No need for change tracking tables
- Self-healing: if HWM is corrupted, FULL mode resets everything
- Works with any source system that provides a load timestamp

---

### MERGE-Based Idempotency

Silver and Gold layers use MERGE statements:

```sql
MERGE INTO target USING source
ON target.surrogate_key = source.surrogate_key
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ...;
```

This ensures:
- **Re-runnability**: Same data processed twice doesn't create duplicates
- **Late-arriving data**: Updates previous records if they change
- **Resume safety**: Partial runs can be resumed without corruption

---

### SCD Type-2 Incremental Logic

The SCD2 procedure handles incremental changes differently:

1. **Compute hash** of all tracked attributes for current source data
2. **Compare** against hash stored in current SCD2 version
3. **If different**: Close current version, insert new version
4. **If same**: No action (record unchanged)
5. **If new NPI**: Insert first version

```
Source Change → Hash Mismatch → Close Old Version → Insert New Version
No Change → Hash Match → Skip
New Record → No Existing → Insert First Version
```

---

### Processing Flow by Mode

#### FULL Mode
```
1. Truncate BRONZE tables
2. Load ALL source records (DQ filter applied)
3. Truncate SILVER tables  
4. Rebuild unified/deduped/enriched
5. Run SCD2 (inserts new versions for all)
6. Truncate GOLD tables
7. Rebuild dimensions/facts/OBT
```

#### INCREMENTAL Mode
```
1. Get HWM from BRONZE tables
2. Load only NEW source records (DQ filter applied)
3. MERGE into SILVER tables (update existing, insert new)
4. Run SCD2 (detect changes via hash)
5. Rebuild GOLD dimensions (full rebuild from SCD2)
6. MERGE into FCT_PROVIDER_VISITS (incremental)
7. Rebuild OBT (full rebuild from aggregates)
```

---

### Edge Cases Handled

| Scenario | Behavior |
|----------|----------|
| No new data | Step completes with rows_read = 0, no processing |
| All records rejected | Step fails if threshold exceeded, succeeds with 0 written otherwise |
| Source table empty | Counted as 0 rows, step completes normally |
| Duplicate source records | Deduplicated in Silver layer |
| Late-arriving updates | MERGE updates existing records |
| Run after FULL on same day | INCREMENTAL finds no new records (HWM = latest) |

---

### Monitoring Incremental Health

```sql
-- Check how many records are processed per run
SELECT 
    r.run_id,
    r.run_mode,
    r.start_timestamp,
    s.step_name,
    s.rows_read,
    s.rows_written,
    s.rows_rejected
FROM P360_SP.AUDIT.PKG_RUN_LOG r
JOIN P360_SP.AUDIT.STEP_RUN_LOG s ON r.run_id = s.run_id
WHERE r.run_mode = 'INCREMENTAL'
ORDER BY r.start_timestamp DESC, s.step_name;

-- Detect if incremental is stuck (no new data for N runs)
SELECT step_name, COUNT(*) AS zero_runs
FROM P360_SP.AUDIT.STEP_RUN_LOG
WHERE rows_read = 0 AND step_layer = 'BRONZE'
  AND start_timestamp > DATEADD('DAY', -7, CURRENT_TIMESTAMP())
GROUP BY step_name
HAVING COUNT(*) > 3;
```
