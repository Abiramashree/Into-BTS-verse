-- Into BTSVerse reporting views.

-- Spotify streams per song per snapshot. Tracks of one song within 1% of each other count once.
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
CREATE OR REPLACE VIEW song_mv_views AS
SELECT v.song_id, n.observed_at, sum(n.views) AS views, count(DISTINCT n.video_id) AS videos
FROM video_snapshot n JOIN video v USING (video_id)
WHERE v.kind = 'mv' AND v.version = 'original' AND v.song_id IS NOT NULL
GROUP BY ALL;

-- Audio features per song. key: pitch class, 0 = C, -1 = none. mode: 1 = major, 0 = minor. loudness: dB.
CREATE OR REPLACE VIEW song_audio AS
WITH rb AS (
    SELECT s.song_id, 'reccobeats' AS source, s.track_id, f.feature, f.value
    FROM song_audio_track s JOIN track_audio f USING (track_id)
), lb AS (
    SELECT e.song_id, 'librosa' AS source, NULL AS track_id, e.feature, e.value
    FROM song_audio_estimate e WHERE e.song_id NOT IN (SELECT song_id FROM rb)
)
PIVOT (SELECT * FROM rb UNION ALL SELECT * FROM lb)
ON feature IN ('tempo', 'energy', 'danceability', 'valence', 'acousticness', 'instrumentalness', 'liveness', 'speechiness',
               'loudness', 'key', 'mode')
USING first(value) GROUP BY song_id, source, track_id;

-- One row per song, with latest totals.
CREATE OR REPLACE VIEW song_summary AS
WITH latest_streams AS (
    SELECT song_id, arg_max(streams, observed_at) AS spotify_streams FROM song_spotify_streams GROUP BY 1
), latest_views AS (
    SELECT song_id, arg_max(views, observed_at) AS mv_views FROM song_mv_views GROUP BY 1
), hot100 AS (
    SELECT song_id, min(rank) AS hot100_peak, count(*) AS hot100_weeks FROM hot100_entry WHERE song_id IS NOT NULL GROUP BY 1
)
SELECT
    s.song_id, s.slug, s.title, s.title_ko, s.is_single, s.first_release_date, s.album_id, al.title AS album,
    ls.spotify_streams, lv.mv_views, h.hot100_peak, h.hot100_weeks,
    a.energy, a.valence, a.danceability, a.tempo, a.acousticness,
    (SELECT count(DISTINCT person_id) FROM credit c WHERE c.song_id = s.song_id) AS credited_people
FROM song s
LEFT JOIN album al USING (album_id)
LEFT JOIN latest_streams ls USING (song_id)
LEFT JOIN latest_views lv USING (song_id)
LEFT JOIN song_audio a USING (song_id)
LEFT JOIN hot100 h USING (song_id);

-- Credits per song and person, as writer or producer.
CREATE OR REPLACE VIEW song_credit AS
SELECT DISTINCT c.song_id, c.person_id, p.is_member, CASE WHEN c.role = 'producer' THEN 'producer' ELSE 'writer' END AS role
FROM credit c JOIN person p USING (person_id);

