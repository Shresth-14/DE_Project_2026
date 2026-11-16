-- Phase 4: Optimization Indexes
-- Team T0066

SET search_path TO youtube;

-- 1. Serves R05 (History page)
-- Composite key (user_id, started_at DESC) enables index lookups by user_id
-- and retrieves rows pre-sorted by started_at DESC without an explicit sort step.
CREATE INDEX idx_watch_events_user_started
ON watch_events (user_id, started_at DESC);

-- 2. Serves R23 (Moderation queue)
-- Pre-sorts comments by created_at DESC to eliminate the external merge sort on disk.
CREATE INDEX idx_comments_created_at_desc
ON comments (created_at DESC);

-- 3. Serves R13 and R24 (Channel subscriber lookups)
-- The primary key pk_subscriptions is composite on (user_id, channel_id).
-- Because user_id is the leading column, PostgreSQL cannot use it to filter on channel_id alone.
CREATE INDEX idx_subscriptions_channel_id
ON subscriptions (channel_id);

-- 4. Serves R10 and R11 (Date-filtered watch events)
-- Enables range scans over qualifying date windows (e.g. June 2026 or last 7 days)
-- rather than scanning the entire table.
CREATE INDEX idx_watch_events_started_at
ON watch_events (started_at);
