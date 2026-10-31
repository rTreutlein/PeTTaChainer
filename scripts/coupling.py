#!/usr/bin/env python3
"""Measure static subsystem coupling in a committed MeTTa/Prolog tree.

Names defined in more than one subsystem have no unique owner and are omitted.
References are lexical names, not resolved calls. Cross-functions counts each
distinct name once per directed subsystem pair; interface width counts the union
of names used by all outside subsystems. File grouping is first-match wins.
"""

import argparse
from collections import defaultdict
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

GROUPS = (
    ("Posterior", r"prolog/(event_|source_catalog)|compiler/event_model"),
    ("Evaluator: values/merge/folds", r"backward/(eval_values|eval_merge|eval_folds|eval_versions|value_store)"),
    ("Evaluator: core/work", r"backward/(eval_core|eval_work|evaluation|execution|eval_sampling|upward|eval_types)"),
    ("Proof search", r"backward/skeleton|skeleton_journal|proofs\.metta|prolog/proof_semantics|runtime/query\.metta|application_discovery|prolog/application_support"),
    ("Compiler", r"metta/compiler/"),
    ("Prolog stores", r"prolog/(runtime_state|store_schema|runtime_helpers|ingestion|context_overlay|sorts|eval_)"),
    ("Statistics/learning", r"statistical_ledger|hypothesis_|rule_policy|rate_plans|forward/aggregates|base_rate|refinement"),
    ("Forgetting", r"forgetting"),
    ("Forward", r"runtime/forward/"),
    ("Core types", r"metta/core/|bootstrap|logic_config"),
)


def measure(repo, ref="HEAD"):
    archive = subprocess.check_output(
        ["git", "-C", str(repo), "archive", ref, "pettachainer/metta"],
        stdin=subprocess.DEVNULL)
    sources = {}
    groups = {}
    definitions = defaultdict(set)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        for member in tree:
            if not member.isfile() or Path(member.name).suffix not in (".metta", ".pl"):
                continue
            source = tree.extractfile(member).read().decode("utf-8", "replace")
            sources[member.name] = re.sub(r";[^\n]*|%[^\n]*", "", source)
            group = next((name for name, pattern in GROUPS if re.search(pattern, member.name)),
                         "Other runtime")
            groups[member.name] = group
            if member.name.endswith(".metta"):
                names = re.findall(r"^\(=\s+\(([^\s()]+)", source, re.M)
                names += re.findall(r"^\(=\s+([^\s()]+)", source, re.M)
            else:
                names = re.findall(r"^([a-z][A-Za-z0-9_]*)\s*(?:\(|:-)", source, re.M)
            for name in names:
                definitions[name].add(group)
    owners = {name: next(iter(groups)) for name, groups in definitions.items() if len(groups) == 1}
    edges = defaultdict(set)
    for path, source in sources.items():
        for name in set(re.findall(r"[A-Za-z_][A-Za-z0-9_\-!?*]*", source)):
            owner = owners.get(name)
            if owner and owner != groups[path]:
                edges[groups[path], owner].add(name)
    interfaces = defaultdict(set)
    for (_, target), names in edges.items():
        interfaces[target].update(names)
    nodes = [{"id": group, "api": len(interfaces[group]),
              "defs": sum(owner == group for owner in owners.values())}
             for group in sorted(set(groups.values()))]
    widest = max(nodes, key=lambda node: node["api"], default=None)
    pairs = [(source, target) for source, target in sorted(edges)
             if source < target and (target, source) in edges]
    return {
        "ref": ref,
        "nodes": nodes,
        "edges": [{"from": source, "to": target, "symbols": len(names),
                   "functions": sorted(names)}
                  for (source, target), names in sorted(edges.items())],
        "subsystem_edges": len(edges),
        "cross_functions": sum(map(len, edges.values())),
        "two_way_pairs": len(pairs),
        "two_way": pairs,
        "widest_interface": widest["api"] if widest else 0,
        "widest_subsystem": widest["id"] if widest else None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ref", nargs="?", default="HEAD", help="git revision (default: HEAD)")
    parser.add_argument("--json", action="store_true", help="emit the report as JSON")
    args = parser.parse_args()
    report = measure(Path.cwd(), args.ref)
    if args.json:
        print(json.dumps(report, indent=2))
        return
    print(f"Coupling at {args.ref}: {report['subsystem_edges']} subsystem edges, "
          f"{report['cross_functions']} cross-boundary functions, "
          f"{report['two_way_pairs']} two-way pairs")
    print(f"Widest interface: {report['widest_interface']} ({report['widest_subsystem']})")
    for edge in report["edges"]:
        print(f"  {edge['from']} -> {edge['to']}: {edge['symbols']}")
    for source, target in report["two_way"]:
        print(f"  Two-way: {source} <-> {target}")


if __name__ == "__main__":
    main()
