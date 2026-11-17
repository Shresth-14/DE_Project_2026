# Checkpoint 4 (CP4) / Phase 5: Scalability Report

**Team T0066** | **Database:** PostgreSQL 17 | **Database Name:** `youtube_large`

---

## 1. Test Environment & Setup

### Seed vs Large Dataset

| Table | Seed rows | Large rows (≈20×) | Growth factor |
|-------|----------:|---------:|:---:|
| `users` | 30,000 | ~600,000 | 20× |
| `channels` | 3,000 | ~60,000 | 20× |
| `videos` | 30,000 | ~600,000 | 20× |
| `subscriptions` | 129,253 | ~2,585,000 | 20× |
| `watch_events` | 200,000 | ~4,000,000 | 20× |
| `video_reactions` | 67,417 | ~1,350,000 | 20× |
| `comments` | 60,000 | ~1,200,000 | 20× |
| `playlists` | 8,000 | ~160,000 | 20× |
| `playlist_items` | 56,005 | ~1,120,000 | 20× |
| `ad_impressions` | 57,014 | ~1,140,000 | 20× |

### Setup Procedure
```bash
createdb youtube_large
psql -d youtube_large -f sql/01_schema.sql
# Edit 02_load_data.sql: change 'seed_data/' to 'large_data/'
psql -d youtube_large -f sql/02_load_data.sql
psql -d youtube_large -f sql/08_partitioning.sql   # partition watch_events
psql -d youtube_large -f sql/05_indexes.sql
psql -d youtube_large -c "SET search_path TO youtube; ANALYZE;"
./benchmarks/run_benchmark.sh youtube_large large 3 sql/06_optimized_queries.sql
```

---

## 2. Results Table

### Performance Targets

| Query group | Queries | Target |
|-------------|---------|-------:|
| Real-time / viewer-facing | R01, R02, R03, R05, R15, R21, W01, W02, W03 | **< 5 ms** |
| Interactive Studio / search | R04, R06, R07, R08, R09, R13, R14, R24, W05 | **< 250 ms** |
| Reports and analytics | R10, R11, R12, R16, R17, R18, R19, R20, R22, R23, R25 | **< 5,000 ms** |
| Batch jobs | W04 | **< 2,000 ms** |

### Timing Comparison

> ⏳ **Large-data columns below are projections based on algorithmic growth analysis.** Replace with actual measurements from `benchmarks/results/large/summary.csv` once `large_data.zip` is available and benchmarks have been run.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what changed |
|:------|---:|---:|---:|:---:|:---|
| R01 | 3.112 | ⏳ | ⏳ | ⏳ | If > 5 ms: add `idx_videos_channel_vis_pub` (see §3.2) |
| R02 | 0.068 | ⏳ | ⏳ | ⏳ | PK lookup — expected ✅ |
| R03 | 5.195 | ⏳ | ⏳ | ⏳ | If > 5 ms: add `idx_videos_channel_vis_pub` |
| R04 | 23.735 | ⏳ | ⏳ | ⏳ | If > 250 ms: add GIN trigram index (see §3.2) |
| R05 | 0.251 | ⏳ | ⏳ | ⏳ | Index seek + LIMIT 50 — expected ✅ |
| R06 | 3.421 | ⏳ | ⏳ | ⏳ | Partial index on SCHEDULED — expected ✅ |
| R07 | 17.140 | ⏳ | ⏳ | ⏳ | If > 250 ms: partition pruning + sargable rewrite (see §3.3) |
| R08 | 9.752 | ⏳ | ⏳ | ⏳ | If > 250 ms: add `idx_watch_events_video_id` |
| R09 | 16.226 | ⏳ | ⏳ | ⏳ | If > 250 ms: add `idx_watch_events_video_id` |
| R10 | 5.276 | ⏳ | ⏳ | ⏳ | Partition pruning helps — expected ✅ |
| R11 | 20.095 | ⏳ | ⏳ | ⏳ | Partition pruning — expected ✅ |
| R12 | 23.656 | ⏳ | ⏳ | ⏳ | Full-table agg, linear growth — expected ✅ |
| R13 | 4.748 | ⏳ | ⏳ | ⏳ | Index anti-join — expected ✅ |
| R14 | 16.810 | ⏳ | ⏳ | ⏳ | If > 250 ms: add `idx_video_reactions_video_id` |
| R15 | 4.098 | ⏳ | ⏳ | ⏳ | If > 5 ms: add `idx_comments_video_parent` (see §3.2) |
| R16 | 23.293 | ⏳ | ⏳ | ⏳ | Partition pruning on join — expected ✅ |
| R17 | 24.871 | ⏳ | ⏳ | ⏳ | Pre-filter via sub count — expected ✅ |
| R18 | 18.865 | ⏳ | ⏳ | ⏳ | EXISTS semi-join — expected ✅ |
| R19 | 78.240 | ⏳ | ⏳ | ⏳ | Pre-aggregated, linear growth — expected ✅ |
| R20 | 16.722 | ⏳ | ⏳ | ⏳ | Sargable rewrite + partition prune — expected ✅ |
| R21 | 0.113 | ⏳ | ⏳ | ⏳ | PK lookup — expected ✅ |
| R22 | 38.535 | ⏳ | ⏳ | ⏳ | Full-table group — expected ✅ |
| R23 | 5.325 | ⏳ | ⏳ | ⏳ | Index scan, OFFSET unchanged — expected ✅ |
| R24 | 0.310 | ⏳ | ⏳ | ⏳ | Bitmap index seek — expected ✅ |
| R25 | 67.645 | ⏳ | ⏳ | ⏳ | 3-way join, linear — expected ✅ |
| W01 | 0.856 | ⏳ | ⏳ | ⏳ | Single INSERT — expected ✅ |
| W02 | 1.089 | ⏳ | ⏳ | ⏳ | Single INSERT, partition-routed — expected ✅ |
| W03 | 0.407 | ⏳ | ⏳ | ⏳ | PK point update — expected ✅ |
| W04 | 47.256 | ⏳ | ⏳ | ⏳ | Full scan subs — expected ✅ if < 2,000 ms |
| W05 | 3.862 | ⏳ | ⏳ | ⏳ | Partial scan SCHEDULED — expected ✅ |

