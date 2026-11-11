-- Into BTSVerse reporting views.

-- Spotify streams per song per snapshot. Tracks of one song within 1% of each other count once.
-- observed_at: Snapshot date.
-- streams: Total Spotify streams of the song's original tracks.
-- tracks: Tracks counted.
CREATE OR REPLACE VIEW song_spotify_streams AS
WITH s AS (
    SELECT t.song_id, n.track_id, n.observed_at, n.value
    FROM track_snapshot n JOIN track t USING (track_id)
    WHERE t.platform = 'spotify' AND n.metric = 'streams' AND t.version = 'original' AND t.song_id IS NOT NULL
)
SELECT song_id, observed_at, sum(value) AS streams, count(DISTINCT track_id) AS tracks
FROM s
WHERE NOT EXISTS (
    SELECT 1 FROM s d
    WHERE d.song_id = s.song_id AND d.observed_at = s.observed_at AND d.track_id <> s.track_id
      AND abs(d.value - s.value) <= 0.01 * greatest(d.value, s.value)
      AND (d.value > s.value OR (d.value = s.value AND d.track_id < s.track_id))
)
GROUP BY ALL;

-- Streams gained between snapshots, per song. NULL where the total decreases or exceeds three times the daily figure.
-- period_start: Previous snapshot, or the release date.
-- period_end: This snapshot.
-- streams_gained: Streams gained in the period.
-- days: Days in the period.
-- streams_per_day: Streams gained per day in the period.
CREATE OR REPLACE VIEW song_streams_daily AS
WITH s AS (
    SELECT st.song_id, st.observed_at, st.streams,
        lag(st.streams) OVER w AS prev_streams, lag(st.observed_at) OVER w AS prev_at, so.first_release_date
    FROM song_spotify_streams st JOIN song so USING (song_id)
    WINDOW w AS (PARTITION BY st.song_id ORDER BY st.observed_at)
), daily AS (
    SELECT t.song_id, n.observed_at, sum(n.value) AS daily FROM track_snapshot n JOIN track t USING (track_id)
    WHERE t.platform = 'spotify' AND n.metric = 'daily' AND t.version = 'original' AND t.song_id IS NOT NULL GROUP BY ALL
), g AS (
    SELECT s.song_id, coalesce(s.prev_at, s.first_release_date) AS period_start, s.observed_at AS period_end,
        s.streams - coalesce(s.prev_streams, 0) AS gained,
        s.observed_at - coalesce(s.prev_at, s.first_release_date) AS days,
        greatest(a.daily, b.daily) AS kworb_daily
    FROM s
    LEFT JOIN daily a ON a.song_id = s.song_id AND a.observed_at = s.prev_at
    LEFT JOIN daily b ON b.song_id = s.song_id AND b.observed_at = s.observed_at
    WHERE s.prev_at IS NOT NULL OR s.first_release_date > (SELECT min(observed_at) FROM song_spotify_streams)
)
SELECT song_id, period_start, period_end,
    CASE WHEN gained >= 0 AND NOT coalesce(gained / days > 3 * kworb_daily, false) THEN gained END AS streams_gained,
    days,
    CASE WHEN gained >= 0 AND NOT coalesce(gained / days > 3 * kworb_daily, false) THEN round(gained / days, 0) END
        AS streams_per_day
FROM g;

-- Music video views per song per snapshot.
-- observed_at: Snapshot date.
-- views: Total views of the song's official music videos.
-- videos: Videos counted.
CREATE OR REPLACE VIEW song_mv_views AS
SELECT v.song_id, n.observed_at, sum(n.views) AS views, count(DISTINCT n.video_id) AS videos
FROM video_snapshot n JOIN video v USING (video_id)
WHERE v.kind = 'mv' AND v.version = 'original' AND v.song_id IS NOT NULL
GROUP BY ALL;

