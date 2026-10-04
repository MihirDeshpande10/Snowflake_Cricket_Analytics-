-- ============================================================
-- CRICKET ANALYTICS PROJECT
-- SNOWFLAKE-ONLY ALTERNATIVE IMPLEMENTATION
-- ============================================================
--
-- ORIGINAL DESIGN:
-- JSON → AWS S3 → Snowflake External Stage → Snowpipe
-- → RAW → STAGING → DW → ANALYTICS
--
-- AWS RESULT:
-- External S3 access was blocked by an AWS STS AssumeRole
-- authorization issue in the learner environment.
--
-- ALTERNATIVE IMPLEMENTATION:
-- Local JSON → Snowflake Internal Stage → RAW
-- → STAGING → DW → ANALYTICS
--
-- PURPOSE:
-- This worksheet documents the alternative implementation
-- so the project is completed rather than abandoned because
-- of an external AWS IAM integration issue.
--
-- The original AWS implementation remains preserved separately.
-- ============================================================

-- ============================================================
-- STEP 2: SNOWFLAKE INTERNAL STAGE
-- ============================================================

USE WAREHOUSE CRICKET_WH;

USE DATABASE CRICKET_ANALYTICS;

USE SCHEMA RAW;


CREATE OR REPLACE FILE FORMAT CRICKET_ANALYTICS.RAW.JSON_FILE_FORMAT
TYPE = JSON;


CREATE OR REPLACE STAGE CRICKET_ANALYTICS.RAW.CRICKET_INTERNAL_STAGE
FILE_FORMAT = CRICKET_ANALYTICS.RAW.JSON_FILE_FORMAT;


-- Check that the internal stage exists
LIST @CRICKET_ANALYTICS.RAW.CRICKET_INTERNAL_STAGE;

-- ============================================================
-- STEP 6: LOAD JSON FILES INTO RAW TABLE
-- ============================================================

COPY INTO CRICKET_ANALYTICS.RAW.RAW_DATA
(
    RAW_FILE,
    FILENAME
)
FROM
(
    SELECT
        $1,
        METADATA$FILENAME
    FROM @CRICKET_ANALYTICS.RAW.CRICKET_INTERNAL_STAGE
)
FILE_FORMAT = (
    FORMAT_NAME = CRICKET_ANALYTICS.RAW.JSON_FILE_FORMAT
)
ON_ERROR = CONTINUE;

SELECT COUNT(*) AS RAW_RECORD_COUNT
FROM CRICKET_ANALYTICS.RAW.RAW_DATA;

SELECT
    RAW_FILE,
    FILENAME
FROM CRICKET_ANALYTICS.RAW.RAW_DATA
LIMIT 1;

-- ============================================================
-- STEP 7: RAW → STAGING RAW DATA
-- ============================================================
--
-- Copy the complete JSON documents from RAW into the
-- staging input table.
--
-- RAW_FILE remains VARIANT.
-- ============================================================

INSERT OVERWRITE INTO CRICKET_ANALYTICS.STAGING.STG_RAW_DATA
(
    RAW_FILE,
    FILENAME
)
SELECT
    RAW_FILE,
    FILENAME
FROM CRICKET_ANALYTICS.RAW.RAW_DATA;


-- ============================================================
-- VALIDATE STAGING RAW DATA
-- ============================================================

SELECT COUNT(*) AS STG_RAW_RECORD_COUNT
FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA;


-- ============================================================
-- STEP 8: STAGING - TEAMS
-- ============================================================
--
-- JSON structure:
--
-- info
--   └── teams
--       ├── Team 1
--       └── Team 2
--
-- FLATTEN converts the teams array into rows.
-- ============================================================

INSERT OVERWRITE INTO CRICKET_ANALYTICS.STAGING.STG_TEAMS
(
    TEAM_NAME,
    TEAM_TYPE
)
SELECT DISTINCT
    F.VALUE::STRING AS TEAM_NAME,
    R.RAW_FILE:info.team_type::STRING AS TEAM_TYPE
FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA R,
LATERAL FLATTEN(
    INPUT => R.RAW_FILE:info.teams
) F
WHERE F.VALUE IS NOT NULL;


-- ============================================================
-- CHECK TEAMS
-- ============================================================

SELECT
    COUNT(*) AS TEAM_ROWS
FROM CRICKET_ANALYTICS.STAGING.STG_TEAMS;

SELECT *
FROM CRICKET_ANALYTICS.STAGING.STG_TEAMS
LIMIT 20;


-- ============================================================
-- STEP 9: STAGING - PLAYERS
-- ============================================================
--
-- JSON structure:
--
-- info
--   └── players
--       ├── Team A
--       │    ├── Player 1
--       │    └── Player 2
--       └── Team B
--            ├── Player 3
--            └── Player 4
--
-- First FLATTEN = team
-- Second FLATTEN = players
-- ============================================================

INSERT OVERWRITE INTO CRICKET_ANALYTICS.STAGING.STG_PLAYERS
(
    PLAYER_NAME,
    TEAM_NAME
)
SELECT DISTINCT
    P.VALUE::STRING AS PLAYER_NAME,
    T.KEY::STRING AS TEAM_NAME
FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA R,
LATERAL FLATTEN(
    INPUT => R.RAW_FILE:info.players
) T,
LATERAL FLATTEN(
    INPUT => T.VALUE
) P
WHERE P.VALUE IS NOT NULL;


-- ============================================================
-- CHECK PLAYERS
-- ============================================================

SELECT
    COUNT(*) AS PLAYER_ROWS
FROM CRICKET_ANALYTICS.STAGING.STG_PLAYERS;

SELECT *
FROM CRICKET_ANALYTICS.STAGING.STG_PLAYERS
LIMIT 20;


-- ============================================================
-- STEP 10: STAGING - MATCH INFORMATION
-- ============================================================
--
-- Extract match-level information from:
--
-- RAW_FILE:info
--
-- One JSON file = one cricket match.
-- ============================================================

INSERT OVERWRITE INTO CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO
(
    MATCH_TYPE,
    GENDER,
    SEASON,
    CITY,
    VENUE,
    MATCH_DATE,
    TEAM1,
    TEAM2,
    TOSS_WINNER,
    TOSS_DECISION,
    MATCH_WINNER,
    MARGIN,
    EVENT_NAME,
    EVENT_TYPE,
    POM,
    FILENAME
)
SELECT

    R.RAW_FILE:info.match_type::STRING,

    R.RAW_FILE:info.gender::STRING,

    R.RAW_FILE:info.season::STRING,

    R.RAW_FILE:info.city::STRING,

    R.RAW_FILE:info.venue::STRING,

    R.RAW_FILE:info.dates[0]::DATE,

    R.RAW_FILE:info.teams[0]::STRING,

    R.RAW_FILE:info.teams[1]::STRING,

    R.RAW_FILE:info.toss.winner::STRING,

    R.RAW_FILE:info.toss.decision::STRING,

    R.RAW_FILE:info.outcome.winner::STRING,

    CASE

        WHEN R.RAW_FILE:info.outcome.by.runs IS NOT NULL
            THEN R.RAW_FILE:info.outcome.by.runs::STRING
                 || ' runs'

        WHEN R.RAW_FILE:info.outcome.by.wickets IS NOT NULL
            THEN R.RAW_FILE:info.outcome.by.wickets::STRING
                 || ' wickets'

        ELSE 'No Result'

    END,

    R.RAW_FILE:info.event.name::STRING,

    R.RAW_FILE:info.team_type::STRING,

    R.RAW_FILE:info.player_of_match[0]::STRING,

    R.FILENAME

FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA R;


-- ============================================================
-- CHECK MATCH INFORMATION
-- ============================================================

SELECT
    COUNT(*) AS MATCH_COUNT
FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO;

SELECT *
FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO
LIMIT 5;