---

## 3. Growth Analysis

### 3.1 Queries grouped by expected scaling behaviour

#### Group A: Stayed about the same (O(log n) — index lookups, LIMIT cuts early)

| Query | Why |
|-------|-----|
| R02 | PK lookup on `videos` + PK lookup on `channels`. Both are B-tree seeks: O(log n). Going from 30k to 600k videos adds ~4 more B-tree levels, adding microseconds. |
| R05 | B-tree index seek on `idx_watch_events_user_started(user_id, started_at DESC)` → returns pre-sorted rows for one user, stops at LIMIT 50. Time is proportional to the number of watches by user 1042, not the table size. |
| R21 | PK lookup on `playlist_items(playlist_id, position)` → at most ~7 rows for playlist 501. O(log n). |
| R24 | Bitmap Index Scan on `idx_subscriptions_channel_id` for channel 217 → returns ~92 rows regardless of total table size. O(log n + k) where k is the match count per channel. |
| W01 | Single INSERT into `videos`. B-tree PK insertion: O(log n). |
| W02 | Single INSERT into `watch_events`. With partitioning, routes to one partition. O(log n). |
| W03 | Single-row PK UPDATE on `videos`. O(log n). |

#### Group B: Grew about 20× (linear scans of the full table or a fixed share)

| Query | Why |
|-------|-----|
| R01 | Seq Scan on `videos` with filter `channel_id = 217 AND visibility = 'PUBLIC'`. Scans all video rows; 20× more rows ≈ 20× more time. |
| R03 | Seq Scan on `videos` joined to subscriptions. The subscription lookup is indexed, but the video scan is not. ~20× growth from videos. |
| R04 | Seq Scan with `ILIKE '%tutorial%'` on `videos`. Full-table scan; linear growth. |
| R06 | Seq Scan on `videos` with filter `visibility = 'SCHEDULED'`. Linear. |
| R07 | Seq Scan on `watch_events` joined to `videos`. Without partitioning scans all watch events; with partitioning prunes to June 2026 partition (~1/18 of data). Growth ~20× without pruning, ~20×/18 ≈ 1.1× with pruning. |
| R08 | Seq Scan on `watch_events` filtering `video_id = 'ZkNSlUB1EOs'`. Linear without an index. |
| R09 | Seq Scan on `watch_events` × `videos` for channel 217. Linear in watch_events size. |
| R10 | Index range on `started_at ≥ '2026-06-24'`. Proportional to rows in that range; with partitioning, pruned to June 2026 partition. |
| R11 | Index range on `started_at ≥ '2026-06-01'`. Similar to R10 but broader. |
| R12 | Full-table aggregation of `watch_events` by device. Linear — must read every row. |
| R14 | Seq Scan on `video_reactions` joined to `videos`. Both grow 20×. |
| R15 | Seq Scan on `comments` filtering `video_id`. Linear in comments count. |
| R16 | 3-way join `ad_impressions` × `watch_events` × `videos` with date filter. Linear with partitioning; without, proportional to full join. |
| R17 | 3-way join filtering `NOT_ELIGIBLE` channels. Linear. |
| R18 | EXISTS semi-join `videos` × `comments`. Linear in made-for-kids video count. |
| R19 | Pre-aggregated set-based join (rewritten in CP3). Full scans of `watch_events`, `videos`, `channels`. Linear. |
| R20 | Seq Scan on `watch_events` for June. With partitioning, pruned to one partition. |
| R22 | Full GROUP BY on `videos`. Linear. |
| R23 | Index Scan with `OFFSET 30000`. The offset is fixed at 30,000 regardless of table size; the index eliminates the sort. Time grows sublinearly: traversing 30k index entries is fast regardless of total comment count. |
| R25 | 3-way join `ad_impressions` × `watch_events` × `users`. Linear. |
| W04 | Full scan of `subscriptions` + UPDATE all `channels`. Linear in subscriptions count. |
| W05 | Seq Scan on `videos` filtering SCHEDULED. Linear but SCHEDULED is rare. |

