# Checkpoint 3 (CP3) / Phase 4: Query Optimization Report

**Team T0066** | **Database:** PostgreSQL 18.6 | **Database Name:** `youtube_db`

---

## 1. Objective and Database Environment

The objective of Checkpoint 3 (Phase 4: Query Optimization) is to improve the execution performance of the 30-query YouTube database workload without altering query results or violating schema constraints.

### Baseline Schema State
Following Phase 2 and Checkpoint 2, the database schema contained only primary key and unique constraints created automatically by PostgreSQL:
- 14 constraint-backed indexes existed (`PRIMARY KEY` and `UNIQUE`).
- No secondary, composite, foreign key, or tuning indexes existed.
- Baseline measurements therefore reflected an untuned database.

### Test Environment & Seed Dataset
All measurements were recorded on the team benchmark environment (PostgreSQL 18.6 on macOS `aarch64`):
- **Database:** `youtube_db`
- **Schema:** `youtube`
- **Seed Dataset Row Counts:**
  - `users`: 30,000 rows
  - `channels`: 3,000 rows
  - `videos`: 30,000 rows
  - `subscriptions`: 129,253 rows
  - `watch_events`: 200,000 rows
  - `video_reactions`: 67,417 rows
  - `comments`: 60,000 rows
  - `playlists`: 8,000 rows
  - `playlist_items`: 56,005 rows
  - `ad_impressions`: 57,014 rows

---

## 2. Measurement Methodology

To ensure strict comparability:
1. Every query was measured using `./benchmarks/run_benchmark.sh` across **3 consecutive runs** with `EXPLAIN (ANALYZE, BUFFERS)`.
2. The benchmark recorded `Execution Time` and buffer statistics for each run. The arithmetic **average** of the three runs is reported as the benchmark figure.
3. Write queries (`W01` through `W05`) were executed inside `BEGIN ... ROLLBACK;` blocks so that mutations were discarded and table states remained identical across runs.
4. The before-optimization measurements were taken from the local untuned baseline run recorded in `benchmarks/results/baseline_raw/summary.csv`.
5. The optimized measurements were taken from `benchmarks/results/optimized/summary.csv` after applying the approved indexes in `sql/05_indexes.sql` and the workload rewrites in `sql/06_optimized_queries.sql`.
6. All tests were executed on the same machine to avoid hardware discrepancies.

---

## 3. Deployed Optimization Indexes (`sql/05_indexes.sql`)

Four selective B-tree indexes were deployed to address high-cost access paths identified in the baseline execution plans:

1. **`idx_watch_events_user_started` ON `watch_events (user_id, started_at DESC)`**
   Supports **R05** (User History). Eliminates the sequential scan across all 200,000 rows of `watch_events`, enabling direct B-tree seeks and returning rows pre-sorted without an explicit sort step.
2. **`idx_comments_created_at_desc` ON `comments (created_at DESC)`**
   Supports **R23** (Moderation queue pagination). Pre-sorts comments to eliminate the 3,656 kB disk sort spill observed in baseline execution. *(Note: As detailed in Section 10, this index removes the sort phase but does not eliminate the sequential index page traversal required by `OFFSET 30000`).*
3. **`idx_subscriptions_channel_id` ON `subscriptions (channel_id)`**
   Supports **R24** and **R13** for channel lookups (`WHERE channel_id = 217`), enabling fast Bitmap Index Scans by `channel_id`. The existing primary key `(user_id, channel_id)` has `user_id` as its leading column and cannot be used for filtering solely on `channel_id`. *(Note: This does not produce an Index Only Scan for R24 because `subscribed_at` must still be retrieved from the heap table, nor does W04 use it because whole-table aggregation across all 129,253 rows remains cheaper via sequential scan).*
4. **`idx_watch_events_started_at` ON `watch_events (started_at)`**
   Supports **R10** (Shorts shelf in the last 7 days of June 2026) and **R11** (Trending category rankings in June 2026). Allows the query engine to scan only date-qualifying tuples via an index range scan rather than scanning the entire table.

