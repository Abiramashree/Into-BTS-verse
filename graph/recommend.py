"""Five recommendations per song, picked from rec_candidate (graph.sql) and written as recommends edges (weight 1 / rank).

Relevance is the candidate's score against the song's best, lowered by the hidden gem nudge (popularity). Songs are
picked one at a time by MMR: lambda x relevance - (1 - lambda) x similarity to songs already picked, where similarity is
audio closeness, or 1 for the same first release. Ties go to the song that sounds closer, then the less streamed (streams
per day), then the earlier track on the song's first release.
Settings come from graph_setting (ontology.ttl).
"""

from collections import defaultdict

import duckdb

PICKS = 5


def pick(candidates: list[tuple], audio: dict, same_album: set, seed: str, gem: float, lam: float) -> list[str]:
    """candidates: (song, score, popularity percentile, streams per day, track on the song's first release). Returns up
    to PICKS songs in order."""
    best = max(c[1] for c in candidates)
    relevance = {y: score / best - gem * popularity / 100 for y, score, popularity, _, _ in candidates}
    streams = {y: s for y, _, _, s, _ in candidates}
    track = {y: t if t is not None else 10**9 for y, _, _, _, t in candidates}

    def similarity(a, b):
        return 1.0 if (a, b) in same_album else audio.get((a, b), 0.0)

    chosen, remaining = [], set(relevance)
    while remaining and len(chosen) < PICKS:
        def key(y):
            mmr = lam * relevance[y] - (1 - lam) * max((similarity(y, z) for z in chosen), default=0.0)
            return (-round(mmr, 9), -audio.get((seed, y), 0.0), streams[y], track[y], y)
        y = min(remaining, key=key)
        chosen.append(y)
        remaining.remove(y)
    return chosen


def run(con: duckdb.DuckDBPyConnection) -> None:
    settings = dict(con.execute("SELECT setting, value FROM graph_setting").fetchall())
    gem, lam = settings["HiddenGemWeight"], settings["VarietyLambda"]
    audio, same_album = {}, set()
    for x, y, a, same in con.execute("SELECT x, y, audio, same_album FROM rec_similarity").fetchall():
        if a is not None:
            audio[x, y] = a
        if same:
            same_album.add((x, y))
    candidates, reasons = defaultdict(list), {}
    rows = con.execute("SELECT x, y, score, reasons, popularity, streams, track FROM rec_candidate ORDER BY x, y").fetchall()
    for x, y, score, why, popularity, streams, track in rows:
        candidates[x].append((y, score, popularity, streams, track))
        reasons[x, y] = why
    edges = []
    for x in sorted(candidates):
        for rank, y in enumerate(pick(candidates[x], audio, same_album, x, gem, lam), start=1):
            edges.append((x, y, round(1 / rank, 4), reasons[x, y]))
    con.executemany("INSERT INTO edge VALUES (?, 'recommends', ?, ?, ?, 'IntoBTSVerse', 'inferred')", edges)