#### Group C: Could grow more than 20× (non-linear effects at scale)

| Query | Why | Mitigation |
|-------|-----|------------|
| R13 | Anti-join `NOT EXISTS` between subscriptions and watch_events. With 20× more watch events and 20× more subscriptions, the nested loop anti-join may become quadratic for channels with many subscribers. | The correlated `NOT EXISTS` already uses the index on `watch_events(user_id, started_at DESC)`, limiting it to O(subs × log(watches)). If needed, convert to a hash anti-join with `LEFT JOIN ... WHERE w.watch_id IS NULL`. |
| R19 (original) | The correlated subquery version would have been catastrophic: 20× channels × 20× videos × 20× watches = 8,000× growth. | Already rewritten to set-based pre-aggregation in CP3. Now grows linearly. |
| R25 | 3-way hash join. If `ad_impressions` (1.14M) × `watch_events` (4M) hash table exceeds `work_mem`, it spills to disk, causing super-linear slowdown. | Increase `work_mem` for the session or add `idx_ad_impressions_watch_id` to convert to indexed nested loop. |

### 3.2 Anticipated fixes: additional indexes for the large dataset

If benchmarks confirm the following queries miss their targets, these indexes should be added to `sql/05_indexes.sql`:

```sql
-- R01, R03: Channel page & subscriptions feed (target: < 5 ms)
-- Composite index allows Index Scan by channel_id + visibility filter,
-- pre-sorted by published_at DESC for the ORDER BY + LIMIT.
CREATE INDEX idx_videos_channel_vis_pub
ON videos (channel_id, visibility, published_at DESC);

-- R15: Watch page comments (target: < 5 ms)
-- Covers the WHERE clause (video_id, parent_comment_id IS NULL) and
-- supports the ORDER BY (is_pinned DESC, like_count DESC) + LIMIT 11.
CREATE INDEX idx_comments_video_parent
ON comments (video_id)
WHERE parent_comment_id IS NULL;

-- R04: Search by title (target: < 250 ms)
-- GIN trigram index enables indexed ILIKE '%tutorial%' searches.
-- Requires: CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_videos_title_trgm
ON videos USING gin (title gin_trgm_ops);

-- R07, R08, R09: Studio charts and traffic sources (target: < 250 ms)
-- Enables index lookups on watch_events by video_id instead of seq scan.
CREATE INDEX idx_watch_events_video_id
ON watch_events (video_id);

-- R14: Likes/dislikes per video (target: < 250 ms)
-- Enables index lookup on video_reactions by video_id.
CREATE INDEX idx_video_reactions_video_id
ON video_reactions (video_id);

-- R16, R25: Finance and Premium audit
-- Index on ad_impressions for date range (R16) and join (R25).
CREATE INDEX idx_ad_impressions_watch_id
ON ad_impressions (watch_id);

CREATE INDEX idx_ad_impressions_shown_at
ON ad_impressions (shown_at);
```

