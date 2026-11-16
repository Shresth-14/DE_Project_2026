# Optimized Benchmark Summary (Checkpoint 3 / Phase 4)

**Phase:** Optimized (Checkpoint 3 post-optimization benchmark)  
**Database:** `youtube_db` | **Schema:** `youtube`  
**Workload:** `sql/06_optimized_queries.sql` (30 queries: 25 reads, 5 writes)  
**Indexes Applied:** 4 selective B-tree indexes defined in `sql/05_indexes.sql`  
**Runs:** 3 consecutive runs per query with `EXPLAIN (ANALYZE, BUFFERS)`  
**Environment:** Fully indexed and analyzed schema; raw execution plans saved in `R01.txt` through `W05.txt`

---

## Methodology

- Executed via `./benchmarks/run_benchmark.sh youtube_db optimized 3 sql/06_optimized_queries.sql`.
- Each query was executed 3 times with `EXPLAIN (ANALYZE, BUFFERS)`.
- Full execution plans for all 3 runs are preserved in `R01.txt` through `W05.txt`.
- Write queries (`W01`–`W05`) were executed inside `BEGIN ... ROLLBACK;` blocks to ensure mutations were rolled back.
- Reported numbers represent the arithmetic mean (`avg_ms`) of the three runs.

---

## Key Optimization Highlights

### 1. R19 Correlated Subquery Rewrite (310.3× Speedup)
- **Baseline:** `24,278.224 ms` → **Optimized:** `78.240 ms` (**+99.7% reduction**).
- **Mechanism:** In the baseline, two correlated scalar subqueries executed for each of the 1,087 eligible channels (`loops=1087`), repeatedly scanning `videos` and `watch_events`. The rewrite pre-aggregates video uploads and view counts in joined subqueries, executing each aggregation exactly once. Semantics and edge cases (channels with 0 uploads or 0 views) are preserved using `LEFT JOIN` and `COALESCE`.

### 2. R13 Correctness Fix & Speedup (5.5× Speedup)
- **Baseline:** `26.101 ms` (returning **0 rows**, incorrect) → **Optimized:** `4.748 ms` (returning the true **88 inactive subscribers**).
- **Mechanism:** The baseline query used `NOT IN (SELECT w.user_id ...)`. Because `watch_events` contains logged-out views where `user_id IS NULL`, SQL three-valued logic evaluated `s.user_id NOT IN (..., NULL)` to `UNKNOWN`, filtering out all candidates. Rewriting with correlated `NOT EXISTS` correctly handles NULLs while `idx_subscriptions_channel_id` and `idx_watch_events_user_started` accelerate lookup execution.

### 3. Significant Index-Driven Improvements
- **R05 (User Watch History):** `8.597 ms` → `0.251 ms` (**34.3× faster**) via `idx_watch_events_user_started (user_id, started_at DESC)`. Direct index seek retrieves pre-sorted tuples without a sort step.
- **R24 (Studio Monthly Subscriptions):** `2.854 ms` → `0.310 ms` (**9.2× faster**) via `idx_subscriptions_channel_id (channel_id)`. Bypasses full index scans of the composite primary key.
- **R23 (Moderation Queue Pagination):** `28.477 ms` → `5.325 ms` (**5.3× faster**) via `idx_comments_created_at_desc (created_at DESC)`. Eliminates the full sequential scan and the 3.6 MB disk sort spill.
- **R10 (Shorts Shelf - Last 7 Days):** `17.359 ms` → `5.276 ms` (**3.3× faster**) via `idx_watch_events_started_at (started_at)` range scans.
- **R11 (Trending Rankings - June 2026):** `30.418 ms` → `20.095 ms` (**1.5× faster**) via `idx_watch_events_started_at (started_at)` date filtering.

---

## Results Table

