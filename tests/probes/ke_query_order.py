"""Replay KE issue 61 in one native worker, retaining every query's state."""
import json
from pathlib import Path
import sys

from pettachainer import PeTTaChainer


data = Path(__file__).resolve().parents[1] / "data"
fixture = json.loads((data / "ke_query_order_61.json").read_text())
handlers = {}


def handler(entries):
    atoms = tuple(entry["atom"] for entry in entries)
    if atoms not in handlers:
        h = PeTTaChainer()
        for atom in atoms:
            h.add_atom(atom)
        handlers[atoms] = h
    return handlers[atoms]


def query(h, atom, diagnostics, steps=300):
    if diagnostics:
        return h.query_with_diagnostics(atom, steps=steps)["proofs"]
    return h.query(atom, steps=steps, timeout_sec=0)


scenario = sys.argv[1]
diagnostics = "diag" in scenario
if scenario == "history":
    history = json.loads((data / "ke_query_order_61_history.json").read_text())
    counts = []
    # The saved worker retained one handler per exact entry set. Reproduce
    # those three worlds rather than combining their different knowledge.
    for record in history:
        request = record["request"]
        h = handler(request["entries"])
        counts.append([len(query(h, q, request["diagnostics"], request["steps"]))
                       for q in request["queries"]])
    h = handler(fixture["entries"])
else:
    h = handler(fixture["entries"])
    if scenario.startswith("warm"):
        for atom in fixture["prelude_queries"]:
            query(h, atom, diagnostics)
proofs = query(h, fixture["target_query"], diagnostics)
print(json.dumps({"proofs": proofs, **({"history_counts": counts} if scenario == "history" else {})}))
