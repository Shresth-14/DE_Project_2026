-- =====================================================================
-- YouTube DBMS Project: Phase 4 Optimized Workload
-- Team T0066 | DE_Project_2026
--
-- RULES
--   * Benchmark with: ./benchmarks/run_benchmark.sh <db> optimized [runs] sql/06_optimized_queries.sql
--   * Only R13 and R19 are rewritten; all other queries are identical to workload_30.sql.
--   * R13 fixes a semantic NULL bug in NOT IN by using NOT EXISTS.
--   * R19 converts two correlated subqueries into pre-aggregated set-based joins.
--   * W01–W05 write queries remain inside BEGIN ... ROLLBACK so data stays unchanged.
-- =====================================================================
SET search_path TO youtube;
BEGIN;

-- @R01
-- Channel page: the 20 newest public videos of channel 217
SELECT video_id, title, duration_sec, view_count, published_at
FROM videos
WHERE channel_id = 217 AND visibility = 'PUBLIC'
ORDER BY published_at DESC
LIMIT 20;

-- @R02
-- Watch page: one video with its channel
SELECT v.video_id, v.title, v.description, v.view_count, c.channel_name, c.handle, c.subscriber_count
FROM videos v
JOIN channels c ON c.channel_id = v.channel_id
WHERE v.video_id = 'ZkNSlUB1EOs';

-- @R03
-- Subscriptions feed: public videos from channels user 1042 subscribes to, newest first
SELECT v.video_id, v.title, c.channel_name, v.published_at
FROM subscriptions s
JOIN videos v   ON v.channel_id = s.channel_id
JOIN channels c ON c.channel_id = s.channel_id
WHERE s.user_id = 1042 AND v.visibility = 'PUBLIC'
ORDER BY v.published_at DESC
LIMIT 30;

-- @R04
-- Search: public videos with "tutorial" in the title, most viewed first
SELECT video_id, title, view_count
FROM videos
WHERE title ILIKE '%tutorial%' AND visibility = 'PUBLIC'
ORDER BY view_count DESC
LIMIT 20;

-- @R05
-- History page: the last 50 videos user 1042 watched
SELECT w.started_at, w.watch_seconds, v.video_id, v.title
FROM watch_events w
JOIN videos v ON v.video_id = w.video_id
WHERE w.user_id = 1042
ORDER BY w.started_at DESC
LIMIT 50;

-- @R06
-- Publishing service: videos scheduled to go live in the first week of July 2026
SELECT video_id, channel_id, title, published_at
FROM videos
WHERE visibility = 'SCHEDULED'
  AND published_at < '2026-07-08'
ORDER BY published_at;

-- @R07
-- YouTube Studio: channel 217's daily views and watch hours in June 2026
SELECT DATE(w.started_at) AS day, count(*) AS views, round(sum(w.watch_seconds) / 3600.0, 2) AS watch_hours
FROM watch_events w
JOIN videos v ON v.video_id = w.video_id
WHERE v.channel_id = 217
  AND DATE(w.started_at) BETWEEN '2026-06-01' AND '2026-06-30'
GROUP BY 1
ORDER BY 1;

-- @R08
-- YouTube Studio: where views of video ZkNSlUB1EOs come from
SELECT traffic_source, count(*) AS views, round(avg(watch_seconds), 0) AS avg_seconds
FROM watch_events
WHERE video_id = 'ZkNSlUB1EOs'
GROUP BY traffic_source
ORDER BY views DESC;

-- @R09
-- YouTube Studio: average percentage watched for each of channel 217's videos
SELECT v.video_id, v.title, count(*) AS views,
       round(100.0 * avg(w.watch_seconds::numeric / v.duration_sec), 1) AS avg_pct_watched
FROM videos v
JOIN watch_events w ON w.video_id = v.video_id
WHERE v.channel_id = 217
GROUP BY v.video_id, v.title
ORDER BY avg_pct_watched DESC;

-- @R10
-- Shorts shelf: most viewed Shorts in the last 7 days of June 2026
SELECT v.video_id, v.title, count(*) AS views
FROM watch_events w
JOIN videos v ON v.video_id = w.video_id
WHERE v.is_short
  AND w.started_at >= '2026-06-24'
GROUP BY v.video_id, v.title
ORDER BY views DESC
LIMIT 20;

