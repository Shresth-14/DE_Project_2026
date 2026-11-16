# Phase 3: Baseline Timings

Team T0066 | PostgreSQL 18.6 | Database `youtube_db`

## How we measured

- The database was built with `sql/01_schema.sql` and loaded with `sql/02_load_data.sql`, which ends with `ANALYZE`. At the time of measurement only the 14 indexes created automatically for PRIMARY KEY and UNIQUE constraints existed, so this baseline reflects an untuned database.
- All 30 queries were run with `./benchmarks/run_benchmark.sh youtube_db baseline`. The script runs every query 3 times with `EXPLAIN (ANALYZE, BUFFERS)` and records the `Execution Time` of each run.
- The write queries W01 to W05 were executed inside `BEGIN ... ROLLBACK`, so the data was not changed.
- The complete plans of all three runs are stored in `benchmarks/results/baseline/R01.txt` to `W05.txt`, and the averages are in `benchmarks/results/baseline/summary.csv`. Every number in this document is taken directly from those files.
- The same laptop will be used for the Phase 4 measurements so that the two sets of results can be compared fairly.

## Timing table

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Channel page: the 20 newest public videos of channel 217 | READ | 31.599 | 1.874 | 2.514 | 11.996 |
| R02: Watch page: one video with its channel | READ | 1.081 | 0.034 | 0.066 | 0.394 |
| R03: Subscriptions feed: public videos from channels user 1042 subscribes to, newest first | READ | 7.296 | 4.150 | 3.735 | 5.060 |
| R04: Search: public videos with "tutorial" in the title, most viewed first | READ | 17.677 | 18.286 | 15.885 | 17.283 |
| R05: History page: the last 50 videos user 1042 watched | READ | 95.389 | 7.781 | 7.659 | 36.943 |
| R06: Publishing service: videos scheduled to go live in the first week of July 2026 | READ | 2.405 | 3.162 | 2.756 | 2.774 |
| R07: YouTube Studio: channel 217's daily views and watch hours in June 2026 | READ | 13.737 | 11.621 | 12.103 | 12.487 |
| R08: YouTube Studio: where views of video ZkNSlUB1EOs come from | READ | 6.043 | 6.109 | 6.402 | 6.185 |
| R09: YouTube Studio: average percentage watched for each of channel 217's videos | READ | 12.410 | 13.012 | 10.642 | 12.021 |
| R10: Shorts shelf: most viewed Shorts in the last 7 days of June 2026 | READ | 10.572 | 10.307 | 9.124 | 10.001 |
| R11: Trending tab: top 5 videos per category by views in June 2026 | READ | 16.629 | 15.843 | 16.082 | 16.185 |
| R12: Growth: share of logged-out viewing per device type | READ | 13.034 | 13.452 | 13.651 | 13.379 |
| R13: Creator insights: subscribers of channel 217 who have never watched any of its videos | READ | 57.341 | 15.165 | 13.571 | 28.692 |
| R14: YouTube Studio: likes, dislikes and like ratio per video of channel 217 | READ | 21.994 | 9.220 | 9.349 | 13.521 |
| R15: Watch page: pinned comment and top 10 comments of video ZkNSlUB1EOs | READ | 26.810 | 2.166 | 2.168 | 10.381 |
| R16: Finance: ad revenue per channel in June 2026, top 20 | READ | 43.402 | 20.361 | 16.793 | 26.852 |
| R17: Partner program: NOT_ELIGIBLE channels that now have 100+ subscribers and 40+ watch hours | READ | 14.363 | 13.890 | 17.696 | 15.316 |
| R18: Child safety: "made for kids" videos that still have comments (comments must be disabled) | READ | 10.783 | 10.845 | 11.007 | 10.878 |
| R19: Partner report: for every monetized channel, its latest upload and its total views | READ | 13,183.033 | 13,075.552 | 13,279.463 | 13,179.349 |
| R20: Platform analytics: daily watch hours and running total for June 2026 | READ | 8.785 | 8.515 | 8.443 | 8.581 |
| R21: Playlist page: playlist 501 in order | READ | 1.174 | 0.069 | 0.065 | 0.436 |
| R22: Copyright team: same title and duration uploaded by more than one channel | READ | 20.365 | 20.421 | 20.534 | 20.440 |
| R23: Moderation queue: all comments, newest first, page 1,201 (25 per page) | READ | 14.222 | 13.578 | 13.703 | 13.834 |
| R24: YouTube Studio: new subscribers per month for channel 217 | READ | 1.717 | 1.305 | 1.297 | 1.440 |
| R25: Premium audit: ads that were shown to users with an active Premium membership | READ | 53.274 | 31.135 | 30.026 | 38.145 |
| W01: Upload: a new public video on channel 217 | WRITE | 3.515 | 0.428 | 0.404 | 1.449 |
| W02: Player: record a view of video ZkNSlUB1EOs by user 1042 | WRITE | 1.878 | 0.474 | 0.467 | 0.940 |
| W03: View counter: add one view to video ZkNSlUB1EOs | WRITE | 1.158 | 0.188 | 0.193 | 0.513 |
| W04: Nightly job: recompute every channel's subscriber count | WRITE | 62.941 | 36.670 | 33.482 | 44.364 |
| W05: Publishing service: make scheduled videos public once their time has come (run at 3 Jul 2026 00:00) | WRITE | 2.114 | 2.046 | 2.022 | 2.061 |
| **Total (sum of all 30)** | | **13,756.741** | **13,367.659** | **13,561.302** | **13,561.900** |