-- ============================================================
-- STEP 11: STAGING - BALL BY BALL MATCH INNINGS
-- ============================================================
--
-- THIS IS THE CORE JSON TRANSFORMATION.
--
-- JSON hierarchy:
--
-- Match
--   ↓
-- Innings
--   ↓
-- Overs
--   ↓
-- Deliveries
--
-- FLATTEN converts the nested arrays into relational rows.
--
-- ONE DELIVERY = ONE ROW
--
-- This is the most important part of the project.
-- ============================================================

INSERT OVERWRITE INTO CRICKET_ANALYTICS.STAGING.STG_MATCH_INNINGS
(
    INNING_ID,
    OVER,
    BATTING_TEAM,
    BALL_IN_OVER,
    BATTER,
    BOWLER,
    NON_STRIKER,
    RUNS_BATTER,
    EXTRA_TYPE,
    RUNS_EXTRAS,
    RUNS_TOTAL,
    DISMISSAL_KIND,
    OUT_PLAYER,
    POWERPLAYS_START_OVER,
    POWERPLAYS_END_OVER,
    IS_POWERPLAY,
    FILENAME
)

WITH DELIVERY_DATA AS
(
    SELECT

        I.INDEX + 1 AS INNING_ID,

        O.VALUE:over::INT + 1 AS OVER,

        I.VALUE:team::STRING AS BATTING_TEAM,

        D.INDEX + 1 AS BALL_IN_OVER,

        D.VALUE:batter::STRING AS BATTER,

        D.VALUE:bowler::STRING AS BOWLER,

        D.VALUE:non_striker::STRING AS NON_STRIKER,

        D.VALUE:runs.batter::INT AS RUNS_BATTER,

        CASE

            WHEN D.VALUE:extras.wides IS NOT NULL
                THEN 'wides'

            WHEN D.VALUE:extras.noballs IS NOT NULL
                THEN 'noballs'

            WHEN D.VALUE:extras.byes IS NOT NULL
                THEN 'byes'

            WHEN D.VALUE:extras.legbyes IS NOT NULL
                THEN 'legbyes'

            WHEN D.VALUE:extras.penalty IS NOT NULL
                THEN 'penalty'

            ELSE NULL

        END AS EXTRA_TYPE,

        D.VALUE:runs.extras::INT AS RUNS_EXTRAS,

        D.VALUE:runs.total::INT AS RUNS_TOTAL,

        D.VALUE:wickets[0].kind::STRING
            AS DISMISSAL_KIND,

        D.VALUE:wickets[0].player_out::STRING
            AS OUT_PLAYER,

        COALESCE(
            CEIL(
                D.VALUE:powerplay_start::FLOAT
            ),
            DP.START_OVER,
            1
        ) AS POWERPLAY_START,

        COALESCE(
            CEIL(
                D.VALUE:powerplay_end::FLOAT
            ),
            DP.END_OVER,
            CASE
                WHEN R.RAW_FILE:info.match_type::STRING = 'T20'
                    THEN 6
                WHEN R.RAW_FILE:info.match_type::STRING = 'ODI'
                    THEN 10
                ELSE 0
            END
        ) AS POWERPLAY_END,

        R.FILENAME

    FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA R

    LEFT JOIN CRICKET_ANALYTICS.RAW.DEFAULT_POWERPLAYS DP
        ON R.RAW_FILE:info.match_type::STRING
           = DP.MATCH_TYPE

    ,LATERAL FLATTEN(
        INPUT => R.RAW_FILE:innings
    ) I

    ,LATERAL FLATTEN(
        INPUT => I.VALUE:overs
    ) O

    ,LATERAL FLATTEN(
        INPUT => O.VALUE:deliveries
    ) D
)

SELECT

    INNING_ID,

    OVER,

    BATTING_TEAM,

    BALL_IN_OVER,

    BATTER,

    BOWLER,

    NON_STRIKER,

    RUNS_BATTER,

    EXTRA_TYPE,

    RUNS_EXTRAS,

    RUNS_TOTAL,

    DISMISSAL_KIND,

    OUT_PLAYER,

    POWERPLAY_START,

    POWERPLAY_END,

    CASE

        WHEN OVER BETWEEN POWERPLAY_START
                      AND POWERPLAY_END

        THEN 1

        ELSE 0

    END AS IS_POWERPLAY,

    FILENAME

