import itertools
import unittest
from pathlib import Path

import janus_swi as janus

from pettachainer import PeTTaChainer


class HistoryIndependenceTests(unittest.TestCase):
    def test_c1_cold_and_warm_have_both_independent_leaves(self):
        expected = ('(: (merge/revision xf (by (no_inverse bx) (by (no_inverse mb) mf))) '
                    '(X a) (STV 1.0 0.888849375588311))')
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
                self.assertAlmostEqual(assumed[0].tv[2], 0.9997004492512355)
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


if __name__ == '__main__':
    unittest.main()
