"""Issue #60: executable acceptance tests for context-node rounds.

The expected failures specify the intended behavior, with their landing round.
Positive fixture checks live outside expectedFailure so a broken reproducer
cannot silently turn into an expected failure. Round 1 uses context-node publications and node subscriptions.
"""
from contextlib import ExitStack
from functools import lru_cache
import itertools
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import traceback
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer

WORK = ('row_computes', 'context_nodes_created', 'merged_cache_misses', 'conditioned_evaluations', 'conditions_unpaid')


def sample(h, goals, repeats=24, budget=2000, label=None):
    rows = []
    quiet = 0
    for _ in range(repeats):
        started = time.monotonic()
        answers = h.query_many_refs(goals, steps=budget)
        if janus.query_once('current_predicate(context_probe_installed/0)')['truth']:
            invalid = janus.query_once('context_probe_invalid(Rows)')['Rows']
            if invalid:
                raise AssertionError(invalid)
        rows.append(dict(tvs=[[a.tv for a in group] for group in answers],
                         work={k: h.last_query_metrics().get(k, 0) for k in WORK}))
        if label:
            print(json.dumps(dict(history=label, budget=budget, repeat=len(rows),
                seconds=time.monotonic() - started, work=rows[-1]['work'])), flush=True)
        quiet = quiet + 1 if not any(rows[-1]['work'].values()) and (len(rows) < 2 or rows[-1]['tvs'] == rows[-2]['tvs']) else 0
        if quiet >= 3:
            break
    return rows


def history_worker(history, out):
    """Fork the identical history prefix for each final budget, as the MeTTa runner does."""
    record = json.loads((Path(__file__).resolve().parents[1] / 'data/history_u4_r12.json').read_text())
    h = PeTTaChainer()
    h.set_query_metrics(True)
    started = time.monotonic()
    janus.consult(str(Path(__file__).resolve().parents[1] / 'context_node_probe.pl'))
    janus.query_once('context_probe_install')
    at = 0
    for snap in record['snaps']:
        for name, args in record['calls'][at:snap['n']]:
            getattr(h, name)(*args)
        at = snap['n']
        if history != 'cold':
            h.query_many_refs(snap['goals'], steps=2000)
            print(f'{history} prefix {at}: {time.monotonic() - started:.2f}s', flush=True)
    position = snap['goals'].index('(: $prf (Degraded power-plant t13) $tv)')
    janus.query_once('use_module(library(unix))')
    # Warm-all extends the same unchanged warm prefix. Forking the final
    # samples leaves that prefix untouched and avoids rebuilding it twice.
    for mode in (('warm', 'warm-all') if history == 'warm' else (history,)):
        if mode == 'warm-all':
            for _ in range(3):
                for prior in record['snaps']:
                    h.query_many_refs(prior['goals'], steps=20000)
                print(f'{mode} pass {_ + 1}: {time.monotonic() - started:.2f}s', flush=True)
        target = out.with_name(f'{mode}.json')
        results = {}
        pidfile = out.with_suffix('.pid')
        for budget in (2000, 20000):
            child_out = target.with_suffix(f'.{budget}.json')
            pid = janus.query_once('fork(Pid)')['Pid']
            if pid == 'child':
                try:
                    rows = sample(h, snap['goals'], budget=budget, label=mode)
                    child_out.write_text(json.dumps(dict(tv=rows[-1]['tvs'][position][0], rows=rows)))
                except BaseException:
                    child_out.write_text(json.dumps(dict(error=traceback.format_exc())))
                    os._exit(1)
                os._exit(0)
            pidfile.write_text(str(pid))
            deadline = time.monotonic() + 240
            while True:
                os.kill(pid, 0)
                ended, status = os.waitpid(pid, os.WNOHANG)
                if ended:
                    break
                if time.monotonic() >= deadline:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                    raise TimeoutError(f'T1 {mode} budget {budget}')
                time.sleep(.05)
            pidfile.unlink()
            result = json.loads(child_out.read_text())
            if status:
                raise AssertionError(result)
            results[str(budget)] = result
        target.write_text(json.dumps(results))


