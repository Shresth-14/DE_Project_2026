-- Phase 5: Table Partitioning for Scalability
-- Team T0066
--
-- Converts watch_events from a regular heap table into a RANGE-partitioned
-- table on started_at (monthly granularity).
--
-- ========================================================================
-- WHY PARTITION watch_events?
-- ========================================================================
-- watch_events is the largest table (200,000 seed → ~4,000,000 at 20×).
-- Most analytical queries filter on date ranges:
--
--   R07  WHERE DATE(w.started_at) BETWEEN '2026-06-01' AND '2026-06-30'
--   R10  WHERE w.started_at >= '2026-06-24'
--   R11  WHERE w.started_at >= '2026-06-01'
--   R16  (joined to ad_impressions filtered on shown_at in June 2026)
--   R20  WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
--   W02  INSERT routes directly to the target partition
--
-- With monthly partitioning the planner prunes all partitions outside the
-- WHERE clause.  A June-only query on 4M rows touches only the ~222k rows
-- in the June 2026 partition instead of scanning the full table.
--
-- ========================================================================
-- KEY DESIGN DECISIONS
-- ========================================================================
--
-- 1. Partition key: started_at (timestamptz)
--    Watch events are naturally time-ordered.  Monthly granularity keeps
--    the partition count manageable (24 for 2 years) while giving good
--    pruning for monthly reports.
--
-- 2. Primary-key rule (PostgreSQL requirement):
--    Every UNIQUE / PRIMARY KEY on a partitioned table MUST include the
--    partition key.  The PK changes from:
--
--      PRIMARY KEY (watch_id)                  -- original
--      PRIMARY KEY (watch_id, started_at)      -- partitioned
--
--    watch_id remains unique in practice (application-assigned or sequence)
--    but is no longer enforced as globally unique by the PK alone.
--
-- 3. Foreign-key impact:
--    ad_impressions(watch_id) → watch_events(watch_id) cannot be enforced
--    declaratively because a partitioned table cannot have UNIQUE(watch_id)
--    without the partition key.  The FK is dropped before migration.
--    Referential integrity is maintained by the application layer or
--    verified with a periodic audit:
--
--      SELECT a.watch_id
--      FROM   ad_impressions a
--      LEFT JOIN watch_events w USING (watch_id)
--      WHERE  w.watch_id IS NULL;        -- should return 0 rows
--
-- 4. Granularity trade-off:
--    Monthly → 24 partitions for 2 years, small catalog overhead, good
--    pruning for monthly reports.  Weekly/daily would give finer pruning
--    for R10 (7-day window) but hundreds of partitions increase planning
--    time and DDL maintenance.
--
-- ========================================================================
-- RUN ORDER
-- ========================================================================
--   01_schema.sql  →  02_load_data.sql  →  08_partitioning.sql
--                                           →  05_indexes.sql  →  ANALYZE
--
-- Indexes defined on the partitioned parent in 05_indexes.sql are
-- automatically propagated to every existing and future partition.
-- ========================================================================

SET search_path TO youtube;

-- ----------------------------------------------------------------
-- Step 1: Drop the FK from ad_impressions that references watch_events
-- ----------------------------------------------------------------
ALTER TABLE ad_impressions
    DROP CONSTRAINT IF EXISTS fk_ad_impressions_watch;

-- ----------------------------------------------------------------
-- Step 2: Rename the original unpartitioned table
-- ----------------------------------------------------------------
ALTER TABLE watch_events RENAME TO watch_events_unpartitioned;

