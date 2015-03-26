SET LINESIZE 180
SET PAGESIZE 999

-- Given a sql_id, return the execution progress.

-- This script depends on the simplify_count() and simplify_size() functions.
-- You cam find the source code in simplify_count.sql

-- <formatting_hacks>
-- Force the user's input before we suppress all output
UNDEFINE sql_id
DEFINE sql_id = '&&sql_id.'

SET TERMOUT OFF
-- Find the longest plan step description, then use that as the column's width
COLUMN dummy NEW_VALUE op_fmt NOPRINT
SELECT
    'A'||(MAX( LENGTH(NVL(op_text, ' ')) + 2)) AS dummy
FROM
(
    SELECT
        (LPAD(' ', depth) || operation || options || NVL2(object_name, ' - ' || object_name, NULL)) AS op_text
    FROM v$sql_plan
    WHERE sql_id = '&&sql_id.'
);

-- Default value in case the plan is empty
SELECT
    DECODE('&&op_fmt.', 'A', 'A16', '&&op_fmt.') AS dummy
FROM dual;

CLEAR COMPUTES
CLEAR BREAKS
SET TERMOUT ON
-- </formatting_hacks>



COLUMN plan_line_id HEADING "ID"                  FORMAT             999
COLUMN op_text      HEADING "Plan Step"           FORMAT       &&op_fmt.
COLUMN est_rows     HEADING "Est. Rows"           FORMAT              A9
COLUMN output_rows  HEADING "Row Count"           FORMAT 999,999,999,990
COLUMN est_pct      HEADING "Row %"               FORMAT          99,990
COLUMN cur_mem      HEADING "Memory"              FORMAT              A8
COLUMN cur_temp     HEADING "Temp"                FORMAT              A8
COLUMN plan_cost    HEADING "Plan Cost"           FORMAT      99,999,990
COLUMN step_run_min HEADING "Exec Time|(Min)"     FORMAT           9,990
COLUMN status       HEADING "Step Status"         FORMAT             A15

COLUMN sql_exec_id    NEW_VALUE query_id   NOPRINT
COLUMN sql_exec_start NEW_VALUE query_time NOPRINT
COLUMN sql_sid        NEW_VALUE query_sid  NOPRINT

BREAK ON sql_exec_id SKIP PAGE
TTITLE SKIP 2 -
  LEFT '==============================================' SKIP 1 -
  LEFT 'Query Sid:       ' FORMAT 9999999999 query_sid  SKIP 1 -
  LEFT 'Query Exec ID:   ' FORMAT 9999999999 query_id   SKIP 1 -
  LEFT 'Query Exec Time: '                   query_time SKIP 2

  