-- One row per album, EP or single. Totals cover songs first released on it.
CREATE OR REPLACE VIEW album_summary AS
WITH songs AS (
    SELECT ss.song_id, ss.title, ss.is_single, ss.album_id,
        ss.spotify_streams, ss.mv_views, ss.hot100_peak, ss.energy, ss.valence, ss.danceability, ss.tempo
    FROM song_summary ss
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
CREATE OR REPLACE VIEW person_summary AS
WITH songs AS (
    SELECT DISTINCT c.person_id, c.song_id, ss.title, ss.first_release_date, ss.spotify_streams, ss.hot100_peak, ss.album_id
    FROM song_credit c JOIN song_summary ss USING (song_id)
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

-- Daily streams per song, spread evenly between snapshots.
CREATE OR REPLACE VIEW song_streams_by_day AS
SELECT t.day::DATE AS day, d.song_id, (d.streams_gained / d.days)::DECIMAL(24, 6) AS streams
FROM song_streams_daily d, range(d.period_start, d.period_end, INTERVAL 1 DAY) t(day)
WHERE d.streams_gained IS NOT NULL;

-- Streams per day per song in 2024, 2025 and April to October 2026. Each window requires data on 75% of its days.
CREATE OR REPLACE VIEW song_longevity AS
WITH w AS (
    SELECT * FROM (VALUES ('y2024', DATE '2024-01-01', DATE '2025-01-01'), ('y2025', DATE '2025-01-01', DATE '2026-01-01'),
                          ('since_arirang', DATE '2026-04-01', DATE '2026-11-01')) t(name, start, stop)
), per AS (
    SELECT b.song_id, w.name, avg(b.streams) AS per_day, count(*) AS days, any_value(w.stop - w.start) AS window_days,
        any_value(w.start) AS start
    FROM song_streams_by_day b JOIN w ON b.day >= w.start AND b.day < w.stop
    GROUP BY ALL
), ok AS (
    SELECT p.song_id, p.name, round(p.per_day, 0) AS per_day
    FROM per p JOIN song s USING (song_id)
    WHERE s.first_release_date <= p.start AND p.days >= 0.75 * p.window_days
), wide AS (
    PIVOT ok ON name IN ('y2024', 'y2025', 'since_arirang') USING first(per_day) GROUP BY song_id
)
SELECT w.song_id,
    w.y2024 AS daily_2024, w.y2025 AS daily_2025, round(w.y2025 / w.y2024 - 1, 3) AS change_2025,
    w.since_arirang AS daily_since_arirang, round(w.since_arirang / w.y2025 - 1, 3) AS lift_since_arirang
FROM wide w;

-- Streams per album per calendar month.
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
CREATE OR REPLACE VIEW song_streams_monthly AS
SELECT song_id, date_trunc('month', day)::DATE AS month, round(avg(streams), 0)::BIGINT AS streams_per_day, count(*) AS days
FROM song_streams_by_day
GROUP BY ALL;

-- Analytical signals per song. Rates compare the last 90 days with the 90 before. revival_score: largest monthly
-- surge against the song's prior 6-month median (at least 5,000 streams per day), net of the same surge for songs a
-- year or more old, for songs released a year or more before. has_revival: that month at least doubled.
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
), peak AS (
    SELECT song_id, max(streams_per_day) AS peak, arg_max(streams_per_day, month) AS latest
    FROM months GROUP BY 1
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
), credits AS (
    SELECT song_id,
        count(DISTINCT person_id) FILTER (WHERE role = 'writer') AS writer_count,
        count(DISTINCT person_id) FILTER (WHERE role = 'producer') AS producer_count,
        round(count(DISTINCT person_id) FILTER (WHERE role = 'writer' AND is_member)
              / nullif(count(DISTINCT person_id) FILTER (WHERE role = 'writer'), 0), 3) AS member_writer_share
    FROM song_credit GROUP BY 1
), base AS (
    SELECT s.song_id, s.slug, s.title, s.album_id, s.first_release_date,
        round((a.d0 - s.first_release_date) / 365.25, 1) AS release_age_years,
        ss.spotify_streams AS current_streams,
        CASE WHEN sp.n0 >= 68 THEN round(sp.r0, 0) END AS streams_per_day,
        CASE WHEN sp.n0 >= 68 AND sp.n1 >= 68 THEN round(sp.r0 / sp.r1 - 1, 3) END AS stream_growth_rate,
        CASE WHEN sp.n0 >= 68 AND sp.n1 >= 68 AND sp.n2 >= 68
             THEN round((sp.r0 / sp.r1 - 1) - (sp.r1 / sp.r2 - 1), 3) END AS growth_acceleration,
        CASE WHEN mv.n0 >= 68 THEN round(mv.v0, 0) END AS mv_views_per_day,
        CASE WHEN mv.n0 >= 68 AND mv.n1 >= 68 THEN round(mv.v0 / mv.v1 - 1, 3) END AS mv_growth_rate,
        ss.hot100_peak, ss.hot100_weeks,
        pk.peak AS peak_streams_per_day_since_2023,
        round(pk.latest / pk.peak, 3) AS retention_since_2023,
        lg.daily_2025,
        round(su.revival, 3) AS revival_score, su.revival_month, su.revival >= 1 AS has_revival,
        cr.writer_count, cr.producer_count, cr.member_writer_share,
        au.tempo, au.energy, au.danceability, au.valence,
        au.source AS audio_source,
        CASE au.source WHEN 'reccobeats' THEN 'verified' WHEN 'librosa' THEN 'estimated' END AS audio_confidence
    FROM song s
    CROSS JOIN anchor a
    LEFT JOIN song_summary ss ON ss.song_id = s.song_id
    LEFT JOIN spotify sp ON sp.song_id = s.song_id
    LEFT JOIN mv ON mv.song_id = s.song_id
    LEFT JOIN peak pk ON pk.song_id = s.song_id
    LEFT JOIN song_longevity lg ON lg.song_id = s.song_id
    LEFT JOIN surge su ON su.song_id = s.song_id
    LEFT JOIN credits cr ON cr.song_id = s.song_id
    LEFT JOIN song_audio au ON au.song_id = s.song_id
)
SELECT b.* EXCLUDE (daily_2025),
    CASE WHEN b.streams_per_day IS NOT NULL
         THEN round(100 * percent_rank() OVER (PARTITION BY b.streams_per_day IS NOT NULL ORDER BY b.streams_per_day)) END
        AS popularity_score,
    CASE WHEN b.daily_2025 IS NOT NULL AND b.first_release_date < DATE '2023-01-01'
         THEN round(100 * percent_rank() OVER (PARTITION BY b.daily_2025 IS NOT NULL AND b.first_release_date < DATE '2023-01-01'
                                              ORDER BY b.daily_2025)) END
        AS long_tail_score
FROM base b;
