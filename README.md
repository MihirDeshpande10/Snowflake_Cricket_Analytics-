# Snowflake_Cricket_Analytics

# 🏏 Cricket Analytics — Snowflake Data Warehouse & Analytics

A hands-on **Snowflake-based cricket analytics project** built to transform thousands of ball-by-ball JSON cricket records into a structured data warehouse and answer real-world analytical questions using SQL.

The project demonstrates practical concepts in **Snowflake, SQL, semi-structured JSON data, ETL/ELT, data warehousing, analytical SQL, window functions, and cloud data ingestion**.

---

## 📌 Project Overview

This project processes cricket match data containing:

- IPL
- T20 Internationals
- ODI
- Test matches
- WPL
- Men's and Women's cricket

The dataset contains approximately **8,836 JSON match files**.

The goal is to transform raw nested JSON data into structured Snowflake tables and use SQL to generate meaningful cricket analytics.

---

# 🎯 Project Objectives

The project focuses on:

- Loading large volumes of semi-structured JSON data into Snowflake
- Working with Snowflake `VARIANT` data
- Extracting nested JSON using `FLATTEN`
- Building RAW, STAGING and DATA WAREHOUSE layers
- Transforming ball-by-ball cricket data
- Handling extras and wickets
- Identifying powerplay deliveries
- Creating player and team dimensions
- Building analytical views
- Using SQL aggregations and window functions
- Answering real-world cricket analytics questions

---

# 🏗️ Architecture

## Original Cloud Architecture

The original project design followed:

```text
JSON Files
    ↓
AWS S3
    ↓
Snowflake External Stage
    ↓
Snowpipe
    ↓
RAW
    ↓
STAGING
    ↓
DATA WAREHOUSE
    ↓
ANALYTICS
```

An AWS S3 → Snowflake integration was implemented and tested.

However, the S3 ingestion path encountered an AWS IAM `STS AssumeRole` authorization issue in the learner environment.

Instead of abandoning the project, the ingestion dependency was isolated and a Snowflake-native alternative was implemented.

---

## Final Implemented Architecture

```text
Local JSON Files
       ↓
Snowflake Internal Stage
       ↓
COPY INTO
       ↓
RAW Layer
       ↓
STAGING Layer
       ↓
DATA WAREHOUSE
       ↓
ANALYTICS / SQL
```

This allowed the core Snowflake warehouse and analytics pipeline to be implemented independently of the AWS IAM issue.

---

# 📊 Dataset

The dataset consists of cricket match JSON files covering multiple formats and competitions.

Approximately:

**8,836 JSON match files**

The JSON structure contains information such as:

- Match metadata
- Teams
- Players
- Toss
- Venue
- Match result
- Innings
- Overs
- Deliveries
- Batters
- Bowlers
- Runs
- Extras
- Wickets
- Powerplays

---

# 🧩 JSON Structure

A typical match JSON contains two major sections:

```text
info
 ├── city
 ├── date
 ├── event
 ├── gender
 ├── match_type
 ├── players
 ├── season
 ├── teams
 ├── toss
 ├── venue
 └── outcome

innings
 ├── team
 ├── overs
 │    ├── over number
 │    └── deliveries
 │         ├── batter
 │         ├── bowler
 │         ├── non_striker
 │         ├── runs
 │         ├── extras
 │         └── wickets
```

This nested structure makes Snowflake's semi-structured data capabilities particularly useful.

---

# ❄️ Snowflake Implementation

## Database

```text
CRICKET_ANALYTICS
```

## Warehouse

```text
CRICKET_WH
```

## Schemas

```text
RAW
STAGING
DW
```

---

# 🗂️ Data Warehouse Layers

## 1. RAW Layer

The RAW layer stores the original JSON document as Snowflake `VARIANT` data.

Main table:

```text
RAW_DATA
```

Important columns:

```text
RAW_FILE
FILENAME
```

Using `VARIANT` allows the original nested JSON structure to be preserved before transformation.

---

## 2. STAGING Layer

The STAGING layer extracts and flattens information from the raw JSON.

Main staging tables include:

```text
STG_RAW_DATA
STG_MATCH_INFO
STG_MATCH_INNINGS
STG_PLAYERS
STG_TEAMS
```

The staging layer converts nested JSON structures into relational columns suitable for further transformation.

---

## 3. DATA WAREHOUSE Layer

The DW layer contains structured analytical tables.

Main tables:

```text
MATCH_INFO
MATCH_INNINGS
PLAYERS
TEAMS
```

The warehouse layer provides a cleaner relational structure for analytical queries.