### 3.3 Sargable rewrites for partition pruning

Two queries use function calls on `started_at` that **prevent** partition pruning:

**R07 (original):**
```sql
WHERE DATE(w.started_at) BETWEEN '2026-06-01' AND '2026-06-30'
```
**R07 (sargable rewrite):**
```sql
WHERE w.started_at >= '2026-06-01' AND w.started_at < '2026-07-01'
```
The `GROUP BY DATE(w.started_at)` in the SELECT list still produces daily buckets — only the WHERE clause changes.

**R20 (original):**
```sql
WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
```
**R20 (sargable rewrite):**
```sql
WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
```

> These rewrites produce identical results (every timestamp in June maps to the same date range) but allow the planner to match the predicate against partition bounds and prune 23 of 24 partitions.

---

## 4. What Broke at Scale and How We Fixed It

> ⏳ **This section will be populated with EXPLAIN plan comparisons after running benchmarks on the large dataset.** The anticipated issues below are based on algorithmic analysis of the seed-data plans.

### 4.1 R01 — Channel page becomes slow (viewer-facing, < 5 ms target)

**Expected problem:** The seed-data Seq Scan on `videos` (3.1 ms on 30k rows) scales to ~62 ms on 600k rows, missing the 5 ms target by 12×.

**Fix:** Add a composite B-tree index:
```sql
CREATE INDEX idx_videos_channel_vis_pub
ON videos (channel_id, visibility, published_at DESC);
```
- **channel_id** as the leading column gives equality pruning (channel 217 has ~10 videos).
- **visibility** as the second column filters to `'PUBLIC'` only.
- **published_at DESC** satisfies the `ORDER BY published_at DESC LIMIT 20` without a sort.
- Plan changes from `Seq Scan → Sort → Limit` to `Index Scan → Limit` (at most 20 index entries read).

**Expected after:** < 1 ms.

### 4.2 R15 — Watch page comments (viewer-facing, < 5 ms target)

**Expected problem:** Seq Scan on `comments` (4.1 ms on 60k rows) scales to ~82 ms on 1.2M rows.

**Fix:** Partial index on top-level comments for a specific video:
```sql
CREATE INDEX idx_comments_video_parent
ON comments (video_id)
WHERE parent_comment_id IS NULL;
```
Plan changes from `Seq Scan on comments` to `Index Scan using idx_comments_video_parent`.

**Expected after:** < 1 ms.

### 4.3 R04 — Title search (interactive, < 250 ms target)

**Expected problem:** `ILIKE '%tutorial%'` Seq Scan on 600k videos ≈ 475 ms.

**Fix:** GIN trigram index:
```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_videos_title_trgm ON videos USING gin (title gin_trgm_ops);
```
Enables `Bitmap Index Scan using idx_videos_title_trgm` with trigram matching.

**Expected after:** < 20 ms.

### 4.4 R07, R09 — Studio charts (interactive, < 250 ms target)

**Expected problem:** Seq Scan on 4M watch_events joined to videos for one channel ≈ 340 ms.

**Fix (two-pronged):**
1. **Index on watch_events(video_id):** Allows indexed nested loop join — look up only the watch events for channel 217's ~10 videos.
2. **Partition pruning (sargable rewrite for R07):** Prune to June 2026 partition, reducing scan from 4M to ~222k rows.

```sql
CREATE INDEX idx_watch_events_video_id ON watch_events (video_id);
```

Combined with the sargable WHERE clause rewrite for R07, the plan becomes:
```
Index Scan on watch_events_y2026m06 using idx_watch_events_video_id
  Index Cond: (video_id = ANY (channel 217's video_ids from inner scan))
```

**Expected after:** < 50 ms.

### 4.5 R25 — Premium audit (reporting, < 5,000 ms target)

**Expected problem:** 3-way hash join across ad_impressions (1.14M) × watch_events (4M) × users (600k). Hash table for watch_events may exceed `work_mem` and spill to disk, causing super-linear growth.

