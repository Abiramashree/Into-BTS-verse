-- Into BTSVerse knowledge graph: nodes and edges built from the warehouse. Classes and relations come from
-- ontology.ttl (graph_class, graph_relation).

-- Nodes: one per entity, keyed table:id with the warehouse ID (person:12 is person_id 12). class: the most specific
-- ontology class (member, album, single).
CREATE TABLE node (
    node_id VARCHAR PRIMARY KEY,
    class VARCHAR NOT NULL REFERENCES graph_class (class),
    entity_id INTEGER NOT NULL,
    label VARCHAR NOT NULL,
    detail VARCHAR
);

INSERT INTO node VALUES
    ('group:1', 'group', 1, 'BTS', NULL),
    ('chart:1', 'chart', 1, 'Billboard Hot 100', NULL),
    ('chart:2', 'chart', 2, 'Billboard 200', NULL);

INSERT INTO node
SELECT 'person:' || person_id, CASE WHEN is_member THEN 'member' ELSE 'person' END, person_id, display_name, NULL FROM person;

INSERT INTO node
SELECT 'song:' || song_id, coalesce(nullif(lower(regexp_extract(title, '(?i)^(intro|outro|interlude|skit)(?:duction)?\b', 1)), ''), 'song'), song_id, title,
       year(first_release_date)::VARCHAR
FROM song;

INSERT INTO node
SELECT 'album:' || album_id, lower(kind::VARCHAR), album_id, title, kind || ' · ' || year(release_date) FROM album;

INSERT INTO node
SELECT 'recording:' || recording_id, 'recording', recording_id, title,
       concat_ws(' · ', coalesce(version_label, version::VARCHAR), year(first_release_date)::VARCHAR)
FROM recording;

INSERT INTO node
SELECT 'track:' || track_id, 'track', track_id, title,
       concat_ws(' · ', CASE platform WHEN 'spotify' THEN 'Spotify' ELSE 'Deezer' END, version::VARCHAR)
FROM track WHERE song_id IS NOT NULL;

INSERT INTO node
SELECT 'video:' || video_id, 'video', video_id, title,
       concat_ws(' · ', replace(kind::VARCHAR, '_', ' '), year(published_month)::VARCHAR)
FROM video WHERE match = 'song';

INSERT INTO node
SELECT 'verified_analysis:' || a.verified_analysis_id, 'verified_analysis', a.verified_analysis_id, t.title, t.version::VARCHAR
FROM verified_analysis a JOIN track t USING (track_id) WHERE t.song_id IS NOT NULL;

INSERT INTO node
SELECT 'estimated_analysis:' || a.estimated_analysis_id, 'estimated_analysis', a.estimated_analysis_id, s.title, 'preview'
FROM estimated_analysis a JOIN song s USING (song_id);

INSERT INTO node
SELECT 'album_series:' || album_series_id, 'album_series', album_series_id, title, NULL FROM album_series;

-- Edges. evidence: what supports the edge, as label-value pairs.
CREATE TABLE edge (
    source VARCHAR NOT NULL REFERENCES node (node_id),
    relation VARCHAR NOT NULL,
    target VARCHAR NOT NULL REFERENCES node (node_id),
    weight DOUBLE NOT NULL,
    evidence STRUCT(label VARCHAR, value VARCHAR)[] NOT NULL,
    provenance VARCHAR,                    -- The source of this claim (graph_term)
    confidence VARCHAR,                    -- stated, verified, estimated or inferred (graph_term)
    PRIMARY KEY (source, relation, target)
);

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'person:' || person_id, 'member_of', 'group:1', 1, [] FROM person WHERE is_member;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'song:' || song_id, 'by_artist', 'group:1', 1, [] FROM song
UNION ALL
SELECT 'album:' || album_id, 'by_artist', 'group:1', 1, [] FROM album;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'song:' || song_id,
       CASE role WHEN 'writer' THEN 'written_by' WHEN 'lyricist' THEN 'lyrics_by' WHEN 'composer' THEN 'music_by' ELSE 'produced_by' END,
       'person:' || person_id, 1,
       list_transform(list_sort(pages), lambda p: {'label': 'source', 'value': 'Wikipedia: ' || p})
