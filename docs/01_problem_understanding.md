# Phase 1: Problem Understanding

Team T0066 | PostgreSQL 18


| # | What the business needs | Who is affected | Type | Target | Queries |
|---|---|---|---|---|---|
| P1 | Channel pages, watch pages and playlists are the pages people open the most. If they load slowly people just leave, and that also means fewer views for the creator. | Viewers, creators (they lose views) | Customer-facing / real-time | under 5 ms | R01, R02, R15, R21 |
| P2 | The subscriptions feed and watch history are different for every user. The more someone watches or subscribes, the slower these get, so the most active users end up with the worst experience. | Viewers | Customer-facing / real-time | under 5 ms | R03, R05 |
| P3 | Search should show results almost while the user is typing. The problem is that it searches for a word anywhere inside the title (`%tutorial%`), and a normal B-tree index can't help with that. | Viewers | Customer-facing, interactive | under 250 ms | R04 |
| P4 | Creators use YouTube Studio to check daily views, traffic sources, how much of each video people watch, likes and subscriber growth. It's analytics, but the creator is looking at the screen waiting, so we treat it as interactive. | Creators, YouTube Studio team | Customer-facing, interactive | under 250 ms | R07, R08, R09, R14, R24 |
| P5 | This one isn't about speed. The report always comes back empty, which means it's giving the wrong answer, so creators think every subscriber has watched them. We need to fix the result first and then make it fast. | Creators, YouTube Studio team | Interactive (correctness bug) | under 250 ms | R13 |
| P6 | The Shorts shelf and Trending tab rank videos using lots of watch events. Everyone sees them, but they don't need to be calculated for every visit. They can be refreshed in the background every so often. | Trending / recommendations, and viewers indirectly | Reporting / analytics | under 5 s | R10, R11 |
| P7 | Two separate problems here. First, scheduled videos have to go public right on time, otherwise the creator's launch gets messed up. Second, uploading, logging a view and updating the view counter happen all the time, so these writes have to stay fast even when traffic is high. | Creators (publishing), viewers (player) | Scheduling job is interactive, the writes are real-time | 250 ms for R06/W05, 5 ms for W01 to W03 | R06, W05, W01, W02, W03 |
| P8 | Finance wants ad revenue per channel. The partner program wants to know which channels now qualify for monetization. Premium users paid to not see ads, so if any ads were shown to them it has to be caught. The nightly subscriber recount also has to finish in time. | Finance, partner program, Premium subscribers | Reporting / analytics, W04 is a nightly batch job | under 5 s, W04 under 2 s | R16, R17, R19, R25, W04 |
| P9 | Child safety needs to find kids videos that still have comments (comments should be off on those). Copyright wants videos with the same title and length uploaded by different channels. Moderation needs to page through all comments. Growth wants logged-out viewing and daily watch hours. And all of this has to keep working when traffic is 20 times bigger. | Child safety, copyright, moderation, growth team | Reporting / analytics | under 5 s | R12, R18, R20, R22, R23 |

### How we grouped the 30 queries

| Group | Queries | Reason |
|---|---|---|
| Real-time | R01, R02, R03, R05, R15, R21, W01, W02, W03 | One user and one page, only a few rows, but it runs a huge number of times a day |
| Interactive (Studio and search) | R04, R06, R07, R08, R09, R13, R14, R24, W05 | Someone is waiting, but it only looks at one channel or one video |
| Reporting | R10, R11, R12, R16, R17, R18, R19, R20, R22, R23, R25 | Internal teams, reads a big part of the data, can be precomputed |
| Batch | W04 | Runs once a night over every channel |

### Things we noticed

- P5 is the only complaint about a wrong answer instead of a slow one. Around a quarter of watch events have no `user_id` (logged-out views), and we think those NULLs are what's breaking the R13 query, since it uses `NOT IN`.
- P7 reminded us that indexes aren't free. Every index we add for the read queries makes W01, W02 and W03 a bit slower, so we can't just index everything.
- Because of the 20x growth in P9, we need fixes that actually scale with the data, not just ones that happen to work on 200,000 rows.

### Assumptions

1. All timestamps are in IST (+05:30), so when a report says "a day" or "June", we mean the Indian calendar day or month.
2. A watch event with no `user_id` is a logged-out view. It still counts as a view, it just isn't linked to any user.
3. Channel 217, user 1042, video `ZkNSlUB1EOs` and playlist 501 are just examples. In the real app the same queries would run with whatever ID the user asks for.
4. "Today" is around the end of June / start of July 2026, since that's where the data ends. So "last 7 days" and "June 2026" are based on that.
5. Reports (P6, P8, P9) can be a bit out of date, a few minutes or even hours is fine. Viewer pages (P1, P2) have to show live data.
6. `subscriber_count` and `view_count` are stored on the table only so pages load faster. They can be slightly behind and get corrected by W04 and W03.
7. We expect around 20 times more data within a year (roughly 4 million watch events), and the same targets should still hold then.
