# YouTube Video Sharing Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 10 CSV files (200,000 watch events): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details (fill in before you start)

| Role | Name | Enrollment No. | GitHub Username |
|------|------|----------------|-----------------|
| Group Lead | Sarthak Gupta | 2501010408 | sarthak-gupta-229 |
| Member 2 | Shresth Juyal | 2501010436 | Shresth-14 |
| Member 3 | Yuvansh Juneja | 2501010537 | Yuvanshj |
| Member 4 | Yashaswi Gusain | 2501010524 | gusainyashaswi |

**Team No.:** T0066 · **Section:** E and C · **Repository URL:** https://github.com/Shresth-14/DE_Project_2026

---

## How this project works

| Phase | What you do | You submit | Counts toward | Marks |
|-------|-------------|------------|---------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | Query Execution | 2 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | Query Execution | 5 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | Query Execution | 3 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | Code Optimization | 16 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | Code Optimization | 14 |
| | **Total** | | | **40** |

---

## Phase 1: Problem statements

YouTube lets anyone run a **channel** and upload **videos** (long videos and Shorts). Each video has an 11-character ID, a category and a visibility (public, unlisted, private, or scheduled to go live later). Viewers—signed in or not—generate **watch events**; signed-in users can subscribe to channels, like or dislike videos, comment, and build **playlists**. Ads shown during views earn revenue for monetized channels, but YouTube Premium members should never see ads. You have joined the YouTube India data team.

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "**Channel pages, watch pages and playlists** are slow to open." | Viewer app | R01, R02, R15, R21 |
| P2 | "The **subscriptions feed** and **watch history** take seconds for active users." | Viewer app | R03, R05 |
| P3 | "**Search** by title is too slow." | Search | R04 |
| P4 | "**YouTube Studio** charts (daily views, traffic sources, retention, likes, subscriber growth) lag for creators." | Creators / Studio | R07, R08, R09, R14, R24 |
| P5 | "A creator report of **subscribers who never watched** the channel always comes back **empty**." | Creators / Studio | R13 |
| P6 | "The **Shorts shelf** and **Trending** tab are recomputed too slowly." | Recommendations | R10, R11 |
| P7 | "The publishing service misses **scheduled videos**; uploads and view counters slow down under load." | Publishing | R06, W01, W02, W03, W05 |
| P8 | "**Finance and partner-program** reports (ad revenue, eligibility, Premium ads audit) time out." | Finance / Partner program | R16, R17, R19, R25, W04 |
| P9 | "Trust teams need **child-safety, copyright and moderation** reports; growth wants logged-out and watch-time trends, and traffic will grow **20×**." | Trust & Safety / Growth | R12, R18, R20, R22, R23 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P9, write in your own words what the business needs and which **stakeholder** is affected (viewer, creator, Premium subscriber, YouTube Studio team, trending/recommendations, partner program, finance, child safety, copyright, moderation).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 10 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `users.csv` | 30,000 | Signed-in YouTube users |
| `channels.csv` | 3,000 | Creator channels (each owned by one user) |
| `videos.csv` | 30,000 | Uploaded videos and Shorts |
| `subscriptions.csv` | 129,253 | Which user subscribes to which channel |
| `watch_events.csv` | 200,000 | Every view from 1 Jan 2025 to 30 Jun 2026 (signed-in or not) |
| `video_reactions.csv` | 67,417 | Likes and dislikes |
| `comments.csv` | 60,000 | Comments and replies |
| `playlists.csv` | 8,000 | User playlists |
| `playlist_items.csv` | 56,005 | Videos inside each playlist, in order |
| `ad_impressions.csv` | 57,014 | Ads shown during views and the revenue earned |

The first line of every file is the header (column names). Here are the headers and the first rows of each file:

**users.csv**
```
user_id,email,display_name,country_code,birth_year,premium_until,created_at
1,vivaan.sharma1@gmail.com,Vivaan Sharma,US,1994,,2020-07-10 17:00:49+05:30
2,aditya.sharma2@gmail.com,Aditya Sharma,GB,1960,,2018-12-18 02:48:25+05:30
```

