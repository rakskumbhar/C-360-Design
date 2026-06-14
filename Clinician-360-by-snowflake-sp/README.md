# Provider-360-by-snowflake-sp

Enterprise-grade Provider 360 data pipeline built entirely with Snowflake native stored procedures.

## Quick Start

Execute in order:
1. `CALL P360_SP.CONFIG.SP_SETUP_INFRASTRUCTURE();`
2. `CALL P360_SP.CONFIG.SP_SEED_CONFIGURATION();`
3. `CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');`

See `docs/` for detailed documentation.