| Query | Type | Avg Time (ms) | Median (ms) | Min (ms) | Max (ms) | Scan Nodes / Plan Observations |
|:---|:---:|---:|---:|---:|---:|:---|
| **R01** | READ | 3.112 | 3.045 | 2.935 | 3.357 | Seq Scan on videos |
| **R02** | READ | 0.068 | 0.064 | 0.061 | 0.079 | Index Scan using pk_videos on videos \| Index Scan using pk_channels on channels |
| **R03** | READ | 5.195 | 5.132 | 5.129 | 5.323 | Seq Scan on videos \| Index Only Scan using pk_subscriptions on subscriptions \| Index Scan using pk_channels on channels |
| **R04** | READ | 23.735 | 23.704 | 23.607 | 23.894 | Seq Scan on videos (wildcard search ILIKE '%tutorial%') |
| **R05** | READ | 0.251 | 0.117 | 0.104 | 0.532 | Bitmap Heap Scan on watch_events \| Bitmap Index Scan on `idx_watch_events_user_started` \| Index Scan using pk_videos on videos |
| **R06** | READ | 3.421 | 3.478 | 3.290 | 3.495 | Seq Scan on videos |
| **R07** | READ | 17.140 | 17.111 | 16.956 | 17.354 | Seq Scan on watch_events \| Seq Scan on videos |
| **R08** | READ | 9.752 | 9.684 | 9.623 | 9.949 | Seq Scan on watch_events |
| **R09** | READ | 16.226 | 16.198 | 16.163 | 16.318 | Seq Scan on watch_events \| Seq Scan on videos |
| **R10** | READ | 5.276 | 4.859 | 4.765 | 6.203 | Index Scan using `idx_watch_events_started_at` on watch_events \| Seq Scan on videos |
| **R11** | READ | 20.095 | 20.144 | 19.987 | 20.153 | Index Scan using `idx_watch_events_started_at` on watch_events \| Seq Scan on videos |
| **R12** | READ | 23.656 | 23.866 | 22.548 | 24.553 | Seq Scan on watch_events (full-table aggregation) |
| **R13** | READ | 4.748 | 2.600 | 2.569 | 9.076 | Bitmap Heap Scan on subscriptions using `idx_subscriptions_channel_id` \| Index Scan using `idx_watch_events_user_started` on watch_events (Correctness fix: 88 rows) |
| **R14** | READ | 16.810 | 16.843 | 16.667 | 16.919 | Seq Scan on video_reactions \| Seq Scan on videos |
| **R15** | READ | 4.098 | 4.042 | 4.022 | 4.229 | Seq Scan on comments |
| **R16** | READ | 23.293 | 23.797 | 22.097 | 23.984 | Seq Scan on watch_events \| Seq Scan on ad_impressions \| Index Scan using pk_videos on videos |
| **R17** | READ | 24.871 | 24.816 | 24.648 | 25.149 | Seq Scan on watch_events \| Seq Scan on videos \| Seq Scan on channels |
| **R18** | READ | 18.865 | 18.830 | 18.548 | 19.217 | Seq Scan on comments \| Seq Scan on videos |
| **R19** | READ | 78.240 | 77.919 | 77.210 | 79.592 | Seq Scan on watch_events \| Seq Scan on videos \| Seq Scan on channels (pre-aggregated set-based joins) |
| **R20** | READ | 16.722 | 16.661 | 16.530 | 16.975 | Seq Scan on watch_events |
| **R21** | READ | 0.113 | 0.113 | 0.111 | 0.114 | Index Scan using pk_playlist_items on playlist_items \| Index Scan using pk_videos on videos |
| **R22** | READ | 38.535 | 38.536 | 37.501 | 39.569 | Seq Scan on videos |
| **R23** | READ | 5.325 | 5.030 | 4.971 | 5.973 | Index Scan using `idx_comments_created_at_desc` on comments (sort eliminated) |
| **R24** | READ | 0.310 | 0.301 | 0.294 | 0.336 | Bitmap Heap Scan on subscriptions using `idx_subscriptions_channel_id` |
| **R25** | READ | 67.645 | 67.738 | 66.559 | 68.639 | Seq Scan on watch_events \| Seq Scan on ad_impressions \| Seq Scan on users |
| **W01** | WRITE | 0.856 | 0.822 | 0.804 | 0.941 | (no scan) |
| **W02** | WRITE | 1.089 | 1.036 | 0.991 | 1.240 | (no scan) |
| **W03** | WRITE | 0.407 | 0.405 | 0.401 | 0.415 | Index Scan using pk_videos on videos |
| **W04** | WRITE | 47.256 | 48.595 | 41.150 | 52.022 | Seq Scan on channels \| Seq Scan on subscriptions |
| **W05** | WRITE | 3.862 | 3.821 | 3.766 | 3.999 | Seq Scan on videos |
| **Total** | — | **480.972** | — | — | — | Sum of average execution times across all 30 queries (51.5× speedup vs baseline_raw) |
