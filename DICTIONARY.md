# Data dictionary

Every column of every table and view, generated from the ontology and the SQL that defines them.

## `album`

Albums, EPs and singles.

| Column | Type | Meaning |
|---|---|---|
| `album_id` | integer | ID of this album. |
| `slug` | varchar | Readable identifier, unique per table. |
| `title` | varchar | The title as its source gives it. |
| `kind` | enum | Album, EP or Single, from the suffix of Apple's title. |
| `release_date` | date | The date the release came out. |
| `track_count` | integer | The number of tracks Apple lists on the release. |
| `has_tracklist` | boolean | Apple lists the tracks on the release. |

## `album_series`

Series of releases.

| Column | Type | Meaning |
|---|---|---|
| `album_series_id` | integer | ID of this album series. |
| `slug` | varchar | Readable identifier, unique per table. |
| `title` | varchar | The title as its source gives it. |

## `album_series_member`

Releases in each series, in order.

| Column | Type | Meaning |
|---|---|---|
| `album_series_id` | integer | The album series (`album_series.album_series_id`). |
| `album_id` | integer | The album (`album.album_id`). |
| `position` | integer | Order of the release within the series. |
| `evidence` | varchar | Where the membership is stated. |

## `song`

Songs.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | ID of this song. |
| `slug` | varchar | Readable identifier, unique per table. |
| `title` | varchar | The title as its source gives it. |
| `title_ko` | varchar | The song's Korean title, where it has one. |
| `is_generic_title` | boolean | Titled Intro, Outro, Skit or Interlude with nothing else. |
| `is_single` | boolean | Wikipedia lists the song as a single. |
| `first_release_date` | date | The earliest known release date. |
| `album_id` | integer | First release. |
| `album_from` | enum | Source of album_id. |

## `album_track`

Tracklists.

| Column | Type | Meaning |
|---|---|---|
| `album_id` | integer | The album (`album.album_id`). |
| `disc` | integer | Disc number on the release. |
| `position` | integer | Track number on its disc. |
| `title` | varchar | Track title as Apple lists it. |
| `song_id` | integer | The song (`song.song_id`). |
| `version` | enum | Which version the track is: original, live, remix and so on. |

## `recording`

Recordings of each song, by version.

| Column | Type | Meaning |
|---|---|---|
| `recording_id` | integer | ID of this recording. |
| `song_id` | integer | The song (`song.song_id`). |
| `version` | enum | original, live, remix, instrumental, demo, japanese, korean, alternate or atmos. |
| `version_label` | varchar | The version as the source words it, such as 'V demo ver.'. |
| `title` | varchar | The title as its source gives it. |
| `length_ms` | integer | The length of the recording (milliseconds). |
| `first_release_date` | date | The earliest known release date. |
| `first_release_precision` | enum | year, month or day: how much of a recording's first release date is known. |
| `is_video` | boolean | MusicBrainz marks the recording as a video. |

## `track`

Spotify and Deezer tracks.

| Column | Type | Meaning |
|---|---|---|
| `track_id` | integer | ID of this track. |
| `platform` | enum | spotify or deezer. |
| `song_id` | integer | The song (`song.song_id`). |
| `recording_id` | integer | The recording (`recording.recording_id`). |
| `version` | enum | original, live, remix, instrumental, demo, japanese, korean, alternate or atmos. |
| `title` | varchar | The title as its source gives it. |
| `is_feature` | boolean | BTS appears as a featured artist. |

## `video`

YouTube videos.

| Column | Type | Meaning |
|---|---|---|
| `video_id` | integer | ID of this video. |
| `song_id` | integer | The song (`song.song_id`). |
| `version` | enum | original, live, remix, instrumental, demo, japanese, korean, alternate or atmos. |
| `kind` | enum | mv, dance_practice, lyric_video, teaser, performance or other. |
| `title` | varchar | The title as its source gives it. |
| `is_feature` | boolean | BTS appears as a featured artist. |
| `published_month` | date | The month the video was published (first day of the month). |
| `match` | enum | How the video relates to BTS songs: song (one song), feature, not_group or not_one_song. |

## `track_snapshot`

Streaming metrics per track, by date.

| Column | Type | Meaning |
|---|---|---|
| `track_id` | integer | The track (`track.track_id`). |
| `metric` | enum | streams: cumulative; daily: per day; rank: higher is more popular. |
| `observed_at` | date | Date of the reading. |
| `value` | bigint | The reading: total streams, daily streams or rank, by metric. |
| `source` | enum | Where the reading came from: kworb, the Wayback Machine or Deezer. |

## `video_snapshot`

