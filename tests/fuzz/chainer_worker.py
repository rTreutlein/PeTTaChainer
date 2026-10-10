"""Answers of one knowledge base by PeTTaChainer, in a process of its own.

Reads one JSON job on stdin: the chainer settings, statements, base-rate pins,
queries and budgets. Each budget gets a fresh handler (a fresh KB). Writes,
per budget, each query's answers as [strength, confidence, proof] (the proof
expanded only with ``expand``)."""

import json
import sys

from pettachainer import PeTTaChainer


def run(job, budget):
    chainer = PeTTaChainer()
    chainer.set_evidence_confidence_k(job["k"])
    for head in job["complete"]:
        chainer.set_complete_predicate(head)
    if job["refinement"]:
        chainer.set_rule_refinement(True)
    chainer.add_atoms_no_check(job["statements"])
    for pattern, tv in job["base_rates"]:
        chainer.handler.process_metta_string(f"!(set-base-rate {chainer.kb} {pattern} {tv})")
    rows = chainer.query_many_refs(job["queries"], steps=budget)
    return [
        [[a.tv[1], a.tv[2], chainer.expand_proof(a.proof) if job["expand"] else None] for a in answers if a.tv[0] == "STV"]
        for answers in rows
    ]


job = json.load(sys.stdin)
result = {str(budget): run(job, budget) for budget in job["budgets"]}
sys.stdout.write("\n@@RESULT@@" + json.dumps(result) + "\n")
