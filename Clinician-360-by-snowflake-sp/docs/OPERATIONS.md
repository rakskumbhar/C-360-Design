# Operations Guide

## Provider-360-by-snowflake-sp

---

### Deployment

#### Prerequisites
- Role: `ACCOUNTADMIN` (or role with CREATE DATABASE/SCHEMA/PROCEDURE privileges)
- Warehouse: `COMPUTE_WH` (or modify in configuration)
- Source: `SNOWFLAKE_LEARNING_DB.RAW_INGESTION` schema with populated tables

#### Deployment Steps

```sql
-- 1. Execute infrastructure setup
-- Run each file in order from 07_DEPLOY/001_deploy_all.sql guide

-- 2. Validate deployment
SELECT 'PROCEDURES' AS type, COUNT(*) AS count 
FROM P360_SP.INFORMATION_SCHEMA.PROCEDURES;

-- 3. Seed configuration
-- Execute 00_CONFIG/003_seed_configuration.sql

-- 4. Run initial full load
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');
```

---

### Running the Pipeline

#### Full Refresh
```sql
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');
```

#### Incremental (Daily)
```sql
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('INCREMENTAL');
```

#### Resume Failed Run
```sql
-- Get the failed run_id from the run history
SELECT run_id, failed_step_id, error_message 
FROM P360_SP.AUDIT.PKG_RUN_LOG 
WHERE run_status = 'FAILED' 
ORDER BY start_timestamp DESC LIMIT 1;

-- Resume from failure point
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RESUME', '<run_id>');
```

#### Re-run Single Step
```sql
-- Re-execute step 10 (INT_PROVIDERS_UNIFIED)
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('RERUN_STEP', NULL, 10);
```

---

### Monitoring

#### Run History
```sql
SELECT * FROM P360_SP.ORCHESTRATION.VW_RUN_HISTORY;
```

#### Step Performance
```sql
SELECT * FROM P360_SP.ORCHESTRATION.VW_STEP_PERFORMANCE
WHERE run_id = '<run_id>';
```

#### Data Quality Dashboard
```sql
SELECT * FROM P360_SP.ORCHESTRATION.VW_DQ_DASHBOARD
WHERE run_id = '<run_id>';
```

#### Error Investigation
```sql
SELECT * FROM P360_SP.ORCHESTRATION.VW_ERROR_ANALYSIS
WHERE run_id = '<run_id>';
```

#### Reject Analysis
```sql
SELECT * FROM P360_SP.ORCHESTRATION.VW_REJECT_ANALYSIS
WHERE run_id = '<run_id>';
```

---

### Configuration Management

#### View Current Configuration
```sql
SELECT config_key, config_value, config_category, description
FROM P360_SP.CONFIG.PKG_CONFIG
WHERE is_active = TRUE
ORDER BY config_category, config_key;
```

#### Modify Configuration
```sql
-- Change DQ threshold
UPDATE P360_SP.CONFIG.PKG_CONFIG 
SET config_value = '3.0', updated_at = CURRENT_TIMESTAMP()
WHERE config_key = 'DQ_REJECT_THRESHOLD';

-- Enable notifications
UPDATE P360_SP.CONFIG.PKG_CONFIG 
SET config_value = 'TRUE', updated_at = CURRENT_TIMESTAMP()
WHERE config_key = 'ENABLE_EMAIL_NOTIFY';

-- Switch to FULL mode
UPDATE P360_SP.CONFIG.PKG_CONFIG 
SET config_value = 'FALSE', updated_at = CURRENT_TIMESTAMP()
WHERE config_key = 'INCREMENTAL_MODE';
```

#### Disable/Enable Steps
```sql
-- Disable SCD2 step
UPDATE P360_SP.CONFIG.PKG_STEP_REGISTRY 
SET is_active = FALSE WHERE step_id = 20;

-- Re-enable
UPDATE P360_SP.CONFIG.PKG_STEP_REGISTRY 
SET is_active = TRUE WHERE step_id = 20;
```

---

### Scheduling

#### Enable Daily Task
```sql
ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL RESUME;
```

#### Suspend Task
```sql
ALTER TASK P360_SP.ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL SUSPEND;
```

#### Check Task Status
```sql
SHOW TASKS IN SCHEMA P360_SP.ORCHESTRATION;
```

---

### Email Notifications

#### Setup (One-time)
```sql
-- Create email integration (requires ACCOUNTADMIN)
CREATE OR REPLACE NOTIFICATION INTEGRATION P360_EMAIL_INT
    TYPE = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('data-engineering@company.com', 'on-call@company.com');

-- Enable notifications in config
UPDATE P360_SP.CONFIG.PKG_CONFIG 
SET config_value = 'TRUE' WHERE config_key = 'ENABLE_EMAIL_NOTIFY';
```

#### Notification Events
| Event | When | Recipients |
|-------|------|-----------|
| RUN_START | Pipeline begins | data-engineering |
| RUN_COMPLETE | Pipeline succeeds | data-engineering |
| RUN_FAILURE | Pipeline fails (after all retries) | data-engineering + on-call |
| DQ_THRESHOLD | Reject rate exceeds threshold | data-quality |
| STEP_FAILURE | Individual step fails (retrying) | data-engineering |

---

### Troubleshooting

#### Common Issues

| Symptom | Cause | Resolution |
|---------|-------|-----------|
| DQ_THRESHOLD_EXCEEDED | Reject rate > configured threshold | Review rejects, fix source data or adjust threshold |
| Step timeout | Long-running query | Increase `timeout_minutes` in step registry |
| Resume fails | Run log corrupted | Start fresh with FULL mode |
| No data processed | HWM ahead of source | Run in FULL mode to reset |

#### Investigating Failures
```sql
-- 1. Find the failed run
SELECT run_id, failed_step_id, error_message
FROM P360_SP.AUDIT.PKG_RUN_LOG WHERE run_status = 'FAILED'
ORDER BY start_timestamp DESC LIMIT 5;

-- 2. Check step details
SELECT * FROM P360_SP.AUDIT.STEP_RUN_LOG
WHERE run_id = '<run_id>' AND step_status = 'FAILED';

-- 3. Check error log
SELECT * FROM P360_SP.AUDIT.ERROR_LOG
WHERE run_id = '<run_id>' ORDER BY error_timestamp;

-- 4. Check reject details
SELECT step_name, source_table, reject_reason, reject_count
FROM P360_SP.REJECT.REJECT_SUMMARY
WHERE run_id = '<run_id>' ORDER BY reject_count DESC;
```

---

### Data Retention

| Schema | Retention | Purpose |
|--------|-----------|---------|
| CONFIG | 90 days | Configuration time-travel |
| BRONZE | 30 days | Staged data recovery |
| SILVER | 30 days | Intermediate recovery |
| GOLD | 90 days | Business data recovery |
| AUDIT | 365 days | Compliance/audit trail |
| REJECT | 365 days | DQ investigation |
| SNAPSHOTS | 365 days | Historical SCD2 data |