-- Audio features per track (Spotify's values, via ReccoBeats): one verified analysis each.
CREATE OR REPLACE VIEW verified_analysis AS
SELECT track_id AS verified_analysis_id, track_id, max(observed_at) AS observed_at,
    max(value) FILTER (WHERE feature = 'tempo') AS tempo, max(value) FILTER (WHERE feature = 'energy') AS energy,
    max(value) FILTER (WHERE feature = 'danceability') AS danceability, max(value) FILTER (WHERE feature = 'valence') AS valence,
    max(value) FILTER (WHERE feature = 'acousticness') AS acousticness, max(value) FILTER (WHERE feature = 'instrumentalness') AS instrumentalness,
    max(value) FILTER (WHERE feature = 'liveness') AS liveness, max(value) FILTER (WHERE feature = 'speechiness') AS speechiness,
    max(value) FILTER (WHERE feature = 'loudness') AS loudness, max(value) FILTER (WHERE feature = 'key') AS key,
    max(value) FILTER (WHERE feature = 'mode') AS mode
FROM track_audio GROUP BY track_id;

-- Audio features estimated from a song's preview: one estimated analysis each.
CREATE OR REPLACE VIEW estimated_analysis AS
SELECT song_id AS estimated_analysis_id, song_id, max(observed_at) AS observed_at,
    max(value) FILTER (WHERE feature = 'tempo') AS tempo, max(value) FILTER (WHERE feature = 'energy') AS energy,
    NULL::DOUBLE AS danceability, NULL::DOUBLE AS valence, NULL::DOUBLE AS acousticness, NULL::DOUBLE AS instrumentalness,
    NULL::DOUBLE AS liveness, NULL::DOUBLE AS speechiness, NULL::DOUBLE AS loudness, NULL::DOUBLE AS key, NULL::DOUBLE AS mode
FROM song_audio_estimate GROUP BY song_id;

-- Audio features per song: its audio profile, the verified analysis of the track on its album or else its preview
-- estimate. key: pitch class, 0 = C, -1 = none. mode: 1 = major, 0 = minor. loudness: dB.
-- source: reccobeats for verified audio, librosa for estimated.
CREATE OR REPLACE VIEW song_audio AS
SELECT t.song_id, 'reccobeats' AS source, v.track_id, v.tempo, v.energy, v.danceability, v.valence, v.acousticness,
    v.instrumentalness, v.liveness, v.speechiness, v.loudness, v.key, v.mode
FROM song_audio_track t JOIN verified_analysis v USING (track_id)
UNION ALL
SELECT e.song_id, 'librosa', NULL::INTEGER, e.tempo, e.energy, e.danceability, e.valence, e.acousticness,
    e.instrumentalness, e.liveness, e.speechiness, e.loudness, e.key, e.mode
FROM estimated_analysis e WHERE e.song_id NOT IN (SELECT song_id FROM song_audio_track);

-- Credits per song and person, as writer or producer.
-- is_member: A member of BTS.
-- role: writer (writer, lyricist or composer) or producer.
CREATE OR REPLACE VIEW song_credit AS
SELECT DISTINCT c.song_id, c.person_id, p.is_member, CASE WHEN c.role = 'producer' THEN 'producer' ELSE 'writer' END AS role
FROM credit c JOIN person p USING (person_id);

-- Daily streams per song, spread evenly between snapshots.
CREATE OR REPLACE VIEW song_streams_by_day AS
SELECT t.day::DATE AS day, d.song_id, (d.streams_gained / d.days)::DECIMAL(24, 6) AS streams
FROM song_streams_daily d, range(d.period_start, d.period_end, INTERVAL 1 DAY) t(day)
WHERE d.streams_gained IS NOT NULL;

-- Streams per album per calendar month.
-- month: Calendar month.
-- streams: Streams of the release's songs that month.
-- streams_per_day: That month's streams per day.
CREATE OR REPLACE VIEW album_streams_monthly AS
WITH bounds AS (
    SELECT date_trunc('month', min(observed_at)) + INTERVAL 1 MONTH AS m0, date_trunc('month', max(observed_at)) AS m1
    FROM song_spotify_streams
)
SELECT date_trunc('month', day)::DATE AS month, s.album_id,
    round(sum(streams), 0)::BIGINT AS streams,
    round(sum(streams) / any_value(day(last_day(day))), 0) AS streams_per_day
FROM song_streams_by_day JOIN song s USING (song_id), bounds
WHERE day >= m0 AND day < m1
GROUP BY ALL;

-- Daily music video views per song, spread evenly between snapshots.
CREATE OR REPLACE VIEW song_mv_by_day AS
WITH s AS (
    SELECT song_id, observed_at, views,
        lag(views) OVER w AS prev_views, lag(observed_at) OVER w AS prev_at
    FROM song_mv_views
    WINDOW w AS (PARTITION BY song_id ORDER BY observed_at)
)
SELECT t.day::DATE AS day, s.song_id, ((s.views - s.prev_views) / (s.observed_at - s.prev_at))::DECIMAL(24, 6) AS views
FROM s, range(s.prev_at, s.observed_at, INTERVAL 1 DAY) t(day)
WHERE s.prev_at IS NOT NULL AND s.views >= s.prev_views;

-- Monthly average daily streams per song.
-- month: Calendar month.
-- streams_per_day: Average streams per day that month.
-- days: Days with data that month.
CREATE OR REPLACE VIEW song_streams_monthly AS
SELECT song_id, date_trunc('month', day)::DATE AS month, round(avg(streams), 0)::BIGINT AS streams_per_day, count(*) AS days
FROM song_streams_by_day
GROUP BY ALL;

-- One row per song: catalog facts, latest totals and analytical signals. Rates compare the last 90 days with the 90
-- before. long_tail_score: percentile of 2025 streams per day among songs released before 2023, the measure of staying
-- power. revival_score: largest monthly
-- surge against the song's prior 6-month median (at least 5,000 streams per day), net of the same surge for songs a
-- year or more old, for songs released a year or more before. has_revival: that month at least doubled.
-- album: Title of the song's first release.
-- audio_source: reccobeats for verified audio, librosa for estimated.
CREATE OR REPLACE VIEW song_intelligence AS
WITH anchor AS (
    SELECT max(day) + 1 AS d0 FROM song_streams_by_day
), spotify AS (
    SELECT b.song_id,
        avg(b.streams) FILTER (WHERE b.day >= a.d0 - 90) AS r0,
        avg(b.streams) FILTER (WHERE b.day >= a.d0 - 180 AND b.day < a.d0 - 90) AS r1,
        avg(b.streams) FILTER (WHERE b.day >= a.d0 - 270 AND b.day < a.d0 - 180) AS r2,
        count(*) FILTER (WHERE b.day >= a.d0 - 90) AS n0,
        count(*) FILTER (WHERE b.day >= a.d0 - 180 AND b.day < a.d0 - 90) AS n1,
        count(*) FILTER (WHERE b.day >= a.d0 - 270 AND b.day < a.d0 - 180) AS n2
    FROM song_streams_by_day b CROSS JOIN anchor a
    GROUP BY 1
), mv AS (
    SELECT m.song_id,
        avg(m.views) FILTER (WHERE m.day >= a.d0 - 90) AS v0,
        avg(m.views) FILTER (WHERE m.day >= a.d0 - 180 AND m.day < a.d0 - 90) AS v1,
        count(*) FILTER (WHERE m.day >= a.d0 - 90) AS n0,
        count(*) FILTER (WHERE m.day >= a.d0 - 180 AND m.day < a.d0 - 90) AS n1
    FROM song_mv_by_day m CROSS JOIN anchor a
    GROUP BY 1
), months AS (
    SELECT * FROM song_streams_monthly WHERE days >= 28
), catalog AS (
    SELECT m.month, sum(m.streams_per_day) AS total
    FROM months m JOIN song s USING (song_id)
    WHERE m.month >= s.first_release_date + INTERVAL 1 YEAR
    GROUP BY 1
), catalog_ratio AS (
    SELECT c.month, c.total / median(p.total) AS ratio
    FROM catalog c JOIN catalog p ON p.month < c.month AND p.month >= c.month - INTERVAL 6 MONTH
    GROUP BY c.month, c.total
    HAVING count(*) = 6
), song_base AS (
    SELECT m.song_id, m.month, m.streams_per_day,
        (SELECT median(p.streams_per_day) FROM months p
         WHERE p.song_id = m.song_id AND p.month < m.month AND p.month >= m.month - INTERVAL 6 MONTH) AS median_6m,
        (SELECT count(*) FROM months p
         WHERE p.song_id = m.song_id AND p.month < m.month AND p.month >= m.month - INTERVAL 6 MONTH) AS base_months
    FROM months m
), surge AS (
    SELECT b.song_id, max((b.streams_per_day / b.median_6m) / cr.ratio - 1) AS revival,
        arg_max(b.month, (b.streams_per_day / b.median_6m) / cr.ratio) AS revival_month
    FROM song_base b
    JOIN song s ON s.song_id = b.song_id
    JOIN catalog_ratio cr ON cr.month = b.month
    WHERE b.base_months = 6 AND b.median_6m >= 5000 AND b.month >= s.first_release_date + INTERVAL 1 YEAR
    GROUP BY 1
), latest AS (
    SELECT song_id, arg_max(streams, observed_at) AS spotify_streams FROM song_spotify_streams GROUP BY 1
), views AS (
    SELECT song_id, arg_max(views, observed_at) AS mv_views FROM song_mv_views GROUP BY 1
), hot100 AS (
    SELECT song_id, min(rank) AS hot100_peak, count(*) AS hot100_weeks FROM hot100_entry WHERE song_id IS NOT NULL GROUP BY 1
), y2025 AS (
    -- Streams per day in 2025, for songs released by then with data on at least 75% of its days.
    SELECT b.song_id, round(avg(b.streams), 0) AS per_day
    FROM song_streams_by_day b JOIN song s USING (song_id)
    WHERE b.day >= DATE '2025-01-01' AND b.day < DATE '2026-01-01' AND s.first_release_date <= DATE '2025-01-01'
    GROUP BY 1 HAVING count(*) >= 0.75 * 365
), credits AS (
    SELECT song_id,
        count(DISTINCT person_id) FILTER (WHERE role = 'writer') AS writer_count,
        count(DISTINCT person_id) FILTER (WHERE role = 'producer') AS producer_count,
        round(count(DISTINCT person_id) FILTER (WHERE role = 'writer' AND is_member)
              / nullif(count(DISTINCT person_id) FILTER (WHERE role = 'writer'), 0), 3) AS member_writer_share
    FROM song_credit GROUP BY 1
), base AS (
    SELECT s.song_id, s.slug, s.title, s.title_ko, s.is_single, s.album_id, al.title AS album, s.first_release_date,
        round((a.d0 - s.first_release_date) / 365.25, 1) AS release_age_years,
        ls.spotify_streams AS current_streams, lv.mv_views,
        CASE WHEN sp.n0 >= 68 THEN round(sp.r0, 0) END AS streams_per_day,
        CASE WHEN sp.n0 >= 68 AND sp.n1 >= 68 THEN round(sp.r0 / sp.r1 - 1, 3) END AS stream_growth_rate,
        CASE WHEN sp.n0 >= 68 AND sp.n1 >= 68 AND sp.n2 >= 68
             THEN round((sp.r0 / sp.r1 - 1) - (sp.r1 / sp.r2 - 1), 3) END AS growth_acceleration,
        CASE WHEN mv.n0 >= 68 THEN round(mv.v0, 0) END AS mv_views_per_day,
        CASE WHEN mv.n0 >= 68 AND mv.n1 >= 68 THEN round(mv.v0 / mv.v1 - 1, 3) END AS mv_growth_rate,
        h.hot100_peak, h.hot100_weeks,
        y.per_day AS streams_per_day_2025,
        round(su.revival, 3) AS revival_score, su.revival_month, su.revival >= 1 AS has_revival,
        cr.writer_count, cr.producer_count, cr.member_writer_share,
        au.tempo, au.energy, au.danceability, au.valence,
        au.source AS audio_source,
        CASE au.source WHEN 'reccobeats' THEN 'verified' WHEN 'librosa' THEN 'estimated' END AS audio_confidence
    FROM song s
    CROSS JOIN anchor a
    LEFT JOIN album al ON al.album_id = s.album_id
    LEFT JOIN latest ls ON ls.song_id = s.song_id
    LEFT JOIN views lv ON lv.song_id = s.song_id
    LEFT JOIN hot100 h ON h.song_id = s.song_id
    LEFT JOIN spotify sp ON sp.song_id = s.song_id
    LEFT JOIN mv ON mv.song_id = s.song_id
    LEFT JOIN y2025 y ON y.song_id = s.song_id
    LEFT JOIN surge su ON su.song_id = s.song_id
    LEFT JOIN credits cr ON cr.song_id = s.song_id
    LEFT JOIN song_audio au ON au.song_id = s.song_id
)
SELECT b.*,
    CASE WHEN b.streams_per_day IS NOT NULL
         THEN round(100 * percent_rank() OVER (PARTITION BY b.streams_per_day IS NOT NULL ORDER BY b.streams_per_day)) END
        AS popularity_score,
    CASE WHEN b.streams_per_day_2025 IS NOT NULL AND b.first_release_date < DATE '2023-01-01'
         THEN round(100 * percent_rank() OVER (PARTITION BY b.streams_per_day_2025 IS NOT NULL AND b.first_release_date < DATE '2023-01-01'
                                              ORDER BY b.streams_per_day_2025)) END
        AS long_tail_score
FROM base b;

-- One row per album, EP or single. Totals cover songs first released on it.
-- kind: Album, EP or Single.
-- new_songs: Songs first released on it.
-- singles: Of those, songs released as singles.
-- spotify_streams: Spotify streams of its new songs.
-- median_song_streams: Median Spotify streams of its new songs.
-- top_song: Its most-streamed new song.
-- mv_views: Music video views of its new songs.
-- hot100_songs: New songs that reached the Hot 100.
-- best_hot100_peak: Best Hot 100 position among its new songs.
-- bb200_weeks: Weeks the release spent on the Billboard 200.
-- bb200_peak: Its best Billboard 200 position.
-- audio_songs: New songs with audio features.
-- avg_tempo: Average tempo of its new songs.
-- avg_energy: Average energy of its new songs.
-- avg_valence: Average valence of its new songs.
-- avg_danceability: Average danceability of its new songs.
-- credited_songs: New songs with credits.
-- writers: People credited as writer across its new songs.
-- producers: People credited as producer across its new songs.
-- member_writer_share: Share of its writer credits held by members.
CREATE OR REPLACE VIEW album_summary AS
WITH songs AS (
    SELECT ss.song_id, ss.title, ss.is_single, ss.album_id,
        ss.current_streams AS spotify_streams, ss.mv_views, ss.hot100_peak, ss.energy, ss.valence, ss.danceability, ss.tempo
    FROM song_intelligence ss
    WHERE ss.album_id IS NOT NULL
), bb200 AS (
    SELECT album_id, count(*) AS weeks, min(rank) AS peak FROM billboard200_entry GROUP BY 1
), credits AS (
    SELECT s.album_id, c.* FROM song_credit c JOIN songs s USING (song_id)
)
SELECT
    a.album_id, a.slug, a.title, a.kind, a.release_date, a.track_count,
    count(s.song_id) AS new_songs,
    count(*) FILTER (WHERE s.is_single) AS singles,
    sum(s.spotify_streams) AS spotify_streams,
    median(s.spotify_streams) AS median_song_streams,
    arg_max(s.title, s.spotify_streams) AS top_song,
    sum(s.mv_views) AS mv_views,
    count(s.hot100_peak) AS hot100_songs,
    min(s.hot100_peak) AS best_hot100_peak,
    any_value(b.weeks) AS bb200_weeks,
    any_value(b.peak) AS bb200_peak,
    count(s.tempo) AS audio_songs,
    round(avg(s.tempo), 1) AS avg_tempo,
    round(avg(s.energy), 3) AS avg_energy,
    round(avg(s.valence), 3) AS avg_valence,
    round(avg(s.danceability), 3) AS avg_danceability,
    (SELECT nullif(count(DISTINCT song_id), 0) FROM credits c WHERE c.album_id = a.album_id) AS credited_songs,
    (SELECT CASE WHEN count(*) > 0 THEN count(DISTINCT person_id) FILTER (WHERE role = 'writer') END
     FROM credits c WHERE c.album_id = a.album_id) AS writers,
    (SELECT CASE WHEN count(*) > 0 THEN count(DISTINCT person_id) FILTER (WHERE role = 'producer') END
     FROM credits c WHERE c.album_id = a.album_id) AS producers,
    (SELECT round(avg(is_member::INT), 3) FROM credits c WHERE c.album_id = a.album_id AND role = 'writer') AS member_writer_share
FROM album a
LEFT JOIN songs s ON s.album_id = a.album_id
LEFT JOIN bb200 b ON b.album_id = a.album_id
GROUP BY a.album_id, a.slug, a.title, a.kind, a.release_date, a.track_count;

-- One row per credited person.
-- is_member: A member of BTS.
-- roles: Roles credited: writer, producer.
-- songs_written: Songs credited as writer.
-- songs_produced: Songs credited as producer.
-- songs: Songs credited in any role.
-- releases: First releases those songs came out on.
-- first_year: Year of the earliest credited song.
-- last_year: Year of the latest credited song.
-- spotify_streams: Spotify streams of credited songs.
-- top_song: The most-streamed credited song.
-- hot100_songs: Credited songs that reached the Hot 100.
CREATE OR REPLACE VIEW person_summary AS
WITH songs AS (
    SELECT DISTINCT c.person_id, c.song_id, ss.title, ss.first_release_date, ss.current_streams AS spotify_streams, ss.hot100_peak, ss.album_id
    FROM song_credit c JOIN song_intelligence ss USING (song_id)
)
SELECT
    p.person_id, p.slug, p.display_name AS name, p.is_member,
    (SELECT string_agg(DISTINCT role, ', ' ORDER BY role) FROM song_credit c WHERE c.person_id = p.person_id) AS roles,
    (SELECT count(DISTINCT song_id) FROM song_credit c WHERE c.person_id = p.person_id AND role = 'writer') AS songs_written,
    (SELECT count(DISTINCT song_id) FROM song_credit c WHERE c.person_id = p.person_id AND role = 'producer') AS songs_produced,
    count(*) AS songs,
    count(DISTINCT s.album_id) AS releases,
    year(min(s.first_release_date)) AS first_year,
    year(max(s.first_release_date)) AS last_year,
    sum(s.spotify_streams) AS spotify_streams,
    arg_max(s.title, s.spotify_streams) AS top_song,
    count(s.hot100_peak) AS hot100_songs
FROM person p JOIN songs s USING (person_id)
GROUP BY p.person_id, p.slug, p.display_name, p.is_member;
