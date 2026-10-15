"""Measure numeric ownership lookup selectivity in a fresh pinned runtime."""
import json

import janus_swi as janus
from pettachainer import PeTTaChainer

h = PeTTaChainer()
h.set_positive_only_predicate('NumericInput')
h.add_atoms_no_check([
    f'(: (no_inverse r{i}) (Implication (NumericInput {i} $t) (NumericLabel {i} $t)) '
    '(CTV (STV 0.8 0.9) (STV 0 0.9)))'
    for i in range(33)
])
measurements = []
for step in range(4):
    # Unanswered predictions retain ownership across periods. New one-hot
    # outcomes cause ownership misses at another time: 32 false, one true.
    h.query_many_refs([
        f'(: $p (NumericLabel {i} q{step}) $tv)' for i in range(33)
    ], steps=100)
    h.add_atoms_no_check([
        f'(: label{step}_{i} (NumericLabel {i} t{step}) (STV {int(i == 0)} 1))'
        for i in range(33)
    ])
    measurements.append(janus.query_once(
        "_Head=sk_search_clause(_,_,_),"
        "predicate_property(user:_Head,number_of_clauses(Rows)),"
        "arg(1,_Head,_Hash),findall(_Hash,call(user:_Head),_Hashes),"
        "sort(_Hashes,_Keys),length(_Keys,Keys),"
        "predicate_property(user:_Head,indexed(_Indexes)),"
        "member(_Index,_Indexes),get_dict(arguments,_Index,[1]),"
        "get_dict(position,_Index,[]),get_dict(speedup,_Index,Speedup)"))
print(json.dumps(measurements))
