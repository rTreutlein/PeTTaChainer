"""Census a live aggregate across add/query/idle cycles.

--kind exact counts members with a generic FoldAll; --kind base-rate reads an
inversion over an incremental population estimate. Defaults to 1000 cycles.
Use a fresh process and PYTHONPATH to select the checkout. The result includes
its final value and an independently queried fresh-KB value, even on a stale
baseline. As in the earlier memory census, RSS is sampled from /proc and
predicate bytes are SWI's size/1, including unreclaimed erased clauses.
"""
import argparse
import json
import os
from pathlib import Path
import resource

import janus_swi as janus
import pettachainer
from pettachainer import PeTTaChainer

parser = argparse.ArgumentParser()
parser.add_argument('--detailed', action='store_true')
parser.add_argument('--cycles', type=int, default=1000)
parser.add_argument('--kind', choices=('exact', 'base-rate'), default='exact')
args = parser.parse_args()
h = PeTTaChainer()
h.set_forgetting(1)
if args.kind == 'exact':
    rule = ('(: (no_inverse count) (Implication '
            '(FoldAll (Measurement $i) 1 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total) '
            '(LiveCount $total)) (CTV (STV 1 1) (STV 0 1)))')
    initial = []
    facts = [f'(: m{n} (Measurement i{n}) (STV 1 1))' for n in range(args.cycles)]
    goal = '(: $p (LiveCount $n) $tv)'
else:
    rule = '(: sensor (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9)))'
    initial = ['(: qa (Q alice) (STV 0.9 0.8))', '(: pb (P bob) (STV 0.7 0.8))']
    facts = [f'(: m{n} (P i{n}) (STV {0.3 if n % 2 == 0 else 0.7} 0.8))' for n in range(args.cycles)]
    goal = '(: $p (P alice) $tv)'
h.add_atoms_no_check([rule] + initial)


def value(kb):
    answers = kb.query_many_refs([goal], steps=100)[0]
    return [answer.statement[1] if args.kind == 'exact' else answer.tv for answer in answers]


def census(cycle, answer):
    stores = {}
    for name, arity in [('&sk_aggregate_row', 3), ('&sk_row', 4), ('&sk_summary', 5),
                        ('&sk_join_link', 2), ('sk_wait_payload', 4), ('&kb', 4),
                        ('&sk_latest', 3), ('&sk_view', 4), ('&proof', 4),
                        ('&sk_frozen', 2), ('&sk_open_node', 3),
                        ('ev_set', 5), ('ev_union_memo', 2), ('deps_node', 4)]:
        head = f"'{name}'({','.join(['_'] * arity)})"
        row = janus.query_once(
            f"(current_predicate('{name}'/{arity}) -> aggregate_all(count,{head},N),"
            f"predicate_property({head},size(Bytes));N=0,Bytes=0)")
        stores[name] = {'rows': row['N'], 'bytes': row['Bytes']}
    if args.detailed:
        detail = janus.query_once(
            "findall([_Bytes,_Name,_Arity,_Count],(current_predicate(_Name/_Arity),"
            "functor(_Head,_Name,_Arity),predicate_property(_Head,dynamic),"
            "predicate_property(_Head,size(_Bytes)),predicate_property(_Head,number_of_clauses(_Count))),_Rows),"
            "sort(0,@>=,_Rows,_Sorted),length(Top,15),append(Top,_,_Sorted),"
            "statistics(globalused,Global),statistics(localused,Local),statistics(trailused,Trail),"
            "statistics(heapused,Heap),statistics(atom_space,AtomBytes)")
        print(json.dumps({'cycle': cycle, 'details': detail}), flush=True)
    rss = int(Path('/proc/self/statm').read_text().split()[1]) * os.sysconf('SC_PAGE_SIZE')
    print(json.dumps({'cycle': cycle, 'value': answer, 'rss_bytes': rss,
                      'peak_rss_bytes': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024,
                      'stores': stores}), flush=True)


print(json.dumps({'pettachainer': pettachainer.__file__, **vars(args)}), flush=True)
census(0, [])
for n in range(args.cycles):
    h.add_atom(facts[n])
    answer = value(h)
    h.advance_epoch()
    h.advance_epoch()
    if (n + 1) % 100 == 0:
        census(n + 1, answer)
if args.cycles % 100:
    census(args.cycles, answer)
h.set_forgetting(0)
fresh = PeTTaChainer()
fresh.add_atoms_no_check([rule] + initial + facts)
print(json.dumps({'actual': answer, 'fresh': value(fresh)}), flush=True)
