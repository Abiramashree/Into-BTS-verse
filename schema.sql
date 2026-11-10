-- Into BTSVerse warehouse: tables, keys and allowed values.

CREATE TYPE album_kind AS ENUM ('Album', 'EP', 'Single');
CREATE TYPE album_source AS ENUM ('apple', 'musicbrainz');
CREATE TYPE version_kind AS ENUM ('original', 'live', 'remix', 'instrumental', 'demo', 'japanese', 'korean', 'alternate', 'atmos');
CREATE TYPE date_precision AS ENUM ('year', 'month', 'day');
CREATE TYPE platform_kind AS ENUM ('spotify', 'deezer');
CREATE TYPE video_kind AS ENUM ('mv', 'dance_practice', 'lyric_video', 'teaser', 'performance', 'other');
CREATE TYPE video_match AS ENUM ('song', 'feature', 'not_group', 'not_one_song');
CREATE TYPE metric_kind AS ENUM ('streams', 'daily', 'rank');
CREATE TYPE snapshot_source AS ENUM ('kworb', 'wayback', 'deezer');
CREATE TYPE audio_feature AS ENUM ('tempo', 'energy', 'danceability', 'valence', 'acousticness', 'instrumentalness', 'liveness',
                                   'speechiness', 'loudness', 'key', 'mode');
CREATE TYPE credit_role AS ENUM ('writer', 'lyricist', 'composer', 'producer');
CREATE TYPE link_kind AS ENUM ('alias', 'wiki_note', 'isrc', 'override');

-- Albums, EPs and singles.
CREATE TABLE album (
    album_id INTEGER PRIMARY KEY,
    slug VARCHAR NOT NULL UNIQUE,
    title VARCHAR NOT NULL,
    kind album_kind NOT NULL,
    release_date DATE NOT NULL,
    track_count INTEGER NOT NULL,
    has_tracklist BOOLEAN NOT NULL
);

-- Songs.
CREATE TABLE song (
    song_id INTEGER PRIMARY KEY,
    slug VARCHAR NOT NULL UNIQUE,
    title VARCHAR NOT NULL,
    title_ko VARCHAR,
    is_generic_title BOOLEAN NOT NULL,     -- Intro, Outro, Skit, Interlude
    is_single BOOLEAN NOT NULL,
    first_release_date DATE,
    album_id INTEGER REFERENCES album (album_id),  -- First release
    album_from album_source                -- Source of album_id
);

-- Tracklists.
CREATE TABLE album_track (
    album_id INTEGER NOT NULL REFERENCES album (album_id),
    disc INTEGER NOT NULL,
    position INTEGER NOT NULL,
    title VARCHAR NOT NULL,
    song_id INTEGER REFERENCES song (song_id),
    version version_kind NOT NULL,
    PRIMARY KEY (album_id, disc, position)
);

-- Recordings of each song, by version.
CREATE TABLE recording (
    recording_id INTEGER PRIMARY KEY,
    song_id INTEGER NOT NULL REFERENCES song (song_id),
    version version_kind NOT NULL,
    version_label VARCHAR,
    title VARCHAR NOT NULL,
    length_ms INTEGER,
    first_release_date DATE,
    first_release_precision date_precision,
    is_video BOOLEAN NOT NULL
);

-- Spotify and Deezer tracks.
CREATE TABLE track (
    track_id INTEGER PRIMARY KEY,
    platform platform_kind NOT NULL,
    song_id INTEGER REFERENCES song (song_id),
    recording_id INTEGER REFERENCES recording (recording_id),
    version version_kind NOT NULL,
    title VARCHAR NOT NULL,
    is_feature BOOLEAN NOT NULL            -- BTS as featured artist
);

-- YouTube videos.
CREATE TABLE video (
    video_id INTEGER PRIMARY KEY,
    song_id INTEGER REFERENCES song (song_id),
    version version_kind,
    kind video_kind NOT NULL,
    title VARCHAR NOT NULL,
    is_feature BOOLEAN NOT NULL,
    published_month DATE,
    match video_match NOT NULL
);

