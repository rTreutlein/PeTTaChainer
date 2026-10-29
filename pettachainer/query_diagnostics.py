"""Compact snapshots of the skeleton the last query left, never a second reasoner."""

import json
from .metta_syntax import parse_term, render


_INTERPRETATION = (
    "Observed search only. Empty agenda does not prove logical completeness or falsity. "
    "A goal proof need not be admissible to every continuation. Routes are source-backed "
    "continuations or compiled rule candidates of unproved parents, not claims of absent knowledge. "
    "Candidate premises may belong to dormant or pruned rules and need not be executable. "
    "Variables are scoped per record. Temporary query scaffolds are not included. Counts are lower bounds "
    "when traversal is truncated. Agenda entries count work the budget left, not queued nodes."
)


def _size(value):
    return len(json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode())


def _identity(term):
    # Alpha identity for native patterns; preserve repeated variables.
    variables = {}

    def walk(value):
        if isinstance(value, list):
            return tuple(map(walk, value))
        if value.startswith("$"):
            return variables.setdefault(value, f"${len(variables)}")
        return value

    return walk(term)


def snapshot(chainer, metrics, max_goals, max_routes, max_bytes):
    """Walk the latest query's skeleton from its roots, breadth first, reading
    at most ``max_goals`` nodes and never inferring anything."""
    (search,) = chainer.handler.process_metta_string("!(query-diagnostic-search)")
    _, roots, pending_roots, queued, remaining = parse_term(search)
    queue, ids = [], {}

    def register(term, depth):
        identity = _identity(term)
        if identity not in ids:
            ids[identity] = len(ids) + 1
            queue.append((term, ids[identity], depth))
        return ids[identity]

    root_ids = [register(term, 0) for term in roots]
    goals, routes = [], []
    cursor = 0
    while cursor < len(queue) and cursor < max_goals:
        term, gid, depth = queue[cursor]
        cursor += 1
        (record,) = chainer._call("query-diagnostic-node", [render(term)])
        _, expanded, work, supported, children, node_routes = parse_term(record)
        if term[0] != "CPU":
            goals.append(
                dict(
                    id=gid,
                    depth=depth,
                    expression=render(term[0]),
                    expanded=expanded == "true",
                    work_requested=work == "true",
                    proof_count=int(supported),
                )
            )
            if int(supported):
                continue
        for child in children:
            register(child, depth + 1)
        # A rule a join already continues is no further candidate.
        started = {r[1] for r in node_routes if r[0] == "continuation"}
        for origin, rule, child, conclusion, proof, remaining_premises, entries in node_routes:
            if child[0] == "CPU" or (origin == "candidate" and rule in started):
                continue
            support = []
            for entry in entries:
                item = (
                    dict(kind="fact", name=render(entry[2]), expression=render(entry[3]))
                    if entry[0] == "fact-ev"
                    else dict(kind="rule", name=render(entry[2]))
                )
                if item not in support:
                    support.append(item)
            route = dict(
                parent_id=gid,
                child_id=register(child, depth + 1),
                conclusion=render(conclusion),
                rule_proof=render(proof),
                remaining_premises=list(map(render, remaining_premises)),
                supported_evidence=support,
                origin=origin,
            )
            if route not in routes:
                routes.append(route)
    pending = len(queue) - cursor
    unfinished = (
        int(pending_roots)
        + int(queued)
        + metrics.get("rows_unpaid", 0)
        + metrics.get("conditions_unpaid", 0)
    )
    goals.sort(key=lambda g: (g["depth"] != 0, bool(g["proof_count"]), g["depth"], g["id"]))
    result = dict(
        schema_version=1,
        termination=dict(
            reason="budget_exhausted" if unfinished else "agenda_exhausted",
            requested_steps=metrics["steps"],
            remaining_steps=int(remaining),
            agenda_entries=unfinished,
            pruned_entries=0,
        ),
        roots=root_ids,
        goals=[],
        routes=[],
        totals=dict(goals=len(goals) + pending, routes=len(routes)),
        omitted=dict(goals=len(goals) + pending, routes=len(routes)),
        limits=dict(max_goals=max_goals, max_routes=max_routes, max_bytes=max_bytes),
        truncated=True,
        interpretation=_INTERPRETATION,
    )
    # The byte limit covers the whole serialized snapshot. Goals come first,
    # and only routes whose ends are both included follow.
    for goal in goals:
        result["goals"].append(goal)
        if _size(result) > max_bytes:
            result["goals"].pop()
            break
    included = {g["id"] for g in result["goals"]}
    for route in routes:
        if len(result["routes"]) >= max_routes:
            break
        if {route["parent_id"], route["child_id"]} <= included:
            result["routes"].append(route)
            if _size(result) > max_bytes:
                result["routes"].pop()
                break
    result["omitted"] = dict(
        goals=len(goals) + pending - len(result["goals"]),
        routes=len(routes) - len(result["routes"]),
    )
    result["truncated"] = any(result["omitted"].values())
    while _size(result) > max_bytes:
        field = "routes" if result["routes"] else "goals"
        result[field].pop()
        result["omitted"][field] += 1
        result["truncated"] = True
    return result