Video views, by date.

| Column | Type | Meaning |
|---|---|---|
| `video_id` | integer | The video (`video.video_id`). |
| `observed_at` | date | Date of the reading. |
| `views` | bigint | Total YouTube views on that date. |
| `source` | enum | Where the reading came from. |

## `track_audio`

Audio features per track.

| Column | Type | Meaning |
|---|---|---|
| `track_id` | integer | The track (`track.track_id`). |
| `feature` | enum | Which audio feature. |
| `value` | double | The feature's value for the track. |
| `observed_at` | date | Date ReccoBeats returned it. |

## `song_audio_estimate`

Audio features estimated from 30-second previews.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `feature` | enum | Which audio feature. |
| `value` | double | The value estimated from the song's preview. |
| `observed_at` | date | Date the preview was downloaded. |

## `audio_validation`

Estimates compared with reference values.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `feature` | enum | The feature compared. |
| `reccobeats` | double | Spotify's value, via ReccoBeats. |
| `librosa` | double | Our estimate from the preview. |

## `song_audio_track`

Track that supplies each song's audio features.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `track_id` | integer | The track (`track.track_id`). |

## `person`

Writers, composers, lyricists and producers.

| Column | Type | Meaning |
|---|---|---|
| `person_id` | integer | ID of this person. |
| `slug` | varchar | Readable identifier, unique per table. |
| `name` | varchar | Name as credited. |
| `display_name` | varchar | The person's name for display, without a Wikipedia disambiguator. |
| `is_member` | boolean | A member of BTS. |

## `credit`

Song credits.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `person_id` | integer | The person (`person.person_id`). |
| `role` | enum | writer, lyricist, composer or producer, as credited. |
| `pages` | varchar[] | Wikipedia pages listing the credit. |

## `hot100_entry`

Billboard Hot 100 weeks.

| Column | Type | Meaning |
|---|---|---|
| `week` | date | Chart week. |
| `rank` | integer | Position that week. |
| `title` | varchar | As charted. |
| `performer` | varchar | Artist as credited on the chart. |
| `peak` | integer | Peak position to date, as published that week. |
| `weeks_on_chart` | integer | Weeks on the chart to date, as published that week. |
| `song_id` | integer | NULL when BTS is a featured artist. |

## `billboard200_entry`

Billboard 200 weeks.

| Column | Type | Meaning |
|---|---|---|
| `week` | date | Chart week. |
| `rank` | integer | Position that week. |
| `title` | varchar | Album title as charted. |
| `peak` | integer | Peak position to date, as published that week. |
| `weeks_on_chart` | integer | Weeks on the chart to date, as published that week. |
| `album_id` | integer | The album (`album.album_id`). |

## `song_link`

Links between titles of the same song.

| Column | Type | Meaning |
|---|---|---|
| `a` | varchar | Title key. |
| `b` | varchar | Title key. |
| `kind` | enum | How the titles were linked: alias, Wikipedia note, shared ISRC or reviewed override. |
| `song_id` | integer | The song (`song.song_id`). |
| `evidence` | struct | Where the link was seen: source and text. |

## `song_audio`

Audio features per song: its audio profile, the verified analysis of the track on its album or else its preview estimate. key: pitch class, 0 = C, -1 = none. mode: 1 = major, 0 = minor. loudness: dB.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `source` | varchar | reccobeats for verified audio, librosa for estimated. |
| `track_id` | integer | The track (`track.track_id`). |
| `tempo` | double | The estimated tempo of the audio (beats per minute). |
| `energy` | double | Intensity and activity. |
| `danceability` | double | How suitable the audio is for dancing, from 0 to 1. |
| `valence` | double | Musical positiveness. |
| `acousticness` | double | Confidence from 0 to 1 that the audio is acoustic. |
| `instrumentalness` | double | Confidence from 0 to 1 that the audio has no vocals. |
| `liveness` | double | Presence of a live audience. |
| `speechiness` | double | Presence of spoken words, such as rap. |
| `loudness` | double | The overall loudness of the audio (decibels). |
| `key` | double | The estimated key of the audio, as a pitch class. |
| `mode` | double | 1 = major, 0 = minor. |

## `song_spotify_streams`

Spotify streams per song per snapshot. Tracks of one song within 1% of each other count once.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `observed_at` | date | Snapshot date. |
| `streams` | hugeint | Total Spotify streams of the song's original tracks. |
| `tracks` | bigint | Tracks counted. |

## `song_streams_daily`