**channels.csv**
```
channel_id,owner_user_id,handle,channel_name,country_code,is_verified,monetization_status,subscriber_count,created_at
1,1,@vivaanvlogs1,Vivaan Vlogs,IN,t,NOT_ELIGIBLE,4929,2019-08-02 21:36:50+05:30
2,2,@adityacooks2,Aditya Kitchen,IN,t,NOT_ELIGIBLE,1669,2021-08-18 12:42:37+05:30
```

**videos.csv**
```
video_id,channel_id,title,description,category,duration_sec,is_short,is_made_for_kids,visibility,uploaded_at,published_at,view_count
__21WjTDc9K,2392,Python Tips & Tricks,"Don't forget to like, share and subscribe! Timestamps in the comments.",Music,2594,f,f,PRIVATE,2025-10-21 21:10:33+05:30,,0
__3MrubXQ0i,1863,Home Workout Reaction,"Don't forget to like, share and subscribe! Timestamps in the comments.",Gaming,2039,f,f,PUBLIC,2024-08-15 01:34:04+05:30,2024-08-15 07:16:04+05:30,10
```

**subscriptions.csv**
```
user_id,channel_id,notifications,subscribed_at
1,15,NONE,2023-03-04 21:20:09+05:30
1,209,PERSONALIZED,2025-02-25 19:51:48+05:30
```

**watch_events.csv**
```
watch_id,user_id,video_id,started_at,watch_seconds,device,traffic_source
1,13624,ooA4j3IUch0,2025-01-01 00:00:00+05:30,2998,WEB,SUGGESTED
2,15558,Fvhk-e233LM,2025-01-01 00:03:55+05:30,16,ANDROID,SHORTS_FEED
```

**video_reactions.csv**
```
user_id,video_id,reaction,reacted_at
1,1vQ6x6KRz_8,LIKE,2025-12-26 21:59:57+05:30
1,ocbZsNGqV8r,LIKE,2025-01-11 20:56:14+05:30
```

**comments.csv**
```
comment_id,video_id,user_id,parent_comment_id,body,like_count,is_pinned,created_at
1,a0u0HPJTQKt,25719,,"Great explanation, thank you!",10,f,2025-01-01 00:00:00+05:30
2,XmX1KpttDaF,21267,,Who is watching in 2026?,137,f,2025-01-01 00:13:06+05:30
```

**playlists.csv**
```
playlist_id,owner_user_id,title,visibility,created_at
1,14847,Favourites 1,PRIVATE,2024-09-01 16:47:30+05:30
2,667,Study Music 2,PRIVATE,2025-02-07 01:10:50+05:30
```

**playlist_items.csv**
```
playlist_id,position,video_id,added_at
1,1,OUwQ73hgFJk,2026-06-05 16:10:04+05:30
1,2,B6OdEb7t1lm,2025-10-22 01:29:16+05:30
```

