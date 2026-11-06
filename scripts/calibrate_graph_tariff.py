"""Measure the event-graph tariff: how many scalar graph operations cost the CPU
time of one evaluation unit (docs/metta/event_node_contract.md, "Tariff").

Runs a workload in this process with probes on the compiled runtime:
- graph side: CPU seconds inside graph_moments and the operations graph_take paid;
- search side: CPU seconds of each backward invocation's outermost sk-walk!
  and sk-evaluate! phases, less the graph work nested in them, and the query
  steps (sk_budget) and evaluation units (sk_eval_budget) they debited.
ops_per_step = (search seconds / step) / (graph seconds / operation).

    calibrate_graph_tariff.py --label L --out F.jsonl -- -m supplynet.cli run ...
    calibrate_graph_tariff.py --label L --out F.jsonl -- -m unittest discover -s tests -p test_x.py
    calibrate_graph_tariff.py --label L --out F.jsonl --ke REQUEST.json [--steps N]

Run it under bench/capped with the resource limits of docs/agent_workflow.md.
"""
import argparse
import json
import runpy
import sys

import janus_swi as janus

from pettachainer import PeTTaChainer

PROBE = r"""
:- use_module(library(prolog_wrap)).
tariff_add(K, V) :- nb_getval(K, O), N is O + V, nb_setval(K, N).
tariff_install :-
    forall(member(K, [tariff_graph_ops, tariff_graph_seconds, tariff_steps, tariff_eval_units, tariff_eval_seconds, tariff_depth]),
           nb_setval(K, 0)),
    wrap_predicate(graph_take(Ops), tariff, Take, (Take, tariff_add(tariff_graph_ops, Ops))),
    wrap_predicate(graph_moments(_, _, _, _, _), tariff, Moments, tariff_graph(Moments)),
    wrap_predicate('sk-walk!'(_, _), tariff, Walk, tariff_phase(Walk)),
    wrap_predicate('sk-evaluate!'(_), tariff, Evaluate, tariff_phase(Evaluate)).
tariff_graph(Goal) :-
    statistics(cputime, T0), ( call(Goal) -> Ok = true ; Ok = false ), statistics(cputime, T1),
    D is T1 - T0, tariff_add(tariff_graph_seconds, D), Ok == true.
tariff_phase(Goal) :-
    (   nb_getval(tariff_depth, 1) -> call(Goal)
    ;   nb_setval(tariff_depth, 1), 'search-id-value'(sk_eval_budget, B0), 'search-id-value'(sk_budget, P0),
        nb_getval(tariff_graph_seconds, G0),
        statistics(cputime, T0),
        catch(( call(Goal) -> Ok = true ; Ok = false ), E, ( nb_setval(tariff_depth, 0), throw(E) )),
        statistics(cputime, T1), nb_getval(tariff_graph_seconds, G1), 'search-id-value'(sk_eval_budget, B1),
        'search-id-value'(sk_budget, P1), nb_setval(tariff_depth, 0), U is B0 - B1, P is P0 - P1, S is T1 - T0 - (G1 - G0),
        tariff_add(tariff_eval_units, U), tariff_add(tariff_steps, P), tariff_add(tariff_eval_seconds, S), Ok == true ).
tariff_totals(Ops, GS, Steps, Units, ES) :-
    nb_getval(tariff_graph_ops, Ops), nb_getval(tariff_graph_seconds, GS), nb_getval(tariff_steps, Steps),
    nb_getval(tariff_eval_units, Units), nb_getval(tariff_eval_seconds, ES).
"""


def replay_ke(path, steps):
    request = json.load(open(path))
    request = request.get('request', request)
    h = PeTTaChainer()
    for declaration in request.get('ir_declarations', []):
        name, args = declaration['function'], declaration['args']
        if name == 'set-evidence-confidence-k':
            h.set_evidence_confidence_k(float(args[0]))
        elif name == 'set-argument-sorts':
            h.set_argument_sorts(args[0], args[1].strip('()').split())
        elif name == 'set-predicate-time':
            h.set_predicate_time(args[0], int(args[1]), int(args[2]))
        else:
            getattr(h, name.replace('-', '_'))(*args)
    h.add_atoms_no_check([entry['atom'] for entry in request['entries']])
    h.query_many_refs(request['queries'], steps=steps or request['steps'])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--label', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--ke')
    parser.add_argument('--steps', type=int)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    a = parser.parse_args()
    PeTTaChainer()  # loads the runtime the probes wrap
    janus.consult('graph_tariff_probe', PROBE)
    janus.query_once('tariff_install')
    status = 0
    try:
        if a.ke:
            replay_ke(a.ke, a.steps)
        else:
            command = a.command[1:] if a.command[:1] == ['--'] else a.command
            sys.argv = command[1:] if command[0] == '-m' else command
            try:
                if command[0] == '-m':
                    sys.argv[0] = command[1]
                    runpy.run_module(command[1], run_name='__main__', alter_sys=True)
                else:
                    runpy.run_path(command[0], run_name='__main__')
            except SystemExit as stop:
                status = stop.code if isinstance(stop.code, int) else 0
    finally:
        row = {'label': a.label, 'status': status}
        totals = janus.query_once('tariff_totals(Ops, GS, Steps, Units, ES)')
        row.update(graph_ops=totals['Ops'], graph_seconds=totals['GS'], steps=totals['Steps'],
                   eval_units=totals['Units'], search_seconds=totals['ES'])
        if row['graph_ops'] and row['graph_seconds'] and row['steps']:
            row['ops_per_step'] = (row['search_seconds'] / row['steps']) / (row['graph_seconds'] / row['graph_ops'])
        with open(a.out, 'a') as stream:
            stream.write(json.dumps(row) + '\n')
        print('graph-tariff', json.dumps(row), file=sys.stderr, flush=True)


if __name__ == '__main__':
    main()