Streams gained between snapshots, per song. NULL where the total decreases or exceeds three times the daily figure.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `period_start` | date | Previous snapshot, or the release date. |
| `period_end` | date | This snapshot. |
| `streams_gained` | hugeint | Streams gained in the period. |
| `days` | bigint | Days in the period. |
| `streams_per_day` | double | Streams gained per day in the period. |

## `album_streams_monthly`

Streams per album per calendar month.

| Column | Type | Meaning |
|---|---|---|
| `month` | date | Calendar month. |
| `album_id` | integer | The album (`album.album_id`). |
| `streams` | bigint | Streams of the release's songs that month. |
| `streams_per_day` | double | That month's streams per day. |

## `song_streams_monthly`

Monthly average daily streams per song.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `month` | date | Calendar month. |
| `streams_per_day` | bigint | Average streams per day that month. |
| `days` | bigint | Days with data that month. |

## `song_intelligence`

One row per song: catalog facts, latest totals and analytical signals. Rates compare the last 90 days with the 90 before. long_tail_score: percentile of 2025 streams per day among songs released before 2023, the measure of staying power. revival_score: largest monthly surge against the song's prior 6-month median (at least 5,000 streams per day), net of the same surge for songs a year or more old, for songs released a year or more before. has_revival: that month at least doubled.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `slug` | varchar | Readable identifier, unique per table. |
| `title` | varchar | The title as its source gives it. |
| `title_ko` | varchar | The song's Korean title, where it has one. |
| `is_single` | boolean | Wikipedia lists the song as a single. |
| `album_id` | integer | The album (`album.album_id`). |
| `album` | varchar | Title of the song's first release. |
| `first_release_date` | date | The earliest known release date. |
| `release_age_years` | double | The time from the song's first release to the latest snapshot (years). |
| `current_streams` | hugeint | Total Spotify streams at the latest snapshot (streams). |
| `mv_views` | hugeint | Total official music video views at the latest snapshot (views). |
| `streams_per_day` | double | Average daily Spotify streams over the last 90 days (streams per day). |
| `stream_growth_rate` | double | Last 90 days' streams per day against the 90 before, minus 1 (ratio). |
| `growth_acceleration` | double | This 90-day growth rate minus the previous one (ratio). |
| `mv_views_per_day` | double | Average daily official music video views over the last 90 days (views per day). |
| `mv_growth_rate` | double | Last 90 days' video views per day against the 90 before, minus 1 (ratio). |
| `hot100_peak` | integer | The song's highest Billboard Hot 100 position. |
| `hot100_weeks` | bigint | The weeks the song has spent on the Billboard Hot 100 (weeks). |
| `streams_per_day_2025` | double | Average daily Spotify streams in 2025, for songs released by then with data on at least 75% of its days. The basis of long_tail_score (streams per day). |
| `revival_score` | double | Largest monthly surge against the song's prior six-month median, net of the same surge for songs a year or more old. Songs a year or more old with at least 5,000 streams per day (ratio). |
| `revival_month` | date | The month of the song's largest surge (first day of the month). |
| `has_revival` | boolean | The revival month at least doubled the song's usual level (revival score of 1 or more). |
| `writer_count` | bigint | The people credited as writer on the song. |
| `producer_count` | bigint | The people credited as producer on the song. |
| `member_writer_share` | double | Share of a song's writers who are members. |
| `tempo` | double | The estimated tempo of the audio (beats per minute). |
| `energy` | double | Intensity and activity. |
| `danceability` | double | How suitable the audio is for dancing, from 0 to 1. |
| `valence` | double | Musical positiveness. |
| `audio_source` | varchar | reccobeats for verified audio, librosa for estimated. |
| `audio_confidence` | varchar | verified: Spotify's values via ReccoBeats. estimated: tempo and energy from previews. |
| `popularity_score` | double | Percentile of streams per day among songs that have it. |
| `long_tail_score` | double | Percentile of 2025 streams per day among songs released before 2023: the dataset's one measure of staying power. |

## `song_mv_views`

Music video views per song per snapshot.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `observed_at` | date | Snapshot date. |
| `views` | hugeint | Total views of the song's official music videos. |
| `videos` | bigint | Videos counted. |

## `song_credit`

Credits per song and person, as writer or producer.

| Column | Type | Meaning |
|---|---|---|
| `song_id` | integer | The song (`song.song_id`). |
| `person_id` | integer | The person (`person.person_id`). |
| `is_member` | boolean | A member of BTS. |
| `role` | varchar | writer (writer, lyricist or composer) or producer. |

## `album_summary`

One row per album, EP or single. Totals cover songs first released on it.