FROM DELIVERY_DATA;


-- ============================================================
-- CHECK BALL BY BALL DATA
-- ============================================================

SELECT
    COUNT(*) AS DELIVERY_COUNT
FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INNINGS;


SELECT *
FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INNINGS
LIMIT 20;


-- ============================================================
-- STEP 12: DATA WAREHOUSE - TEAMS
-- ============================================================

INSERT INTO CRICKET_ANALYTICS.DW.TEAMS
(
    TEAM_ID,
    TEAM_NAME,
    TEAM_TYPE
)
SELECT DISTINCT

    CRICKET_ANALYTICS.RAW.SEQ_TEAMS.NEXTVAL,

    TEAM_NAME,

    TEAM_TYPE

FROM CRICKET_ANALYTICS.STAGING.STG_TEAMS;


-- ============================================================
-- CHECK DW TEAMS
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.DW.TEAMS
ORDER BY TEAM_ID
LIMIT 30;


-- ============================================================
-- STEP 13: DATA WAREHOUSE - PLAYERS
-- ============================================================
--
-- A player can represent multiple teams.
-- Therefore TEAMS is stored as an ARRAY.
-- ============================================================

INSERT INTO CRICKET_ANALYTICS.DW.PLAYERS
(
    PLAYER_ID,
    PLAYER_NAME,
    TEAMS
)
SELECT

    CRICKET_ANALYTICS.RAW.SEQ_PLAYERS.NEXTVAL,

    P.PLAYER_NAME,

    ARRAY_AGG(
        DISTINCT T.TEAM_ID
    )

FROM CRICKET_ANALYTICS.STAGING.STG_PLAYERS P

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T

    ON P.TEAM_NAME = T.TEAM_NAME

GROUP BY
    P.PLAYER_NAME;


-- ============================================================
-- CHECK DW PLAYERS
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.DW.PLAYERS
LIMIT 20;


-- ============================================================
-- STEP 14: DATA WAREHOUSE - MATCH INFO
-- ============================================================

INSERT INTO CRICKET_ANALYTICS.DW.MATCH_INFO
(
    MATCH_ID,
    MATCH_TYPE,
    GENDER,
    SEASON,
    CITY,
    VENUE,
    MATCH_DATE,
    TEAM1_ID,
    TEAM2_ID,
    TOSS_WINNER_ID,
    TOSS_DECISION,
    MATCH_WINNER_ID,
    MARGIN,
    EVENT_NAME,
    EVENT_TYPE,
    POM_ID,
    FILENAME
)
SELECT

    CRICKET_ANALYTICS.RAW.SEQ_MATCHES.NEXTVAL,

    MI.MATCH_TYPE,

    MI.GENDER,

    MI.SEASON,

    MI.CITY,

    MI.VENUE,

    MI.MATCH_DATE,

    T1.TEAM_ID,

    T2.TEAM_ID,

    T3.TEAM_ID,

    MI.TOSS_DECISION,

    T4.TEAM_ID,

    MI.MARGIN,

    MI.EVENT_NAME,

    MI.EVENT_TYPE,

    P.PLAYER_ID,

    MI.FILENAME

FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO MI

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T1
    ON MI.TEAM1 = T1.TEAM_NAME

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T2
    ON MI.TEAM2 = T2.TEAM_NAME

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T3
    ON MI.TOSS_WINNER = T3.TEAM_NAME

LEFT JOIN CRICKET_ANALYTICS.DW.TEAMS T4
    ON MI.MATCH_WINNER = T4.TEAM_NAME

LEFT JOIN CRICKET_ANALYTICS.DW.PLAYERS P
    ON MI.POM = P.PLAYER_NAME;


-- ============================================================
-- CHECK DW MATCH INFO
-- ============================================================

SELECT
    COUNT(*) AS MATCH_COUNT
FROM CRICKET_ANALYTICS.DW.MATCH_INFO;


