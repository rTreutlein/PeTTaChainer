"""One persistent KB; functional input deliveries retire prediction waiters.

Run in a fresh process with the desired checkout on PYTHONPATH. Reports
Linux RSS/peak RSS and SWI live clause counts/bytes, as in the earlier memory
census. Counts intentionally include all stores, not just this KB's joins.
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
parser.add_argument('--cycles', type=int, default=2000)
parser.add_argument('--fanout', type=int, default=16)
args = parser.parse_args()
h = PeTTaChainer()
h.set_functional_predicate('StreamInput', 2, (2,))
h.add_atoms_no_check([
    f'(: (no_inverse stream{i}) (Implication (StreamInput yes $t) (StreamOutput{i} $t)) '
    '(CTV (STV 0.8 0.9) (STV 0 0.9)))' for i in range(args.fanout)
])


def census(cycle):
    stores = {}
    for name, arity in [('&sk_join_link', 2), ('sk_join_wait', 2), ('sk_retire_wait', 1),
                        ('sk_wait_payload', 4), ('sk_search_clause', 3), ('&sk_row', 4),
                        ('&sk_summary', 5), ('&kb', 4)]:
        head = f"'{name}'({','.join(['_'] * arity)})"
        row = janus.query_once(
            f"(current_predicate('{name}'/{arity}) -> "
            f"aggregate_all(count,{head},N),predicate_property({head},size(Bytes));N=0,Bytes=0)")
        stores[name] = {'rows': row['N'], 'bytes': row['Bytes']}
    rss = int(Path('/proc/self/statm').read_text().split()[1]) * os.sysconf('SC_PAGE_SIZE')
    print(json.dumps({'cycle': cycle, 'rss_bytes': rss,
                      'peak_rss_bytes': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024,
                      'stores': stores}), flush=True)


print(json.dumps({'pettachainer': pettachainer.__file__, **vars(args)}), flush=True)
census(0)
for n in range(args.cycles):
    goals = [f'(: $p (StreamOutput{i} t{n}) $tv)' for i in range(args.fanout)]
    h.query_many_refs(goals, steps=100)
    h.add_atom(f'(: in{n} (StreamInput yes t{n}) (STV 1 1))')
    answers = h.query_many_refs(goals, steps=100)
    assert all(len(answer) == 1 and answer[0].tv[1] == 0.8 for answer in answers)
    if (n + 1) % 250 == 0:
        census(n + 1)
if args.cycles % 250:
    census(args.cycles)
