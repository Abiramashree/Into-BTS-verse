# Data license

**Our work** in this dataset is licensed under [Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)](https://creativecommons.org/licenses/by-sa/4.0/):

- the structure: tables, columns and identifiers such as `song_id`
- the song matching: which titles, recordings, tracks and videos belong to which song (`song`, `song_link`, and the `song_id` and `version` columns everywhere)
- the credits in `credit`, derived from Wikipedia (CC BY-SA 4.0), which is why share-alike applies
- the values computed with librosa (`song_audio_estimate`) and the `audio_validation` comparison
- the catalog facts from MusicBrainz core data and Wikidata, both CC0

**Third-party values are not ours to license.** They are included under their own sources' terms:

| Values | Source |
|---|---|
| Spotify streams, YouTube views | kworb.net, directly and via the Internet Archive's Wayback Machine |
| Deezer ranks | Deezer API |
| Audio features in `track_audio` (Spotify's values) | ReccoBeats |
| Album titles, release dates, tracklists (`album`, `album_track`) | Apple Music, via the iTunes lookup API |
| Billboard chart positions | Billboard, via utdata/rwd-billboard-data (MIT repository) |

They are reproduced here for a non-commercial portfolio project.

Attribution: "Into BTSVerse" by Abi, with sources as listed above.

The code that collects and matches the source data is not part of this repository.

## Code

The code in `graph/`, which rebuilds the graph and recommendations from `data/bts.duckdb`, is licensed under the MIT
License:

Copyright (c) 2026 Abi

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