SELECT *
FROM CRICKET_ANALYTICS.DW.MATCH_INFO
LIMIT 5;


-- ============================================================
-- STEP 15: DATA WAREHOUSE - MATCH INNINGS
-- ============================================================
--
-- This is the main fact-style ball-by-ball table.
-- ============================================================

INSERT INTO CRICKET_ANALYTICS.DW.MATCH_INNINGS
(
    MATCH_ID,
    INNING_ID,
    OVER,
    BATTING_TEAM,
    BALL_IN_OVER,
    BATTER,
    BOWLER,
    NON_STRIKER,
    RUNS_BATTER,
    EXTRA_TYPE,
    RUNS_EXTRAS,
    RUNS_TOTAL,
    DISMISSAL_KIND,
    OUT_PLAYER,
    IS_POWERPLAY
)
SELECT

    M.MATCH_ID,

    I.INNING_ID,

    I.OVER,

    T.TEAM_ID,

    I.BALL_IN_OVER,

    I.BATTER,

    I.BOWLER,

    I.NON_STRIKER,

    I.RUNS_BATTER,

    I.EXTRA_TYPE,

    I.RUNS_EXTRAS,

    I.RUNS_TOTAL,

    I.DISMISSAL_KIND,

    I.OUT_PLAYER,

    I.IS_POWERPLAY

FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INNINGS I

INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

    ON I.FILENAME = M.FILENAME

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T

    ON I.BATTING_TEAM = T.TEAM_NAME;


-- ============================================================
-- STEP 16: FINAL DW VALIDATION
-- ============================================================

SELECT
    'TEAMS' AS TABLE_NAME,
    COUNT(*) AS ROW_COUNT
FROM CRICKET_ANALYTICS.DW.TEAMS

UNION ALL

SELECT
    'PLAYERS',
    COUNT(*)
FROM CRICKET_ANALYTICS.DW.PLAYERS

UNION ALL

SELECT
    'MATCH_INFO',
    COUNT(*)
FROM CRICKET_ANALYTICS.DW.MATCH_INFO

UNION ALL

SELECT
    'MATCH_INNINGS',
    COUNT(*)
FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS;


-- ============================================================
-- STEP 17: CREATE PLAYER STATISTICS VIEW
-- ============================================================

CREATE OR REPLACE VIEW
CRICKET_ANALYTICS.DW.PLAYER_STATISTICS
AS

WITH BASE AS
(
    SELECT

        I.*,

        M.MATCH_TYPE AS FORMAT,

        M.GENDER,

        M.EVENT_TYPE AS FORMAT_TYPE

    FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS I

    INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

        ON I.MATCH_ID = M.MATCH_ID
),

BATTING AS
(
    SELECT

        BATTER AS PLAYER_NAME,

        FORMAT,

        GENDER,

        FORMAT_TYPE,

        SUM(RUNS_BATTER) AS TOTAL_RUNS,

        SUM(
            CASE
                WHEN COALESCE(EXTRA_TYPE, '') <> 'wides'
                THEN 1
                ELSE 0
            END
        ) AS BALLS_FACED,

        SUM(
            CASE
                WHEN OUT_PLAYER = BATTER
                THEN 1
                ELSE 0
            END
        ) AS DISMISSALS

    FROM BASE

    GROUP BY
        BATTER,
        FORMAT,
        GENDER,
        FORMAT_TYPE
),

BOWLING AS
(
    SELECT

        BOWLER AS PLAYER_NAME,

        FORMAT,

        GENDER,

        FORMAT_TYPE,

        SUM(
            RUNS_TOTAL
            -
            CASE
                WHEN EXTRA_TYPE IN ('byes', 'legbyes')
                THEN COALESCE(RUNS_EXTRAS,0)
                ELSE 0
            END
        ) AS RUNS_CONCEDED,

        SUM(
            CASE
                WHEN EXTRA_TYPE NOT IN ('wides','noballs')
                     OR EXTRA_TYPE IS NULL
                THEN 1
                ELSE 0
            END
        ) AS LEGAL_BALLS,

        SUM(
            CASE
                WHEN DISMISSAL_KIND IS NOT NULL
                 AND LOWER(DISMISSAL_KIND)
                     NOT IN
                     (
                         'run out',
                         'retired hurt',
                         'retired out',
                         'obstructing the field',
                         'timed out'
                     )
                THEN 1
                ELSE 0
            END
        ) AS TOTAL_WICKETS

    FROM BASE

    GROUP BY
        BOWLER,
        FORMAT,
        GENDER,
        FORMAT_TYPE
)

