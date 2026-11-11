"""ontology.ttl -> graph_class, graph_relation, graph_attribute, graph_metapath and graph_setting: the ontology the
graph is built and checked against.

graph_relation lists every class pair a relation allows: a relation on Person also allows Member, and one on Release
allows Album, EP and Single. Sub-relations inherit their parent's classes and evidence.
"""

import re
from pathlib import Path

import duckdb
from rdflib import OWL, RDF, RDFS, BNode, Graph, URIRef
from rdflib.collection import Collection
from rdflib.namespace import DCTERMS, SKOS

TTL = Path(__file__).parent / "ontology.ttl"
BV = "https://abiramashree.github.io/Into-BTS-verse/ontology#"
ROOTS = {"Agent", "CreativeWork", "Chart", "AudioAnalysis"}  # graph classes descend from these; Source and ChartRun don't

DDL = """
CREATE TABLE graph_class (
    class VARCHAR PRIMARY KEY,  -- Class name, as in node.class
    iri VARCHAR NOT NULL UNIQUE,  -- The class's address in the ontology
    parent VARCHAR,  -- The class it specialises
    is_abstract BOOLEAN NOT NULL,          -- No nodes of its own
    label VARCHAR NOT NULL,  -- Name for display
    definition VARCHAR NOT NULL,  -- What the class means
    table_name VARCHAR,                    -- Warehouse table its nodes come from
    schema_org VARCHAR,  -- Close matches on schema.org
    wikidata VARCHAR  -- Close matches on Wikidata
);

CREATE TABLE graph_relation (
    relation VARCHAR NOT NULL,  -- Relation name, as in edge.relation
    source_class VARCHAR NOT NULL REFERENCES graph_class (class),  -- A class the relation may start from
    target_class VARCHAR NOT NULL REFERENCES graph_class (class),  -- A class it may point to
    iri VARCHAR NOT NULL,  -- The relation's address in the ontology
    parent VARCHAR,  -- The relation it specialises
    inverse VARCHAR,  -- Name of the inverse relation
    is_symmetric BOOLEAN NOT NULL,         -- Stored once, source < target
    is_functional BOOLEAN NOT NULL,        -- At most one target per source
    is_inferred BOOLEAN NOT NULL,          -- Derived from other facts by rule
    weight VARCHAR,                        -- NULL: always 1
    evidence VARCHAR,                      -- NULL: none required
    rule VARCHAR,  -- How an inferred relation is derived
    label VARCHAR NOT NULL,  -- Name for display
    definition VARCHAR,  -- What the relation means
    schema_org VARCHAR,  -- Close matches on schema.org
    wikidata VARCHAR,  -- Close matches on Wikidata
    PRIMARY KEY (relation, source_class, target_class)
);

CREATE TABLE graph_attribute (
    attribute VARCHAR PRIMARY KEY,  -- Attribute name
    iri VARCHAR NOT NULL UNIQUE,  -- The attribute's address in the ontology
    classes VARCHAR[] NOT NULL,  -- Classes it describes
    datatype VARCHAR NOT NULL,  -- Type of its values
    unit VARCHAR,  -- Unit of its values
    table_name VARCHAR,                    -- NULL: the table of the node's class
    column_name VARCHAR NOT NULL,  -- Column holding it
    sources VARCHAR[] NOT NULL,  -- Sources its values come from
    changes_each_build BOOLEAN NOT NULL,   -- As of the latest snapshot
    label VARCHAR NOT NULL,  -- Name for display
    definition VARCHAR  -- What the attribute means
);

CREATE TABLE graph_term (
    kind VARCHAR NOT NULL,                 -- source or confidence
    name VARCHAR NOT NULL,                 -- As used in edge.provenance and edge.confidence
    iri VARCHAR NOT NULL UNIQUE,  -- The term's address in the ontology
    label VARCHAR NOT NULL,  -- Name for display
    definition VARCHAR,  -- What it means
    PRIMARY KEY (kind, name)
);

CREATE TABLE graph_setting (
    setting VARCHAR PRIMARY KEY,  -- Setting name
    iri VARCHAR NOT NULL UNIQUE,  -- The setting's address in the ontology
    value DOUBLE NOT NULL,  -- Its value
    label VARCHAR NOT NULL,  -- Name for display
    definition VARCHAR NOT NULL  -- What it controls
);

CREATE TABLE graph_metapath (
    metapath VARCHAR PRIMARY KEY,  -- Route name
    iri VARCHAR NOT NULL UNIQUE,  -- The route's address in the ontology
    route VARCHAR NOT NULL,  -- The route as text
    relations VARCHAR[] NOT NULL,          -- The relations it walks; the recommendation query reads these
    weight DOUBLE NOT NULL,                -- How much the path counts in a recommendation score
    reason VARCHAR NOT NULL,               -- Evidence label on recommends edges
    label VARCHAR NOT NULL,  -- Name for display
    definition VARCHAR NOT NULL  -- How the route scores a pair of songs
);
"""


