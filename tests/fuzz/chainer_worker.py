"""Answers of one knowledge base by PeTTaChainer, in a process of its own.

Reads one JSON job on stdin: the chainer settings, statements, base-rate pins,
queries and budgets. Each budget gets a fresh handler (a fresh KB). Writes,
per budget, each query's answers as [strength, confidence, expanded proof]."""

import json
import sys
from pathlib import Path
import pettachainer

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
        [[a.tv[1], a.tv[2], chainer.expand_proof(a.proof)] for a in answers if a.tv[0] == "STV"]
        for answers in rows
    ]


job = json.load(sys.stdin)
runtime = str(Path(pettachainer.__file__).resolve())
if job.get("target") and not Path(runtime).is_relative_to(Path(job["target"]).resolve()):
    raise RuntimeError(f"target mismatch: imported {runtime}, expected {job['target']}")
if job.get("probe"):
    import janus_swi as janus
    probe = []
    for n in job["probe"]:
        h = PeTTaChainer()
        h.add_atoms_no_check(job["statements"] + [
            f'(: r{i} (Implication (O e) (A e)) (FTV 1 1))' for i in range(n)])
        # Inferences are deterministic work units; CPU seconds remain diagnostic.
        # Measure the catalog phase identified in the KE review, not process startup.
        four_args = janus.query_once('current_predicate(source_catalog_template/4)')['truth']
        setup = "source_catalog_inputs(['A',e],[Kb,'MAIN','Nil'],_Sources)," if four_args else ''
        template = "source_catalog_template(['A',e],[Kb,'MAIN','Nil'],_Sources,_)" if four_args else "source_catalog_template(['A',e],[Kb,'MAIN','Nil'],_)"
        query = setup + f"""statistics(inferences,I0),statistics(cputime,T0),
           forall(between(1,3,_),({template} -> true ; true)),
           statistics(inferences,I1),statistics(cputime,T1),
           Work is (I1-I0)/3,Seconds is (T1-T0)/3"""
        row = janus.query_once(query, {'Kb': h.kb})
        probe.append({'n': n, 'inferences': row['Work'], 'seconds': row['Seconds']})
    result = {'answers': {}, 'probe': probe, 'runtime': runtime}
else:
    result = {str(budget): run(job, budget) for budget in job["budgets"]}
    if job.get('event'):
        result = {'answers': result, 'runtime': runtime}
sys.stdout.write("\n@@RESULT@@" + json.dumps(result) + "\n")