@lru_cache(None)
def replays():
    # A fresh process per history avoids unrelated KBs changing absorption or
    # aggregate state. Run the independent histories together (two CPU slots).
    # Budget forks share only the prefix, never final queries.
    results = {2000: {}, 20000: {}}
    errors = []
    with tempfile.TemporaryDirectory(prefix='context-histories-') as directory, ExitStack() as streams:
        jobs = []
        try:
            for history in ('cold', 'warm'):
                out = Path(directory) / f'{history}.json'
                log = out.with_suffix('.log')
                stream = streams.enter_context(log.open('w'))
                process = subprocess.Popen([sys.executable, __file__, '--history', history, str(out)],
                                           stdout=stream, stderr=subprocess.STDOUT)
                jobs.append((history, out, log, process, time.monotonic() + 500))
            for history, out, log, process, deadline in jobs:
                while process.poll() is None:
                    os.kill(process.pid, 0)
                    if time.monotonic() >= deadline:
                        raise TimeoutError(f'T1 {history} setup and budget samples')
                    time.sleep(.05)
                if process.returncode:
                    errors.append(log.read_text())
                    continue
                for mode in (('warm', 'warm-all') if history == 'warm' else (history,)):
                    data = json.loads(out.with_name(f'{mode}.json').read_text())
                    for budget in results:
                        results[budget][mode] = data[str(budget)]
                        print('T1 ' + json.dumps(dict(budget=budget, history=mode,
                            tv=data[str(budget)]['tv'], last_work=[r['work'] for r in data[str(budget)]['rows'][-3:]])), flush=True)
        finally:
            for _history, out, _log, process, _deadline in jobs:
                if process.poll() is None:
                    pidfile = out.with_suffix('.pid')
                    if pidfile.exists():
                        child = int(pidfile.read_text())
                        stat = Path(f'/proc/{child}/stat')
                        if stat.exists() and int(stat.read_text().split()[3]) == process.pid:
                            os.kill(child, signal.SIGKILL)
                    process.kill()
                process.wait()
    return dict(error='\n'.join(errors)) if errors else results


def replay(budget):
    results = replays()
    if 'error' in results:
        raise AssertionError(results['error'])
    return results[budget]


@lru_cache(None)
def base_rate_loop():
    h = PeTTaChainer()
    h.set_query_metrics(True)
    h.set_evidence_confidence_k(5)
    for p in ('P', 'Q', 'F'):
        h.set_complete_predicate(p)
    h.add_atoms_no_check([
        '(: persist (Implication (And (Next $p $t) (D $p)) (D $t)) (CTV (STV 0.75 1) (STV 0.05 1)))',
        '(: runsP (Implication (And (F $t) (Not (D $t))) (P $t)) (CTV (STV 1 1) (STV 0 1)))',
        '(: runsQ (Implication (And (P $t) (Not (E $t))) (Q $t)) (CTV (STV 1 1) (STV 0 1)))',
        '(: fuel (Implication (Q $t) (F $t)) (CTV (STV 1 1) (STV 0 1)))',
        '(: d0 (D t0) (STV 0 1))', '(: e0 (E t0) (STV 0 1))',
        '(: f1 (F t1) (STV 1 1))',
    ])
    snaps = []
    for i in range(1, 5):
        h.add_atoms_no_check([f'(: n{i} (Next t{i-1} t{i}) (STV 1 1))'])
        goals = [f'(: $p ({p} t{i}) $tv)' for p in ('D', 'E', 'P', 'Q', 'F')]
        snaps.append(goals)
        h.query_many_refs(goals, steps=2000)
    h.add_atoms_no_check(['(: ob (P t2) (STV 1 1))'])
    for _ in range(3):
        for goals in snaps:
            h.query_many_refs(goals, steps=20000)
    rows = sample(h, goals, repeats=12)
    print('T2 ' + json.dumps(rows[-3:]), flush=True)
    return h, rows


@lru_cache(None)
def deep_stale():
    results = []
    for warm in (False, True):
        h = PeTTaChainer()
        h.set_query_metrics(True)
        h.set_evidence_confidence_k(5)
        h.set_complete_predicate('P')
        h.add_atoms_no_check([
            '(: persist (Implication (And (Next $p $t) (D $p)) (D $t)) (CTV (STV 0.75 1) (STV 0.05 1)))',
            '(: runs (Implication (And (F $t) (Not (D $t))) (P $t)) (CTV (STV 1 1) (STV 0 1)))',
            '(: d0 (D t0) (STV 0.1 0.8))',
            *[f'(: f{i} (F t{i}) (STV 1 1))' for i in range(6)],
        ])
        for i in range(1, 6):
            h.add_atoms_no_check([f'(: n{i} (Next t{i-1} t{i}) (STV 1 1))'])
            if warm:
                h.query_many_refs([f'(: $p (D t{i}) $tv)'], steps=2000)
        # Observed output completes the antecedent at t1, four persistence
        # links from t5 (free depth is two). Warm t1 retains stale rows.
        h.add_atoms_no_check(['(: ob (P t1) (STV 1 1))'])
        rows = sample(h, ['(: $p (D t5) $tv)'], repeats=12)
        results.append(dict(tv=rows[-1]['tvs'][0][0], rows=rows, kb=h.kb))
    print('T3 ' + json.dumps([dict(tv=r['tv'], work=r['rows'][-1]['work']) for r in results]), flush=True)
    return results