SELECT

    COALESCE(B.PLAYER_NAME,W.PLAYER_NAME)
        AS PLAYER_NAME,

    COALESCE(B.FORMAT,W.FORMAT)
        AS FORMAT,

    COALESCE(B.GENDER,W.GENDER)
        AS GENDER,

    COALESCE(B.FORMAT_TYPE,W.FORMAT_TYPE)
        AS FORMAT_TYPE,

    COALESCE(B.TOTAL_RUNS,0)
        AS TOTAL_RUNS,

    COALESCE(W.TOTAL_WICKETS,0)
        AS TOTAL_WICKETS,

    DIV0(
        COALESCE(B.TOTAL_RUNS,0),
        COALESCE(B.DISMISSALS,0)
    ) AS BATTING_AVERAGE,

    DIV0(
        COALESCE(W.RUNS_CONCEDED,0),
        COALESCE(W.TOTAL_WICKETS,0)
    ) AS BOWLING_AVERAGE,

    DIV0(
        COALESCE(B.TOTAL_RUNS,0) * 100,
        COALESCE(B.BALLS_FACED,0)
    ) AS BATTING_STRIKE_RATE,

    DIV0(
        COALESCE(W.RUNS_CONCEDED,0) * 6,
        COALESCE(W.LEGAL_BALLS,0)
    ) AS BOWLING_STRIKE_RATE

FROM BATTING B

FULL OUTER JOIN BOWLING W

    ON B.PLAYER_NAME = W.PLAYER_NAME

   AND B.FORMAT = W.FORMAT

   AND B.GENDER = W.GENDER

   AND B.FORMAT_TYPE = W.FORMAT_TYPE;


-- ============================================================
-- STEP 18: PLAYER STATISTICS RESULT
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.DW.PLAYER_STATISTICS
ORDER BY TOTAL_RUNS DESC
LIMIT 20;


-- ============================================================
-- STEP 19: TOURNAMENT / EVENT TOP RUN SCORERS
-- ============================================================

WITH RUNS AS
(
    SELECT

        M.EVENT_NAME,

        I.BATTER AS PLAYER_NAME,

        SUM(I.RUNS_BATTER) AS TOTAL_RUNS

    FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS I

    INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

        ON I.MATCH_ID = M.MATCH_ID

    WHERE M.EVENT_NAME IS NOT NULL

    GROUP BY
        M.EVENT_NAME,
        I.BATTER
),

RANKED AS
(
    SELECT

        *,

        RANK() OVER
        (
            PARTITION BY EVENT_NAME
            ORDER BY TOTAL_RUNS DESC
        ) AS RUN_RANK

    FROM RUNS
)

SELECT

    EVENT_NAME,

    PLAYER_NAME,

    TOTAL_RUNS

FROM RANKED

WHERE RUN_RANK = 1

ORDER BY EVENT_NAME;


-- ============================================================
-- STEP 20: TOURNAMENT / EVENT TOP WICKET TAKERS
-- ============================================================

WITH WICKETS AS
(
    SELECT

        M.EVENT_NAME,

        I.BOWLER AS PLAYER_NAME,

        COUNT(*) AS TOTAL_WICKETS

    FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS I

    INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

        ON I.MATCH_ID = M.MATCH_ID

    WHERE M.EVENT_NAME IS NOT NULL

      AND I.DISMISSAL_KIND IS NOT NULL

      AND LOWER(I.DISMISSAL_KIND)
          NOT IN
          (
              'run out',
              'retired hurt',
              'retired out',
              'obstructing the field',
              'timed out'
          )

    GROUP BY
        M.EVENT_NAME,
        I.BOWLER
),

