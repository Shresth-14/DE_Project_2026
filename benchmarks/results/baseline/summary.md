# Baseline Benchmark Summary (Checkpoint 2)

**Phase:** Baseline (Original Checkpoint 2 submission)  
**Database:** `youtube_db` | **Schema:** `youtube`  
**Workload:** `queries/workload_30.sql` (30 queries: 25 reads, 5 writes)  
**Runs:** 3 consecutive runs per query with `EXPLAIN (ANALYZE, BUFFERS)`  
**Environment:** Untuned schema (only 14 constraint-backed primary key and unique indexes present)

---

## Methodology

Each query was executed 3 times using `./benchmarks/run_benchmark.sh`. The arithmetic mean of the three runs is reported as `avg_ms`. Write operations (`W01` through `W05`) were executed inside `BEGIN ... ROLLBACK;` blocks to ensure the database state remained unchanged across runs.

This summary reflects the original baseline benchmark committed for Checkpoint 2 and documented in `docs/03_baseline_timings.md`.

---

## Results Table

| Query | Type | Avg Time (ms) | Median (ms) | Min (ms) | Max (ms) | Scan Nodes / Plan Observations |
|:---|:---:|---:|---:|---:|---:|:---|
| **R01** | READ | 11.996 | 2.514 | 1.874 | 31.599 | Seq Scan on videos (no index on channel_id) |
| **R02** | READ | 0.394 | 0.066 | 0.034 | 1.081 | Index Scan using pk_videos on videos \| Index Scan using pk_channels on channels |
| **R03** | READ | 5.060 | 4.150 | 3.735 | 7.296 | Seq Scan on videos \| Index Only Scan using pk_subscriptions on subscriptions \| Index Scan using pk_channels on channels |
| **R04** | READ | 17.283 | 17.677 | 15.885 | 18.286 | Seq Scan on videos (wildcard ILIKE '%tutorial%' requires full table scan) |
| **R05** | READ | 36.943 | 7.781 | 7.659 | 95.389 | Seq Scan on watch_events \| Index Scan using pk_videos on videos |
| **R06** | READ | 2.774 | 2.756 | 2.405 | 3.162 | Seq Scan on videos |
| **R07** | READ | 12.487 | 12.103 | 11.621 | 13.737 | Seq Scan on watch_events \| Seq Scan on videos |
| **R08** | READ | 6.185 | 6.109 | 6.043 | 6.402 | Seq Scan on watch_events (no index on video_id) |
| **R09** | READ | 12.021 | 12.410 | 10.642 | 13.012 | Seq Scan on watch_events \| Seq Scan on videos |
| **R10** | READ | 10.001 | 10.307 | 9.124 | 10.572 | Seq Scan on watch_events \| Seq Scan on videos |
| **R11** | READ | 16.185 | 16.082 | 15.843 | 16.629 | Seq Scan on watch_events \| Seq Scan on videos |
| **R12** | READ | 13.379 | 13.452 | 13.034 | 13.651 | Seq Scan on watch_events |
| **R13** | READ | 28.692 | 15.165 | 13.571 | 57.341 | Index Scan on subscriptions \| Seq Scan on watch_events & videos (returns 0 rows due to NULL user_id bug) |
| **R14** | READ | 13.521 | 9.349 | 9.220 | 21.994 | Seq Scan on video_reactions \| Seq Scan on videos |
| **R15** | READ | 10.381 | 2.168 | 2.166 | 26.810 | Seq Scan on comments |
| **R16** | READ | 26.852 | 20.361 | 16.793 | 43.402 | Seq Scan on watch_events \| Seq Scan on ad_impressions \| Index Scan using pk_videos on videos |
| **R17** | READ | 15.316 | 14.363 | 13.890 | 17.696 | Seq Scan on watch_events \| Seq Scan on videos \| Seq Scan on channels |
| **R18** | READ | 10.878 | 10.845 | 10.783 | 11.007 | Seq Scan on comments \| Seq Scan on videos |
| **R19** | READ | 13179.349 | 13183.033 | 13075.552 | 13279.463 | Seq Scan on channels \| Seq Scan on videos \| Seq Scan on watch_events (correlated subqueries executed 1,087 times) |
| **R20** | READ | 8.581 | 8.515 | 8.443 | 8.785 | Seq Scan on watch_events |
| **R21** | READ | 0.436 | 0.069 | 0.065 | 1.174 | Index Scan using pk_playlist_items on playlist_items \| Index Scan using pk_videos on videos |
| **R22** | READ | 20.440 | 20.421 | 20.365 | 20.534 | Seq Scan on videos (whole-table grouping) |
| **R23** | READ | 13.834 | 13.703 | 13.578 | 14.222 | Seq Scan on comments (external merge sort) |
| **R24** | READ | 1.440 | 1.305 | 1.297 | 1.717 | Index Scan using pk_subscriptions on subscriptions |
| **R25** | READ | 38.145 | 31.135 | 30.026 | 53.274 | Seq Scan on watch_events \| Seq Scan on ad_impressions \| Seq Scan on users |
| **W01** | WRITE | 1.449 | 0.428 | 0.404 | 3.515 | (no scan) Single-row insert into videos |
| **W02** | WRITE | 0.940 | 0.474 | 0.467 | 1.878 | (no scan) Single-row insert into watch_events |
| **W03** | WRITE | 0.513 | 0.193 | 0.188 | 1.158 | Index Scan using pk_videos on videos |
| **W04** | WRITE | 44.364 | 36.670 | 33.482 | 62.941 | Seq Scan on channels \| Seq Scan on subscriptions |
| **W05** | WRITE | 2.061 | 2.046 | 2.022 | 2.114 | Seq Scan on videos |
| **Total** | — | **13,561.900** | — | — | — | Sum of average execution times across all 30 queries |

---

## Key Observations

1. **R19 Dominance:** Query R19 alone accounts for 13,179.349 ms out of the 13,561.900 ms workload total (97.2%). The bottleneck is structural: two scalar correlated subqueries re-scan `videos` and `watch_events` for each of the 1,087 `ELIGIBLE` channels.
2. **Missing Secondary Indexes:** Because only constraints were indexed in Phase 2, queries filtering on foreign keys (`watch_events.user_id`, `watch_events.video_id`, `videos.channel_id`, `subscriptions.channel_id`) or date ranges fall back to full table scans.
3. **Semantic Bug in R13:** Query R13 returned 0 rows because `NOT IN` against a subquery containing NULLs evaluates to `UNKNOWN` in SQL three-valued logic.
