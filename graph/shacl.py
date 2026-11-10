"""SHACL validation: the graph and its attributes, as RDF in memory, against shapes. The full shapes are the hand-written
ones plus those generated from ontology.ttl (datatypes, ranges, single values, the classes each relation connects).
"""

from decimal import Decimal

import duckdb
from pyshacl import validate
from rdflib import OWL, RDF, XSD, BNode, Graph, Literal, Namespace, URIRef
from rdflib.collection import Collection

from . import ontology

SH = Namespace("http://www.w3.org/ns/shacl#")
BV = Namespace(ontology.BV)
BVS = Namespace("https://abiramashree.github.io/Into-BTS-verse/shapes#")
ID = Namespace("https://abiramashree.github.io/Into-BTS-verse/id/")  # node IRIs; in memory only
NAMED = {"group:1": BV.BTS, "chart:1": BV.Hot100, "chart:2": BV.Billboard200}  # individuals in the ontology
INTEGERS = {"integer", "nonNegativeInteger", "positiveInteger"}


def _iri(node_id: str) -> URIRef:
    return NAMED.get(node_id) or ID[node_id.replace(":", "/")]


def _datatypes(ont: Graph) -> dict[str, tuple[str, list[tuple[URIRef, Literal]]]]:
    """Our named datatypes -> (xsd base, [(xsd:minInclusive, 0), ...]), read from their OWL definitions."""
    out = {}
    for d in ont.subjects(RDF.type, URIRef("http://www.w3.org/2000/01/rdf-schema#Datatype")):
        if not str(d).startswith(ontology.BV):
            continue
        eq = ont.value(d, OWL.equivalentClass)
        base = str(ont.value(eq, OWL.onDatatype)).rsplit("#", 1)[1]
        facets = [(p, o) for r in Collection(ont, ont.value(eq, OWL.withRestrictions)) for p, o in ont.predicate_objects(r)]
        out[str(d)[len(ontology.BV):]] = (base, facets)
    return out


def _literal(value, base: str) -> Literal:
    if base == "decimal":
        return Literal(Decimal(str(value)), datatype=XSD.decimal)
    if base in INTEGERS:
        lexical = str(int(value)) if isinstance(value, float) and value.is_integer() else str(value)
        return Literal(lexical, datatype=XSD[base])  # ill-typed if not a whole number in range
    if base == "boolean":
        return Literal(bool(value))
    if base == "date":
        return Literal(value, datatype=XSD.date)
    return Literal(str(value))


def data_graph(con: duckdb.DuckDBPyConnection, ont: Graph) -> Graph:
    g = Graph()
    class_iri = dict(con.execute("SELECT class, iri FROM graph_class").fetchall())
    for node_id, cls in con.execute("SELECT node_id, class FROM node").fetchall():
        g.add((_iri(node_id), RDF.type, URIRef(class_iri[cls])))
    for s, r, t in con.execute("SELECT source, relation, target FROM edge").fetchall():
        g.add((_iri(s), BV[r], _iri(t)))

    parent = dict(con.execute("SELECT class, parent FROM graph_class").fetchall())
    table_of = dict(con.execute("SELECT class, table_name FROM graph_class").fetchall())

    def lineage(c):
        while c:
            yield c
            c = parent[c]

    datatypes = _datatypes(ont)
    columns = {}
    attributes = con.execute("SELECT attribute, classes, datatype, table_name, column_name FROM graph_attribute").fetchall()
    for cls in [r[0] for r in con.execute("SELECT DISTINCT class FROM node").fetchall()]:
        home = table_of[cls]
        if home == "node":
            continue
        for attr, classes, datatype, table, column in attributes:
            if not set(classes) & set(lineage(cls)):
                continue
            table = table or home
            if table not in columns:
                columns[table] = {r[0] for r in con.execute(f"DESCRIBE {table}").fetchall()}
            if column not in columns[table]:
                raise ValueError(f"ontology.ttl: {attr} is stored in {table}.{column}, which doesn't exist")
            base = datatypes[datatype][0] if datatype in datatypes else datatype.removeprefix("xsd:")
            rows = con.execute(
                f"SELECT n.node_id, x.{column} FROM node n JOIN {table} x ON n.node_id = '{home}:' || x.{home}_id "
                f"WHERE n.class = ? AND x.{column} IS NOT NULL",
                [cls],
            ).fetchall()
            for node_id, value in rows:
                g.add((_iri(node_id), BV[attr], _literal(value, base)))
    return g