-- ----------------------------------------------------------------
-- Step 3: Create the partitioned parent table
-- ----------------------------------------------------------------
-- Constraints are identical to the original except:
--   • PK includes started_at (partition key rule)
--   • FK to watch_events from ad_impressions is not re-created (see above)
CREATE TABLE watch_events (
    watch_id        bigint       NOT NULL,
    user_id         integer,
    video_id        varchar(11),
    started_at      timestamptz  NOT NULL,
    watch_seconds   integer      NOT NULL,
    device          varchar(10)  NOT NULL,
    traffic_source  varchar(12)  NOT NULL,

    CONSTRAINT pk_watch_events       PRIMARY KEY (watch_id, started_at),
    CONSTRAINT fk_watch_events_user  FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_watch_events_video FOREIGN KEY (video_id)
        REFERENCES videos (video_id) ON DELETE SET NULL,
    CONSTRAINT chk_watch_events_seconds CHECK (watch_seconds >= 0),
    CONSTRAINT chk_watch_events_device  CHECK (device IN ('ANDROID', 'IOS', 'WEB', 'TV')),
    CONSTRAINT chk_watch_events_traffic CHECK (traffic_source IN (
        'HOME', 'SUGGESTED', 'SEARCH', 'SUBSCRIPTION', 'SHORTS_FEED', 'EXTERNAL'))
) PARTITION BY RANGE (started_at);

-- ----------------------------------------------------------------
-- Step 4: Create monthly partitions
-- ----------------------------------------------------------------
-- Seed data covers Jan 2025 – Jun 2026.  Large data covers the same
-- range with 20× volume.  Extra partitions through Dec 2026 accommodate
-- W02-style inserts and future growth.
-- FROM is inclusive, TO is exclusive (standard RANGE semantics).

-- 2025
CREATE TABLE watch_events_y2025m01 PARTITION OF watch_events
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE watch_events_y2025m02 PARTITION OF watch_events
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE watch_events_y2025m03 PARTITION OF watch_events
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE watch_events_y2025m04 PARTITION OF watch_events
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE watch_events_y2025m05 PARTITION OF watch_events
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE watch_events_y2025m06 PARTITION OF watch_events
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE watch_events_y2025m07 PARTITION OF watch_events
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE watch_events_y2025m08 PARTITION OF watch_events
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE watch_events_y2025m09 PARTITION OF watch_events
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE watch_events_y2025m10 PARTITION OF watch_events
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE watch_events_y2025m11 PARTITION OF watch_events
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE watch_events_y2025m12 PARTITION OF watch_events
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- 2026
CREATE TABLE watch_events_y2026m01 PARTITION OF watch_events
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE watch_events_y2026m02 PARTITION OF watch_events
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE watch_events_y2026m03 PARTITION OF watch_events
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE watch_events_y2026m04 PARTITION OF watch_events
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE watch_events_y2026m05 PARTITION OF watch_events
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE watch_events_y2026m06 PARTITION OF watch_events
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE watch_events_y2026m07 PARTITION OF watch_events
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE watch_events_y2026m08 PARTITION OF watch_events
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE watch_events_y2026m09 PARTITION OF watch_events
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE watch_events_y2026m10 PARTITION OF watch_events
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE watch_events_y2026m11 PARTITION OF watch_events
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE watch_events_y2026m12 PARTITION OF watch_events
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

-- Default partition catches rows outside defined ranges
-- (e.g. late-arriving corrections, timezone edge cases, or data beyond 2026).
CREATE TABLE watch_events_default PARTITION OF watch_events DEFAULT;

-- ----------------------------------------------------------------
-- Step 5: Migrate data from the unpartitioned table
-- ----------------------------------------------------------------
-- PostgreSQL routes each row to the correct partition based on started_at.
INSERT INTO watch_events
SELECT * FROM watch_events_unpartitioned;

-- ----------------------------------------------------------------
-- Step 6: Verify row counts match
-- ----------------------------------------------------------------
-- Run manually after migration:
--
--   SELECT 'partitioned' AS source, count(*) FROM watch_events
--   UNION ALL
--   SELECT 'original',    count(*) FROM watch_events_unpartitioned;
--
-- Both counts must be identical (200,000 on seed data; ~4,000,000 on large).

-- ----------------------------------------------------------------
-- Step 7: Drop the old unpartitioned table
-- ----------------------------------------------------------------
DROP TABLE watch_events_unpartitioned;