---

## 4. Query R19 Optimization: Correlated Subquery Elimination

### Bottleneck Analysis
In the baseline execution plan (`benchmarks/results/baseline_raw/R19.txt`), query R19 took **24,278.224 ms** (over 24 seconds), accounting for **98.0% of the entire baseline workload execution time**.

The original query used two correlated scalar subqueries in the `SELECT` list:
```sql
SELECT c.channel_id, c.handle,
       (SELECT max(v.uploaded_at) FROM videos v WHERE v.channel_id = c.channel_id) AS last_upload,
       (SELECT count(*) FROM watch_events w JOIN videos v ON v.video_id = w.video_id
         WHERE v.channel_id = c.channel_id) AS total_views
FROM channels c
WHERE c.monetization_status = 'ELIGIBLE'
ORDER BY total_views DESC;
```
For each of the 1,087 `ELIGIBLE` channels, PostgreSQL executed:
- `SubPlan 1`: Scanned the 30,000 video rows in each of the 1,087 outer iterations, representing an approximate cumulative estimate of **~32.6 million row evaluations**.
- `SubPlan 2`: Joined the 200,000 watch event rows with the 30,000 video rows across the 1,087 iterations, representing an approximate cumulative estimate of **~217.4 million row evaluations**.
- Total buffer traffic exceeded **3.66 million shared buffer hits** (~28.6 GB memory touched).

### Rewritten Strategy (`sql/06_optimized_queries.sql`)
The query was rewritten into a set-based model that pre-aggregates videos and watch events once, joining the pre-aggregated results to channels:
```sql
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
```

### Correctness Verification
To ensure complete semantic equivalence:
- `LEFT JOIN` guarantees that channels with zero videos or zero views are not dropped from the report.
- `COALESCE(w_agg.total_views, 0)` preserves exact zero counts for channels with no views.
- `last_upload` remains `NULL` for channels without uploads, matching original subquery behavior.
- A bidirectional `EXCEPT ALL` query executed on `youtube_db` confirmed **0 row differences in both directions**.

### Measured Result
- **Baseline Time:** `24,278.224 ms`
- **Optimized Time:** `78.240 ms`
- **Improvement:** **+99.7% (310.3× faster)** on this test system.

---

## 5. Query R13 Correction: NULL-Handling in Subqueries

### Observed Defect on the Channel 217 Dataset
Query R13 is designed to find subscribers of channel 217 who have never watched any of its videos using `NOT IN`:
```sql
SELECT s.user_id, s.subscribed_at
FROM subscriptions s
WHERE s.channel_id = 217
  AND s.user_id NOT IN (SELECT w.user_id
                        FROM watch_events w JOIN videos v ON v.video_id = w.video_id
                        WHERE v.channel_id = 217);
```

In the seed dataset for channel 217:
- The subquery matches **97 watch event rows**, of which **24 rows have `user_id IS NULL`** (logged-out views).
- In SQL three-valued logic:
  - For subscribers who did watch channel 217, their `user_id` matches a non-NULL value in the subquery, making `IN` evaluate to `TRUE` and `NOT IN` evaluate to `FALSE` (correctly excluded).
  - For subscribers who did NOT watch channel 217, their `user_id` does not match any non-NULL value in the list, but when compared against the NULL entries (`s.user_id = NULL`), the equality evaluates to `UNKNOWN`. Because `NOT (UNKNOWN)` is `UNKNOWN`, the entire `WHERE` clause condition evaluates to `UNKNOWN` rather than `TRUE`.
- Consequently, every candidate subscriber was filtered out, causing the baseline query to erroneously return **0 rows**.

### Corrected Query (`sql/06_optimized_queries.sql`)
Replaced `NOT IN` with a correlated `NOT EXISTS`:
```sql
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
```

