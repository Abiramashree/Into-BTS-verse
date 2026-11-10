"""Rebuild the graph and recommendations inside bts.duckdb from its tables, and validate them.

    python -m graph data/bts.duckdb

Replaces graph_*, node and edge using ontology.ttl and graph.sql, picks the recommendations, and checks everything
against shapes.ttl (SHACL). The files are found next to the graph folder.
"""

import sys
from pathlib import Path

import duckdb
from rdflib import Graph

from . import ontology, recommend, shacl

ROOT = Path(__file__).resolve().parent.parent
TABLES = ["edge", "node", "graph_relation", "graph_class", "graph_attribute", "graph_metapath", "graph_setting"]


def main(db: str) -> int:
    con = duckdb.connect(db)
    for table in TABLES:
        con.execute(f"DROP TABLE IF EXISTS {table}")
    ontology.load(con, ROOT / "ontology.ttl")
    con.execute((ROOT / "graph.sql").read_text())
    recommend.run(con)
    ok = shacl.check(con, Graph().parse(ROOT / "ontology.ttl"), Graph().parse(ROOT / "shapes.ttl"))
    for table in ["node", "edge"]:
        print(f"  {table}: {con.execute(f'SELECT count(*) FROM {table}').fetchone()[0]}")
    con.close()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "data" / "bts.duckdb")))
