-- Phase 4: Performance Optimization Indexes
-- Team T0066 | DE_Project_2026
--
-- These indexes are justified by execution plan evidence from the Phase 3 baseline benchmark.
-- Only high-selectivity columns and foreign keys subject to frequent join/filter operations are indexed.

SET search_path TO youtube;

-- 1. Serves R05: History page (the last 50 videos user 1042 watched)
-- Eliminates parallel sequential scan of 200,000 rows in watch_events.
-- Composite order (user_id, started_at DESC) enables direct index seek for user_id
-- and retrieves rows pre-sorted by started_at DESC without an extra Sort step.
CREATE INDEX idx_watch_events_user_started
ON watch_events (user_id, started_at DESC);

-- 2. Serves R23: Moderation queue (all comments, newest first, page 1,201)
-- Eliminates full 60,000-row table scan and the 3.6 MB external merge disk spill.
-- Pre-sorts comments by created_at DESC so the query planner can scan the index directly.
CREATE INDEX idx_comments_created_at_desc
ON comments (created_at DESC);

-- 3. Serves W04, R13, R24: Foreign key lookup and aggregation on subscriptions by channel_id
-- The existing primary key pk_subscriptions is composite on (user_id, channel_id).
-- Because user_id is the leading column, PostgreSQL cannot use it to filter or group by channel_id alone.
-- This index enables Index-Only Scans for subscriber count aggregations.
CREATE INDEX idx_subscriptions_channel_id
ON subscriptions (channel_id);

-- 4. Serves R10, R11, R20: Date-range filtering on watch events (e.g. June 2026, last 7 days)
-- In R11, 189,000 non-matching rows are discarded by a full table scan.
-- This index allows range scans directly over the ~11,000 matching rows.
CREATE INDEX idx_watch_events_started_at
ON watch_events (started_at);