| Column | Type | Meaning |
|---|---|---|
| `album_id` | integer | The album (`album.album_id`). |
| `slug` | varchar | Readable identifier, unique per table. |
| `title` | varchar | The title as its source gives it. |
| `kind` | enum | Album, EP or Single. |
| `release_date` | date | The date the release came out. |
| `track_count` | integer | The number of tracks Apple lists on the release. |
| `new_songs` | bigint | Songs first released on it. |
| `singles` | bigint | Of those, songs released as singles. |
| `spotify_streams` | hugeint | Spotify streams of its new songs. |
| `median_song_streams` | double | Median Spotify streams of its new songs. |
| `top_song` | varchar | Its most-streamed new song. |
| `mv_views` | hugeint | Music video views of its new songs. |
| `hot100_songs` | bigint | New songs that reached the Hot 100. |
| `best_hot100_peak` | integer | Best Hot 100 position among its new songs. |
| `bb200_weeks` | bigint | Weeks the release spent on the Billboard 200. |
| `bb200_peak` | integer | Its best Billboard 200 position. |
| `audio_songs` | bigint | New songs with audio features. |
| `avg_tempo` | double | Average tempo of its new songs. |
| `avg_energy` | double | Average energy of its new songs. |
| `avg_valence` | double | Average valence of its new songs. |
| `avg_danceability` | double | Average danceability of its new songs. |
| `credited_songs` | bigint | New songs with credits. |
| `writers` | bigint | People credited as writer across its new songs. |
| `producers` | bigint | People credited as producer across its new songs. |
| `member_writer_share` | double | Share of its writer credits held by members. |

## `person_summary`

One row per credited person.

| Column | Type | Meaning |
|---|---|---|
| `person_id` | integer | The person (`person.person_id`). |
| `slug` | varchar | Readable identifier, unique per table. |
| `name` | varchar | Name as credited. |
| `is_member` | boolean | A member of BTS. |
| `roles` | varchar | Roles credited: writer, producer. |
| `songs_written` | bigint | Songs credited as writer. |
| `songs_produced` | bigint | Songs credited as producer. |
| `songs` | bigint | Songs credited in any role. |
| `releases` | bigint | First releases those songs came out on. |
| `first_year` | bigint | Year of the earliest credited song. |
| `last_year` | bigint | Year of the latest credited song. |
| `spotify_streams` | hugeint | Spotify streams of credited songs. |
| `top_song` | varchar | The most-streamed credited song. |
| `hot100_songs` | bigint | Credited songs that reached the Hot 100. |

## `verified_analysis`