-- The actual meat and potatoes starts here.
WITH
plan AS
(
    -- Pull the SQL plan for the desired sql_id, format for easy reading.
    -- CONNECT BY is not required because of the "depth" column.
    -- Plan entries can be duplicated, so use ROW_NUMBER to dedupe them.
    SELECT
        p.*,
        (
            -- Create a nice indention pattern
            SUBSTR(LPAD(' ', 99, '|   '), 1, depth)
         || operation
         || NVL2(options,     ' '   || options,     NULL)
         || NVL2(object_name, ' - ' || object_name, NULL)
        ) AS op_text,
        ROW_NUMBER() OVER (PARTITION BY sql_id, id ORDER BY timestamp) AS plan_copy_num
    FROM v$sql_plan p
    WHERE sql_id = '&&sql_id.'
),
plan_and_progress_raw AS
(
    -- Pull the records relevant to our desired sql_id only.
    -- sql_id, sql_exec_id, and sql_exec_start uniquely identify the query instance.
    -- The rest are to condense the data down to the plan step level.
    SELECT
        m.sql_id,
        sql_exec_id,
        sql_exec_start,
        plan_line_id,
        -- This used to use an actual hash function, but for compatability reasons
        --   it has been simplified to concatination.
        (
            m.sql_id        || ',' ||
            sql_exec_id     || ',' ||
            sql_exec_start
        ) AS query_hash,
        -- Occasionally plan_parent_id is null on v$sql_plan_monitor for some records.
        -- If we have one with a populated value for a given step, use it.
        MAX(p.parent_id)        AS plan_parent_id,
        MIN(sid)                AS sql_sid,
        MAX(plan_cardinality)   AS est_rows,
        SUM(output_rows)        AS output_rows,
        -- Prevent div-by-zero
        100 * SUM(output_rows)
            / NULLIF(MAX(plan_cardinality), 0) AS est_pct,
        SUM(workarea_mem)       AS cur_mem,
        SUM(workarea_tempseg)   AS cur_temp,
        SUM(plan_cost)          AS plan_cost,
        MIN(first_change_time)  AS step_start_time,
        MAX(last_change_time)   AS last_change_time,
        MAX(status)             AS status_raw,
        -- All the op_text values are the same but we have to pick one to keep.
        MAX(p.op_text)          AS op_text
    FROM v$sql_plan_monitor m
    LEFT OUTER JOIN plan p
      ON m.sql_id = p.sql_id
     AND m.plan_line_id = p.id
    WHERE m.sql_id = '&&sql_id.'
      AND p.plan_copy_num = 1
    GROUP BY m.sql_id, sql_exec_id, sql_exec_start, plan_line_id
),
plan_and_progress_cont AS
(
    -- The status given in the status column is almost worthless.
    -- It's either "EXECUTING" or "DONE" and it's at the query level, not step level.
    -- We need a bit more info to make a meaningful status message, so gather that info now.
    SELECT
        p1.*,
        -- Including yourself, look at your children steps and keep the MAX last change time.
        -- We will use this value to help determine the current step's status.
        -- (If a child step is still running, then the parent cannot be considered complete.)
        (
            SELECT MAX(p2.last_change_time)
            FROM plan_and_progress_raw p2
            START WITH p2.query_hash   = p1.query_hash
                   AND p2.plan_line_id = p1.plan_line_id
            CONNECT BY PRIOR p2.query_hash   = p2.query_hash
                   AND PRIOR p2.plan_line_id = p2.plan_parent_id
        ) AS last_child_change_time,
        -- Oracle dates have a default unit of days, so convert it to minutes.
        ROUND(24 * 60 * (last_change_time - step_start_time)) AS step_run_min
    FROM plan_and_progress_raw p1
),
plan_and_progress AS
(
    -- Join our execution stats to the plan table to pick up the plan info.
    -- This also gives us an opportunity to fix the status column's accuracy.
    --
    -- If you'd like to add additional calculations, this is a good place to do so.
    -- Good candidates include estimated completion time and rows per second.
    -- We've been using * to propagate all columns, so all columns are available for use.
    SELECT
        prog.*,
        CASE
            -- If the start time is null, then step hasnt started.
            WHEN step_start_time IS NULL
                THEN 'WAITING'
            -- If us or any of our children haven't changed in 2 minutes, we're probably ready.
            -- last_child_change_time can be NULL if this entry and all children below it are NULL.
            -- In that case, use the time data borrowed from our parent nodes.
            -- (If they're in a ready state, we should be too.)
            WHEN status_raw = 'EXECUTING'
             AND (24 * 60 * (SYSDATE - COALESCE(last_child_change_time, last_change_time))) > 2
                THEN 'READY'
            -- Default to the originally supplied status.
            -- This includes the "executing", "done", and "error" status values.
            ELSE status_raw
        END AS status
    FROM plan_and_progress_cont prog
)
SELECT
    sql_exec_id,
    TO_CHAR(sql_exec_start, 'YYYY-MON-DD HH:MI PM') AS sql_exec_start,
    sql_sid,
    plan_line_id,
    op_text,
    SIMPLIFY_COUNT(est_rows) AS est_rows,
    output_rows,
    -- The estimated progress percent can be very inaccurate, especially after certain joins.
    -- est_pct,
    SIMPLIFY_SIZE(cur_mem)  AS cur_mem,
    SIMPLIFY_SIZE(cur_temp) AS cur_temp,
    -- plan_cost,
    step_run_min,
    status
FROM plan_and_progress
ORDER BY sql_exec_id ASC, plan_line_id ASC
;

-- Forgetting to unset this makes things really annoying.
TTITLE OFF

SET TERMOUT OFF
CLEAR COMPUTES
CLEAR BREAKS
SET TERMOUT ON