@lru_cache(None)
def h1_diamond():
    h = PeTTaChainer()
    h.add_atoms_no_check([
        '(: shared_source (Implication (Exists ($x) (P $site $x)) (Mid $site)) (CTV (STV 0.8 0.9) (STV 0 1)))',
        '(: left_source (Implication (Mid $site) (Left $site)) (CTV (STV 1 1) (STV 0 1)))',
        '(: right_source (Implication (Mid $site) (Right $site)) (CTV (STV 1 1) (STV 0 1)))',
        '(: join_source (Implication (And (Left $site) (Right $site)) (Done $site)) (CTV (STV 1 1) (STV 0 1)))',
    ])
    answers = h.query_many_refs([
        '(: $p (Implication (Exists ($x) (P $site $x)) (Done $site)) $tv)',
    ], steps=500)[0]
    return [dict(tv=a.tv, statement=a.statement) for a in answers]


@lru_cache(None)
def h1_many_root_error():
    h = PeTTaChainer()
    source = (Path(__file__).resolve().parents[1] / 'metta/test_anytime_roots.metta').read_text()
    fixture = source[:source.index('!(test')]
    h.handler.process_metta_string('\n'.join(
        line for line in fixture.splitlines() if not line.strip().startswith('!(import!')))
    error = h.handler.process_metta_string(f'!(any-error-at 50 {h.kb})')
    return float(error[0])


class FixtureTests(unittest.TestCase):
    def test_h1_fixtures_have_valid_numeric_answers(self):
        answers = h1_diamond()
        self.assertEqual(len(answers), 1)
        self.assertEqual(answers[0]['statement'][0], 'Implication')
        self.assertEqual(answers[0]['tv'][0], 'STV')
        self.assertTrue(all(0 <= value <= 1 for value in answers[0]['tv'][1:]))
        self.assertTrue(0 <= h1_many_root_error() <= 4)

    def test_t1_fixture_has_full_tvs_and_unchanged_inputs(self):
        for budget in (2000, 20000):
            result = replay(budget)
            for history, item in result.items():
                self.assertEqual(item['tv'][0], 'STV')
                self.assertEqual(len(item['tv']), 3)
                self.assertTrue(all(row['tvs'] for row in item['rows']), history)

    def test_t2_fixture_has_fold_subscribed_nodes(self):
        h, rows = base_rate_loop()
        self.assertTrue(all(row['tvs'][0] for row in rows))
        # A row node's direct inputs include a base-rate fold. This checks the
        # aggregate path, independently of the quiescence assertion.
        result = janus.query_once(
            "aggregate_all(count, ('&sk_context'(_D,_RowId,_H,_K,_R,_Q,_E,_C,_Deps,_V,_Fresh), "
            "_K=['sk-key',_,[Kb,'MAIN','Nil']], '&sk_context_reader'(_MergeId,_RowId), "
            "'&sk_context_merge'(_MD,_MergeId,_MH,['sk-fold',_],_MR,_MQ,_ME,_MC,_MDeps,_MV,_MF)), Count)",
            {'Kb': h.kb})
        self.assertGreater(result['Count'], 0)

    def test_t3_fixture_is_quiet_and_has_deep_rows(self):
        for result in deep_stale():
            self.assertEqual(result['tv'][0], 'STV')
            self.assertTrue(all(not any(row['work'].values()) for row in result['rows'][-3:]))
        warm = deep_stale()[1]
        deep_rows = janus.query_once(
            "aggregate_all(count, ('&sk_row'(_H,_K,_R,_), "
            "_K=['sk-key',['D',t1],[Kb,'MAIN','Nil']]),Count)",
            {'Kb': warm['kb']})['Count']
        self.assertGreater(deep_rows, 0)