**ad_impressions.csv**
```
impression_id,watch_id,ad_format,revenue_inr,shown_at
1,8,MIDROLL,0.5308,2025-01-01 00:32:31+05:30
2,8,PREROLL,0.3378,2025-01-01 00:27:31+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, timestamps with a time-zone offset, yes/no columns, small whole numbers, decimals and short codes.
3. **Primary key.** Is it one column, or a combination? (What type is `video_id`? Look closely at `subscriptions`, `video_reactions` and `playlist_items`.)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why**, and decide which columns must never be empty. Why do some watch events have no `user_id`? When are `published_at`, `premium_until`, `birth_year`, `description` and `parent_comment_id` empty?
6. **UNIQUE** columns (natural candidate keys such as emails, phone numbers, codes and handles).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Look for formats (11-character video id, @handle, 2-letter country code), allowed values (categories, visibility, devices, traffic sources, ad formats), and rules tying columns together (a Short is at most 60 seconds, private videos have no publish time, a reply can't be pinned, a watch can't be longer than… ?).
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: `channels.subscriber_count`, `videos.view_count`, `videos.is_short` vs `duration_sec`) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`youtube`**: `CREATE SCHEMA youtube;` and `SET search_path TO youtube;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO youtube;
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true)
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "nobody watched a video before it was uploaded", "watch_seconds never exceeds the video duration", "a playlist does not contain the same video twice"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 10 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 25 reads (`R01`–`R25`) and 5 writes (`W01`–`W05`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W05`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **several seconds** on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Channel page: the 20 newest public videos of channel 217 | READ | | | | |
| R02: Watch page: one video with its channel | READ | | | | |
| R03: Subscriptions feed: public videos from channels user 1042 subscribes to, newest first | READ | | | | |
| R04: Search: public videos with "tutorial" in the title, most viewed first | READ | | | | |
| R05: History page: the last 50 videos user 1042 watched | READ | | | | |
| R06: Publishing service: videos scheduled to go live in the first week of July 2026 | READ | | | | |
| R07: YouTube Studio: channel 217's daily views and watch hours in June 2026 | READ | | | | |
| R08: YouTube Studio: where views of video ZkNSlUB1EOs come from | READ | | | | |
| R09: YouTube Studio: average percentage watched for each of channel 217's videos | READ | | | | |
| R10: Shorts shelf: most viewed Shorts in the last 7 days of June 2026 | READ | | | | |
| R11: Trending tab: top 5 videos per category by views in June 2026 | READ | | | | |
| R12: Growth: share of logged-out viewing per device type | READ | | | | |
| R13: Creator insights: subscribers of channel 217 who have never watched any of its videos | READ | | | | |
| R14: YouTube Studio: likes, dislikes and like ratio per video of channel 217 | READ | | | | |
| R15: Watch page: pinned comment and top 10 comments of video ZkNSlUB1EOs | READ | | | | |
| R16: Finance: ad revenue per channel in June 2026, top 20 | READ | | | | |
| R17: Partner program: NOT_ELIGIBLE channels that now have 100+ subscribers and 40+ watch hours | READ | | | | |
| R18: Child safety: "made for kids" videos that still have comments (comments must be disabled) | READ | | | | |
| R19: Partner report: for every monetized channel, its latest upload and its total views | READ | | | | |
| R20: Platform analytics: daily watch hours and running total for June 2026 | READ | | | | |
| R21: Playlist page: playlist 501 in order | READ | | | | |
| R22: Copyright team: same title and duration uploaded by more than one channel | READ | | | | |
| R23: Moderation queue: all comments, newest first, page 1,201 (25 per page) | READ | | | | |
| R24: YouTube Studio: new subscribers per month for channel 217 | READ | | | | |
| R25: Premium audit: ads that were shown to users with an active Premium membership | READ | | | | |
| W01: Upload: a new public video on channel 217 | WRITE | | | | |
| W02: Player: record a view of video ZkNSlUB1EOs by user 1042 | WRITE | | | | |
| W03: View counter: add one view to video ZkNSlUB1EOs | WRITE | | | | |
| W04: Nightly job: recompute every channel's subscriber count | WRITE | | | | |
| W05: Publishing service: make scheduled videos public once their time has come (run at 3 Jul 2026 00:00) | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN index | for `ILIKE '%text%'` (extension `pg_trgm`), arrays or full-text search |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination; `UNION ALL` instead of `OR` across columns |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule about NULLs. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R05 | | e.g. Seq Scan on 200k watch events | e.g. index on `watch_events(user_id, started_at DESC)` | | e.g. 99% (120×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which write queries got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 200,000 watch events. Next year the business expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 10 CSV files with about **20× the rows** (≈ 4,000,000 watch events, ≈ 1,140,000 ad impressions, ≈ 2,585,000 subscriptions, ≈ 600,000 videos, ≈ 600,000 users). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them could run for a very long time.
   - R23 pages with `OFFSET`; if you replaced it with keyset pagination, explain how the "last seen" value is chosen for the large data.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / viewer-facing | R01, R02, R03, R05, R15, R21, W01, W02, W03 | **under 5 ms** |
| Interactive Studio and search | R04, R06, R07, R08, R09, R13, R14, R24, W05 | **under 250 ms** |
| Reports and analytics | R10, R11, R12, R16, R17, R18, R19, R20, R22, R23, R25 | **under 5,000 ms** |
| Batch jobs | W04 | **under 2,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100×:** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `watch_events`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** Would you shard watch events by video, by channel, by user, or by time? Think about Studio charts (per channel) vs watch history (per user). Which queries become cross-shard, and how would you handle them?
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `watch_events`, archiving old data, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
youtube-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Tue 3 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |
| Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | **CP5** Individual analysis |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

## Evaluation (40 marks)

These 40 marks are the DE part of the project: **Query Execution (10)** and **Code Optimization (30)**.
The AP project (20) and your Individual analysis (40) make up the rest of the 100.

| Phase | Criteria | Marks |
|-------|----------|------:|
| | **Query Execution** | **10** |
| 1 | Problems understood, stakeholders and query groups correctly identified | 2 |
| 2 | Correct data types (1), keys and foreign keys with justified delete rules (1), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (1), ER diagram + normal-form analysis (1), data loads cleanly + integrity checks (1) | 5 |
| 3 | All 30 queries measured with the required method: 3 runs, average (1), raw plans committed (1), scan type and reason for each query (1) | 3 |
| | **Code Optimization** | **30** |
| 4 | Speed-up achieved with appropriate techniques (6), every index justified (3), results proven unchanged (2), wrong-result query found and explained (2), write overhead and index storage reported (3) | 16 |
| 5 | Large-dataset results with all targets met or explained (4), growth analysis (3), scale-only problems found and fixed (3), partitioning DDL + sharding/replica design backed by your numbers (4) | 14 |
| | **Total** | **40** |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Channel page: the 20 newest public videos of channel 217**
```sql
SELECT video_id, title, duration_sec, view_count, published_at
FROM videos
WHERE channel_id = 217 AND visibility = 'PUBLIC'
ORDER BY published_at DESC
LIMIT 20;
```

**R02: Watch page: one video with its channel**
```sql
SELECT v.video_id, v.title, v.description, v.view_count, c.channel_name, c.handle, c.subscriber_count
FROM videos v
JOIN channels c ON c.channel_id = v.channel_id
WHERE v.video_id = 'ZkNSlUB1EOs';
```

**R03: Subscriptions feed: public videos from channels user 1042 subscribes to, newest first**
```sql
SELECT v.video_id, v.title, c.channel_name, v.published_at
FROM subscriptions s
JOIN videos v   ON v.channel_id = s.channel_id
JOIN channels c ON c.channel_id = s.channel_id
WHERE s.user_id = 1042 AND v.visibility = 'PUBLIC'
ORDER BY v.published_at DESC
LIMIT 30;
```

**R04: Search: public videos with "tutorial" in the title, most viewed first**
```sql
SELECT video_id, title, view_count
FROM videos
WHERE title ILIKE '%tutorial%' AND visibility = 'PUBLIC'
ORDER BY view_count DESC
LIMIT 20;
```

**R05: History page: the last 50 videos user 1042 watched**
```sql
SELECT w.started_at, w.watch_seconds, v.video_id, v.title
FROM watch_events w
JOIN videos v ON v.video_id = w.video_id
WHERE w.user_id = 1042
ORDER BY w.started_at DESC
LIMIT 50;
```

**R06: Publishing service: videos scheduled to go live in the first week of July 2026**
```sql
SELECT video_id, channel_id, title, published_at
FROM videos
WHERE visibility = 'SCHEDULED'
  AND published_at < '2026-07-08'
ORDER BY published_at;
```

**R07: YouTube Studio: channel 217's daily views and watch hours in June 2026**
```sql
SELECT DATE(w.started_at) AS day, count(*) AS views, round(sum(w.watch_seconds) / 3600.0, 2) AS watch_hours
FROM watch_events w
JOIN videos v ON v.video_id = w.video_id
WHERE v.channel_id = 217
  AND DATE(w.started_at) BETWEEN '2026-06-01' AND '2026-06-30'
GROUP BY 1
ORDER BY 1;
```

**R08: YouTube Studio: where views of video ZkNSlUB1EOs come from**
```sql
SELECT traffic_source, count(*) AS views, round(avg(watch_seconds), 0) AS avg_seconds
FROM watch_events
WHERE video_id = 'ZkNSlUB1EOs'
GROUP BY traffic_source
ORDER BY views DESC;
```

**R09: YouTube Studio: average percentage watched for each of channel 217's videos**
```sql
SELECT v.video_id, v.title, count(*) AS views,
       round(100.0 * avg(w.watch_seconds::numeric / v.duration_sec), 1) AS avg_pct_watched
FROM videos v
JOIN watch_events w ON w.video_id = v.video_id
WHERE v.channel_id = 217
GROUP BY v.video_id, v.title
ORDER BY avg_pct_watched DESC;
```

**R10: Shorts shelf: most viewed Shorts in the last 7 days of June 2026**
```sql
SELECT v.video_id, v.title, count(*) AS views
FROM watch_events w
JOIN videos v ON v.video_id = w.video_id
WHERE v.is_short
  AND w.started_at >= '2026-06-24'
GROUP BY v.video_id, v.title
ORDER BY views DESC
LIMIT 20;
```

**R11: Trending tab: top 5 videos per category by views in June 2026**
```sql
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
```

**R12: Growth: share of logged-out viewing per device type**
```sql
SELECT device,
       count(*) AS views,
       round(100.0 * count(*) FILTER (WHERE user_id IS NULL) / count(*), 1) AS logged_out_pct
FROM watch_events
GROUP BY device
ORDER BY views DESC;
```

**R13: Creator insights: subscribers of channel 217 who have never watched any of its videos**
```sql
SELECT s.user_id, s.subscribed_at
FROM subscriptions s
WHERE s.channel_id = 217
  AND s.user_id NOT IN (SELECT w.user_id
                        FROM watch_events w JOIN videos v ON v.video_id = w.video_id
                        WHERE v.channel_id = 217);
```

**R14: YouTube Studio: likes, dislikes and like ratio per video of channel 217**
```sql
SELECT v.video_id, v.title,
       count(*) FILTER (WHERE r.reaction = 'LIKE')    AS likes,
       count(*) FILTER (WHERE r.reaction = 'DISLIKE') AS dislikes,
       round(100.0 * count(*) FILTER (WHERE r.reaction = 'LIKE') / NULLIF(count(r.*), 0), 1) AS like_pct
FROM videos v
LEFT JOIN video_reactions r ON r.video_id = v.video_id
WHERE v.channel_id = 217
GROUP BY v.video_id, v.title
ORDER BY likes DESC;
```

**R15: Watch page: pinned comment and top 10 comments of video ZkNSlUB1EOs**
```sql
SELECT comment_id, user_id, body, like_count, is_pinned
FROM comments
WHERE video_id = 'ZkNSlUB1EOs' AND parent_comment_id IS NULL
ORDER BY is_pinned DESC, like_count DESC
LIMIT 11;
```

**R16: Finance: ad revenue per channel in June 2026, top 20**
```sql
SELECT v.channel_id, count(*) AS impressions, sum(a.revenue_inr) AS revenue_inr
FROM ad_impressions a
JOIN watch_events w ON w.watch_id = a.watch_id
JOIN videos v       ON v.video_id = w.video_id
WHERE a.shown_at >= '2026-06-01' AND a.shown_at < '2026-07-01'
GROUP BY v.channel_id
ORDER BY revenue_inr DESC
LIMIT 20;
```

**R17: Partner program: NOT_ELIGIBLE channels that now have 100+ subscribers and 40+ watch hours**
```sql
SELECT c.channel_id, c.handle, c.subscriber_count, round(sum(w.watch_seconds) / 3600.0, 1) AS watch_hours
FROM channels c
JOIN videos v       ON v.channel_id = c.channel_id
JOIN watch_events w ON w.video_id = v.video_id
WHERE c.monetization_status = 'NOT_ELIGIBLE'
  AND c.subscriber_count >= 100
GROUP BY c.channel_id, c.handle, c.subscriber_count
HAVING sum(w.watch_seconds) / 3600.0 >= 40
ORDER BY watch_hours DESC;
```

**R18: Child safety: "made for kids" videos that still have comments (comments must be disabled)**
```sql
SELECT v.video_id, v.title, v.channel_id
FROM videos v
WHERE v.is_made_for_kids
  AND EXISTS (SELECT 1 FROM comments c WHERE c.video_id = v.video_id)
ORDER BY v.video_id;
```

**R19: Partner report: for every monetized channel, its latest upload and its total views**
```sql
SELECT c.channel_id, c.handle,
       (SELECT max(v.uploaded_at) FROM videos v WHERE v.channel_id = c.channel_id) AS last_upload,
       (SELECT count(*) FROM watch_events w JOIN videos v ON v.video_id = w.video_id
         WHERE v.channel_id = c.channel_id) AS total_views
FROM channels c
WHERE c.monetization_status = 'ELIGIBLE'
ORDER BY total_views DESC;
```

**R20: Platform analytics: daily watch hours and running total for June 2026**
```sql
SELECT day, hours, sum(hours) OVER (ORDER BY day) AS running_hours
FROM (
    SELECT started_at::date AS day, round(sum(watch_seconds) / 3600.0, 1) AS hours
    FROM watch_events
    WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;
```

**R21: Playlist page: playlist 501 in order**
```sql
SELECT pi.position, v.video_id, v.title, v.duration_sec
FROM playlist_items pi
JOIN videos v ON v.video_id = pi.video_id
WHERE pi.playlist_id = 501
ORDER BY pi.position;
```

**R22: Copyright team: same title and duration uploaded by more than one channel**
```sql
SELECT title, duration_sec, count(DISTINCT channel_id) AS channels, count(*) AS uploads
FROM videos
GROUP BY title, duration_sec
HAVING count(DISTINCT channel_id) > 1
ORDER BY channels DESC, uploads DESC
LIMIT 50;
```

**R23: Moderation queue: all comments, newest first, page 1,201 (25 per page)**
```sql
SELECT comment_id, video_id, user_id, body, created_at
FROM comments
ORDER BY created_at DESC
OFFSET 30000
LIMIT 25;
```

**R24: YouTube Studio: new subscribers per month for channel 217**
```sql
SELECT date_trunc('month', subscribed_at) AS month, count(*) AS new_subscribers
FROM subscriptions
WHERE channel_id = 217
GROUP BY 1
ORDER BY 1;
```

**R25: Premium audit: ads that were shown to users with an active Premium membership**
```sql
SELECT a.impression_id, w.user_id, u.premium_until, a.shown_at, a.revenue_inr
FROM ad_impressions a
JOIN watch_events w ON w.watch_id = a.watch_id
JOIN users u        ON u.user_id = w.user_id
WHERE u.premium_until >= a.shown_at::date
ORDER BY a.shown_at DESC;
```

**W01: Upload: a new public video on channel 217**
```sql
INSERT INTO videos (video_id, channel_id, title, category, duration_sec, is_short, visibility, uploaded_at, published_at)
VALUES ('NeWvId00001', 217, 'DBMS Indexing - Explained', 'Education', 742, FALSE, 'PUBLIC',
        '2026-07-01 18:00:00+05:30', '2026-07-01 18:30:00+05:30');
```

**W02: Player: record a view of video ZkNSlUB1EOs by user 1042**
```sql
INSERT INTO watch_events (watch_id, user_id, video_id, started_at, watch_seconds, device, traffic_source)
VALUES (90000001, 1042, 'ZkNSlUB1EOs', '2026-07-01 19:00:00+05:30', 180, 'ANDROID', 'HOME');
```

**W03: View counter: add one view to video ZkNSlUB1EOs**
```sql
UPDATE videos SET view_count = view_count + 1 WHERE video_id = 'ZkNSlUB1EOs';
```

**W04: Nightly job: recompute every channel's subscriber count**
```sql
UPDATE channels c
SET subscriber_count = s.n
FROM (SELECT channel_id, count(*) AS n FROM subscriptions GROUP BY channel_id) s
WHERE s.channel_id = c.channel_id;
```

**W05: Publishing service: make scheduled videos public once their time has come (run at 3 Jul 2026 00:00)**
```sql
UPDATE videos
SET visibility = 'PUBLIC'
WHERE visibility = 'SCHEDULED'
  AND published_at <= '2026-07-03 00:00:00+05:30';
```