### Verification & Performance
- **Result:** The corrected query returns the 88 inactive subscribers (the baseline returned 0).
- **Classification:** This change is a correctness bug fix resolving NULL three-valued logic in `NOT IN`, rather than a pure performance optimization.
- **Execution Time:** Combined with `idx_subscriptions_channel_id` and `idx_watch_events_user_started`, execution time improved from **26.101 ms** to **4.748 ms** (**5.5× faster**).

---

## 6. Complete Workload Timing Comparison (All 30 Queries)

Exact measurements from `benchmarks/results/baseline_raw/summary.csv` and `benchmarks/results/optimized/summary.csv`:

| SQL Query | Type | Baseline (ms) | Optimized (ms) | Improvement | Optimized Scan Type |
|:---|:---:|---:|---:|:---:|:---|
| R01: Channel page: the 20 newest public videos of channel 217 | READ | 3.193 | 3.112 | +2.5% | Seq Scan on videos |
| R02: Watch page: one video with its channel | READ | 0.062 | 0.068 | -9.7% | Index Scan using pk_videos on videos \| Index Scan using pk_channels on channels |
| R03: Subscriptions feed: public videos from channels user 1042 subscribes to, newest first | READ | 5.348 | 5.195 | +2.9% | Seq Scan on videos \| Index Only Scan using pk_subscriptions on subscriptions \| Index Scan using pk_channels on channels |
| R04: Search: public videos with "tutorial" in the title, most viewed first | READ | 24.047 | 23.735 | +1.3% | Seq Scan on videos |
| R05: History page: the last 50 videos user 1042 watched | READ | 8.597 | 0.251 | **+97.1% (34.3×)** | Bitmap Heap Scan on watch_events \| Bitmap Index Scan on `idx_watch_events_user_started` \| Index Scan using pk_videos on videos |
| R06: Publishing service: videos scheduled to go live in the first week of July 2026 | READ | 3.596 | 3.421 | +4.9% | Seq Scan on videos |
| R07: YouTube Studio: channel 217's daily views and watch hours in June 2026 | READ | 17.332 | 17.140 | +1.1% | Seq Scan on watch_events \| Seq Scan on videos |
| R08: YouTube Studio: where views of video ZkNSlUB1EOs come from | READ | 9.905 | 9.752 | +1.5% | Seq Scan on watch_events |
| R09: YouTube Studio: average percentage watched for each of channel 217's videos | READ | 16.174 | 16.226 | -0.3% | Seq Scan on watch_events \| Seq Scan on videos |
| R10: Shorts shelf: most viewed Shorts in the last 7 days of June 2026 | READ | 17.359 | 5.276 | **+69.6% (3.3×)** | Index Scan using `idx_watch_events_started_at` on watch_events \| Seq Scan on videos |
| R11: Trending tab: top 5 videos per category by views in June 2026 | READ | 30.418 | 20.095 | **+33.9% (1.5×)** | Index Scan using `idx_watch_events_started_at` on watch_events \| Seq Scan on videos |
| R12: Growth: share of logged-out viewing per device type | READ | 22.774 | 23.656 | -3.9% | Seq Scan on watch_events |
| R13: Creator insights: subscribers of channel 217 who have never watched any of its videos | READ | 26.101 | 4.748 | **+81.8% (5.5×)** | Bitmap Heap Scan on subscriptions using `idx_subscriptions_channel_id` \| Index Scan using `idx_watch_events_user_started` on watch_events *(Correctness fix)* |
| R14: YouTube Studio: likes, dislikes and like ratio per video of channel 217 | READ | 16.403 | 16.810 | -2.5% | Seq Scan on video_reactions \| Seq Scan on videos |
| R15: Watch page: pinned comment and top 10 comments of video ZkNSlUB1EOs | READ | 4.126 | 4.098 | +0.7% | Seq Scan on comments |
| R16: Finance: ad revenue per channel in June 2026, top 20 | READ | 22.739 | 23.293 | -2.4% | Seq Scan on watch_events \| Seq Scan on ad_impressions \| Index Scan using pk_videos on videos |
| R17: Partner program: NOT_ELIGIBLE channels that now have 100+ subscribers and 40+ watch hours | READ | 24.775 | 24.871 | -0.4% | Seq Scan on watch_events \| Seq Scan on videos \| Seq Scan on channels |
| R18: Child safety: "made for kids" videos that still have comments | READ | 21.553 | 18.865 | +12.5% | Seq Scan on comments \| Seq Scan on videos |
| R19: Partner report: for every monetized channel, its latest upload and its total views | READ | 24278.224 | 78.240 | **+99.7% (310.3×)** | Seq Scan on watch_events \| Seq Scan on videos \| Seq Scan on channels *(Pre-aggregated joins)* |
| R20: Platform analytics: daily watch hours and running total for June 2026 | READ | 16.627 | 16.722 | -0.6% | Seq Scan on watch_events |
| R21: Playlist page: playlist 501 in order | READ | 0.131 | 0.113 | +13.7% | Index Scan using pk_playlist_items on playlist_items \| Index Scan using pk_videos on videos |
| R22: Copyright team: same title and duration uploaded by more than one channel | READ | 39.753 | 38.535 | +3.1% | Seq Scan on videos |
| R23: Moderation queue: all comments, newest first, page 1,201 (25 per page) | READ | 28.477 | 5.325 | **+81.3% (5.3×)** | Index Scan using `idx_comments_created_at_desc` on comments |
| R24: YouTube Studio: new subscribers per month for channel 217 | READ | 2.854 | 0.310 | **+89.1% (9.2×)** | Bitmap Heap Scan on subscriptions using `idx_subscriptions_channel_id` |
| R25: Premium audit: ads that were shown to users with an active Premium membership | READ | 70.088 | 67.645 | +3.5% | Seq Scan on watch_events \| Seq Scan on ad_impressions \| Seq Scan on users |
| W01: Upload: a new public video on channel 217 | WRITE | 1.021 | 0.856 | +16.2% | (no scan) |
| W02: Player: record a view of video ZkNSlUB1EOs by user 1042 | WRITE | 1.187 | 1.089 | +8.3% | (no scan) |
| W03: View counter: add one view to video ZkNSlUB1EOs | WRITE | 0.463 | 0.407 | +12.1% | Index Scan using pk_videos on videos |
| W04: Nightly job: recompute every channel's subscriber count | WRITE | 54.235 | 47.256 | +12.9% | Seq Scan on channels \| Seq Scan on subscriptions |
| W05: Publishing service: make scheduled videos public once their time has come | WRITE | 9.678 | 3.862 | +60.1% | Seq Scan on videos |
| **Workload Total (Sum of Averages)** | — | **24,777.240** | **480.972** | **+98.06% (51.5×)** | — |