RANKED AS
(
    SELECT

        *,

        RANK() OVER
        (
            PARTITION BY EVENT_NAME
            ORDER BY TOTAL_WICKETS DESC
        ) AS WICKET_RANK

    FROM WICKETS
)

SELECT

    EVENT_NAME,

    PLAYER_NAME,

    TOTAL_WICKETS

FROM RANKED

WHERE WICKET_RANK = 1

ORDER BY EVENT_NAME;


-- ============================================================
-- STEP 21: T20 POWERPLAY HIGHEST STRIKE RATE
-- ============================================================

SELECT

    I.BATTER AS PLAYER_NAME,

    SUM(I.RUNS_BATTER) AS POWERPLAY_RUNS,

    SUM(
        CASE
            WHEN I.EXTRA_TYPE <> 'wides'
                 OR I.EXTRA_TYPE IS NULL
            THEN 1
            ELSE 0
        END
    ) AS BALLS_FACED,

    DIV0(
        SUM(I.RUNS_BATTER) * 100,

        SUM(
            CASE
                WHEN I.EXTRA_TYPE <> 'wides'
                     OR I.EXTRA_TYPE IS NULL
                THEN 1
                ELSE 0
            END
        )
    ) AS STRIKE_RATE

FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS I

INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

    ON I.MATCH_ID = M.MATCH_ID

WHERE UPPER(M.MATCH_TYPE) = 'T20'

  AND I.IS_POWERPLAY = 1

GROUP BY
    I.BATTER

HAVING
    BALLS_FACED >= 10

ORDER BY
    STRIKE_RATE DESC

LIMIT 10;


-- ============================================================
-- STEP 22: T20 OVERS 17-20 - MAXIMUM SIXES
-- ============================================================

SELECT

    I.BATTER AS PLAYER_NAME,

    COUNT(*) AS SIXES

FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS I

INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

    ON I.MATCH_ID = M.MATCH_ID

WHERE UPPER(M.MATCH_TYPE) = 'T20'

  AND I.OVER BETWEEN 17 AND 20

  AND I.RUNS_BATTER = 6

GROUP BY
    I.BATTER

ORDER BY
    SIXES DESC

LIMIT 10;


-- ============================================================
-- STEP 23: INTERNATIONAL CENTURIONS
-- ============================================================

WITH PLAYER_INNINGS AS
(
    SELECT

        M.MATCH_TYPE,

        M.GENDER,

        I.MATCH_ID,

        I.INNING_ID,

        I.BATTER AS PLAYER_NAME,

        SUM(I.RUNS_BATTER) AS INNINGS_RUNS

    FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS I

    INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

        ON I.MATCH_ID = M.MATCH_ID

    WHERE LOWER(M.EVENT_TYPE) = 'international'

      AND UPPER(M.MATCH_TYPE)
          IN ('TEST','ODI','T20')

    GROUP BY

        M.MATCH_TYPE,

        M.GENDER,

        I.MATCH_ID,

        I.INNING_ID,

        I.BATTER
)

SELECT

    PLAYER_NAME,

    MATCH_TYPE,

    GENDER,

    COUNT(*) AS CENTURIES

FROM PLAYER_INNINGS

WHERE INNINGS_RUNS >= 100

GROUP BY

    PLAYER_NAME,

    MATCH_TYPE,

    GENDER

ORDER BY
    CENTURIES DESC;


-- ============================================================
-- STEP 24: WOMEN'S ODI - TOP 5 RUN SCORERS
-- ============================================================

SELECT

    I.BATTER AS PLAYER_NAME,

    SUM(I.RUNS_BATTER) AS TOTAL_RUNS

FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS I

INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

    ON I.MATCH_ID = M.MATCH_ID

WHERE UPPER(M.MATCH_TYPE) = 'ODI'

  AND LOWER(M.GENDER) IN ('female','women')

