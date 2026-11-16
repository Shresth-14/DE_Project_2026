# Local Baseline Benchmark Summary (Pre-Optimization)

**Phase:** Local Pre-Optimization Baseline (Comparative Baseline for Checkpoint 3)  
**Database:** `youtube_db` | **Schema:** `youtube`  
**Workload:** `queries/workload_30.sql` (30 queries: 25 reads, 5 writes)  
**Runs:** 3 consecutive runs per query with `EXPLAIN (ANALYZE, BUFFERS)`  
**Environment:** Untuned schema before applying Phase 4 indexes or rewrites; full execution plan files preserved in `R01.txt` through `W05.txt`

---

## Role and Context

This directory contains the local, pre-optimization baseline executed in the exact local environment immediately before applying the Checkpoint 3 optimizations (`sql/05_indexes.sql` and `sql/06_optimized_queries.sql`). 

To ensure fair, hardware-identical comparisons in `docs/04_optimization_report.md`, these measurements serve as the authoritative "before" baseline against which the post-optimization results in `benchmarks/results/optimized/` are evaluated.

---

## Methodology

- Executed via `./benchmarks/run_benchmark.sh youtube_db baseline_raw 3 queries/workload_30.sql`.
- Each query was run 3 times with `EXPLAIN (ANALYZE, BUFFERS)`.
- Full execution plans for all 3 runs of every query are stored in `R01.txt` through `W05.txt`.
- Write queries (`W01`–`W05`) ran inside `BEGIN ... ROLLBACK;` blocks to preserve state.
- The average execution time across all 3 runs is reported as `avg_ms`.

---

## Results Table

| Query | Type | Avg Time (ms) | Median (ms) | Min (ms) | Max (ms) | Scan Nodes / Plan Observations |
|:---|:---:|---:|---:|---:|---:|:---|
| **R01** | READ | 3.193 | 3.044 | 2.788 | 3.746 | Seq Scan on videos |
| **R02** | READ | 0.062 | 0.060 | 0.060 | 0.067 | Index Scan using pk_videos on videos \| Index Scan using pk_channels on channels |
| **R03** | READ | 5.348 | 5.296 | 5.240 | 5.508 | Seq Scan on videos \| Index Only Scan using pk_subscriptions on subscriptions \| Index Scan using pk_channels on channels |
| **R04** | READ | 24.047 | 23.968 | 23.779 | 24.393 | Seq Scan on videos (wildcard search '%tutorial%') |
| **R05** | READ | 8.597 | 8.610 | 8.551 | 8.631 | Seq Scan on watch_events \| Index Scan using pk_videos on videos |
| **R06** | READ | 3.596 | 3.588 | 3.587 | 3.614 | Seq Scan on videos |
| **R07** | READ | 17.332 | 17.377 | 17.214 | 17.405 | Seq Scan on watch_events \| Seq Scan on videos |
| **R08** | READ | 9.905 | 9.982 | 9.499 | 10.234 | Seq Scan on watch_events (no secondary index on video_id) |
| **R09** | READ | 16.174 | 16.084 | 16.078 | 16.360 | Seq Scan on watch_events \| Seq Scan on videos |
| **R10** | READ | 17.359 | 17.011 | 16.877 | 18.188 | Seq Scan on watch_events \| Seq Scan on videos |
| **R11** | READ | 30.418 | 30.018 | 29.553 | 31.683 | Seq Scan on watch_events \| Seq Scan on videos |
| **R12** | READ | 22.774 | 22.737 | 22.662 | 22.924 | Seq Scan on watch_events |
| **R13** | READ | 26.101 | 25.973 | 25.785 | 26.546 | Index Scan on subscriptions \| Seq Scan on watch_events & videos (returns 0 rows due to NULLs in NOT IN) |
| **R14** | READ | 16.403 | 16.429 | 16.297 | 16.482 | Seq Scan on video_reactions \| Seq Scan on videos |
| **R15** | READ | 4.126 | 4.112 | 3.992 | 4.275 | Seq Scan on comments |
| **R16** | READ | 22.739 | 22.714 | 22.224 | 23.280 | Seq Scan on watch_events \| Seq Scan on ad_impressions \| Index Scan using pk_videos on videos |
| **R17** | READ | 24.775 | 24.710 | 24.677 | 24.939 | Seq Scan on watch_events \| Seq Scan on videos \| Seq Scan on channels |
| **R18** | READ | 21.553 | 18.989 | 18.985 | 26.686 | Seq Scan on comments \| Seq Scan on videos |
| **R19** | READ | 24278.224 | 24153.110 | 24144.770 | 24536.791 | Seq Scan on channels \| Seq Scan on videos \| Seq Scan on watch_events (correlated subqueries, loops=1087) |
| **R20** | READ | 16.627 | 16.548 | 16.379 | 16.954 | Seq Scan on watch_events |
| **R21** | READ | 0.131 | 0.130 | 0.129 | 0.133 | Index Scan using pk_playlist_items on playlist_items \| Index Scan using pk_videos on videos |
| **R22** | READ | 39.753 | 39.665 | 39.048 | 40.545 | Seq Scan on videos (whole-table grouping) |
| **R23** | READ | 28.477 | 27.455 | 25.449 | 32.527 | Seq Scan on comments (external merge sort with 3.6 MB disk spill) |
| **R24** | READ | 2.854 | 2.966 | 2.570 | 3.025 | Index Scan using pk_subscriptions on subscriptions |
| **R25** | READ | 70.088 | 63.454 | 63.207 | 83.604 | Seq Scan on watch_events \| Seq Scan on ad_impressions \| Seq Scan on users |
| **W01** | WRITE | 1.021 | 0.910 | 0.907 | 1.247 | (no scan) |
| **W02** | WRITE | 1.187 | 1.179 | 1.050 | 1.333 | (no scan) |
| **W03** | WRITE | 0.463 | 0.469 | 0.438 | 0.481 | Index Scan using pk_videos on videos |
| **W04** | WRITE | 54.235 | 54.701 | 45.708 | 62.297 | Seq Scan on channels \| Seq Scan on subscriptions |
| **W05** | WRITE | 9.678 | 4.122 | 3.851 | 21.060 | Seq Scan on videos |
| **Total** | — | **24,777.240** | — | — | — | Sum of average execution times across all 30 queries |

---

## Performance Profile Summary

1. **Dominant Bottleneck:** Query R19 consumed **24,278.224 ms** out of the **24,777.240 ms** total workload runtime (**98.0%**), driven by executing nested scalar subqueries for each of the 1,087 eligible channels.
2. **Sort Overhead on R23:** Query R23 required a full sequential scan and an external disk merge sort (spilling ~3,656 kB to temporary disk files) to sort 60,000 comments before offset pagination.
3. **Correctness Defect in R13:** Due to NULL entries in `watch_events.user_id`, `NOT IN` returned 0 rows instead of identifying inactive subscribers.