---

## 7. Overall Workload Analysis

The total workload time (calculated as the direct sum of the average execution times for all 30 benchmark queries) dropped from **24,777.240 ms** to **480.972 ms**, representing an overall **51.5× speedup (98.06% reduction)** in total batch runtime on this test environment.

### Distribution of Workload Improvements
This 51.5× aggregate speedup is not a uniform across-the-board database speedup. The baseline sum of averages was heavily dominated by a single query: **R19**, which alone accounted for **98.0% of the baseline workload execution time**. Rewriting R19 from nested correlated subqueries into set-based pre-aggregated joins resolved this primary bottleneck.

Across the remaining 29 queries:
- Targeted indexes provided substantial gains for specific access paths (34.3× on R05, 9.2× on R24, 5.3× on R23, 3.3× on R10).
- Analytical queries requiring full-table scans (R12, R20, R22) and write transactions (W01–W03) showed expected minor fluctuations on this 200,000-row seed dataset.

---

## 8. Discussion of Queries with Minimal Change or Slight Variations

A subset of queries showed little to no change, or minor timing variations (<0.5 ms):
- **Full-Table Analytical Queries (R12, R20, R22):** 
  - `R12` (device view shares) and `R20` (daily June totals) must aggregate all rows across `watch_events`.
  - `R22` (duplicate uploads) groups and compares all 30,000 video records across the entire table. For whole-table aggregations without selective filters, sequential scans remain the optimal strategy.
