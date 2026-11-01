#!/usr/bin/env python3
"""Measure static subsystem coupling in a committed MeTTa/Prolog tree.

Names defined in more than one subsystem have no unique owner and are omitted.
References are lexical names, not resolved calls. Cross-functions counts each
distinct name once per directed subsystem pair; interface width counts the union
of names used by all outside subsystems. File grouping is first-match wins.
Function SCCs use lexical references within each definition, unioned across its
clauses/files. The totals use the full graph; each subsystem uses its induced
graph, so its cycles stay inside that subsystem. Singleton SCCs are excluded.
"""

import argparse
from collections import defaultdict
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

# Semantic ownership, not implementation language or load order. The legacy
# paths let the same partition measure the pre-move baseline as well as HEAD.
# Bootstrap/ABI owns declarations and composition; it is not a runtime layer.
GROUPS = (
    ('Posterior', r'prolog/(event_|source_catalog)|compiler/event_model|runtime/posterior/'),
    ('Bootstrap/ABI', r'bootstrap|core/natives|petta_chainer.metta|store/contracts'),
    ('Runtime terms', r'core/(runtime_terms|stored_terms|truth_values|fold_values)'),
    ('Compiler plans', r'rate_plans|statistics/plans'),
    ('API', r'runtime/(query|ingest|observed_predicates|hypothesis_review)|backward/diagnostics'),
    ('Executor', r'backward/(execution|upward|forgetting)|runtime/presentation'),
    ('Installation', r'runtime/(installation|configuration|knowledge_store)'),
    ('Value store', r'(backward|store)/value_store|store/rows|store/retirement'),
    ('Evaluator', r'backward/(eval_|evaluation)|runtime/evaluator/|runtime/(values|scheduling)'),
    ('Proof search', r'backward/skeleton'),
    ('Proofs', r'proofs.metta|prolog/proof_semantics|store/rule_identity'),
    ('Statistics', r'statistical_ledger|hypothesis_mining|rule_policy|rate_plans|forward/aggregates|base_rate|refinement|runtime/statistics/'),
    ('Input journal', r'skeleton_journal|store/journal'),
    ('Fact store', r'runtime/(fact_reads|kb_publication|kb_index|application_policy)|store/(fact_|publication|schema|predicate_policy|application_policy)|forward/schema'),
    ('Search state', r'store/(search_index|applications)|application_discovery|prolog/application_support'),
    ('Allowances', r'runtime/execution|store/allowances'),
    ('Compiler', r'metta/compiler/'),
    ('Native stores', r'metta/prolog/'),
    ('Core types', r'metta/core/|metta/lib/'),
)


def function_definitions(source, metta):
    """Yield the same defined names as the coupling map, with complete clauses."""
    # Prolog semicolons are disjunctions; only MeTTa treats them as comments.
    quoted = r'''(?:"(?:\\.|[^"\\])*"|'(?:\\.|''|[^'\\])*')'''
    comments = r";[^\n]*" if metta else r"%[^\n]*|/\*[\s\S]*?\*/"
    source = re.sub(f"{quoted}|{comments}",
                    lambda token: token[0] if token[0].startswith(('"', "'"))
                    else re.sub(r"[^\n]", " ", token[0]), source)
    pattern = r"^\(=\s+\(?([^\s()]+)" if metta else r"^([a-z][A-Za-z0-9_]*)\s*(?:\(|:-)"
    delimiters = re.compile(f"{quoted}|[()]|\\.(?=\\s|$)")
    for definition in re.finditer(pattern, source, re.M):
        depth = 0
        for token in delimiters.finditer(source, definition.start()):
            depth += (token[0] == "(") - (token[0] == ")")
            if (metta and token[0] == ")" and depth == 0) or (not metta and token[0] == "."):
                yield definition[1], source[definition.start():token.end()]
                break


def function_cycles(graph):
    """Summarize nontrivial SCCs using iterative Kosaraju (no recursion limit)."""
    reverse = {name: set() for name in graph}
    for name, targets in graph.items():
        for target in targets:
            reverse[target].add(name)
    seen = set()
    order = []
    for name in graph:
        if name in seen:
            continue
        seen.add(name)
        stack = [(name, iter(graph[name]))]
        while stack:
            current, targets = stack[-1]
            target = next(targets, None)
            if target is None:
                order.append(current)
                stack.pop()
            elif target not in seen:
                seen.add(target)
                stack.append((target, iter(graph[target])))
    seen.clear()
    cycles = []
    for name in reversed(order):
        if name in seen:
            continue
        seen.add(name)
        component = []
        pending = [name]
        while pending:
            current = pending.pop()
            component.append(current)
            for target in reverse[current] - seen:
                seen.add(target)
                pending.append(target)
        if len(component) > 1:
            cycles.append(sorted(component))
    # Resolve equal-size ties lexically, independent of hash iteration order.
    largest = min(cycles, key=lambda members: (-len(members), members), default=[])
    return {"largest_function_scc": len(largest),
            "functions_in_cycles": sum(map(len, cycles)),
            "largest_function_scc_members": largest}


def measure(repo, ref="HEAD"):
    archive = subprocess.check_output(
        ["git", "-C", str(repo), "archive", ref, "pettachainer/metta"],
        stdin=subprocess.DEVNULL)
    sources = {}
    groups = {}
    definitions = defaultdict(set)
    references = defaultdict(set)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        for member in tree:
            if not member.isfile() or Path(member.name).suffix not in (".metta", ".pl"):
                continue
            source = tree.extractfile(member).read().decode("utf-8", "replace")
            sources[member.name] = re.sub(r";[^\n]*|%[^\n]*", "", source)
            group = next((name for name, pattern in GROUPS if re.search(pattern, member.name)),
                         "Other runtime")
            groups[member.name] = group
            for name, clause in function_definitions(source, member.name.endswith(".metta")):
                definitions[name].add(group)
                references[name].update(re.findall(r"[A-Za-z_][A-Za-z0-9_\-!?*]*", clause))
    owners = {name: next(iter(groups)) for name, groups in definitions.items() if len(groups) == 1}
    graph = {name: references[name] & owners.keys() for name in owners}
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
              "defs": sum(owner == group for owner in owners.values()),
              **function_cycles({name: {target for target in targets if owners[target] == group}
                                 for name, targets in graph.items() if owners[name] == group})}
             for group in sorted(set(groups.values()))]
    widest = max(nodes, key=lambda node: node["api"], default=None)
    pairs = [(source, target) for source, target in sorted(edges)
             if source < target and (target, source) in edges]
    return {
        "ref": ref,
        **function_cycles(graph),
        "unclassified_files": sorted(path for path, group in groups.items() if group == "Other runtime"),
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
    print(f"Function cycles: largest SCC {report['largest_function_scc']}, "
          f"{report['functions_in_cycles']} functions in cycles")
    for node in report["nodes"]:
        print(f"  {node['id']}: largest function SCC {node['largest_function_scc']}, "
              f"{node['functions_in_cycles']} functions in cycles; "
              f"members: {', '.join(node['largest_function_scc_members']) or '(none)'}")
    for edge in report["edges"]:
        print(f"  {edge['from']} -> {edge['to']}: {edge['symbols']}")
    for source, target in report["two_way"]:
        print(f"  Two-way: {source} <-> {target}")


if __name__ == "__main__":
    main()