-- ----------------------------------------------------------------
-- Step 8: Refresh statistics for every partition
-- ----------------------------------------------------------------
ANALYZE watch_events;


-- ================================================================
-- PARTITION PRUNING DEMONSTRATION
-- ================================================================
-- After running this script and 05_indexes.sql, verify pruning with:
--
-- (a) Simple June 2026 count:
--
--   EXPLAIN (COSTS OFF)
--   SELECT count(*)
--   FROM   youtube.watch_events
--   WHERE  started_at >= '2026-06-01' AND started_at < '2026-07-01';
--
--   Expected plan — only the June 2026 partition is scanned:
--
--     Aggregate
--       ->  Seq Scan on watch_events_y2026m06 watch_events
--             Filter: (started_at >= '2026-06-01 ...' AND started_at < '2026-07-01 ...')
--
--   Without partitioning the same query scans all 4,000,000 rows.
--
-- (b) R10 — Shorts shelf, last 7 days of June 2026:
--
--   EXPLAIN (COSTS OFF)
--   SELECT v.video_id, v.title, count(*) AS views
--   FROM   watch_events w
--   JOIN   videos v ON v.video_id = w.video_id
--   WHERE  v.is_short AND w.started_at >= '2026-06-24'
--   GROUP BY v.video_id, v.title
--   ORDER BY views DESC
--   LIMIT 20;
--
--   Expected plan prunes to watch_events_y2026m06 (and y2026m07 if any
--   rows exist there), skipping the other 22 partitions entirely.
--
-- (c) W02 — Insert a new watch event:
--
--   EXPLAIN (COSTS OFF)
--   INSERT INTO watch_events VALUES
--   (90000001, 1042, 'ZkNSlUB1EOs', '2026-07-01 19:00:00+05:30', 180, 'ANDROID', 'HOME');
--
--   Expected plan routes directly to watch_events_y2026m07.
--
-- ================================================================
-- SARGABILITY NOTE FOR PARTITION PRUNING
-- ================================================================
-- Some original queries wrap started_at in a function:
--
--   R07:  WHERE DATE(w.started_at) BETWEEN '2026-06-01' AND '2026-06-30'
--   R20:  WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
--
-- Function calls on the partition key PREVENT pruning because the planner
-- cannot infer the range from DATE(started_at).  To enable pruning,
-- rewrite as explicit range predicates in 06_optimized_queries.sql:
--
--   R07:  WHERE w.started_at >= '2026-06-01' AND w.started_at < '2026-07-01'
--   R20:  WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
--
-- The GROUP BY DATE(started_at) in the SELECT list still produces daily
-- buckets; only the WHERE clause needs the range form.
-- ================================================================


-- ================================================================
-- ADDING NEW MONTHLY PARTITIONS (operational procedure)
-- ================================================================
-- Before data for a new month arrives, create the partition:
--
--   CREATE TABLE watch_events_y2027m01 PARTITION OF youtube.watch_events
--       FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
--
-- If the partition is not created in advance, rows fall into
-- watch_events_default.  Periodically detach the default, create the
-- missing partition, and reattach:
--
--   ALTER TABLE watch_events DETACH PARTITION watch_events_default;
--   CREATE TABLE watch_events_y2027m01 PARTITION OF watch_events
--       FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
--   INSERT INTO watch_events_y2027m01
--       SELECT * FROM watch_events_default
--       WHERE started_at >= '2027-01-01' AND started_at < '2027-02-01';
--   DELETE FROM watch_events_default
--       WHERE started_at >= '2027-01-01' AND started_at < '2027-02-01';
--   ALTER TABLE watch_events ATTACH PARTITION watch_events_default DEFAULT;
--
-- For archiving old data (e.g. after 2 years):
--
--   ALTER TABLE watch_events DETACH PARTITION watch_events_y2025m01;
--   -- move watch_events_y2025m01 to cold storage or drop it
-- ================================================================
