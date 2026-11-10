# Into BTSVerse

BTS catalog data: songs, albums, recordings, credits, Spotify streams, YouTube views, audio features and Billboard
charts, as one normalized warehouse.

- `data/bts.duckdb`: every table and view in one file.
- `data/parquet/`, `data/csv/`: one file per table and view.
- `schema.sql`: table definitions, primary and foreign keys, allowed values (ENUMs).
- `views.sql`: the reporting views built on the tables.
- `ontology.ttl`: the ontology (OWL 2).
- `shapes.ttl`: the rules every build checks the graph against (SHACL).
- `graph/`: rebuilds the graph and recommendations from the tables and validates them.
- `graph.sql`: the knowledge graph built on the tables.

```sh
duckdb data/bts.duckdb
```

## Tables

All keys are Into BTSVerse IDs: permanent integers per table (`song_id` 1, 2, ...), never reused or renumbered. `song`,
`album` and `person` also have a readable `slug` (`spring-day`, `arirang`).

| Table | Key | Links to |
|---|---|---|
| `album` | `album_id` | |
| `song` | `song_id` | `album` (the release it first appeared on) |
| `album_track` | `album_id`, `disc`, `position` | `album`, `song` |
| `recording` | `recording_id` | `song` |
| `track` | `track_id` | `song`, `recording` |
| `video` | `video_id` | `song` |
| `track_snapshot` | `track_id`, `metric`, `observed_at` | `track` |
| `video_snapshot` | `video_id`, `observed_at` | `video` |
| `track_audio` | `track_id`, `feature` | `track` |
| `song_audio_track` | `song_id` | `song`, `track` |
| `song_audio_estimate` | `song_id`, `feature` | `song` |
| `audio_validation` | `song_id`, `feature` | `song` |
| `person` | `person_id` | |
| `credit` | `song_id`, `person_id`, `role` | `song`, `person` |
| `hot100_entry` | `week`, `rank` | `song` |
| `billboard200_entry` | `week`, `rank` | `album` |
| `song_link` | `a`, `b`, `kind` | `song` |

## Views

| View | |
|---|---|
| `song_summary`, `album_summary`, `person_summary` | One row each, with latest totals |
| `song_audio` | Audio features per song |
| `song_credit` | Credits folded to writer and producer |
| `song_spotify_streams`, `song_mv_views` | Streams and music video views per song per snapshot |
| `song_streams_daily`, `album_streams_monthly` | Streams per day between snapshots, and per album per month |
| `song_longevity` | Streams per day in 2024, 2025 and since ARIRANG |
| `song_streams_monthly` | Average daily streams per song per month |
| `song_intelligence` | Analytical signals per song: popularity, growth, retention, long tail, revival, credits, audio confidence |

## Graph

A knowledge graph of the catalog, rebuilt from the tables on every build. Its classes, relations and attributes are
defined in `ontology.ttl` (OWL 2), under `https://abiramashree.github.io/Into-BTS-verse/ontology#`, and every edge is
checked against them. Every build also validates the nodes, edges and attributes against `shapes.ttl` (SHACL):
datatypes and ranges, required values, allowed values and the classes each relation connects.

| Table | |
|---|---|
| `graph_class` | Classes, their parents and `iri`, with schema.org and Wikidata equivalents |
| `graph_relation` | Each class pair a relation allows, with its `iri`, inverse, weight, evidence and rule |
| `graph_attribute` | Attributes: classes, datatype, unit, sources; `changes_each_build` marks measures as of the latest snapshot |
| `graph_metapath` | The routes that relate two songs for recommendations, with their weights and reason labels |
| `graph_setting` | Numbers that tune recommendations: the hidden gem weight and the variety lambda (MMR) |
| `node` | One per entity, `table:id` with the table's ID (`song:94` is `song_id` 94); `class` is the most specific class |
| `edge` | `source`, `relation`, `target`, `weight`, `evidence` |

```
agent          group (BTS) · person → member
creative_work  song → recording → track · video · release → album, EP, single
chart          Billboard Hot 100 · Billboard 200
```

| Relation | Connects | Weight |
|---|---|---|
| `member_of` | member → group | |
| `by_artist` | song, release → group | |
| `written_by`, `lyrics_by`, `music_by`, `produced_by` | song → person | |
| `on_album` | song → release (each listing) | |
| `first_released_on` | song → release (the first) | |
| `recording_of` | recording → song | |
| `track_of` | track → recording | |
| `track_of_song` | track → song, where the recording is unknown | |
| `video_of` | video → song | |
| `charted_on` | song → Hot 100, release → Billboard 200 | Weeks on chart |
| `collaborated_with` | person ↔ person | Songs credited together |
| `shares_writers` | song ↔ song | Cosine similarity of credits, rarer people weighted more (TF-IDF); ten strongest per song |
| `sounds_like` | song ↔ song | Audio similarity, verified audio only; five nearest per song |
| `sounds_like_estimated` | song ↔ song | Tempo and energy for songs with only estimated audio, against verified songs; five nearest each |
| `recommends` | song → song | 1 / rank: five per song, from sounds like (verified or estimated) and same first release, picked for variety |

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
