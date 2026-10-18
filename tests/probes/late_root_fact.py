"""Keep a warm root and its cold control in one fresh native runtime (#79)."""
import json
import sys

import janus_swi as janus
from pettachainer import PeTTaChainer


name, confidence, pre_budget = sys.argv[1:]
rulesets = {
    "facts_only": [],
    "concluding_rule": [
        "(: (no_inverse da) (Implication (D $x) (A $x)) (CTV (STV 1 1) (STV 0 1)))",
    ],
    "cycle": [
        "(: (no_inverse ab) (Implication (A $x) (B $x)) (CTV (STV 1 1) (STV 0 1)))",
        "(: (no_inverse ba) (Implication (B $x) (A $x)) (CTV (STV 1 1) (STV 0 1)))",
    ],
}
warm, cold = PeTTaChainer(), PeTTaChainer()
initial = ["(: other (C c) (STV 1 1))"] + rulesets[name]
warm.add_atoms_no_check(initial)
cold.add_atoms_no_check(initial)


def query(kb, goal, budget):
    # Timed queries replay facts into a subprocess and cannot exercise warm
    # search state. These reads must all use the same live runtime.
    return sorted(kb.query(f"(: $p {goal} $tv)", steps=budget, timeout_sec=0))


empty = [query(warm, goal, int(pre_budget))
         for goal in ("(A a)", "(A a)", "(A $x)")]
ctx = [warm.kb, "MAIN", "Nil"]
key = ["sk-key", ["A", "a"], ctx]
before = janus.query_once(
    "'index-hash'(Key,H),"
    "aggregate_all(count,'&sk_merged'(H,Key,_, 'sk-none',_),Empty),"
    "aggregate_all(count,'&sk_latest'(_,_,_),Versions),"
    "aggregate_all(count,'&sk_expanded'(_, _),Expanded)", {"Key": key})
facts = [f"(: seed (A a) (STV 1 {confidence}))",
         f"(: seedc (A c) (STV 1 {confidence}))"]
warm.add_atoms_no_check(facts)
cold.add_atoms_no_check(facts)
records = []
for goal in ("(A a)", "(A $x)"):
    expected = query(cold, goal, 300)
    for budget in (0, 300, 300):
        records.append({"goal": goal, "budget": budget,
                        "warm": query(warm, goal, budget), "cold": expected})
if name == "cycle":
    records.append({"goal": "(B a)", "budget": 300,
                    "warm": query(warm, "(B a)", 300),
                    "cold": query(cold, "(B a)", 300)})
    records.append({"goal": "(A a)", "budget": 300,
                    "warm": query(warm, "(A a)", 300),
                    "cold": query(cold, "(A a)", 300)})
# Refresh a nonempty fact-only merge too; no row version exists to wake it.
if name == "facts_only" and confidence == "0.8":
    for kb in (warm, cold):
        kb.add_atom("(: seed2 (A a) (STV 0 0.6))")
    records.append({"goal": "(A a)", "budget": 0,
                    "warm": query(warm, "(A a)", 0),
                    "cold": query(cold, "(A a)", 0)})
print(json.dumps({"empty": empty, "before": before, "records": records}))