**Fix:** Add index on `ad_impressions(watch_id)` to convert the ad_impressions → watch_events join from Hash Join to indexed Nested Loop:
```sql
CREATE INDEX idx_ad_impressions_watch_id ON ad_impressions (watch_id);
```

**Expected after:** < 2,000 ms (well within 5,000 ms target).

---

## 5. Storage Analysis

> ⏳ **Actual sizes will be filled in after loading the large dataset.** Below are projections based on seed data measurements.

### 5.1 Projected sizes

| Component | Seed data (est.) | Large data (est. 20×) |
|-----------|---:|---:|
| **Tables total** | ~80 MB | ~1.6 GB |
| `watch_events` | ~25 MB | ~500 MB |
| `videos` | ~8 MB | ~160 MB |
| `comments` | ~12 MB | ~240 MB |
| `subscriptions` | ~8 MB | ~160 MB |
| `ad_impressions` | ~5 MB | ~100 MB |
| Other tables | ~22 MB | ~440 MB |
| **Indexes (PK + UNIQUE)** | ~40 MB | ~800 MB |
| **Phase 4 indexes (4)** | ~15 MB | ~300 MB |
| **Additional scale indexes (7)** | ~20 MB | ~400 MB |
| **Total database** | ~155 MB | ~3.1 GB |

### 5.2 Index storage vs table size

> Run after loading large data:
> ```sql
> SELECT relname,
>        pg_size_pretty(pg_relation_size(oid)) AS data_size,
>        pg_size_pretty(pg_indexes_size(oid))  AS index_size,
>        round(100.0 * pg_indexes_size(oid) / NULLIF(pg_relation_size(oid), 0), 1) AS idx_pct
> FROM pg_class
> WHERE relnamespace = 'youtube'::regnamespace
>   AND relkind = 'r'
> ORDER BY pg_relation_size(oid) DESC;
> ```

### 5.3 Partitioned table storage

With monthly partitioning, `watch_events` splits into 24 monthly partitions plus a default. Each partition stores roughly 1/18 of the data (data spans 18 months), resulting in:
- ~28 MB per active partition (large data)
- Each partition has its own heap file and local index copies
- Slight overhead from per-partition metadata and index duplication, but improved vacuum performance since only recently-modified partitions need vacuuming

---

## 6. Architecture for 100× Growth

At 100× the seed data (20M watch events, 3M videos, 6M ad impressions), the database needs architectural changes beyond indexing.

### 6.1 Partitioning

**Table:** `watch_events`
**Strategy:** RANGE on `started_at`, monthly granularity
**DDL:** See [`sql/08_partitioning.sql`](../sql/08_partitioning.sql)

#### Why monthly RANGE?
- Watch events are append-mostly (new events always go to the latest partition)
- Most queries filter by date window (R07, R10, R11, R16, R20)
- Monthly granularity gives 24 partitions/year — manageable for the planner's partition-pruning logic
- At 100×, each monthly partition holds ~1.1M rows — large enough to benefit from local indexes, small enough for efficient sequential scans

#### Partition pruning demonstration
```sql
EXPLAIN (COSTS OFF)
SELECT count(*)
FROM youtube.watch_events
WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01';
```
Expected output scans only `watch_events_y2026m06`, skipping the other 23+ partitions.

#### Primary-key rule
PostgreSQL requires the partition key in every UNIQUE/PK constraint on partitioned tables. The PK becomes `(watch_id, started_at)`. This is acceptable because `watch_id` is generated by a sequence and is effectively unique; the composite PK adds `started_at` to satisfy the constraint rule without changing semantics.

#### Other partitioning candidates at 100×
| Table | Strategy | Rationale |
|-------|----------|-----------|
| `ad_impressions` | RANGE on `shown_at` (monthly) | Co-partitioned with watch_events; R16 and R25 filter by month |
| `comments` | RANGE on `created_at` (quarterly) | R23 paginates by created_at; pruning eliminates old quarters |
| `videos` | Not partitioned | Only 3M rows at 100×; B-tree indexes are sufficient |

### 6.2 Sharding

At 100× a single PostgreSQL node may hit I/O and memory limits. Sharding distributes data across multiple nodes.

#### Shard key analysis

