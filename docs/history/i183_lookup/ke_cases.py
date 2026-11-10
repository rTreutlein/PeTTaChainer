"""Record the KE fixtures whose assertions changed with the source-read contract.

Optional argv[1] is event_graph.pl extracted from the baseline commit. Consult
it after the ordinary load, in this process only, for the before measurement.
"""
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from pettachainer import PeTTaChainer
from tests.test_conditional_world_facts import scenarios
from tests.test_identity_worlds import I, J, Q, BRIDGE

if len(sys.argv) > 1:
    import janus_swi as janus
    PeTTaChainer()
    janus.consult(sys.argv[1])

cases = [(name, [e['atom'] for e in entries], goal)
         for name, entries, goal, _ in scenarios()]
for strength in (1, .8, .5, .2):
    for goal in (I, Q):
        cases.append((f'identity-certain-{strength}',
                      [f'(: report {I} (STV {strength} 0.9))', f'(: judgment {J} (STV 1 1))'], goal))
for strength, extra in ((1, []), (.8, []), (.5, []),
                        (.8, ['(: neutral (Dilutes Split1) (STV 0.5 0.9))']),
                        (.8, ['(: neutral (Not (Dilutes Split1)) (STV 0.5 0.9))'])):
    for goal in (I, Q):
        cases.append((f'identity-bridge-{strength}-{extra}',
                      [f'(: report {I} (STV {strength} 0.9))', BRIDGE] + extra, goal))
for confidence in (.5, .9):
    for consequent in ('(DoesNotDilute $e)', '(Not (Dilutes $e))'):
        body = f'(And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Implication (Implemented $e) {consequent}))'
        for goal in (body.replace('$e', 'Split1'), f'(Exists ($e) {body})'):
            cases.append((f'bridge-{confidence}-{consequent}',
                [f'(: src_event {I} (STV 1 {confidence}))',
                 f'(: src_bridge (Implication (And (Member $e StockSplit) (Implemented $e)) {consequent}) (STV 1 0.9))'], goal))
for consequent in ('(DoesNotDilute $e)', '(Not (Dilutes $e))'):
    body = f'(And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Implication (Implemented $e) {consequent}))'
    cases.append((f'explicit-{consequent}',
        [f'(: src_event {I} (STV 1 0.9))',
         f'(: src_conditional (Implication (Implemented Split1) {consequent.replace("$e", "Split1")}) (STV 1 0.9))'],
        f'(Exists ($e) {body})'))

for label, facts, goal in cases:
    h = PeTTaChainer()
    h.add_atoms_no_check(facts)
    for repeat in range(2):
        rows = h.query_many_refs([f'(: $p {goal} $tv)'], steps=300)[0]
        print(json.dumps(dict(case=label, facts=facts, query=goal, repeat=repeat,
                              answers=[dict(statement=r.statement, tv=r.tv, proof=h.expand_proof(r.proof))
                                       for r in rows])), flush=True)
