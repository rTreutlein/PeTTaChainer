"""Read-only runtime census for issue #60 context nodes.

Run under bench/capped. No runtime source or benchmark store is changed.
The observed-cut count includes empty ordinary classes. Raw E demand is
retained separately as a conservative envelope, including pending reads,
never silently collapsed to the end-state cache.
"""
import argparse
import collections
import json
import os
from pathlib import Path
import runpy
import sys

import janus_swi as janus
from pettachainer import PeTTaChainer

HERE = Path(__file__).resolve().parent

def counts(rows):
    per = collections.Counter()
    for h, r, _ in {tuple((h, r, tuple(c))) for h, r, c in rows}:
        per[h, r] += 1
    return dict(total=sum(per.values()), rows=len(per), maximum=max(per.values(), default=0),
                mean=sum(per.values()) / len(per) if per else 0,
                histogram=dict(sorted(collections.Counter(per.values()).items())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case', choices=['u4', 'supplynet', 'scale', 'conflict', 'replay'])
    parser.add_argument('out', type=Path)
    parser.add_argument('--plain', action='store_true', help='Run the same workload without Prolog wrappers for validation')
    args = parser.parse_args()
    calls = []
    # Install wrappers after loading the runtime, before any knowledge/query.
    PeTTaChainer()
    janus.consult(str(HERE / 'context_census.pl'))
    if not args.plain:
        janus.query_once('ctx_install')
    active = 0
    for name in ('query', 'query_many', 'query_many_refs'):
        original = getattr(PeTTaChainer, name)
        def wrapped(self, *a, _original=original, _name=name, **kw):
            nonlocal active
            self.set_query_metrics(True)
            outer = active == 0
            before = janus.query_once('(ctx_count(exclusion_merges,M)->true;M=0),(ctx_count(exclusion_conditioned,C)->true;C=0)') if outer else None
            active += 1
            try:
                return _original(self, *a, **kw)
            finally:
                active -= 1
                if outer:
                    after = janus.query_once('(ctx_count(exclusion_merges,M)->true;M=0),(ctx_count(exclusion_conditioned,C)->true;C=0)')
                    calls.append(dict(method=_name, merges=after['M']-before['M'],
                                      conditioned=after['C']-before['C']))
        setattr(PeTTaChainer, name, wrapped)
    try:
        if args.case == 'u4':
            record = json.loads((HERE.parent / 'data/history_u4_r12.json').read_text())
            for history in os.environ.get('CENSUS_HISTORIES','cold,warm,warm-all').split(','):
                h = PeTTaChainer()
                at = 0
                for snap in record['snaps']:
                    for name, params in record['calls'][at:snap['n']]:
                        getattr(h, name)(*params)
                    at = snap['n']
                    if history != 'cold':
                        h.query_many_refs(snap['goals'], steps=2000)
                if history == 'warm-all':
                    for _ in range(3):
                        for snap in record['snaps']:
                            h.query_many_refs(snap['goals'], steps=20000)
                for repeat in range(12):
                    answer = h.query_many_refs(snap['goals'], steps=2000)
                    pos = snap['goals'].index('(: $prf (Degraded power-plant t13) $tv)')
                    print(json.dumps(dict(history=history, repeat=repeat, tv=answer[pos][0].tv, metrics=h.last_query_metrics())), flush=True)
        else:
            sys.path.insert(0, '/nexus/Dev/OpenCog/bench')
            import compare
            job = dict(supplynet=lambda: compare.supplynet(3, 4, 100, cycle='untimed'),
                       scale=lambda: compare.scale('l', 16),
                       conflict=lambda: compare.conflict('m', 2, 4),
                       replay=lambda: compare.replay(4, 50))[args.case]()
            argv, cwd, env = compare.command(job, None)
            # Use this checkout, including for replay's default import.
            root = HERE.parents[1]
            env['PYTHONPATH'] += os.pathsep + str(root)
            os.environ.update(env)
            os.chdir(cwd)
            sys.path[:0] = env['PYTHONPATH'].split(os.pathsep)
            if job.get('chainer_arg'):
                argv += ['--pettachainer-path', str(root)]
            if argv[1] == '-m':
                sys.argv = argv[2:]
                runpy.run_module(argv[2], run_name='__main__')
            else:
                sys.argv = argv[1:]
                runpy.run_path(argv[1], run_name='__main__')
    except SystemExit as exc:
        if exc.code not in (None, 0):
            raise
    finally:
        data = janus.query_once('ctx_stats(Classes,Requests,Merges,Conditioned)')
        payload = dict(case=args.case, observed_cuts=counts(data['Classes']),
                       raw_exclusions=counts(data['Requests']),
                       demand_envelope=counts(data['Requests'] + data['Classes']),
                       queries=len(calls),
                       query_exclusion_merges=sum(c['merges'] for c in calls),
                       query_exclusion_conditioned=sum(c['conditioned'] for c in calls),
                       exclusion_merges=data['Merges'],
                       conditioned_from_exclusion_merges=data['Conditioned'], calls=calls)
        args.out.write_text(json.dumps(payload, indent=2) + '\n')
        print('CONTEXT_CENSUS ' + json.dumps({k:v for k,v in payload.items() if k != 'calls'}), flush=True)

if __name__ == '__main__':
    main()