| Shard key | Pros | Cons | Cross-shard queries |
|-----------|------|------|---------------------|
| **By time (monthly)** | Natural extension of partitioning; archiving is trivial; recent-data queries hit one shard | Hot shard for current month; R05 (history) spans many months | R05, R12, R22, R25 |
| **By user** | R05 (watch history) is local; R03 (sub feed) is local | Studio charts (R07, R09) for a channel need data from all users who watched → cross-shard fan-out | R07, R08, R09, R10, R11, R16, R17, R19 |
| **By channel** | Studio queries (R07, R09, R14, R24) are local | Watch history (R05) spans multiple channels → cross-shard | R05, R10, R11, R12, R20, R22, R25 |
| **By video** | Traffic source (R08) is local | Studio charts (R07) for a channel need all its videos → multi-shard; history (R05) is multi-shard | R05, R07, R09, R10, R11, R12, R20 |

#### Recommended strategy: Time-based sharding with replicated dimension tables

1. **Shard `watch_events` and `ad_impressions` by time** (monthly or quarterly ranges across nodes).
2. **Replicate small dimension tables** (`users`, `channels`, `videos`, `subscriptions`, `video_reactions`, `comments`, `playlists`, `playlist_items`) to every shard. At 100× these tables are ~3M–6M rows each — well within a single node.
3. **Route queries to shards:**
   - Studio charts for June 2026 → June shard only
   - History for user 1042 (LIMIT 50, most recent) → query the latest shard first, then fall back to older shards if needed
   - Full-table analytics (R12, R20) → map-reduce across all shards
4. **Handle cross-shard queries with a coordinator** (e.g. Citus, pgBouncer + application logic) that fans out reads and merges results.

#### Trade-off: Studio vs History
The core tension is:
- **Studio charts** (R07, R09, R14) are per-channel → channel sharding is local
- **Watch history** (R05) is per-user → user sharding is local

Time-based sharding is the compromise: both Studio and History queries need recent data, so the latest time shard handles most real-time queries. Only long-range analytics need cross-shard aggregation.

### 6.3 Read Replicas and Caching

#### Read replicas
| Query class | Route to… | Rationale |
|-------------|-----------|-----------|
| **Real-time reads:** R01, R02, R03, R05, R15, R21 | Primary or any replica | Tolerate slight replication lag (< 1s); round-robin across replicas to distribute load |
| **Studio analytics:** R07, R08, R09, R13, R14, R24 | Dedicated analytics replica | Isolate heavy aggregation from the primary's write path |
| **Reports:** R10, R11, R12, R16–R20, R22, R23, R25 | Analytics replica | These can tolerate seconds of lag; offloading them protects write throughput |
| **Writes:** W01, W02, W03, W04, W05 | Primary only | Must hit the primary for consistency |

#### Caching
| Data | Cache layer | TTL | Invalidation |
|------|-------------|-----|-------------|
| Channel page (R01) | Application (Redis) | 60s | On new video upload (W01) |
| Watch page video metadata (R02) | CDN edge cache | 300s | On video update |
| Trending / Shorts shelf (R10, R11) | Materialized view or Redis | 15 min | Periodic refresh; not live data |
| Subscriber count (R24, W04) | In `channels.subscriber_count` (already cached in schema) | Nightly refresh (W04) | W04 batch job |
| Search results (R04) | Application cache | 120s | On video publish |

#### What must NOT be cached
- Write operations (W01–W05): must always hit the primary
- Premium audit (R25): must reflect current premium_until values
- Child safety (R18): regulatory compliance requires live data
- Financial reports (R16, R19): must be accurate for accounting

### 6.4 Maintenance

#### VACUUM / autovacuum settings for watch_events
At 100× scale, `watch_events` accumulates dead tuples from UPDATE-heavy workloads (W03 bumps view_count on videos, not watch_events, but W04 and W05 produce dead tuples on `channels` and `videos`). With partitioning, autovacuum targets individual partitions:

```sql
-- Per-partition autovacuum tuning for active partitions
ALTER TABLE watch_events_y2026m06 SET (
    autovacuum_vacuum_scale_factor = 0.01,     -- vacuum after 1% dead tuples (not 20%)
    autovacuum_analyze_scale_factor = 0.005,   -- analyze after 0.5% changes
    autovacuum_vacuum_cost_delay = 2           -- less delay → more aggressive
);

-- Older partitions rarely change; default autovacuum settings suffice.
-- Completely frozen partitions skip vacuum entirely.
```

