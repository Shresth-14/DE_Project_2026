-- Phase 2: YouTube schema, worked out from the seed data
-- Team T0066
--
-- Run on an empty database:  psql -d youtube_db -f sql/01_schema.sql
-- Only PK, FK, UNIQUE, NOT NULL, CHECK and DEFAULT here. No extra indexes

--
--   * deleting an account or channel wipes its content (videos, comments,
--     likes, playlists, subscriptions)  -> CASCADE
--   * views and ad revenue that already happened are kept, just unlinked
--     -> SET NULL on watch_events, RESTRICT on ad_impressions

DROP SCHEMA IF EXISTS youtube CASCADE;
CREATE SCHEMA youtube;
SET search_path TO youtube;


-- users: signed-in YouTube accounts
CREATE TABLE users (
    user_id        integer       NOT NULL,
    email          varchar(254)  NOT NULL,
    display_name   varchar(100)  NOT NULL,
    country_code   char(2)       NOT NULL,
    birth_year     smallint,                 -- optional, user may not share it
    premium_until  date,                     -- NULL = never had Premium
    created_at     timestamptz   NOT NULL,

    CONSTRAINT pk_users PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT chk_users_email_format CHECK (email ~ '^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_users_country_code CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT chk_users_birth_year   CHECK (birth_year BETWEEN 1900 AND 2026)
);


-- channels: one per owner account (1:1 with users in this data)
CREATE TABLE channels (
    channel_id           integer      NOT NULL,
    owner_user_id        integer      NOT NULL,
    handle               varchar(30)  NOT NULL,
    channel_name         varchar(100) NOT NULL,
    country_code         char(2)      NOT NULL,
    is_verified          boolean      NOT NULL DEFAULT false,
    monetization_status  varchar(12)  NOT NULL DEFAULT 'NOT_ELIGIBLE',
    subscriber_count     integer      NOT NULL DEFAULT 0,   -- derived, kept for fast reads, refreshed by W04
    created_at           timestamptz  NOT NULL,

    CONSTRAINT pk_channels PRIMARY KEY (channel_id),
    CONSTRAINT uq_channels_handle UNIQUE (handle),
    CONSTRAINT uq_channels_owner  UNIQUE (owner_user_id),
    CONSTRAINT fk_channels_owner FOREIGN KEY (owner_user_id)
        REFERENCES users (user_id) ON DELETE CASCADE,       -- account deleted -> channel deleted
    CONSTRAINT chk_channels_handle_format CHECK (handle ~ '^@[a-z0-9._]+$'),
    CONSTRAINT chk_channels_country_code  CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT chk_channels_monetization  CHECK (monetization_status IN ('ELIGIBLE', 'NOT_ELIGIBLE', 'SUSPENDED')),
    CONSTRAINT chk_channels_subscriber_count CHECK (subscriber_count >= 0)
);


-- videos: long videos and Shorts
CREATE TABLE videos (
    video_id          varchar(11)  NOT NULL,
    channel_id        integer      NOT NULL,
    title             varchar(100) NOT NULL,
    description       text,                              -- optional
    category          varchar(20)  NOT NULL,
    duration_sec      integer      NOT NULL,
    is_short          boolean      NOT NULL,             -- derived from duration_sec, see CHECK below
    is_made_for_kids  boolean      NOT NULL DEFAULT false,   -- W01 leaves it out
    visibility        varchar(9)   NOT NULL,
    uploaded_at       timestamptz  NOT NULL,
    published_at      timestamptz,                       -- NULL only for PRIVATE videos
    view_count        bigint       NOT NULL DEFAULT 0,   -- derived, kept for fast reads, bumped by W03

    CONSTRAINT pk_videos PRIMARY KEY (video_id),
    CONSTRAINT fk_videos_channel FOREIGN KEY (channel_id)
        REFERENCES channels (channel_id) ON DELETE CASCADE, -- channel deleted -> its videos go too
    CONSTRAINT chk_videos_id_format   CHECK (video_id ~ '^[A-Za-z0-9_-]{11}$'),
    CONSTRAINT chk_videos_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT chk_videos_category    CHECK (category IN ('Comedy', 'Cooking', 'Education', 'Film', 'Gaming',
                                                          'Music', 'News', 'Sports', 'Tech', 'Vlogs')),
    CONSTRAINT chk_videos_duration    CHECK (duration_sec > 0),
    CONSTRAINT chk_videos_short_rule  CHECK (is_short = (duration_sec <= 60)),
    CONSTRAINT chk_videos_visibility  CHECK (visibility IN ('PUBLIC', 'UNLISTED', 'PRIVATE', 'SCHEDULED')),
    CONSTRAINT chk_videos_private_unpublished CHECK ((visibility = 'PRIVATE') = (published_at IS NULL)),
    CONSTRAINT chk_videos_publish_after_upload CHECK (published_at >= uploaded_at),
    CONSTRAINT chk_videos_view_count  CHECK (view_count >= 0)
);


-- subscriptions: M:N between users and channels
CREATE TABLE subscriptions (
    user_id        integer      NOT NULL,
    channel_id     integer      NOT NULL,
    notifications  varchar(12)  NOT NULL,
    subscribed_at  timestamptz  NOT NULL,

    CONSTRAINT pk_subscriptions PRIMARY KEY (user_id, channel_id),  -- can't subscribe twice
    CONSTRAINT fk_subscriptions_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_subscriptions_channel FOREIGN KEY (channel_id)
        REFERENCES channels (channel_id) ON DELETE CASCADE,
    CONSTRAINT chk_subscriptions_notifications CHECK (notifications IN ('ALL', 'PERSONALIZED', 'NONE'))
);


-- watch_events: every view, signed in or not
CREATE TABLE watch_events (
    watch_id        bigint       NOT NULL,   -- biggest table, 20x growth expected
    user_id         integer,                 -- NULL = logged-out view (or deleted account)
    video_id        varchar(11),             -- NULL only if the video is deleted later
    started_at      timestamptz  NOT NULL,
    watch_seconds   integer      NOT NULL,
    device          varchar(10)  NOT NULL,
    traffic_source  varchar(12)  NOT NULL,

    CONSTRAINT pk_watch_events PRIMARY KEY (watch_id),
    CONSTRAINT fk_watch_events_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE SET NULL,      -- keep the view, drop the link
    CONSTRAINT fk_watch_events_video FOREIGN KEY (video_id)
        REFERENCES videos (video_id) ON DELETE SET NULL,    -- keep platform totals and revenue
    CONSTRAINT chk_watch_events_seconds CHECK (watch_seconds >= 0),   -- 458 rows are exactly 0
    CONSTRAINT chk_watch_events_device  CHECK (device IN ('ANDROID', 'IOS', 'WEB', 'TV')),
    CONSTRAINT chk_watch_events_traffic CHECK (traffic_source IN ('HOME', 'SUGGESTED', 'SEARCH', 'SUBSCRIPTION',
                                                                  'SHORTS_FEED', 'EXTERNAL'))
);


-- video_reactions: one like or dislike per user per video
CREATE TABLE video_reactions (
    user_id     integer      NOT NULL,
    video_id    varchar(11)  NOT NULL,
    reaction    varchar(7)   NOT NULL,
    reacted_at  timestamptz  NOT NULL,

    CONSTRAINT pk_video_reactions PRIMARY KEY (user_id, video_id),
    CONSTRAINT fk_video_reactions_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_video_reactions_video FOREIGN KEY (video_id)
        REFERENCES videos (video_id) ON DELETE CASCADE,
    CONSTRAINT chk_video_reactions_type CHECK (reaction IN ('LIKE', 'DISLIKE'))
);


-- comments: top-level comments and replies (self-reference)
CREATE TABLE comments (
    comment_id         integer      NOT NULL,
    video_id           varchar(11)  NOT NULL,
    user_id            integer      NOT NULL,
    parent_comment_id  integer,                -- NULL = top-level comment
    body               text         NOT NULL,
    like_count         integer      NOT NULL DEFAULT 0,
    is_pinned          boolean      NOT NULL DEFAULT false,
    created_at         timestamptz  NOT NULL,

    CONSTRAINT pk_comments PRIMARY KEY (comment_id),
    CONSTRAINT fk_comments_video FOREIGN KEY (video_id)
        REFERENCES videos (video_id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_parent FOREIGN KEY (parent_comment_id)
        REFERENCES comments (comment_id) ON DELETE CASCADE, -- deleting a comment removes its replies
    CONSTRAINT chk_comments_body_not_blank CHECK (btrim(body) <> ''),
    CONSTRAINT chk_comments_like_count     CHECK (like_count >= 0),
    CONSTRAINT chk_comments_not_own_parent CHECK (parent_comment_id <> comment_id),
    CONSTRAINT chk_comments_reply_not_pinned CHECK (NOT (is_pinned AND parent_comment_id IS NOT NULL))
);


-- playlists
CREATE TABLE playlists (
    playlist_id    integer       NOT NULL,
    owner_user_id  integer       NOT NULL,
    title          varchar(150)  NOT NULL,   -- not unique per owner, two users have duplicate titles
    visibility     varchar(8)    NOT NULL,
    created_at     timestamptz   NOT NULL,

    CONSTRAINT pk_playlists PRIMARY KEY (playlist_id),
    CONSTRAINT fk_playlists_owner FOREIGN KEY (owner_user_id)
        REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT chk_playlists_visibility CHECK (visibility IN ('PUBLIC', 'UNLISTED', 'PRIVATE'))
);


-- playlist_items: videos in a playlist, in order
CREATE TABLE playlist_items (
    playlist_id  integer      NOT NULL,
    position     smallint     NOT NULL,
    video_id     varchar(11)  NOT NULL,
    added_at     timestamptz  NOT NULL,

    CONSTRAINT pk_playlist_items PRIMARY KEY (playlist_id, position),     -- one video per slot
    CONSTRAINT uq_playlist_items_video UNIQUE (playlist_id, video_id),    -- same video can't be added twice
    CONSTRAINT fk_playlist_items_playlist FOREIGN KEY (playlist_id)
        REFERENCES playlists (playlist_id) ON DELETE CASCADE,
    CONSTRAINT fk_playlist_items_video FOREIGN KEY (video_id)
        REFERENCES videos (video_id) ON DELETE CASCADE,
    CONSTRAINT chk_playlist_items_position CHECK (position >= 1)
);


-- ad_impressions: ads shown during a view, and what they earned
CREATE TABLE ad_impressions (
    impression_id  bigint         NOT NULL,
    watch_id       bigint         NOT NULL,
    ad_format      varchar(7)     NOT NULL,
    revenue_inr    numeric(10,4)  NOT NULL,   -- money: exact decimal, never float
    shown_at       timestamptz    NOT NULL,

    CONSTRAINT pk_ad_impressions PRIMARY KEY (impression_id),
    CONSTRAINT fk_ad_impressions_watch FOREIGN KEY (watch_id)
        REFERENCES watch_events (watch_id) ON DELETE RESTRICT,  -- revenue records can't vanish
    CONSTRAINT chk_ad_impressions_format  CHECK (ad_format IN ('PREROLL', 'MIDROLL')),
    CONSTRAINT chk_ad_impressions_revenue CHECK (revenue_inr > 0)
);