-- @R11
-- Trending tab: top 5 videos per category by views in June 2026
SELECT *
FROM (
    SELECT v.category, v.video_id, v.title, count(*) AS views,
           RANK() OVER (PARTITION BY v.category ORDER BY count(*) DESC) AS rnk
    FROM watch_events w
    JOIN videos v ON v.video_id = w.video_id
    WHERE w.started_at >= '2026-06-01'
    GROUP BY v.category, v.video_id, v.title
) t
WHERE rnk <= 5
ORDER BY category, rnk;

-- @R12
-- Growth: share of logged-out viewing per device type
SELECT device,
       count(*) AS views,
       round(100.0 * count(*) FILTER (WHERE user_id IS NULL) / count(*), 1) AS logged_out_pct
FROM watch_events
GROUP BY device
ORDER BY views DESC;

-- @R13
-- Creator insights: subscribers of channel 217 who have never watched any of its videos
-- REWRITE REASON: In the original query, "s.user_id NOT IN (SELECT w.user_id ...)" failed because
-- watch_events contains logged-out views where user_id IS NULL (24 rows for channel 217).
-- In SQL three-valued logic, "x NOT IN (val1, val2, ..., NULL)" evaluates to UNKNOWN for all rows,
-- causing the original query to return 0 rows.
-- REWRITE: Replacing NOT IN with correlated NOT EXISTS correctly handles NULLs and returns the true
-- 88 subscribers of channel 217 who have never watched any of its videos. Output columns and aliases preserved.
SELECT s.user_id, s.subscribed_at
FROM subscriptions s
WHERE s.channel_id = 217
  AND NOT EXISTS (
      SELECT 1
      FROM watch_events w
      JOIN videos v ON v.video_id = w.video_id
      WHERE v.channel_id = 217
        AND w.user_id = s.user_id
  );

-- @R14
-- YouTube Studio: likes, dislikes and like ratio per video of channel 217
SELECT v.video_id, v.title,
       count(*) FILTER (WHERE r.reaction = 'LIKE')    AS likes,
       count(*) FILTER (WHERE r.reaction = 'DISLIKE') AS dislikes,
       round(100.0 * count(*) FILTER (WHERE r.reaction = 'LIKE') / NULLIF(count(r.*), 0), 1) AS like_pct
FROM videos v
LEFT JOIN video_reactions r ON r.video_id = v.video_id
WHERE v.channel_id = 217
GROUP BY v.video_id, v.title
ORDER BY likes DESC;

-- @R15
-- Watch page: pinned comment and top 10 comments of video ZkNSlUB1EOs
SELECT comment_id, user_id, body, like_count, is_pinned
FROM comments
WHERE video_id = 'ZkNSlUB1EOs' AND parent_comment_id IS NULL
ORDER BY is_pinned DESC, like_count DESC
LIMIT 11;

-- @R16
-- Finance: ad revenue per channel in June 2026, top 20
SELECT v.channel_id, count(*) AS impressions, sum(a.revenue_inr) AS revenue_inr
FROM ad_impressions a
JOIN watch_events w ON w.watch_id = a.watch_id
JOIN videos v       ON v.video_id = w.video_id
WHERE a.shown_at >= '2026-06-01' AND a.shown_at < '2026-07-01'
GROUP BY v.channel_id
ORDER BY revenue_inr DESC
LIMIT 20;

-- @R17
-- Partner program: NOT_ELIGIBLE channels that now have 100+ subscribers and 40+ watch hours
SELECT c.channel_id, c.handle, c.subscriber_count, round(sum(w.watch_seconds) / 3600.0, 1) AS watch_hours
FROM channels c
JOIN videos v       ON v.channel_id = c.channel_id
JOIN watch_events w ON w.video_id = v.video_id
WHERE c.monetization_status = 'NOT_ELIGIBLE'
  AND c.subscriber_count >= 100
GROUP BY c.channel_id, c.handle, c.subscriber_count
HAVING sum(w.watch_seconds) / 3600.0 >= 40
ORDER BY watch_hours DESC;

-- @R18
-- Child safety: "made for kids" videos that still have comments (comments must be disabled)
SELECT v.video_id, v.title, v.channel_id
FROM videos v
WHERE v.is_made_for_kids
  AND EXISTS (SELECT 1 FROM comments c WHERE c.video_id = v.video_id)
ORDER BY v.video_id;

