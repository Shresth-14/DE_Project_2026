-- Phase 2: load the seed data
-- Run from the project root:
--   psql -d youtube_db -f sql/02_load_data.sql


-- Order: parents before children, so every foreign key already has its target.

SET search_path TO youtube;

\copy users           FROM 'seed_data/users.csv'           WITH (FORMAT csv, HEADER true)
\copy channels        FROM 'seed_data/channels.csv'        WITH (FORMAT csv, HEADER true)
\copy videos          FROM 'seed_data/videos.csv'          WITH (FORMAT csv, HEADER true)
\copy subscriptions   FROM 'seed_data/subscriptions.csv'   WITH (FORMAT csv, HEADER true)
\copy watch_events    FROM 'seed_data/watch_events.csv'    WITH (FORMAT csv, HEADER true)
\copy video_reactions FROM 'seed_data/video_reactions.csv' WITH (FORMAT csv, HEADER true)
-- replies point to comments with a smaller id, and the file is sorted by id,
-- so parents are always loaded before their replies
\copy comments        FROM 'seed_data/comments.csv'        WITH (FORMAT csv, HEADER true)
\copy playlists       FROM 'seed_data/playlists.csv'       WITH (FORMAT csv, HEADER true)
\copy playlist_items  FROM 'seed_data/playlist_items.csv'  WITH (FORMAT csv, HEADER true)
\copy ad_impressions  FROM 'seed_data/ad_impressions.csv'  WITH (FORMAT csv, HEADER true)

ANALYZE;

-- Row counts vs the numbers in the README
SELECT t.table_name, t.actual, t.expected, t.actual = t.expected AS ok
FROM (
    SELECT 'users'           AS table_name, (SELECT count(*) FROM users)           AS actual, 30000  AS expected UNION ALL
    SELECT 'channels',                      (SELECT count(*) FROM channels),                  3000  UNION ALL
    SELECT 'videos',                        (SELECT count(*) FROM videos),                    30000 UNION ALL
    SELECT 'subscriptions',                 (SELECT count(*) FROM subscriptions),             129253 UNION ALL
    SELECT 'watch_events',                  (SELECT count(*) FROM watch_events),              200000 UNION ALL
    SELECT 'video_reactions',               (SELECT count(*) FROM video_reactions),           67417 UNION ALL
    SELECT 'comments',                      (SELECT count(*) FROM comments),                  60000 UNION ALL
    SELECT 'playlists',                     (SELECT count(*) FROM playlists),                 8000  UNION ALL
    SELECT 'playlist_items',                (SELECT count(*) FROM playlist_items),            56005 UNION ALL
    SELECT 'ad_impressions',                (SELECT count(*) FROM ad_impressions),            57014
) t;