def _local(u) -> str:
    s = str(u)
    return s[len(BV):] if s.startswith(BV) else s.rsplit("/", 1)[-1].rsplit("#", 1)[-1]


def _snake(name: str) -> str:
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower()  # CreativeWork -> creative_work, EP -> ep


def tables(g: Graph) -> dict[str, list[dict]]:
    bv = lambda u: isinstance(u, URIRef) and str(u).startswith(BV)
    text = lambda s, p: str(g.value(s, p)) if g.value(s, p) is not None else None

    def members(node):  # a class or an owl:unionOf of classes
        if isinstance(node, BNode) and g.value(node, OWL.unionOf) is not None:
            return list(Collection(g, g.value(node, OWL.unionOf)))
        return [node]

    def matches(s, prefix, strip=""):
        out = sorted(str(o)[len(prefix):] for o in g.objects(s, SKOS.closeMatch) if str(o).startswith(prefix))
        return ", ".join(out) or None

    def ancestors(c):
        return set(g.transitive_objects(c, RDFS.subClassOf))  # includes c

    classes = [c for c in g.subjects(RDF.type, OWL.Class) if bv(c) and {_local(a) for a in ancestors(c)} & ROOTS]
    abstract = {c for c in classes if g.value(c, URIRef(BV + "abstract")) is not None}
    concrete = lambda c: sorted(_snake(_local(d)) for d in classes if c in ancestors(d) and d not in abstract)

    class_rows = [
        {
            "class": _snake(_local(c)),
            "iri": str(c),
            "parent": next((_snake(_local(p)) for p in g.objects(c, RDFS.subClassOf) if bv(p)), None),
            "is_abstract": c in abstract,
            "label": text(c, RDFS.label),
            "definition": text(c, SKOS.definition),
            "table_name": text(c, URIRef(BV + "table")),
            "schema_org": matches(c, "https://schema.org/"),
            "wikidata": matches(c, "http://www.wikidata.org/entity/"),
        }
        for c in classes
    ]

    def inherited(p, prop):  # walk up rdfs:subPropertyOf until the property is found
        for q in [p, *[x for x in g.transitive_objects(p, RDFS.subPropertyOf) if x != p]]:
            if g.value(q, prop) is not None:
                return g.value(q, prop)
        return None

    inverses = {o for s, o in g.subject_objects(OWL.inverseOf) if isinstance(s, URIRef)}  # named inverses, not chain steps
    relation_rows = []
    for p in g.subjects(RDF.type, OWL.ObjectProperty):
        if not bv(p) or p in inverses:
            continue
        domain, rng = inherited(p, RDFS.domain), inherited(p, RDFS.range)
        sources = sorted({x for d in members(domain) for x in concrete(d)}) if domain is not None else []
        targets = sorted({x for r in members(rng) for x in concrete(r)}) if rng is not None else []
        types = set(g.objects(p, RDF.type))
        parent = next((q for q in g.objects(p, RDFS.subPropertyOf) if bv(q)), None)
        inverse = g.value(p, OWL.inverseOf)
        for s in sources:
            for t in targets:
                relation_rows.append(
                    {
                        "relation": _local(p),
                        "source_class": s,
                        "target_class": t,
                        "iri": str(p),
                        "parent": _local(parent) if parent is not None else None,
                        "inverse": _local(inverse) if inverse is not None else None,
                        "is_symmetric": OWL.SymmetricProperty in types,
                        "is_functional": OWL.FunctionalProperty in types,
                        "is_inferred": g.value(p, URIRef(BV + "rule")) is not None,
                        "weight": text(p, URIRef(BV + "weight")),
                        "evidence": str(inherited(p, URIRef(BV + "evidence"))) if inherited(p, URIRef(BV + "evidence")) else None,
                        "rule": text(p, URIRef(BV + "rule")),
                        "label": text(p, RDFS.label),
                        "definition": text(p, SKOS.definition),
                        "schema_org": matches(p, "https://schema.org/"),
                        "wikidata": matches(p, "http://www.wikidata.org/entity/"),
                    }
                )

    attribute_rows = []
    for p in g.subjects(RDF.type, OWL.DatatypeProperty):
        if not bv(p):
            continue
        rng = g.value(p, RDFS.range)
        attribute_rows.append(
            {
                "attribute": _local(p),
                "iri": str(p),
                "classes": sorted(_snake(_local(c)) for c in members(g.value(p, RDFS.domain))),
                "datatype": _local(rng) if bv(rng) else "xsd:" + _local(rng),
                "unit": text(p, URIRef(BV + "unit")),
                "table_name": text(p, URIRef(BV + "table")),
                "column_name": text(p, URIRef(BV + "column")) or _local(p),
                "sources": sorted(_local(s) for s in g.objects(p, DCTERMS.source)),
                "changes_each_build": g.value(p, SKOS.scopeNote) is not None,
                "label": text(p, RDFS.label),
                "definition": text(p, SKOS.definition),
            }
        )
    metapath_rows = [
        {
            "metapath": _local(m),
            "iri": str(m),
            "route": text(m, URIRef(BV + "route")),
            "relations": sorted(_local(r) for r in g.objects(m, URIRef(BV + "uses_relation"))),
            "weight": float(g.value(m, URIRef(BV + "path_weight"))),
            "reason": text(m, URIRef(BV + "reason")),
            "label": text(m, RDFS.label),
            "definition": text(m, SKOS.definition),
        }
        for m in g.subjects(RDF.type, URIRef(BV + "MetaPath"))
    ]
    setting_rows = [
        {"setting": _local(x), "iri": str(x), "value": float(g.value(x, URIRef(BV + "value"))),
         "label": text(x, RDFS.label), "definition": text(x, SKOS.definition)}
        for x in g.subjects(RDF.type, URIRef(BV + "Setting"))
    ]
    term_rows = [
        {"kind": kind, "name": _local(x), "iri": str(x), "label": text(x, RDFS.label), "definition": text(x, SKOS.definition)}
        for kind, cls in (("source", "Source"), ("confidence", "Confidence"))
        for x in g.subjects(RDF.type, URIRef(BV + cls))
    ]
    key = {"graph_class": "class", "graph_setting": "setting", "graph_term": ("kind", "name"), "graph_relation": ("relation", "source_class", "target_class"), "graph_attribute": "attribute",
           "graph_metapath": "metapath"}
    out = {"graph_class": class_rows, "graph_relation": relation_rows, "graph_attribute": attribute_rows, "graph_metapath": metapath_rows,
           "graph_setting": setting_rows, "graph_term": term_rows}
    for name, rows in out.items():
        k = key[name]
        rows.sort(key=lambda r: tuple(r[c] for c in k) if isinstance(k, tuple) else r[k])
    return out


def load(con: duckdb.DuckDBPyConnection, ttl: Path = TTL) -> None:
    con.execute(DDL)
    for name, rows in tables(Graph().parse(ttl)).items():
        cols = list(rows[0])
        con.executemany(f"INSERT INTO {name} ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})", [list(r.values()) for r in rows])