def generated_shapes(con: duckdb.DuckDBPyConnection, ont: Graph) -> Graph:
    g = Graph()
    g.bind("sh", SH)
    g.bind("bv", BV)
    g.bind("bvs", BVS)
    class_iri = dict(con.execute("SELECT class, iri FROM graph_class").fetchall())

    def one_of(shape, classes):  # sh:class, or sh:or of sh:class
        if len(classes) == 1:
            g.add((shape, SH["class"], URIRef(class_iri[classes[0]])))
            return
        options = []
        for c in classes:
            option = URIRef(f"{shape}-{c}")
            g.add((option, SH["class"], URIRef(class_iri[c])))
            options.append(option)
        head = BNode()
        g.add((shape, SH["or"], head))
        Collection(g, head, options)

    datatypes = _datatypes(ont)
    for attr, classes, datatype in con.execute("SELECT attribute, classes, datatype FROM graph_attribute ORDER BY 1").fetchall():
        classes = [c for c in classes if c in class_iri]
        if not classes:
            continue  # chart run attributes: carried by charted_on edges as evidence
        node, prop = BVS[attr], BVS[f"{attr}-value"]
        g.add((node, RDF.type, SH.NodeShape))
        g.add((node, SH.targetSubjectsOf, BV[attr]))
        one_of(node, classes)
        g.add((node, SH.property, prop))
        g.add((prop, SH.path, BV[attr]))
        base, facets = datatypes.get(datatype, (datatype.removeprefix("xsd:"), []))
        g.add((prop, SH.datatype, XSD[base]))
        for facet, value in facets:
            g.add((prop, SH[str(facet).rsplit("#", 1)[1]], value))
        if (BV[attr], RDF.type, OWL.FunctionalProperty) in ont:
            g.add((prop, SH.maxCount, Literal(1)))

    relations = con.execute("""
        SELECT relation, list(DISTINCT source_class ORDER BY source_class), list(DISTINCT target_class ORDER BY target_class),
               bool_or(is_functional)
        FROM graph_relation GROUP BY 1 ORDER BY 1""").fetchall()
    for rel, sources, targets, functional in relations:
        node, prop = BVS[rel], BVS[f"{rel}-target"]
        g.add((node, RDF.type, SH.NodeShape))
        g.add((node, SH.targetSubjectsOf, BV[rel]))
        one_of(node, sources)
        g.add((node, SH.property, prop))
        g.add((prop, SH.path, BV[rel]))
        one_of(prop, targets)
        if functional:
            g.add((prop, SH.maxCount, Literal(1)))
    return g


def full_shapes(con: duckdb.DuckDBPyConnection, ont: Graph, hand_written: Graph) -> Graph:
    shapes = hand_written + generated_shapes(con, ont)
    for prefix, ns in (("sh", SH), ("bv", BV), ("bvs", BVS)):
        shapes.bind(prefix, ns)
    return shapes


def violations(results: Graph) -> set[tuple[str, str]]:
    """(focus node, constraint) for each result, e.g. ('song/94', 'MaxInclusive')."""
    out = set()
    for r in results.subjects(RDF.type, SH.ValidationResult):
        focus = str(results.value(r, SH.focusNode))
        component = str(results.value(r, SH.sourceConstraintComponent)).rsplit("#", 1)[1].removesuffix("ConstraintComponent")
        out.add((focus.split("/id/", 1)[-1] if "/id/" in focus else focus.rsplit("#", 1)[-1], component))
    return out


def report(con: duckdb.DuckDBPyConnection, ont: Graph, shapes: Graph) -> tuple[bool, Graph, Graph]:
    """(conforms, validation results, data graph)."""
    data = data_graph(con, ont)
    conforms, results, _ = validate(data, shacl_graph=shapes, ont_graph=ont, inference="none")
    return conforms, results, data


def check(con: duckdb.DuckDBPyConnection, ont: Graph, shapes: Graph) -> bool:
    conforms, results, data = report(con, ont, shapes)
    nodes = len(set(data.subjects(RDF.type, None)))
    print(f"  {'ok  ' if conforms else 'FAIL'} SHACL: {nodes} nodes and {len(data)} triples against {len(shapes)} shape triples")
    if not conforms:
        for r in list(results.subjects(RDF.type, SH.ValidationResult))[:10]:
            print(f"         {results.value(r, SH.focusNode)} {results.value(r, SH.resultPath)}: {results.value(r, SH.resultMessage)}")
    return conforms
