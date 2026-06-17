================================================================================
  CLINICIAN-360 DATA QUALITY FRAMEWORK - DESIGN DOCUMENT
  Version: 1.0 (Draft for Review)
================================================================================

1. PROJECT OBJECTIVE
================================================================================
Enhance the existing Clinician-360 data pipeline (Clinician-360-by-snowflake-sp)
with a dedicated, comprehensive Data Quality (DQ) framework. The goal is to move
from inline DQ checks embedded in Bronze stored procedures to a centralized,
rule-driven, reusable DQ engine that can be applied across all layers.

2. WHAT EXISTS TODAY (Current State)
================================================================================
The existing project (Clinician-360-by-snowflake-sp) has:

- DQ_RULES config table: Defines rules per source table/column with types
  (NOT_NULL, LENGTH, RANGE, PATTERN, REFERENTIAL, CUSTOM)
- Inline DQ in Bronze SPs: Each Bronze procedure has hardcoded CASE-WHEN logic
  to detect rejects and insert into REJECT_RECORDS
- REJECT_RECORDS table: Stores failed records with reject_reasons (ARRAY)
- REJECT_SUMMARY table: Aggregated reject counts by step/reason
- DQ_RUN_LOG table: Per-run DQ metrics (passed/rejected/threshold)
- DQ Threshold check: SP_CHECK_DQ_THRESHOLD stops pipeline if reject % exceeds limit
- Circuit breaker pattern: Pipeline halts before bad data propagates

Current Limitations:
- DQ rules are defined in config table but NOT dynamically evaluated
- Each Bronze SP has manually coded validation logic (not driven by DQ_RULES table)
- No DQ scoring or profiling capability
- No trend analysis (DQ over time)
- No data freshness or completeness checks at dataset level
- No Silver/Gold layer DQ validation
- No anomaly detection (sudden volume changes, distribution shifts)

3. PROPOSED ENHANCEMENT - DQ FRAMEWORK DESIGN
================================================================================

3.1 DESIGN PRINCIPLES
---------------------
| Principle               | Description                                        |
|-------------------------|----------------------------------------------------|
| Rule-Driven             | All DQ checks derived from DQ_RULES config table   |
| Layer-Agnostic          | Apply DQ at Bronze, Silver, and Gold layers         |
| Centralized Engine      | Single SP evaluates rules dynamically               |
| Non-Intrusive           | Existing Bronze SPs call DQ engine, not vice versa  |
| Scorecard Oriented      | Produce a DQ score per table, layer, and run        |
| Trend Aware             | Track DQ metrics over time for degradation alerts   |
| Threshold Configurable  | Per-rule, per-table, per-layer thresholds           |

3.2 DIRECTORY STRUCTURE (Mirrors existing project)
--------------------------------------------------
Clinician-360-DQ-Implemetation/
├── 00_CONFIG/          - DQ-specific configuration (enhanced rules, profiles)
├── 01_FRAMEWORK/       - Core DQ engine tables and utility procedures
├── 02_BRONZE/          - Bronze-layer DQ validation procedures
├── 03_SILVER/          - Silver-layer DQ validation procedures
├── 04_GOLD/            - Gold-layer DQ validation procedures
├── 05_AUDIT/           - DQ reporting, scorecards, trend analysis
├── 06_ORCHESTRATION/   - DQ scheduling, integration with main pipeline
├── 07_DEPLOY/          - Deployment script for DQ framework
└── docs/               - Documentation

3.3 PROPOSED COMPONENTS
-----------------------

A) 00_CONFIG - Enhanced DQ Configuration
   - Enhanced DQ_RULES table with additional columns:
     * rule_category (COMPLETENESS, VALIDITY, ACCURACY, CONSISTENCY, TIMELINESS)
     * expected_threshold_pct (per-rule acceptable failure rate)
     * weight (importance for scoring)
     * check_frequency (EVERY_RUN, DAILY, WEEKLY)
     * applies_to_layer (BRONZE, SILVER, GOLD, ALL)
   - DQ_PROFILES table: Dataset-level profiling configuration
   - DQ_THRESHOLDS table: Granular threshold management
   - DQ_RULE_GROUPS table: Group rules into logical sets

B) 01_FRAMEWORK - Core DQ Engine
   - SP_DQ_EVALUATE_RULES: Dynamic rule evaluator (reads DQ_RULES, executes checks)
   - SP_DQ_PROFILE_TABLE: Automated column profiling (null %, distinct %, min/max)
   - SP_DQ_CHECK_FRESHNESS: Data freshness validation
   - SP_DQ_CHECK_VOLUME: Volume anomaly detection (% change from prior run)
   - SP_DQ_SCORE_CALCULATOR: Computes weighted DQ score per table/layer
   - DQ_RESULTS table: Stores individual rule evaluation results
   - DQ_SCORES table: Stores computed DQ scores over time
   - DQ_PROFILES_HISTORY table: Stores profiling snapshots