---

# 🏏 Match Information

The `MATCH_INFO` table stores information such as:

- Match ID
- Match type
- Gender
- Season
- City
- Venue
- Match date
- Teams
- Toss winner
- Toss decision
- Match winner
- Match margin
- Event
- Player of the match

---

# 🏏 Ball-by-Ball Data

The `MATCH_INNINGS` table represents individual deliveries.

Important fields include:

```text
MATCH_ID
INNING_ID
OVER
BATTING_TEAM
BALL_IN_OVER
BATTER
BOWLER
NON_STRIKER
RUNS_BATTER
EXTRA_TYPE
RUNS_EXTRAS
RUNS_TOTAL
DISMISSAL_KIND
OUT_PLAYER
IS_POWERPLAY
```

This makes it possible to perform detailed ball-level analysis.

---

# 🔥 Cricket-Specific Transformations

The project handles several cricket-specific concepts.

## Runs

Three different run concepts are preserved:

```text
RUNS_BATTER
RUNS_EXTRAS
RUNS_TOTAL
```

This allows batting and team scoring calculations to be handled separately.

---

## Extras

The project accounts for deliveries involving extras such as:

- Wides
- No-balls
- Byes
- Leg-byes

These are important when calculating batting runs, bowling figures and strike rates correctly.

---

## Wickets

Dismissal information is extracted from the nested JSON structure.

This allows wicket-taking statistics to be calculated at player and tournament level.

---

## Powerplay

Powerplay deliveries are identified and stored using:

```text
IS_POWERPLAY
```

This enables separate analysis of batting performance during powerplay overs.

---

# 📈 Analytical Questions

The project answers several practical cricket analytics questions.

### 1. Player Statistics

Generate player-level statistics including:

- Total runs
- Total wickets
- Batting average
- Bowling average
- Batting strike rate
- Bowling strike rate
- Format
- Gender
- Format type

---

### 2. Tournament Leaders

Identify:

- Highest run scorer
- Highest wicket taker

for individual tournaments/events.

---

### 3. T20 Powerplay Strike Rate

Find the player with the highest strike rate during T20 powerplay overs.

---

### 4. Death Overs Sixes

Identify the batsman who hits the maximum number of sixes during overs:

```text
17–20
```

---

### 5. International Centurions

Identify players who have scored centuries across international cricket formats based on the available dataset.

---

### 6. Women's ODI Analysis

Identify the:

- Top 5 run scorers
- Top 5 wicket takers

in Women's ODI cricket.

---

# 🧠 SQL Concepts Used

The project uses practical SQL concepts including:

- `SELECT`
- `WHERE`
- `GROUP BY`
- `HAVING`
- `ORDER BY`
- `JOIN`
- `CASE`
- `COALESCE`
- `COUNT`
- `SUM`
- `AVG`
- `MAX`
- `MIN`
- `NULLIF`
- CTEs
- Window functions
- Ranking
- Conditional aggregation
- `MERGE`
- Sequences

---

# ❄️ Snowflake Concepts Used

The project demonstrates:

### Semi-Structured Data

```text
VARIANT
```

for storing JSON documents.

### JSON Traversal

Using Snowflake's semi-structured data syntax to navigate nested objects and arrays.

### FLATTEN

Used to transform nested arrays such as:

```text
innings
    ↓
overs
    ↓
deliveries
```

into relational rows.

### Internal Stage

Used for Snowflake-native ingestion of the extracted JSON files.

### COPY INTO

Used to load staged JSON data into the RAW table.

### Streams

A Snowflake Stream was explored as a mechanism for tracking changes to RAW data.

### Tasks

Snowflake Tasks were explored as an automation mechanism for executing transformation logic.

---

# 🔄 Streams & Tasks

Streams and Tasks were considered as an automation layer on top of the core pipeline.

Conceptually:

```text
New RAW Data
     ↓
Stream detects changes
     ↓
Task executes transformation
     ↓
STAGING
     ↓
DW
```

The main implementation priority was first establishing and validating the transformation pipeline.

Streams and Tasks therefore represent an **automation/enhancement layer**, rather than the foundation of the project.

---

# ☁️ AWS S3 Integration Attempt

The original project architecture included AWS S3.

The following components were configured:

```text
AWS S3 Bucket
Snowflake Storage Integration
AWS IAM Role
Snowflake External Stage
Snowpipe
```

The S3 bucket used for the project was:

```text
snowflake-cricket-analytics
```

The integration reached the stage configuration stage, but Snowflake's AWS IAM user was unable to assume the configured IAM role because of an `STS AssumeRole` authorization issue.