-- @R19
-- Partner report: for every monetized channel, its latest upload and its total views
-- REWRITE REASON: Original query ran two correlated scalar subqueries per ELIGIBLE channel (loops=1087),
-- scanning videos and watch_events over 1,000 times each, causing ~24 seconds of execution time.
-- REWRITE: Pre-aggregates video uploads and view counts in joined subqueries once.
-- Uses LEFT JOIN and COALESCE to preserve identical NULL last_upload (for channels with no videos)
-- and 0 total_views (for channels with no views). Output columns, aliases, filter, and ordering preserved.
SELECT c.channel_id, c.handle,
       v_agg.last_upload,
       COALESCE(w_agg.total_views, 0) AS total_views
FROM channels c
LEFT JOIN (
    SELECT channel_id, max(uploaded_at) AS last_upload
    FROM videos
    GROUP BY channel_id
) v_agg ON v_agg.channel_id = c.channel_id
LEFT JOIN (
    SELECT v.channel_id, count(*) AS total_views
    FROM watch_events w
    JOIN videos v ON v.video_id = w.video_id
    GROUP BY v.channel_id
) w_agg ON w_agg.channel_id = c.channel_id
WHERE c.monetization_status = 'ELIGIBLE'
ORDER BY total_views DESC;

-- @R20
-- Platform analytics: daily watch hours and running total for June 2026
SELECT day, hours, sum(hours) OVER (ORDER BY day) AS running_hours
FROM (
    SELECT started_at::date AS day, round(sum(watch_seconds) / 3600.0, 1) AS hours
    FROM watch_events
    WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Playlist page: playlist 501 in order
SELECT pi.position, v.video_id, v.title, v.duration_sec
FROM playlist_items pi
JOIN videos v ON v.video_id = pi.video_id
WHERE pi.playlist_id = 501
ORDER BY pi.position;

-- @R22
-- Copyright team: same title and duration uploaded by more than one channel
SELECT title, duration_sec, count(DISTINCT channel_id) AS channels, count(*) AS uploads
FROM videos
GROUP BY title, duration_sec
HAVING count(DISTINCT channel_id) > 1
ORDER BY channels DESC, uploads DESC
LIMIT 50;

-- @R23
-- Moderation queue: all comments, newest first, page 1,201 (25 per page)
SELECT comment_id, video_id, user_id, body, created_at
FROM comments
ORDER BY created_at DESC
OFFSET 30000
LIMIT 25;

-- @R24
-- YouTube Studio: new subscribers per month for channel 217
SELECT date_trunc('month', subscribed_at) AS month, count(*) AS new_subscribers
FROM subscriptions
WHERE channel_id = 217
GROUP BY 1
ORDER BY 1;

-- @R25
-- Premium audit: ads that were shown to users with an active Premium membership
SELECT a.impression_id, w.user_id, u.premium_until, a.shown_at, a.revenue_inr
FROM ad_impressions a
JOIN watch_events w ON w.watch_id = a.watch_id
JOIN users u        ON u.user_id = w.user_id
WHERE u.premium_until >= a.shown_at::date
ORDER BY a.shown_at DESC;

-- @W01
-- Upload: a new public video on channel 217
INSERT INTO videos (video_id, channel_id, title, category, duration_sec, is_short, visibility, uploaded_at, published_at)
VALUES ('NeWvId00001', 217, 'DBMS Indexing - Explained', 'Education', 742, FALSE, 'PUBLIC',
        '2026-07-01 18:00:00+05:30', '2026-07-01 18:30:00+05:30');

-- @W02
-- Player: record a view of video ZkNSlUB1EOs by user 1042
INSERT INTO watch_events (watch_id, user_id, video_id, started_at, watch_seconds, device, traffic_source)
VALUES (90000001, 1042, 'ZkNSlUB1EOs', '2026-07-01 19:00:00+05:30', 180, 'ANDROID', 'HOME');

-- @W03
-- View counter: add one view to video ZkNSlUB1EOs
UPDATE videos SET view_count = view_count + 1 WHERE video_id = 'ZkNSlUB1EOs';

-- @W04
-- Nightly job: recompute every channel's subscriber count
UPDATE channels c
SET subscriber_count = s.n
FROM (SELECT channel_id, count(*) AS n FROM subscriptions GROUP BY channel_id) s
WHERE s.channel_id = c.channel_id;

-- @W05
-- Publishing service: make scheduled videos public once their time has come (run at 3 Jul 2026 00:00)
UPDATE videos
SET visibility = 'PUBLIC'
WHERE visibility = 'SCHEDULED'
  AND published_at <= '2026-07-03 00:00:00+05:30';

-- @END
ROLLBACK;
