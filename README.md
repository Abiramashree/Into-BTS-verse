# Into BTSVerse

BTS catalog data: songs, albums, recordings, credits, Spotify streams, YouTube views, audio features and Billboard
charts, as one normalized warehouse.

## The site

[abiramashree.github.io/Into-BTS-verse](https://abiramashree.github.io/Into-BTS-verse/), built from these files:

- Home: next streaming milestones, the month's trend, hidden gems.
- Songweb: catalog stats, a mood map, rankings, and Compare for any two songs.
- Explore: how songs connect through writers, producers, albums and sound, with the reason for every link.
- Song pages: monthly rank, streams, share of album, audio and credits.
- Ask: a question in plain English becomes one read-only SQL query, written by a language model (Groq, through a
  Cloudflare Worker that holds the key) and run in your browser on these Parquet files. The query is shown with every
  answer. Limits: 6 questions a minute and 20 a day per visitor.

- `data/bts.duckdb`: every table and view in one file.
- `data/parquet/`, `data/csv/`: one file per table and view.
- `schema.sql`: table definitions, primary and foreign keys, allowed values (ENUMs).
- `views.sql`: the reporting views built on the tables.
- `ontology.ttl`: the ontology (OWL 2).
- `shapes.ttl`: the rules every build checks the graph against (SHACL).
- `graph/`: rebuilds the graph and recommendations from the tables and validates them.
- `graph.sql`: the knowledge graph built on the tables.
- `DICTIONARY.md`: every column of every table and view, and what it means.

```sh
duckdb data/bts.duckdb
```

## Tables

All keys are Into BTSVerse IDs: permanent integers per table (`song_id` 1, 2, ...), never reused or renumbered. `song`,
`album` and `person` also have a readable `slug` (`spring-day`, `arirang`).

| Table | Holds | Key | Links to |
|---|---|---|---|
| `album` | Albums, EPs and singles. | `album_id` |  |
| `album_series` | Series of releases. | `album_series_id` |  |
| `album_series_member` | Releases in each series, in order. | `album_series_id`, `position` | `album`, `album_series` |
| `song` | Songs. | `song_id` | `album` |
| `album_track` | Tracklists. | `album_id`, `disc`, `position` | `album`, `song` |
| `recording` | Recordings of each song, by version. | `recording_id` | `song` |
| `track` | Spotify and Deezer tracks. | `track_id` | `recording`, `song` |
| `video` | YouTube videos. | `video_id` | `song` |
| `track_snapshot` | Streaming metrics per track, by date. | `track_id`, `metric`, `observed_at` | `track` |
| `video_snapshot` | Video views, by date. | `video_id`, `observed_at` | `video` |
| `track_audio` | Audio features per track. | `track_id`, `feature` | `track` |
| `song_audio_estimate` | Audio features estimated from 30-second previews. | `song_id`, `feature` | `song` |
| `audio_validation` | Estimates compared with reference values. | `song_id`, `feature` | `song` |
| `song_audio_track` | Track that supplies each song's audio features. | `song_id` | `song`, `track` |
| `person` | Writers, composers, lyricists and producers. | `person_id` |  |
| `credit` | Song credits. | `song_id`, `person_id`, `role` | `person`, `song` |
| `hot100_entry` | Billboard Hot 100 weeks. | `week`, `rank` | `song` |
| `billboard200_entry` | Billboard 200 weeks. | `week`, `rank` | `album` |
| `song_link` | Links between titles of the same song. | `a`, `b`, `kind` | `song` |

## Views

| View | Holds |
|---|---|
| `song_audio` | Audio features per song: its audio profile, the verified analysis of the track on its album or else its preview estimate. key: pitch class, 0 = C, -1 = none. mode: 1 = major, 0 = minor. loudness: dB. |
| `song_spotify_streams` | Spotify streams per song per snapshot. Tracks of one song within 1% of each other count once. |
| `song_streams_daily` | Streams gained between snapshots, per song. NULL where the total decreases or exceeds three times the daily figure. |
| `album_streams_monthly` | Streams per album per calendar month. |
| `song_streams_monthly` | Monthly average daily streams per song. |
| `song_intelligence` | One row per song: catalog facts, latest totals and analytical signals. Rates compare the last 90 days with the 90 before. long_tail_score: percentile of 2025 streams per day among songs released before 2023, the measure of staying power. revival_score: largest monthly surge against the song's prior 6-month median (at least 5,000 streams per day), net of the same surge for songs a year or more old, for songs released a year or more before. has_revival: that month at least doubled. |
| `song_mv_views` | Music video views per song per snapshot. |
| `song_credit` | Credits per song and person, as writer or producer. |
| `album_summary` | One row per album, EP or single. Totals cover songs first released on it. |
| `person_summary` | One row per credited person. |
| `verified_analysis` | Audio features per track (Spotify's values, via ReccoBeats): one verified analysis each. |
| `estimated_analysis` | Audio features estimated from a song's preview: one estimated analysis each. |

## Graph

A knowledge graph of the catalog, rebuilt from the tables on every build. Its classes, relations and attributes are
defined in `ontology.ttl` (OWL 2), under `https://abiramashree.github.io/Into-BTS-verse/ontology#`, and every edge is
checked against them. Every build also validates the nodes, edges and attributes against `shapes.ttl` (SHACL):
datatypes and ranges, required values, allowed values and the classes each relation connects.

| Table | Holds |
|---|---|
| `graph_class` | The ontology's classes, generated from ontology.ttl. |
| `graph_relation` | Each class pair a relation allows, generated from ontology.ttl. |
| `graph_attribute` | The ontology's attributes, generated from ontology.ttl. |
| `graph_metapath` | The routes recommendations walk, generated from ontology.ttl. |
| `graph_setting` | Numbers that tune recommendations, generated from ontology.ttl. |
| `graph_term` | The sources and confidence levels claims refer to, generated from ontology.ttl. |
| `node` | ontology class (member, album, single). |
| `edge` | Edges. evidence: what supports the edge, as label-value pairs. |

```
agent          group (BTS) · person → member
creative_work  song (→ intro, outro, interlude, skit) → recording → track · video · release → album, EP, single
audio_analysis verified_analysis (one track) · estimated_analysis (one preview)
chart          Billboard Hot 100 · Billboard 200
```

| Relation | Connects | Meaning | Weight |
|---|---|---|---|
| `analyses_song` | estimated analysis → song | The song whose preview an estimated analysis measures. |  |
| `analyses_track` | verified analysis → track | The streaming track a verified analysis measures. |  |
| `audio_profile` | song → audio analysis | The analysis that stands for a song's sound: of the track on its own album, or else a preview estimate. |  |
| `by_artist` | release, song → group | The group a song or release is by. |  |
| `charted_on` | release, song → chart | A song charted on the Hot 100, or a release on the Billboard 200. | Weeks on chart |
| `collaborated_with` | person ↔ person | Two people credited together on at least one song. | Songs credited together |
| `credited` | song → person | Someone credited on a song, in any role. |  |
| `first_released_on` | song → release | The release a song first appeared on. |  |
| `in_series` | release → album series | The series a release belongs to. |  |
| `lyrics_by` | song → person | Credited as lyricist. |  |
| `member_of` | person → group | A person belongs to a group. |  |
| `music_by` | song → person | Credited as composer. |  |
| `on_album` | song → release | A song is on a release's tracklist, in any version. |  |
| `produced_by` | song → person | Credited as producer. |  |
| `recommends` | song → song | A song to listen to next after another. | 1 / rank |
| `recording_of` | recording → song | A recording is one version of a song. |  |
| `shares_writers` | song ↔ song | Two songs with credited people in common. | Cosine similarity |
| `sounds_like` | song ↔ song | Two songs with verified audio that are close on audio features. | 1 / (1 + d) |
| `sounds_like_estimated` | song ↔ song | A song with only estimated audio that is close to a song with verified audio on tempo and energy. | 1 / (1 + d) |
| `track_of` | track → recording | The recording a streaming track carries, where its ISRC identifies one. |  |
| `track_of_song` | track → song | The song a streaming track carries. |  |
| `video_of` | video → song | A video shows one song. |  |
| `written_by` | song → person | Credited as writer, lyricist or composer. |  |

Symmetric relations (↔) are stored once, with `source` < `target` compared as text (`song:10` before `song:9`).
`collaborated_with`, `shares_writers`, `sounds_like` and `recommends` are inferred from credits, audio features and
releases; each `recommends` edge lists one reason per meta-path. Skits are left out of recommendations. `by_artist` links
every song and release to BTS; leave it out of centrality measures. Streaming and chart measures are as of the latest
snapshot.

## Rebuild the graph

```sh
pip install -r requirements.txt
python -m graph data/bts.duckdb
```

Replaces the `graph_*`, `node` and `edge` tables in `data/bts.duckdb` from `ontology.ttl` and `graph.sql`, picks the
recommendations, and checks the result against `shapes.ttl`.

## Limits

- History starts December 2015 (Billboard 200), October 2017 (YouTube, Hot 100) and April 2023 (Spotify).
- Snapshots are roughly monthly.
- Audio features cover 194 songs: all features for 171; tempo and energy estimated from previews for 23.
- Credits cover songs with a Wikipedia track listing.

License: [LICENSE.md](LICENSE.md).