class ContextNodeAcceptanceTests(unittest.TestCase):
    @unittest.expectedFailure
    def test_h1_shared_source_judgment_round2(self):
        """H1 still freezes the shared-source diamond; Round 2 removes H1."""
        answer = h1_diamond()[0]
        self.assertAlmostEqual(answer['tv'][1], .8, delta=1e-12)
        self.assertLessEqual(answer['tv'][2], .9 + 1e-12)

    def test_h1_many_root_posterior_round2(self):
        """Larger allowance preserves the many-root posterior bound, restored in Round 1b."""
        self.assertLess(h1_many_root_error(), .001)

    @unittest.expectedFailure
    def test_t1_full_tv_history_equality_round3(self):
        """H1-H3 give different full TVs; context-node rounds 1-3 remove them."""
        for budget in (2000, 20000):
            result = replay(budget)
            for history in ('warm', 'warm-all'):
                for actual, expected in zip(result[history]['tv'][1:], result['cold']['tv'][1:]):
                    self.assertAlmostEqual(actual, expected, delta=1e-12,
                                           msg=f'T1 budget={budget} history={history}; round 3')

    def test_t1_zero_work_three_repeats_round1(self):
        """The #54 aggregate invalidation loop persists; round 1 must be quiet."""
        for budget in (2000, 20000):
            for history, result in replay(budget).items():
                for row in result['rows'][-3:]:
                    self.assertFalse(any(row['work'].values()), (budget, history, row['work']))
                    self.assertEqual(row['tvs'], result['rows'][-1]['tvs'])

    def test_t2_base_rate_loop_quiet_round1(self):
        """Key-level aggregate invalidation rebuilds a branch forever; round 1."""
        for row in base_rate_loop()[1][-3:]:
            self.assertFalse(any(row['work'].values()), row['work'])

    @unittest.expectedFailure
    def test_t3_deep_refresh_history_equality_round3(self):
        """H3 keeps the deep stale snapshot; Round 3 spends leftover allowance."""
        cold, warm = deep_stale()
        for actual, expected in zip(warm['tv'][1:], cold['tv'][1:]):
            self.assertAlmostEqual(actual, expected, delta=1e-12)

    def test_t4_c1_insertion_orders_full_tvs(self):
        facts = ['(: mf (M a) (STV 1 0.8))', '(: xf (X a) (STV 1 0.8))']
        rules = [f'(: (no_inverse {p}{q}) (Implication ({p} a) ({q} a)) (CTV (STV 1 1) (STV 0 1)))'
                 for p, q in (('X', 'M'), ('M', 'B'), ('B', 'X'))]
        goals = [f'(: $p ({p} a) $tv)' for p in ('X', 'M', 'B')]
        self.check_orders(facts, rules, goals)

    def test_t4_three_four_cycle_permutations_full_tvs(self):
        for n in (3, 4):
            facts = ['(: f0 (P0 a) (STV 1 0.8))', '(: f1 (P1 a) (STV 1 0.8))']
            rules = [f'(: (no_inverse r{i}) (Implication (P{i} a) (P{(i+1)%n} a)) '
                     '(CTV (STV 1 1) (STV 0 1)))' for i in range(n)]
            goals = [f'(: $p (P{i} a) $tv)' for i in range(n)]
            self.check_orders(facts, rules, goals)

    def check_orders(self, facts, rules, goals):
        cold = PeTTaChainer()
        cold.add_atoms_no_check(facts + rules)
        expected = [[a.tv for a in group] for group in cold.query_many_refs(goals, steps=5000)]
        self.assertTrue(all(expected))
        for order in itertools.permutations(rules):
            for interleaved in (False, True):
                h = PeTTaChainer()
                h.add_atoms_no_check(facts)
                for rule in order:
                    h.add_atoms_no_check([rule])
                    if interleaved:
                        for goal in goals:
                            h.query_many_refs([goal], steps=200)
                for _ in range(3):
                    actual = [[a.tv for a in group] for group in h.query_many_refs(goals, steps=5000)]
                self.assertEqual([len(g) for g in actual], [len(g) for g in expected])
                for got_group, want_group in zip(actual, expected):
                    for got, want in zip(got_group, want_group):
                        self.assertEqual(got[0], want[0])
                        for component, target in zip(got[1:], want[1:]):
                            self.assertAlmostEqual(component, target, delta=1e-12, msg=str((order, interleaved)))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--history':
        history_worker(sys.argv[2], Path(sys.argv[3]))
    else:
        unittest.main(verbosity=2)