GROUP BY
    I.BATTER

ORDER BY
    TOTAL_RUNS DESC

LIMIT 5;


-- ============================================================
-- STEP 25: WOMEN'S ODI - TOP 5 WICKET TAKERS
-- ============================================================

SELECT

    I.BOWLER AS PLAYER_NAME,

    COUNT(*) AS TOTAL_WICKETS

FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS I

INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO M

    ON I.MATCH_ID = M.MATCH_ID

WHERE UPPER(M.MATCH_TYPE) = 'ODI'

  AND LOWER(M.GENDER) IN ('female','women')

  AND I.DISMISSAL_KIND IS NOT NULL

  AND LOWER(I.DISMISSAL_KIND)
      NOT IN
      (
          'run out',
          'retired hurt',
          'retired out',
          'obstructing the field',
          'timed out'
      )

GROUP BY
    I.BOWLER

ORDER BY
    TOTAL_WICKETS DESC

LIMIT 5;


-- ============================================================
-- STEP 26: FINAL DATA QUALITY CHECK
-- ============================================================

SELECT
    'RAW MATCHES' AS METRIC,
    COUNT(*) AS VALUE
FROM CRICKET_ANALYTICS.RAW.RAW_DATA

UNION ALL

SELECT
    'STAGING MATCHES',
    COUNT(*)
FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO

UNION ALL

SELECT
    'DW MATCHES',
    COUNT(*)
FROM CRICKET_ANALYTICS.DW.MATCH_INFO

UNION ALL

SELECT
    'DW DELIVERIES',
    COUNT(*)
FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS;


-- ============================================================
-- STEP 27: CHECK EXTRAS
-- ============================================================

SELECT

    EXTRA_TYPE,

    COUNT(*) AS DELIVERY_COUNT,

    SUM(RUNS_EXTRAS) AS EXTRA_RUNS

FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS

WHERE EXTRA_TYPE IS NOT NULL

GROUP BY
    EXTRA_TYPE

ORDER BY
    EXTRA_RUNS DESC;


-- ============================================================
-- STEP 28: CHECK WICKETS
-- ============================================================

SELECT

    DISMISSAL_KIND,

    COUNT(*) AS WICKET_COUNT

FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS

WHERE DISMISSAL_KIND IS NOT NULL

GROUP BY
    DISMISSAL_KIND

ORDER BY
    WICKET_COUNT DESC;


-- ============================================================
-- STEP 29: CHECK POWERPLAY
-- ============================================================

SELECT

    IS_POWERPLAY,

    COUNT(*) AS DELIVERY_COUNT

FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS

GROUP BY
    IS_POWERPLAY

ORDER BY
    IS_POWERPLAY;


-- ============================================================
-- STEP 30: FINAL OBJECT CHECK
-- ============================================================

SHOW TABLES IN SCHEMA CRICKET_ANALYTICS.RAW;

SHOW TABLES IN SCHEMA CRICKET_ANALYTICS.STAGING;

SHOW TABLES IN SCHEMA CRICKET_ANALYTICS.DW;

SHOW VIEWS IN SCHEMA CRICKET_ANALYTICS.DW;


-- ============================================================
-- PROJECT COMPLETE
-- ============================================================
--
-- FINAL ARCHITECTURE:
--
-- Cricket JSON
--      ↓
-- Snowflake Internal Stage
--      ↓
-- RAW.RAW_DATA
--      ↓
-- VARIANT
--      ↓
-- FLATTEN
--      ↓
-- STAGING
--      ↓
-- DATA WAREHOUSE
--      ↓
-- ANALYTICS
--
-- ANALYTICS DELIVERABLES:
--
-- 1. Player Statistics View
-- 2. Tournament Run Leaders
-- 3. Tournament Wicket Leaders
-- 4. T20 Powerplay Strike Rate
-- 5. T20 Death-Over Sixes
-- 6. International Centurions
-- 7. Women's ODI Run Leaders
-- 8. Women's ODI Wicket Leaders
--
-- ============================================================
-- END
-- ============================================================