Run 1 is noticeably slower than runs 2 and 3 for several queries (for example R01, R05, R13 and R15). This is expected, because during the first run the table pages are read from disk into PostgreSQL's shared buffers, while runs 2 and 3 find them already in memory. The average of the three runs is used as the official baseline, as the README requires.

## Scan type and why each query is slow or fast

| Query | Scan type (from the plan) | Why |
|---|---|---|
| R01 | Seq Scan on videos | There is no index on `channel_id`, so all 30,000 videos are read to find the public videos of channel 217, which are then sorted. |
| R02 | Index Scan using pk_videos and pk_channels | Both lookups use a primary key, so the query is already fast. |
| R03 | Index Only Scan using pk_subscriptions, Seq Scan on videos | The subscriptions primary key starts with `user_id`, so finding the channels of user 1042 is quick. However, `videos` has no index on `channel_id`, so every video is scanned and hash joined. |
| R04 | Seq Scan on videos | `ILIKE '%tutorial%'` begins with a wildcard, so a normal B-tree index cannot be used and every title must be checked. |
| R05 | Seq Scan on watch_events | There is no index on `watch_events.user_id`, so all 200,000 views are read to find the few views of user 1042. |
| R06 | Seq Scan on videos | There is no index on `visibility` or `published_at`, so every video is read to find the scheduled ones. |
| R07 | Seq Scan on watch_events and videos | There is no index on `videos.channel_id` or `watch_events.video_id`. In addition, `DATE(w.started_at)` applies a function to the column, so even an index on `started_at` could not be used for the June filter. |
| R08 | Seq Scan on watch_events | There is no index on `watch_events.video_id`, so all views are read for one video. |
| R09 | Seq Scan on watch_events and videos | Same cause as R07. The query needs indexes on `channel_id` and `video_id`. |
| R10 | Seq Scan on watch_events and videos | There is no index on `started_at`, so the last 7 days of June are found by reading the whole table. |
| R11 | Seq Scan on watch_events and videos | June 2026 is a small part of the data, but the whole table is read before the rows are grouped and ranked. |
| R12 | Seq Scan on watch_events | The query counts every view per device. Because it is a report over the full table, an index would not help much. |
| R13 | Index Scan using pk_subscriptions, Seq Scan on watch_events and videos | Besides the full scans, the query returns a wrong result of 0 rows. Some `user_id` values in the subquery are NULL, and `NOT IN` against a list that contains NULL can never be true. This is fixed in Phase 4. |
| R14 | Seq Scan on video_reactions and videos | The reactions primary key starts with `user_id`, not `video_id`, so it cannot be used to find the reactions of a video. |
| R15 | Seq Scan on comments | There is no index on `comments.video_id`, so all 60,000 comments are read to return 3 rows. |
| R16 | Seq Scan on watch_events and ad_impressions | There is no index on `shown_at`, and the join needs the matching watch rows. Some scanning is expected because it is a monthly report. |
| R17 | Seq Scan on watch_events, videos and channels | Three full tables are joined, and the filters on channel status and watch hours are applied only afterwards. |
| R18 | Seq Scan on comments and videos | There is no index on `comments.video_id`, so every comment is read to check the made-for-kids videos. |
| R19 | Seq Scan on channels, then on videos and watch_events once per channel | The two correlated subqueries run once for each of the 1,087 ELIGIBLE channels, and each run scans all of `videos` and all 200,000 rows of `watch_events` (the plan shows `loops=1087`). At about 12 ms per channel this adds up to roughly 13 seconds. This is the slow query the README warns about. |
| R20 | Seq Scan on watch_events | `started_at::date` applies a cast to the column, so an index on `started_at` could not be used. |
| R21 | Index Scan using pk_playlist_items and pk_videos | The primary key `(playlist_id, position)` matches the query exactly and already returns the rows in order. |
| R22 | Seq Scan on videos | The query groups every video by title and duration, so it is a full-table report by nature. |
| R23 | Seq Scan on comments | There is no index on `created_at`. All 60,000 comments are sorted (the plan shows an external merge sort using 3,656 kB on disk) only to skip 30,000 rows and return 25. |
| R24 | Index Scan using pk_subscriptions | The primary key starts with `user_id`, so for a `channel_id` filter the whole index has to be walked. It is still fast because the table is small. |
| R25 | Seq Scan on watch_events, ad_impressions and users | Three full tables are joined. Only a small share of users have Premium, but this is not known until after the join. |
| W01 | No scan | A plain insert. Only the primary key and unique indexes are updated and the foreign keys are checked. |
| W02 | No scan | A plain insert into `watch_events`. |
| W03 | Index Scan using pk_videos | An update by primary key. |
| W04 | Seq Scan on channels and subscriptions | A batch job that counts all 129,253 subscriptions and updates all 3,000 channels, so it has to read everything. |
| W05 | Seq Scan on videos | There is no index on `visibility`, so every video is read to find the scheduled ones. |

## Main observations

- R19 alone takes 13,179.349 ms on average, which is about 97% of the total workload time of 13,561.900 ms. Its cost comes from the way it is written (a subquery evaluated once per channel), not from the size of the data.
- Most of the remaining slow plans are Seq Scans on foreign key or filter columns such as `channel_id`, `video_id`, `user_id` and `started_at`. PostgreSQL does not create indexes on foreign key columns automatically, and Phase 2 allowed only constraints.
- Some queries cannot use an index even if one is created, because they apply a function or cast to the column (`DATE(started_at)` in R07, `started_at::date` in R20) or search with a leading wildcard (`'%tutorial%'` in R04).
- R13 must be corrected before its speed matters, since it currently returns no rows.
- Queries that already use a primary key (R02, R21, W03) are under 0.6 ms on average and need no work.
