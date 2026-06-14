# Snowflake Setup Guide

## Provider-360-by-snowflake-sp

---

### Prerequisites

| Requirement | Details |
|-------------|---------|
| Snowflake Account | Enterprise Edition or higher (for Tasks) |
| Role | ACCOUNTADMIN for initial setup |
| Warehouse | COMPUTE_WH (or any available warehouse) |
| Source Data | `SNOWFLAKE_LEARNING_DB.RAW_INGESTION` with populated tables |

---

### Source Tables Required

The following tables must exist in `SNOWFLAKE_LEARNING_DB.RAW_INGESTION`:

| Table | Key Column | Description |
|-------|-----------|-------------|
| NPI_RAW | npi_number | CMS National Provider Identifier registry |
| PROVIDER_CREDENTIALS_RAW | npi_number | Provider credentialing records |
| PROVIDER_MASTER_RAW | npi_number | EMR provider master file |
| CLAIMS_RAW | claim_id, npi_number | Medical claims data |
| NETWORK_AFFILIATIONS_RAW | npi_number | Network participation records |

All source tables must have a `_loaded_at TIMESTAMP_NTZ` column for incremental processing.

---

### Step-by-Step Setup

#### Step 1: Execute Schema Setup
```sql
-- Run: 00_CONFIG/001_setup_database_schemas.sql
-- Creates P360_SP database with all required schemas
```

#### Step 2: Create Configuration Tables
```sql
-- Run: 00_CONFIG/002_configuration_tables.sql
-- Creates PKG_CONFIG, PKG_STEP_REGISTRY, DQ_RULES, etc.
```

#### Step 3: Create Audit Infrastructure
```sql
-- Run: 01_FRAMEWORK/001_audit_tables.sql
-- Creates all logging and audit tables
```

#### Step 4: Create Target Tables
```sql
-- Run: 01_FRAMEWORK/003_target_tables.sql
-- Creates Bronze, Silver, Gold, and Snapshot tables
```

#### Step 5: Create Utility Procedures
```sql
-- Run: 01_FRAMEWORK/002_utility_procedures.sql
-- Creates logging, error handling, notification procedures
```

#### Step 6: Create Transformation Procedures
```sql
-- Run all files in 02_BRONZE/, 03_SILVER/, 04_GOLD/, 05_AUDIT/
```

#### Step 7: Create Orchestrator
```sql
-- Run: 06_ORCHESTRATION/001_sp_run_package.sql
-- Run: 06_ORCHESTRATION/002_scheduling_and_tasks.sql
```

#### Step 8: Seed Configuration
```sql
-- Run: 00_CONFIG/003_seed_configuration.sql
-- Populates all configuration with defaults
```

#### Step 9: Validate
```sql
-- Verify all objects created
SELECT TABLE_SCHEMA, COUNT(*) AS table_count
FROM P360_SP.INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'P360_SP'
GROUP BY TABLE_SCHEMA ORDER BY TABLE_SCHEMA;
```

#### Step 10: Execute First Run
```sql
CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');
```

---

### Email Integration Setup (Optional)

```sql
CREATE OR REPLACE NOTIFICATION INTEGRATION P360_EMAIL_INT
    TYPE = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('your-team@company.com');

-- Grant usage
GRANT USAGE ON INTEGRATION P360_EMAIL_INT TO ROLE ACCOUNTADMIN;

-- Enable in config
UPDATE P360_SP.CONFIG.PKG_CONFIG 
SET config_value = 'TRUE' WHERE config_key = 'ENABLE_EMAIL_NOTIFY';
```

---

### Role-Based Access (Production)

```sql
-- Create operational roles
CREATE ROLE IF NOT EXISTS P360_ADMIN;
CREATE ROLE IF NOT EXISTS P360_OPERATOR;
CREATE ROLE IF NOT EXISTS P360_READER;

-- Admin: Full control
GRANT ALL ON DATABASE P360_SP TO ROLE P360_ADMIN;

-- Operator: Execute procedures, read config
GRANT USAGE ON DATABASE P360_SP TO ROLE P360_OPERATOR;
GRANT USAGE ON ALL SCHEMAS IN DATABASE P360_SP TO ROLE P360_OPERATOR;
GRANT SELECT ON ALL TABLES IN SCHEMA P360_SP.CONFIG TO ROLE P360_OPERATOR;
GRANT USAGE ON ALL PROCEDURES IN SCHEMA P360_SP.ORCHESTRATION TO ROLE P360_OPERATOR;

-- Reader: Query Gold layer only
GRANT USAGE ON DATABASE P360_SP TO ROLE P360_READER;
GRANT USAGE ON SCHEMA P360_SP.GOLD TO ROLE P360_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA P360_SP.GOLD TO ROLE P360_READER;
GRANT SELECT ON ALL VIEWS IN SCHEMA P360_SP.GOLD TO ROLE P360_READER;
```

---

### Environment Configuration

Modify for your environment:

```sql
UPDATE P360_SP.CONFIG.PKG_CONFIG SET config_value = 'PROD' WHERE config_key = 'ENVIRONMENT';
UPDATE P360_SP.CONFIG.PKG_CONFIG SET config_value = 'YOUR_DB' WHERE config_key = 'SOURCE_DATABASE';
UPDATE P360_SP.CONFIG.PKG_CONFIG SET config_value = 'YOUR_SCHEMA' WHERE config_key = 'SOURCE_SCHEMA';
UPDATE P360_SP.CONFIG.PKG_CONFIG SET config_value = 'YOUR_WH' WHERE config_key = 'WAREHOUSE';
UPDATE P360_SP.CONFIG.PKG_CONFIG SET config_value = '2.0' WHERE config_key = 'DQ_REJECT_THRESHOLD';
```