FROM credit;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'song:' || song_id, 'on_album', 'album:' || album_id, 1,
       list({'label': 'track', 'value': 'Disc ' || disc || ', track ' || position
             || CASE WHEN version <> 'original' THEN ' (' || version || ')' ELSE '' END} ORDER BY disc, position)
FROM album_track WHERE song_id IS NOT NULL GROUP BY song_id, album_id;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'song:' || song_id, 'first_released_on', 'album:' || album_id, 1,
       [{'label': 'source', 'value': CASE album_from WHEN 'apple' THEN 'Apple' ELSE 'MusicBrainz' END}]
FROM song WHERE album_id IS NOT NULL;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'recording:' || recording_id, 'recording_of', 'song:' || song_id, 1,
       list_filter([
           {'label': 'version', 'value': coalesce(version_label, version::VARCHAR)},
           {'label': 'released', 'value': CASE first_release_precision WHEN 'year' THEN strftime(first_release_date, '%Y')
                                               WHEN 'month' THEN strftime(first_release_date, '%b %Y')
                                               ELSE strftime(first_release_date, '%-d %b %Y') END},
           {'label': 'length', 'value': (length_ms // 60000) || ':' || lpad(((length_ms // 1000) % 60)::VARCHAR, 2, '0')}
       ], lambda e: e.value IS NOT NULL)
FROM recording;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'track:' || track_id, CASE WHEN recording_id IS NULL THEN 'track_of_song' ELSE 'track_of' END,
       coalesce('recording:' || recording_id, 'song:' || song_id), 1,
       [{'label': 'platform', 'value': CASE platform WHEN 'spotify' THEN 'Spotify' ELSE 'Deezer' END},
        {'label': 'version', 'value': version::VARCHAR}]
FROM track WHERE song_id IS NOT NULL;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'video:' || video_id, 'video_of', 'song:' || song_id, 1,
       list_filter([{'label': 'kind', 'value': replace(kind::VARCHAR, '_', ' ')},
                    {'label': 'published', 'value': strftime(published_month, '%b %Y')}], lambda e: e.value IS NOT NULL)
FROM video WHERE match = 'song';

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'song:' || song_id, 'charted_on', 'chart:1', count(*),
       [{'label': 'peak', 'value': '#' || min(rank)}, {'label': 'weeks', 'value': count(*)::VARCHAR},
        {'label': 'first week', 'value': strftime(min(week), '%-d %b %Y')},
        {'label': 'last week', 'value': strftime(max(week), '%-d %b %Y')}]
FROM hot100_entry WHERE song_id IS NOT NULL GROUP BY song_id
UNION ALL
SELECT 'album:' || album_id, 'charted_on', 'chart:2', count(*),
       [{'label': 'peak', 'value': '#' || min(rank)}, {'label': 'weeks', 'value': count(*)::VARCHAR},
        {'label': 'first week', 'value': strftime(min(week), '%-d %b %Y')},
        {'label': 'last week', 'value': strftime(max(week), '%-d %b %Y')}]
FROM billboard200_entry GROUP BY album_id;

INSERT INTO edge (source, relation, target, weight, evidence)
WITH together AS (
    SELECT DISTINCT a.person_id AS p, b.person_id AS q, a.song_id
    FROM credit a JOIN credit b ON a.song_id = b.song_id AND a.person_id <> b.person_id
)
SELECT 'person:' || p, 'collaborated_with', 'person:' || q, count(*),
       list({'label': 'song', 'value': s.title} ORDER BY s.first_release_date, s.title)
FROM together JOIN song s USING (song_id)
WHERE 'person:' || p < 'person:' || q
GROUP BY p, q;

-- Songs with only estimated audio, placed against songs with verified audio on tempo and energy (the features previews
-- estimate). Each estimated song keeps its five nearest.
INSERT INTO edge (source, relation, target, weight, evidence)
WITH audio AS (
    SELECT song_id, source = 'librosa' AS estimated, tempo, energy FROM song_audio
), stats AS (
    SELECT avg(tempo) AS m_t, stddev_pop(tempo) AS s_t, avg(energy) AS m_e, stddev_pop(energy) AS s_e FROM audio
), z AS (
    SELECT song_id, estimated, tempo, energy, (tempo - m_t) / s_t AS t, (energy - m_e) / s_e AS e FROM audio CROSS JOIN stats
), nearest AS (
    SELECT x.song_id AS x, y.song_id AS y, round(sqrt(((x.t - y.t) ^ 2 + (x.e - y.e) ^ 2) / 2), 6) AS dist
    FROM z x JOIN z y ON y.song_id <> x.song_id AND NOT y.estimated
    WHERE x.estimated
    QUALIFY row_number() OVER (PARTITION BY x.song_id ORDER BY dist, y.song_id) <= 5
), canonical AS (
    -- Store each pair once, source < target as node IDs.
    SELECT CASE WHEN 'song:' || x < 'song:' || y THEN x ELSE y END AS src,
           CASE WHEN 'song:' || x < 'song:' || y THEN y ELSE x END AS tgt, dist
    FROM nearest
)
SELECT 'song:' || c.src, 'sounds_like_estimated', 'song:' || c.tgt, round(1 / (1 + c.dist), 4),
       [{'label': 'tempo', 'value': round(s.tempo)::INT || ' vs ' || round(t.tempo)::INT || ' BPM'},
        {'label': 'energy', 'value': printf('%.2f vs %.2f', s.energy, t.energy)},
        {'label': 'audio', 'value': 'estimated'}]
FROM canonical c JOIN z s ON s.song_id = c.src JOIN z t ON t.song_id = c.tgt;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'album:' || album_id, 'in_series', 'album_series:' || album_series_id, 1,
       [{'label': 'position', 'value': position::VARCHAR}, {'label': 'stated in', 'value': evidence}]
FROM album_series_member;

-- Audio: each analysis measures one track or preview; each song's audio profile is one analysis.
INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'verified_analysis:' || a.track_id, 'analyses_track', 'track:' || a.track_id, 1,
       [{'label': 'observed', 'value': strftime(a.observed_at, '%-d %b %Y')}]
FROM verified_analysis a JOIN track t USING (track_id) WHERE t.song_id IS NOT NULL
UNION ALL
SELECT 'estimated_analysis:' || song_id, 'analyses_song', 'song:' || song_id, 1,
       [{'label': 'observed', 'value': strftime(observed_at, '%-d %b %Y')}]
FROM estimated_analysis;

INSERT INTO edge (source, relation, target, weight, evidence)
SELECT 'song:' || song_id, 'audio_profile', 'verified_analysis:' || track_id, 1, [{'label': 'audio', 'value': 'verified'}] FROM song_audio_track
UNION ALL
SELECT 'song:' || song_id, 'audio_profile', 'estimated_analysis:' || song_id, 1, [{'label': 'audio', 'value': 'estimated'}] FROM estimated_analysis;

-- Credit vectors: each person weighted by rarity, ln(credited songs / songs they are credited on) (TF-IDF). Session only.
CREATE TEMP TABLE credit_weight AS
WITH credited AS (
    SELECT DISTINCT c.song_id, c.person_id, p.is_member, p.display_name FROM credit c JOIN person p USING (person_id)
)
SELECT *, ln((SELECT count(DISTINCT song_id) FROM credited) / count(*) OVER (PARTITION BY person_id)) AS w FROM credited;

-- Songs with credits in common: cosine similarity of their credit vectors. Each song keeps its ten strongest.
INSERT INTO edge (source, relation, target, weight, evidence)
WITH norm AS (
    SELECT song_id, sqrt(sum(w * w)) AS nm FROM credit_weight GROUP BY 1
), pair AS (
    SELECT a.song_id AS x, b.song_id AS y, round(sum((a.w * b.w)::DECIMAL(18, 9)) / (na.nm * nb.nm), 6) AS score,
           list({'label': 'shared', 'value': a.display_name} ORDER BY a.w DESC, a.display_name) AS ev
    FROM credit_weight a
    JOIN credit_weight b ON b.person_id = a.person_id AND b.song_id <> a.song_id
    JOIN norm na ON na.song_id = a.song_id
    JOIN norm nb ON nb.song_id = b.song_id
    WHERE a.w > 0
    GROUP BY a.song_id, b.song_id, na.nm, nb.nm
), strongest AS (
    SELECT * FROM pair QUALIFY row_number() OVER (PARTITION BY x ORDER BY score DESC, y) <= 10
)
SELECT DISTINCT least('song:' || x, 'song:' || y), 'shares_writers', greatest('song:' || x, 'song:' || y), score, ev
FROM strongest;

-- Songs with verified audio only, all compared on the same six features.
INSERT INTO edge (source, relation, target, weight, evidence)
WITH audio AS (
    SELECT song_id, tempo, energy, danceability, valence, acousticness, speechiness FROM song_audio WHERE source = 'reccobeats'
), stats AS (
    SELECT avg(tempo) AS m_t, stddev_pop(tempo) AS s_t, avg(energy) AS m_e, stddev_pop(energy) AS s_e,
           avg(danceability) AS m_d, stddev_pop(danceability) AS s_d, avg(valence) AS m_v, stddev_pop(valence) AS s_v,
           avg(acousticness) AS m_a, stddev_pop(acousticness) AS s_a, avg(speechiness) AS m_s, stddev_pop(speechiness) AS s_s
    FROM audio
), z AS (
    SELECT song_id, (tempo - m_t) / s_t AS t, (energy - m_e) / s_e AS e, (danceability - m_d) / s_d AS d,
           (valence - m_v) / s_v AS v, (acousticness - m_a) / s_a AS a, (speechiness - m_s) / s_s AS sp
    FROM audio CROSS JOIN stats
), pair AS (
    SELECT x.song_id AS x, y.song_id AS y,
           round(sqrt(((x.t - y.t) ^ 2 + (x.e - y.e) ^ 2 + (x.d - y.d) ^ 2 + (x.v - y.v) ^ 2 + (x.a - y.a) ^ 2 + (x.sp - y.sp) ^ 2) / 6), 6) AS dist
    FROM z x JOIN z y ON x.song_id <> y.song_id
), nearest AS (
    SELECT DISTINCT least(x, y) AS x, greatest(x, y) AS y, dist
    FROM pair QUALIFY row_number() OVER (PARTITION BY x ORDER BY dist, y) <= 5
), canonical AS (
    -- Store each pair once, source < target as node IDs.
    SELECT CASE WHEN 'song:' || x < 'song:' || y THEN x ELSE y END AS src,
           CASE WHEN 'song:' || x < 'song:' || y THEN y ELSE x END AS tgt, dist
    FROM nearest
)
SELECT 'song:' || c.src, 'sounds_like', 'song:' || c.tgt, round(1 / (1 + c.dist), 4),
       [{'label': 'tempo', 'value': round(s.tempo)::INT || ' vs ' || round(t.tempo)::INT || ' BPM'},
        {'label': 'energy', 'value': printf('%.2f vs %.2f', s.energy, t.energy)},
        {'label': 'danceability', 'value': printf('%.2f vs %.2f', s.danceability, t.danceability)},
        {'label': 'valence', 'value': printf('%.2f vs %.2f', s.valence, t.valence)},
        {'label': 'acousticness', 'value': printf('%.2f vs %.2f', s.acousticness, t.acousticness)},
        {'label': 'speechiness', 'value': printf('%.2f vs %.2f', s.speechiness, t.speechiness)}]
FROM canonical c JOIN song_audio s ON s.song_id = c.src JOIN song_audio t ON t.song_id = c.tgt;

-- Provenance and confidence of each claim.
UPDATE edge SET
    provenance = CASE
        WHEN relation IN ('member_of', 'by_artist', 'in_series') THEN 'IntoBTSVerse'
        WHEN relation IN ('written_by', 'lyrics_by', 'music_by', 'produced_by', 'collaborated_with', 'shares_writers') THEN 'Wikipedia'
        WHEN relation = 'on_album' THEN 'Apple'
        WHEN relation = 'first_released_on' THEN evidence[1].value
        WHEN relation = 'recording_of' THEN 'MusicBrainz'
        WHEN relation IN ('track_of', 'track_of_song') THEN CASE evidence[1].value WHEN 'Spotify' THEN 'Kworb' ELSE 'Deezer' END
        WHEN relation = 'video_of' THEN 'Kworb'
        WHEN relation = 'charted_on' THEN 'Billboard'
        WHEN relation IN ('sounds_like', 'analyses_track') THEN 'ReccoBeats'
        WHEN relation IN ('sounds_like_estimated', 'analyses_song') THEN 'Previews'
        WHEN relation = 'audio_profile' THEN CASE evidence[1].value WHEN 'verified' THEN 'ReccoBeats' ELSE 'Previews' END
    END,
    confidence = CASE
        WHEN relation IN ('collaborated_with', 'shares_writers') THEN 'inferred'
        WHEN relation IN ('sounds_like', 'analyses_track') THEN 'verified'
        WHEN relation IN ('sounds_like_estimated', 'analyses_song') THEN 'estimated'
        WHEN relation = 'audio_profile' THEN evidence[1].value
        ELSE 'stated'
    END;

-- Recommendation candidates: each meta-path (sounds like, estimated or not, and same first release) scores a pair of songs 0 to 1 and gives a
-- reason; the score is the sum weighted by graph_metapath (from ontology.ttl). Credits are not used. Skits are left out
-- on both sides. recommend.py picks five per song from these. Session only.
CREATE TEMP TABLE rec_candidate AS
WITH eligible AS (
    SELECT node_id AS id FROM node WHERE node_id LIKE 'song:%' AND class <> 'skit'
), seconds AS (
    SELECT 'song:' || song_id AS id, coalesce(max(length_ms) FILTER (WHERE version = 'original'), max(length_ms)) / 1000.0 AS s
    FROM recording GROUP BY song_id
), route AS (
    -- The relations each meta-path walks, from the ontology.
    SELECT metapath, unnest(relations) AS relation FROM graph_metapath
), direct AS (
    SELECT e.source, e.target, e.relation, e.weight, r.metapath
    FROM edge e JOIN route r USING (relation)
    WHERE e.relation IN (SELECT relation FROM graph_relation WHERE is_symmetric)
), pair AS (
    SELECT source AS x, target AS y, relation, weight, metapath FROM direct
    UNION ALL
    SELECT target, source, relation, weight, metapath FROM direct
), sound AS (
    -- Values: the recommended song's, then this song's. Estimated audio compares tempo and energy only.
    SELECT p.x, p.y, p.metapath,
           p.weight / max(p.weight) OVER (PARTITION BY p.x, p.relation) AS s,
           CASE p.relation
               WHEN 'sounds_like' THEN printf('tempo %d vs %d BPM · energy %.2f vs %.2f · speechiness %.2f vs %.2f',
                   round(ay.tempo)::INT, round(ax.tempo)::INT, ay.energy, ax.energy, ay.speechiness, ax.speechiness)
               ELSE printf('tempo %d vs %d BPM · energy %.2f vs %.2f', round(ay.tempo)::INT, round(ax.tempo)::INT, ay.energy, ax.energy)
           END AS reason
    FROM pair p
    JOIN song_audio ax ON 'song:' || ax.song_id = p.x
    JOIN song_audio ay ON 'song:' || ay.song_id = p.y
), album AS (
    SELECT a.source AS x, b.source AS y, r.metapath, 1.0 AS s, n.label AS reason
    FROM edge a
    JOIN route r ON r.relation = a.relation
    JOIN edge b ON b.target = a.target AND b.source <> a.source AND b.relation = a.relation
    JOIN node n ON n.node_id = a.target
    WHERE a.relation NOT IN (SELECT relation FROM graph_relation WHERE is_symmetric)
), path AS (
    SELECT * FROM sound UNION ALL SELECT * FROM album
), position AS (
    -- Where the candidate sits on the song's first release, for the last tie-break.
    SELECT 'song:' || s.song_id AS x, 'song:' || t.song_id AS y, min(t.disc * 1000 + t.position) AS track
    FROM song s JOIN album_track t ON t.album_id = s.album_id AND t.song_id IS NOT NULL AND t.song_id <> s.song_id
    GROUP BY 1, 2
)
SELECT p.x, p.y, round(sum((m.weight * p.s)::DECIMAL(18, 6)), 6)::DOUBLE AS score,
       list({'label': m.reason, 'value': p.reason} ORDER BY m.weight DESC, m.metapath) AS reasons,
       -- No streaming data counts as average: the 50th percentile and the median streams per day.
       coalesce(si.popularity_score, 50) AS popularity,
       coalesce(si.streams_per_day, (SELECT median(streams_per_day) FROM song_intelligence)) AS streams, pos.track
FROM path p
JOIN graph_metapath m USING (metapath)
LEFT JOIN song_intelligence si ON 'song:' || si.song_id = p.y
LEFT JOIN position pos ON pos.x = p.x AND pos.y = p.y
LEFT JOIN seconds sx ON sx.id = p.x
LEFT JOIN seconds sy ON sy.id = p.y
WHERE p.x IN (SELECT id FROM eligible) AND p.y IN (SELECT id FROM eligible)
  -- A short linking track is not a pick after a longer song.
  AND NOT (sy.s < (SELECT value FROM graph_setting WHERE setting = 'MinimumLength')
           AND coalesce(sx.s, 1e9) >= (SELECT value FROM graph_setting WHERE setting = 'MinimumLength'))
GROUP BY p.x, p.y, si.popularity_score, si.streams_per_day, pos.track;

-- How alike two songs are: audio closeness (verified audio) and whether they share a first release. Session only.
CREATE TEMP TABLE rec_similarity AS
WITH audio AS (
    SELECT song_id, tempo, energy, danceability, valence, acousticness, speechiness FROM song_audio WHERE source = 'reccobeats'
), stats AS (
    SELECT avg(tempo) AS m_t, stddev_pop(tempo) AS s_t, avg(energy) AS m_e, stddev_pop(energy) AS s_e,
           avg(danceability) AS m_d, stddev_pop(danceability) AS s_d, avg(valence) AS m_v, stddev_pop(valence) AS s_v,
           avg(acousticness) AS m_a, stddev_pop(acousticness) AS s_a, avg(speechiness) AS m_s, stddev_pop(speechiness) AS s_s
    FROM audio
), z AS (
    SELECT 'song:' || song_id AS id, (tempo - m_t) / s_t AS t, (energy - m_e) / s_e AS e, (danceability - m_d) / s_d AS d,
           (valence - m_v) / s_v AS v, (acousticness - m_a) / s_a AS a, (speechiness - m_s) / s_s AS sp
    FROM audio CROSS JOIN stats
), closeness AS (
    SELECT x.id AS x, y.id AS y,
           round(1 / (1 + sqrt(((x.t - y.t) ^ 2 + (x.e - y.e) ^ 2 + (x.d - y.d) ^ 2 + (x.v - y.v) ^ 2 + (x.a - y.a) ^ 2
                                + (x.sp - y.sp) ^ 2) / 6)), 6) AS sim
    FROM z x JOIN z y ON x.id <> y.id
), album AS (
    SELECT 'song:' || a.song_id AS x, 'song:' || b.song_id AS y
    FROM song a JOIN song b ON b.album_id = a.album_id AND b.song_id <> a.song_id
)
SELECT coalesce(c.x, a.x) AS x, coalesce(c.y, a.y) AS y, c.sim::DOUBLE AS audio, a.x IS NOT NULL AS same_album
FROM closeness c FULL JOIN album a USING (x, y);