Instead of treating this as a reason to stop the project, the ingestion layer was replaced with a Snowflake Internal Stage while preserving the overall RAW → STAGING → DW → ANALYTICS architecture.

This also provided practical experience troubleshooting cloud authentication and data ingestion.

---

# 🧪 Validation

The project includes validation queries for areas such as:

- RAW record counts
- Match counts
- Player counts
- Team counts
- Innings records
- Extras
- Wickets
- Powerplay records
- Analytical outputs

The first large-scale worksheet execution contained **1,400+ lines of SQL**, with approximately **95% successful execution** during the initial implementation.

The remaining statements require individual review and debugging rather than being treated as confirmed production-ready logic.

---

# 📁 Suggested Repository Structure

```text
cricket-analytics/
│
├── README.md
│
├── documentation/
│   └── Cricket_Analytics_Snowflake_Master_Report.pdf
│
├── data/
│
├── python/
│
├── snowflake/
│   ├── 01_create_database.sql
│   ├── 02_create_tables.sql
│   ├── 03_load_data.sql
│   ├── 04_transformations.sql
│   └── 05_analytics_queries.sql
│
├── dbt/
│   ├── dbt_project.yml
│   └── models/
│
└── powerbi/
```

> The repository structure may evolve as the project is further cleaned and modularized.

---

# 📚 Project Documentation

The detailed project documentation is available as:

**`Cricket_Analytics_Snowflake_Master_Report.pdf`**

The report documents:

- Project architecture
- Dataset
- Snowflake concepts
- RAW/STAGING/DW design
- JSON transformation
- Cricket-specific logic
- Analytical questions
- AWS troubleshooting
- Streams & Tasks
- Interview explanation
- Future improvements

### 🔒 Interview Preparation

The separate interview preparation guide is intentionally **kept private** and is **not included in the public GitHub repository**.

---

# 🚀 Future Improvements

Potential future improvements include:

- Complete automated S3 → Snowflake ingestion
- Configure production-ready Snowpipe notifications
- Resolve the AWS IAM integration issue
- Add dbt staging models
- Add dbt marts
- Add dbt tests
- Build Power BI dashboards
- Add automated data quality checks
- Implement production-ready Streams & Tasks
- Improve dimensional modelling
- Add incremental processing
- Add orchestration using Airflow

---

# 💼 Why This Project Matters

This project demonstrates practical experience beyond simply writing SQL queries.

It combines:

```text
Semi-structured Data
        +
Snowflake
        +
SQL
        +
ETL / ELT
        +
Data Warehousing
        +
Analytical Thinking
```

The project is particularly relevant for roles such as:

- Data Analyst
- Business Analyst
- Analytics Engineer
- Junior Data Engineer
- BI Analyst

---

# 🎤 30-Second Interview Explanation

> "I built a cricket analytics data warehouse in Snowflake using around 8,836 ball-by-ball JSON match files. I stored the raw JSON as VARIANT data, used Snowflake's semi-structured functions and FLATTEN to transform nested innings and delivery data, and created RAW, STAGING and DW layers. I then used SQL, CTEs and window functions to calculate player statistics, tournament leaders, powerplay performance and death-over sixes. I also explored S3 integration, Streams and Tasks as part of the ingestion and automation architecture."

---

# 🧠 Key Learning

The core mental model of the project is:

```text
JSON
 ↓
RAW
 ↓
VARIANT
 ↓
FLATTEN
 ↓
STAGING
 ↓
DATA WAREHOUSE
 ↓
SQL ANALYTICS
 ↓
BUSINESS INSIGHTS
```

Understanding this pipeline is more important than memorizing the individual SQL statements.

---

# 👨‍💻 Project Status

| Component | Status |
|---|---|
| Core Snowflake pipeline | ✅ Implemented |
| JSON ingestion | ✅ Implemented through Snowflake Internal Stage |
| RAW layer | ✅ Implemented |
| STAGING layer | ✅ Implemented |
| DW layer | ✅ Implemented |
| Analytical queries | ✅ Implemented |
| AWS S3 integration | ⚠️ Attempted; IAM authorization issue encountered |
| Streams / Tasks | 🔄 Explored as automation layer |
 

---

## ⭐ Final Outcome

This project provided hands-on experience building a complete analytical pipeline from raw semi-structured JSON data to structured Snowflake warehouse tables and analytical SQL outputs.

The primary focus was not simply on cricket statistics, but on understanding how a **real-world data engineering and analytics pipeline** can be designed, transformed, validated and documented using Snowflake.