- **Leading Wildcard Search (R04):**
  - `title ILIKE '%tutorial%'` cannot use standard B-tree indexes due to the leading wildcard. It continues to perform a sequential scan (~23.7 ms). Trigram GIN indexing (`pg_trgm`) is held as an evaluation candidate for later phases.
- **Unindexed Join Columns (R07, R09, R14, R16, R17):**
  - These queries join `watch_events` or `video_reactions` on `video_id` or `channel_id`. Because secondary indexes on those columns were omitted in this conservative index deployment to limit write overhead, these queries continue to perform sequential scans (~16–25 ms).
- **Minor Timing Variations (R02, R12, R14, R16):**
  - Fluctuations between baseline and optimized runs (e.g., R02 changing from 0.062 ms to 0.068 ms, or R12 from 22.77 ms to 23.66 ms) reflect normal operating system CPU scheduling and buffer cache jitter, rather than structural regressions.

---

## 9. Write Observations and Index Overhead

Every secondary index added to a relational table introduces overhead on write operations (`INSERT`, `UPDATE`, `DELETE`) because the database engine must maintain the index B-tree nodes and generate additional WAL records.

### Observations from the Three Benchmark Runs:
- **`W01` (Video Upload):** `1.021 ms` → `0.856 ms`. No new indexes were added to `videos`, so upload performance remained fast and unchanged.
- **`W02` (Watch Event Ingestion):** `1.187 ms` → `1.089 ms`. Two new indexes were added to `watch_events` (`idx_watch_events_user_started` and `idx_watch_events_started_at`). Across the three benchmark runs, `W02` execution time remained around ~1.09 ms, within real-time targets (<5 ms).
- **`W03` (View Counter Increment):** `0.463 ms` → `0.407 ms`. Single-row indexed update on primary key.
- **`W04` (Subscriber Count Batch Recomputation):** `54.235 ms` → `47.256 ms`. Full-table aggregation across subscriptions and channel updates remained consistent.
- **`W05` (Publishing Service Status Update):** `9.678 ms` → `3.862 ms`.

### Write Overhead Considerations
While write execution times remained fast across three controlled benchmark runs on the 200,000-row seed dataset, this does not imply that index overhead is negligible in production. Under high-concurrency ingestion or at larger scales, maintaining multiple secondary indexes on `watch_events` will increase write amplification and WAL volume. Limiting modifications to four high-selectivity indexes keeps write degradation contained.

---

## 10. Limitations & Scalability Implications

1. **R23 and Offset Pagination:**
   - The index `idx_comments_created_at_desc` eliminated the 3.6 MB disk spill and reduced execution time from `28.5 ms` to `5.3 ms`.
   - **Pagination Boundary:** While the index eliminates sorting, it **does not eliminate OFFSET traversal**. With `OFFSET 30000`, PostgreSQL must still scan through the first 30,000 index leaf entries before returning the 25 requested tuples. At larger scales where offsets could reach `OFFSET 600000`, performance will degrade unless keyset pagination (`WHERE created_at < :last_seen`) is adopted.
2. **Missing Search Indexing (R04):**
   - Wildcard text search remains unoptimized until a trigram GIN index (`pg_trgm`) is evaluated.
3. **Projected 20× Dataset Growth (Phase 5 Assumption):**
   - The upcoming Phase 5 scalability evaluation assumes approximately 20× volume growth (~4,000,000 watch events).
   - This 20× growth is an anticipated testing milestone, not a currently measured reality. At that scale, analytical reporting over monthly windows (R07, R11, R16) will require architectural adjustments such as table partitioning by date range (`RANGE (started_at)`) to enable partition pruning.

---
*Report compiled from verified local benchmark data in `benchmarks/results/baseline_raw/` and `benchmarks/results/optimized/`.*
