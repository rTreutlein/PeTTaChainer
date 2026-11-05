import itertools
import unittest
from pathlib import Path

import janus_swi as janus

from pettachainer import PeTTaChainer


class HistoryIndependenceTests(unittest.TestCase):
    def assert_quiet_repeats(self, h, goal, expected):
        h.set_query_metrics(True)
        counters = ('branch_builds', 'row_computes', 'conditioned_evaluations', 'conditions_unpaid')
        for _ in range(16):
            self.assertEqual(h.query(goal, steps=5000, timeout_sec=0), expected)
            if all(h.last_query_metrics()[counter] == 0 for counter in counters):
                break
        else:
            self.fail(f'Cycle did not become quiet: {h.last_query_metrics()}')
        for _ in range(3):
            self.assertEqual(h.query(goal, steps=5000, timeout_sec=0), expected)
            for counter in counters:
                self.assertEqual(h.last_query_metrics()[counter], 0, (counter, h.last_query_metrics()))

    def test_c1_cold_and_warm_have_both_independent_leaves(self):
        expected = ('(: (factored-revision (by (no_inverse bx) (by (no_inverse mb) mf)) '
                    '(prior (STV 1 0.8)) '
                    '(((reported with cpu (prior (STV 0.5 0.0))) xf))) '
                    '(X a) (STV 1 0.8))')
        for warm in (False, True):
            with self.subTest(warm=warm):
                h = PeTTaChainer()
                if not warm:
                    janus.consult(str(Path(__file__).resolve().parents[1] / 'context_overlay_probe.pl'))
                    janus.query_once('overlay_probe_install(none)')
                h.add_atoms_no_check([
                    '(: mf (M a) (STV 1 0.8))',
                    '(: xf (X a) (STV 1 0.8))',
                    '(: (no_inverse xm) (Implication (X $x) (M $x)) (CTV (STV 1 1) (STV 0 1)))',
                    '(: (no_inverse mb) (Implication (M $x) (B $x)) (CTV (STV 1 1) (STV 0 1)))',
                ])
                if warm:
                    for p in ('M', 'B'):
                        h.query(f'(: $p ({p} a) $tv)', steps=200, timeout_sec=0)
                h.add_atoms_no_check([
                    '(: (no_inverse bx) (Implication (B $x) (X $x)) (CTV (STV 1 1) (STV 0 1)))',
                ])
                for budget in (200, 5000):
                    self.assertEqual(h.query('(: $p (X a) $tv)', steps=budget, timeout_sec=0), [expected])
                for p in ('M', 'B'):
                    h.query(f'(: $p ({p} a) $tv)', steps=200, timeout_sec=0)
                self.assertEqual(h.query('(: $p (X a) $tv)', steps=200, timeout_sec=0), [expected])
                # An overlay may strengthen M, but must neither consume the
                # borrowed MAIN cache as current nor mutate it while C is
                # active. Ordinary MAIN maintenance may republish proof IDs.
                cache_query = (
                    "findall(_Text, ('&sk_branch'(_S,['sk-key',['B',a],[Kb,'MAIN','Nil']],"
                    "_R,_C,_F,_V), "
                    " (_V=['sk-val',[_Type,_Scope,_P,_TV],_Ev,_D] "
                    " -> 'sk-full-proof'(_P,_Full), _Stable=['sk-val',[_Type,_Scope,_Full,_TV],_Ev,_D] "
                    " ; _Stable=_V), term_string([_S,_R,_C,_F,_Stable],_Text)), _Rows), sort(_Rows,Rows)"
                )
                before = janus.query_once(cache_query, {"Kb": h.kb})["Rows"]
                if warm:
                    self.assertTrue(before)
                assumed = h.query_many_refs(['(: $p (Assuming (M a) (X a)) $tv)'], steps=200)[0]
                self.assertEqual(len(assumed), 1)
                # The hard assumption forces X through certain rules: a point.
                self.assertAlmostEqual(assumed[0].tv[2], 0.9999)
                self.assertEqual(janus.query_once(cache_query, {"Kb": h.kb})["Rows"], before)
                self.assertEqual(janus.query_once('overlay_probe_main_leaks(Kb,Rows)', {'Kb': h.kb})['Rows'], [])
                self.assertEqual(h.query('(: $p (X a) $tv)', steps=200, timeout_sec=0), [expected])

    def test_cycle_family_rule_permutations_with_interleaved_queries(self):
        # The independent leaf travels along paths of two and three edges.
        # Query every member after each insertion, including before the loop
        # closes. Compare the final proof and TV with the cold graph.
        for size in (3, 4):
            rules = [f'(: (no_inverse r{i}) (Implication (P{i} a) (P{(i+1) % size} a)) '
                     '(CTV (STV 1 1) (STV 0 1)))' for i in range(size)]
            facts = ['(: f0 (P0 a) (STV 1 0.8))', '(: f1 (P1 a) (STV 1 0.8))']
            cold = PeTTaChainer()
            cold.add_atoms_no_check(facts + rules)
            expected = cold.query('(: $p (P0 a) $tv)', steps=1000, timeout_sec=0)
            for order in itertools.permutations(rules):
                with self.subTest(size=size, order=order):
                    h = PeTTaChainer()
                    h.add_atoms_no_check(facts)
                    for rule in order:
                        h.add_atoms_no_check([rule])
                        for i in range(size):
                            h.query(f'(: $p (P{i} a) $tv)', steps=200, timeout_sec=0)
                    self.assertEqual(h.query('(: $p (P0 a) $tv)', steps=1000, timeout_sec=0), expected)
                    self.assert_quiet_repeats(h, '(: $p (P0 a) $tv)', expected)

    def test_cycle_without_independent_support_does_not_revise_itself(self):
        for has_leaf in (False, True):
            h = PeTTaChainer()
            if has_leaf:
                h.add_atoms_no_check(['(: xf (X a) (STV 1 0.8))'])
            for source, target in (('X', 'M'), ('M', 'B'), ('B', 'X')):
                h.add_atoms_no_check([
                    f'(: (no_inverse {source}{target}) (Implication ({source} a) ({target} a)) '
                    '(CTV (STV 1 1) (STV 0 1)))',
                ])
                for p in ('M', 'B', 'X'):
                    h.query(f'(: $p ({p} a) $tv)', steps=200, timeout_sec=0)
            for budget in (200, 5000):
                answer = h.query('(: $p (X a) $tv)', steps=budget, timeout_sec=0)
                self.assertEqual(answer, ['(: xf (X a) (STV 1 0.8))'] if has_leaf else [])
            self.assert_quiet_repeats(h, '(: $p (X a) $tv)', answer)

    def test_truth_fold_feedback_keeps_its_cause_and_becomes_quiet(self):
        # A truth fold reads beliefs as data. Reissuing a fresh cause on
        # every trip through it would let this
        # numerical feedback keep bypassing the finite-support guard.
        rules = [
            '(: (no_inverse total) (Implication '
            '(And (FoldAllTruth (P $x) (STV $s $_c) $s 0.0 '
            '(|-> ($acc $elem) (+ $acc $elem)) -> $sum) '
            '(Compute / ($sum 2.0) -> $mean)) (Total)) '
            '(CTV (STV $mean 1) (STV $mean 1)))',
            '(: (no_inverse feedback) (Implication (Total) (P a)) '
            '(CTV (STV 0.8 0.9) (STV 0.1 0.9)))',
        ]
        for order in itertools.permutations(rules):
            with self.subTest(order=order):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: pa (P a) (STV 0.2 0.8))',
                    '(: pb (P b) (STV 0.6 0.8))',
                    *order,
                ])
                goal = '(: $p (Total) $tv)'
                expected = ['(: (by (no_inverse total) (conjunction (foldall-proof pa pb) cpu)) '
                            '(Total) (STV 0.4 0.9999))']
                self.assertEqual(h.query(goal, steps=5000, timeout_sec=0), expected)
                self.assert_quiet_repeats(h, goal, expected)

                # Quiescence must not freeze the fold. A new independent
                # member changes the total, then the feedback settles again.
                h.add_atoms_no_check(['(: pc (P c) (STV 0.4 0.8))'])
                answer = h.query_many_refs([goal], steps=5000)[0]
                self.assertEqual(len(answer), 1)
                self.assertAlmostEqual(answer[0].tv[1], 0.6)
                updated = h.query(goal, steps=5000, timeout_sec=0)
                self.assertIn('(foldall-proof pa pb pc)', updated[0])
                self.assert_quiet_repeats(h, goal, updated)


if __name__ == '__main__':
    unittest.main()
