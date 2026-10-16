"""Issue #60 Round 0: executable acceptance tests for context-node rounds.

The expected failures specify the intended behavior, with their landing round.
Positive fixture checks live outside expectedFailure so a broken reproducer
cannot silently turn into an expected failure. No runtime implementation edits.
"""
from functools import lru_cache
import itertools
import json
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer

WORK = ('row_computes', 'branch_builds', 'conditioned_evaluations', 'conditions_unpaid')


def sample(h, goals, repeats=24, budget=2000):
    rows = []
    for _ in range(repeats):
        answers = h.query_many_refs(goals, steps=budget)
        rows.append(dict(tvs=[[a.tv for a in group] for group in answers],
                         work={k: h.last_query_metrics().get(k, 0) for k in WORK}))
    return rows


@lru_cache(None)
def replay(budget):
    record = json.loads((Path(__file__).resolve().parents[1] / 'data/history_u4_r12.json').read_text())
    results = {}
    for history in ('cold', 'warm', 'warm-all'):
        h = PeTTaChainer()
        h.set_query_metrics(True)
        at = 0
        for snap in record['snaps']:
            for name, args in record['calls'][at:snap['n']]:
                getattr(h, name)(*args)
            at = snap['n']
            if history != 'cold':
                h.query_many_refs(snap['goals'], steps=2000)
        if history == 'warm-all':
            for _ in range(3):
                for prior in record['snaps']:
                    h.query_many_refs(prior['goals'], steps=20000)
        position = snap['goals'].index('(: $prf (Degraded power-plant t13) $tv)')
        rows = sample(h, snap['goals'], budget=budget)
        results[history] = dict(tv=rows[-1]['tvs'][position][0], rows=rows)
        print('T1 ' + json.dumps(dict(budget=budget, history=history,
                                    tv=results[history]['tv'], last_work=[r['work'] for r in rows[-3:]])), flush=True)
    return results


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


class FixtureTests(unittest.TestCase):
    def test_t1_fixture_has_full_tvs_and_unchanged_inputs(self):
        for budget in (2000, 20000):
            result = replay(budget)
            for history, item in result.items():
                self.assertEqual(item['tv'][0], 'STV')
                self.assertEqual(len(item['tv']), 3)
                self.assertTrue(all(row['tvs'] for row in item['rows']), history)

    def test_t2_fixture_has_fold_subscribed_branches(self):
        h, rows = base_rate_loop()
        self.assertTrue(all(row['tvs'][0] for row in rows))
        # A branch's direct inputs include a base-rate fold. This checks the
        # aggregate path, independently of the expected quiescence failure.
        result = janus.query_once(
            "aggregate_all(count, ('&sk_branch_owner'(_S,_H,_K,_R,_Inputs), "
            "_K=['sk-key',_,[Kb,'MAIN','Nil']], member(_F,_Inputs), _F=['sk-fold',_]), Count)",
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
    def test_t1_full_tv_history_equality_round3(self):
        """H1-H3 give different full TVs; context-node rounds 1-3 remove them."""
        for budget in (2000, 20000):
            result = replay(budget)
            for history in ('warm', 'warm-all'):
                for actual, expected in zip(result[history]['tv'][1:], result['cold']['tv'][1:]):
                    self.assertAlmostEqual(actual, expected, delta=1e-12,
                                           msg=f'T1 budget={budget} history={history}; round 3')

    @unittest.expectedFailure
    def test_t1_zero_work_three_repeats_round1(self):
        """The #54 aggregate invalidation loop persists; round 1 must be quiet."""
        for budget in (2000, 20000):
            for history, result in replay(budget).items():
                for row in result['rows'][-3:]:
                    self.assertFalse(any(row['work'].values()), (budget, history, row['work']))
                    self.assertEqual(row['tvs'], result['rows'][-1]['tvs'])

    @unittest.expectedFailure
    def test_t2_base_rate_loop_quiet_round1(self):
        """Key-level aggregate invalidation rebuilds a branch forever; round 1."""
        for row in base_rate_loop()[1][-3:]:
            self.assertFalse(any(row['work'].values()), row['work'])

    @unittest.expectedFailure
    def test_t3_deep_refresh_history_equality_round3(self):
        """H3 keeps stale t1 below free depth; round 3 spends leftover allowance."""
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
                self.assertEqual(actual, expected, (order, interleaved))


if __name__ == '__main__':
    unittest.main(verbosity=2)