#### Archiving old data
With monthly partitions, archiving is a metadata-only operation:
```sql
-- Detach and archive a partition older than 2 years
ALTER TABLE watch_events DETACH PARTITION watch_events_y2025m01;
-- Move to cold storage, pg_dump, or drop
```
This is instantaneous (no data movement), and future queries automatically skip the detached partition.

#### Refreshing summary tables
For heavy reports that don't need live data (Trending R10/R11, daily analytics R20):
```sql
-- Create a materialized view for daily watch summaries
CREATE MATERIALIZED VIEW mv_daily_watch_summary AS
SELECT started_at::date AS day,
       v.channel_id,
       v.category,
       v.is_short,
       count(*)                       AS views,
       round(sum(w.watch_seconds)/3600.0, 1) AS watch_hours
FROM watch_events w
JOIN videos v ON v.video_id = w.video_id
GROUP BY 1, 2, 3, 4;

CREATE INDEX idx_mv_daily_day ON mv_daily_watch_summary (day);
CREATE INDEX idx_mv_daily_channel ON mv_daily_watch_summary (channel_id, day);

-- Refresh nightly or every 15 minutes (concurrent allows reads during refresh)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_watch_summary;
```

This materialized view serves R07, R09 (channel daily views), R10/R11 (trending), and R20 (platform daily totals) with sub-millisecond lookups regardless of `watch_events` size.

---

## 7. Conclusion

### Is the database ready for next year (20× growth)?

**Yes, with the documented optimizations.** Our analysis shows:

1. **Index-based queries (Group A)** scale logarithmically and meet all targets without changes.
2. **Linear-scan queries (Group B)** grow 20× but most remain within their target brackets. The exceptions (R01, R03, R04, R07, R09, R15) are addressed by the 7 additional indexes documented in §3.2.
3. **Partitioning** (`sql/08_partitioning.sql`) enables partition pruning for date-filtered queries on `watch_events`, keeping June-only reports fast regardless of total table size.
4. **Query rewrites** (sargable date predicates for R07 and R20) ensure partition pruning actually activates.

### Remaining risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Hash join memory spills on 3-way joins (R25, R16) | Super-linear slowdown | Add `idx_ad_impressions_watch_id`; consider session-level `work_mem` increase for reporting queries |
| OFFSET pagination (R23) with deeper pages | O(OFFSET) traversal even with index | Migrate to keyset pagination: `WHERE created_at < :last_seen ORDER BY created_at DESC LIMIT 25` |
| Write amplification from 11+ indexes on `watch_events` | W02 INSERT overhead grows | Monitor INSERT latency; drop BRIN/GIN indexes if write SLA is missed |
| `watch_events` FK to `videos`/`users` on partitioned table | FK checks on each INSERT across partition boundaries | Consider deferring FK checks or validating periodically |
| Single-node I/O ceiling at 100× | Disk throughput bottleneck | Implement time-based sharding with replicated dimension tables (§6.2) |
| Materialized view staleness | Trending/analytics show stale data | Tune refresh interval (15 min for trending, nightly for finance) |

### Summary of optimizations applied across all phases

| Phase | Technique | Queries improved |
|-------|-----------|------------------|
| CP3 | 4 B-tree indexes | R05 (34×), R23 (5.3×), R24 (9.2×), R10 (3.3×), R11 (1.5×) |
| CP3 | R19 rewrite (correlated → set-based) | R19 (310×) |
| CP3 | R13 NULL fix (NOT IN → NOT EXISTS) | R13 (correctness + 5.5×) |
| CP4 | Monthly RANGE partitioning on `watch_events` | R07, R10, R11, R16, R20, W02 |
| CP4 | 7 additional indexes (pending benchmarks) | R01, R03, R04, R07, R08, R09, R14, R15, R16, R25 |
| CP4 | Sargable date rewrites for R07, R20 | Enables partition pruning |
| Design | Time-based sharding + replicated dimensions | 100× readiness |
| Design | Read replicas + caching | Write isolation, read distribution |
| Design | Materialized views for reporting | R07, R10, R11, R20 at O(1) |

---

*Report compiled by Team T0066. Benchmark data placeholders (⏳) will be replaced with actual measurements from `benchmarks/results/large/summary.csv` once `large_data.zip` is available.*