-- Streaming metrics per track, by date.
CREATE TABLE track_snapshot (
    track_id INTEGER NOT NULL REFERENCES track (track_id),
    metric metric_kind NOT NULL,           -- streams: cumulative; daily: per day; rank: higher is more popular
    observed_at DATE NOT NULL,
    value BIGINT NOT NULL,
    source snapshot_source NOT NULL,
    PRIMARY KEY (track_id, metric, observed_at)
);

-- Video views, by date.
CREATE TABLE video_snapshot (
    video_id INTEGER NOT NULL REFERENCES video (video_id),
    observed_at DATE NOT NULL,
    views BIGINT NOT NULL,
    source snapshot_source NOT NULL,
    PRIMARY KEY (video_id, observed_at)
);

-- Audio features per track.
CREATE TABLE track_audio (
    track_id INTEGER NOT NULL REFERENCES track (track_id),
    feature audio_feature NOT NULL,
    value DOUBLE NOT NULL,
    observed_at DATE NOT NULL,
    PRIMARY KEY (track_id, feature)
);

-- Audio features estimated from 30-second previews.
CREATE TABLE song_audio_estimate (
    song_id INTEGER NOT NULL REFERENCES song (song_id),
    feature audio_feature NOT NULL,
    value DOUBLE NOT NULL,
    observed_at DATE NOT NULL,
    PRIMARY KEY (song_id, feature)
);

-- Estimates compared with reference values.
CREATE TABLE audio_validation (
    song_id INTEGER NOT NULL REFERENCES song (song_id),
    feature audio_feature NOT NULL,
    reccobeats DOUBLE NOT NULL,
    librosa DOUBLE NOT NULL,
    PRIMARY KEY (song_id, feature)
);

-- Track that supplies each song's audio features.
CREATE TABLE song_audio_track (
    song_id INTEGER PRIMARY KEY REFERENCES song (song_id),
    track_id INTEGER NOT NULL REFERENCES track (track_id)
);

-- Writers, composers, lyricists and producers.
CREATE TABLE person (
    person_id INTEGER PRIMARY KEY,
    slug VARCHAR NOT NULL UNIQUE,
    name VARCHAR NOT NULL,                 -- As credited
    display_name VARCHAR NOT NULL,
    is_member BOOLEAN NOT NULL
);

-- Song credits.
CREATE TABLE credit (
    song_id INTEGER NOT NULL REFERENCES song (song_id),
    person_id INTEGER NOT NULL REFERENCES person (person_id),
    role credit_role NOT NULL,
    pages VARCHAR[] NOT NULL,              -- Wikipedia pages listing the credit
    PRIMARY KEY (song_id, person_id, role)
);

-- Billboard Hot 100 weeks.
CREATE TABLE hot100_entry (
    week DATE NOT NULL,
    rank INTEGER NOT NULL,
    title VARCHAR NOT NULL,                -- As charted
    performer VARCHAR NOT NULL,
    peak INTEGER,
    weeks_on_chart INTEGER,
    song_id INTEGER REFERENCES song (song_id),   -- NULL when BTS is a featured artist
    PRIMARY KEY (week, rank)
);

-- Billboard 200 weeks.
CREATE TABLE billboard200_entry (
    week DATE NOT NULL,
    rank INTEGER NOT NULL,
    title VARCHAR NOT NULL,
    peak INTEGER,
    weeks_on_chart INTEGER,
    album_id INTEGER NOT NULL REFERENCES album (album_id),
    PRIMARY KEY (week, rank)
);

-- Links between titles of the same song.
CREATE TABLE song_link (
    a VARCHAR NOT NULL,                    -- Title key
    b VARCHAR NOT NULL,                    -- Title key
    kind link_kind NOT NULL,
    song_id INTEGER NOT NULL REFERENCES song (song_id),
    evidence STRUCT(source VARCHAR, text VARCHAR)[] NOT NULL,
    PRIMARY KEY (a, b, kind)
);