Audio features per track (Spotify's values, via ReccoBeats): one verified analysis each.

| Column | Type | Meaning |
|---|---|---|
| `verified_analysis_id` | integer | ID of this verified analysis. |
| `track_id` | integer | The track (`track.track_id`). |
| `observed_at` | date | The date the analysis was obtained. |
| `tempo` | double | The estimated tempo of the audio (beats per minute). |
| `energy` | double | Intensity and activity. |
| `danceability` | double | How suitable the audio is for dancing, from 0 to 1. |
| `valence` | double | Musical positiveness. |
| `acousticness` | double | Confidence from 0 to 1 that the audio is acoustic. |
| `instrumentalness` | double | Confidence from 0 to 1 that the audio has no vocals. |
| `liveness` | double | Presence of a live audience. |
| `speechiness` | double | Presence of spoken words, such as rap. |
| `loudness` | double | The overall loudness of the audio (decibels). |
| `key` | double | The estimated key of the audio, as a pitch class. |
| `mode` | double | 1 = major, 0 = minor. |

## `estimated_analysis`

Audio features estimated from a song's preview: one estimated analysis each.

| Column | Type | Meaning |
|---|---|---|
| `estimated_analysis_id` | integer | ID of this estimated analysis. |
| `song_id` | integer | The song (`song.song_id`). |
| `observed_at` | date | The date the analysis was obtained. |
| `tempo` | double | The estimated tempo of the audio (beats per minute). |
| `energy` | double | Intensity and activity. |
| `danceability` | double | How suitable the audio is for dancing, from 0 to 1. |
| `valence` | double | Musical positiveness. |
| `acousticness` | double | Confidence from 0 to 1 that the audio is acoustic. |
| `instrumentalness` | double | Confidence from 0 to 1 that the audio has no vocals. |
| `liveness` | double | Presence of a live audience. |
| `speechiness` | double | Presence of spoken words, such as rap. |
| `loudness` | double | The overall loudness of the audio (decibels). |
| `key` | double | The estimated key of the audio, as a pitch class. |
| `mode` | double | 1 = major, 0 = minor. |

## `graph_class`

The ontology's classes, generated from ontology.ttl.

| Column | Type | Meaning |
|---|---|---|
| `class` | varchar | Class name, as in node.class. |
| `iri` | varchar | The class's address in the ontology. |
| `parent` | varchar | The class it specialises. |
| `is_abstract` | boolean | No nodes of its own. |
| `label` | varchar | Name for display. |
| `definition` | varchar | What the class means. |
| `table_name` | varchar | Warehouse table its nodes come from. |
| `schema_org` | varchar | Close matches on schema.org. |
| `wikidata` | varchar | Close matches on Wikidata. |

## `graph_relation`

Each class pair a relation allows, generated from ontology.ttl.

| Column | Type | Meaning |
|---|---|---|
| `relation` | varchar | Relation name, as in edge.relation. |
| `source_class` | varchar | A class the relation may start from. |
| `target_class` | varchar | A class it may point to. |
| `iri` | varchar | The relation's address in the ontology. |
| `parent` | varchar | The relation it specialises. |
| `inverse` | varchar | Name of the inverse relation. |
| `is_symmetric` | boolean | Stored once, source < target. |
| `is_functional` | boolean | At most one target per source. |
| `is_inferred` | boolean | Derived from other facts by rule. |
| `weight` | varchar | NULL: always 1. |
| `evidence` | varchar | NULL: none required. |
| `rule` | varchar | How an inferred relation is derived. |
| `label` | varchar | Name for display. |
| `definition` | varchar | What the relation means. |
| `schema_org` | varchar | Close matches on schema.org. |
| `wikidata` | varchar | Close matches on Wikidata. |

## `graph_attribute`

The ontology's attributes, generated from ontology.ttl.

| Column | Type | Meaning |
|---|---|---|
| `attribute` | varchar | Attribute name. |
| `iri` | varchar | The attribute's address in the ontology. |
| `classes` | varchar[] | Classes it describes. |
| `datatype` | varchar | Type of its values. |
| `unit` | varchar | Unit of its values. |
| `table_name` | varchar | NULL: the table of the node's class. |
| `column_name` | varchar | Column holding it. |
| `sources` | varchar[] | Sources its values come from. |
| `changes_each_build` | boolean | As of the latest snapshot. |
| `label` | varchar | Name for display. |
| `definition` | varchar | What the attribute means. |

## `graph_metapath`

The routes recommendations walk, generated from ontology.ttl.

| Column | Type | Meaning |
|---|---|---|
| `metapath` | varchar | Route name. |
| `iri` | varchar | The route's address in the ontology. |
| `route` | varchar | The route as text. |
| `relations` | varchar[] | The relations it walks; the recommendation query reads these. |
| `weight` | double | How much the path counts in a recommendation score. |
| `reason` | varchar | Evidence label on recommends edges. |
| `label` | varchar | Name for display. |
| `definition` | varchar | How the route scores a pair of songs. |

## `graph_setting`

Numbers that tune recommendations, generated from ontology.ttl.

| Column | Type | Meaning |
|---|---|---|
| `setting` | varchar | Setting name. |
| `iri` | varchar | The setting's address in the ontology. |
| `value` | double | Its value. |
| `label` | varchar | Name for display. |
| `definition` | varchar | What it controls. |

## `graph_term`

The sources and confidence levels claims refer to, generated from ontology.ttl.

| Column | Type | Meaning |
|---|---|---|
| `kind` | varchar | source or confidence. |
| `name` | varchar | As used in edge.provenance and edge.confidence. |
| `iri` | varchar | The term's address in the ontology. |
| `label` | varchar | Name for display. |
| `definition` | varchar | What it means. |

## `node`

ontology class (member, album, single).

| Column | Type | Meaning |
|---|---|---|
| `node_id` | varchar | table:id, such as song:94. |
| `class` | varchar | The node's most specific ontology class. |
| `entity_id` | integer | ID in that table. |
| `label` | varchar | Name for display. |
| `detail` | varchar | Short context, such as year or version. |

## `edge`

Edges. evidence: what supports the edge, as label-value pairs.

| Column | Type | Meaning |
|---|---|---|
| `source` | varchar | The node the edge starts from. |
| `relation` | varchar | The relation (graph_relation). |
| `target` | varchar | The node the edge points to. |
| `weight` | double | What it measures depends on the relation (graph_relation.weight); 1 if nothing. |
| `evidence` | struct | Label-value pairs that support the edge. |
| `provenance` | varchar | The source of this claim (graph_term). |
| `confidence` | varchar | stated, verified, estimated or inferred (graph_term). |