C) 02_BRONZE - Bronze Layer DQ
   - SP_DQ_VALIDATE_BRONZE: Runs all active Bronze rules for a given source
   - Replaces hardcoded CASE-WHEN logic in existing Bronze SPs
   - Still produces REJECT_RECORDS entries (backward compatible)

D) 03_SILVER - Silver Layer DQ  
   - SP_DQ_VALIDATE_SILVER: Cross-table consistency checks
   - Referential integrity validation (e.g., all unified providers exist in source)
   - Deduplication quality checks (no orphan records)
   - SCD2 integrity checks (no overlapping effective dates)

E) 04_GOLD - Gold Layer DQ
   - SP_DQ_VALIDATE_GOLD: Business rule validation
   - Dimension completeness checks (no unknown dimension keys in facts)
   - Aggregate reconciliation (fact totals match source totals)
   - 360 Summary completeness (all providers have summary records)

F) 05_AUDIT - DQ Reporting & Scorecards
   - SP_DQ_SCORECARD: Generates run-level DQ scorecard
   - SP_DQ_TREND_REPORT: DQ trend analysis over configurable time window
   - SP_DQ_ALERT_CHECK: Identifies DQ degradation and triggers alerts
   - Views: VW_DQ_CURRENT_SCORES, VW_DQ_TRENDS, VW_DQ_FAILURES

G) 06_ORCHESTRATION - Integration
   - SP_RUN_DQ_PACKAGE: Standalone DQ execution (independent of main pipeline)
   - Integration hooks for existing SP_RUN_PACKAGE (call DQ after each layer)
   - Snowflake Task for scheduled DQ monitoring

H) 07_DEPLOY - Deployment
   - Single deployment script for full DQ framework
   - Backward-compatible with existing P360_SP database

4. DQ RULE CATEGORIES (Proposed Taxonomy)
================================================================================
| Category      | Description                          | Example                   |
|---------------|--------------------------------------|---------------------------|
| COMPLETENESS  | Required fields are populated        | NPI_NUMBER IS NOT NULL    |
| VALIDITY      | Values conform to expected format    | LENGTH(NPI) = 10          |
| ACCURACY      | Values are correct/reasonable        | ENUM_DATE <= CURRENT_DATE |
| CONSISTENCY   | Cross-field/cross-table agreement    | STATUS matches NPI table  |
| TIMELINESS    | Data is fresh/current                | _loaded_at within 24hrs   |
| UNIQUENESS    | No unexpected duplicates             | NPI is unique per source  |

5. DQ SCORING MODEL (Proposed)
================================================================================
- Each rule has a weight (1-10) and category
- Score per table = (passed_weighted / total_weighted) * 100
- Score per layer = AVG(table scores in that layer)
- Overall pipeline score = Weighted AVG across layers
- Thresholds: GREEN (>=95), YELLOW (80-94), RED (<80)

6. INTEGRATION WITH EXISTING PIPELINE
================================================================================
Option A: Post-Step Hook (Recommended)
  - After each Bronze/Silver/Gold SP completes, orchestrator calls DQ engine
  - DQ engine evaluates rules for that step's target table
  - Results logged; pipeline continues or halts based on threshold

Option B: Embedded Call
  - Each SP calls SP_DQ_EVALUATE_RULES before final INSERT
  - More tightly coupled but immediate feedback

Option C: Independent Schedule
  - DQ runs on its own schedule (e.g., after pipeline completion)
  - Less real-time but simpler to implement initially

7. DATABASE OBJECTS (New)
================================================================================
New schemas/tables to be created in P360_SP:

  P360_SP.DQ (new schema)
  ├── DQ_RULE_DEFINITIONS      - Enhanced rule definitions
  ├── DQ_RULE_GROUPS           - Logical grouping of rules
  ├── DQ_RESULTS               - Individual rule evaluation results
  ├── DQ_SCORES                - Computed scores per table/layer/run
  ├── DQ_PROFILES_HISTORY      - Column profiling snapshots
  ├── DQ_THRESHOLDS            - Granular threshold configuration
  ├── DQ_ALERTS                - Alert history
  └── DQ_SCORE_THRESHOLDS      - Green/Yellow/Red definitions

8. OPEN QUESTIONS FOR REVIEW
================================================================================
1. Should DQ framework use the same P360_SP database or a separate database?
2. Which integration option (A/B/C) do you prefer?
3. Should profiling run every execution or on a scheduled basis?
4. Do you want DQ to block pipeline execution (current circuit-breaker behavior)
   or allow soft failures (log warning, continue)?
5. Should we add Snowflake DMF (Data Metric Functions) integration?
6. Do you want a Streamlit dashboard for DQ monitoring?

9. NEXT STEPS
================================================================================
1. You review this design and provide feedback
2. We align on open questions
3. I build out the SQL scripts in the Clinician-360-DQ-Implemetation folder
4. We test against the existing P360_SP pipeline
5. Deploy and integrate

================================================================================
  END OF DESIGN DOCUMENT - AWAITING YOUR REVIEW
================================================================================
