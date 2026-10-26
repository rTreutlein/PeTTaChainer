"""Weighted Assuming facts `(: name statement tv)` keep their values in the query world (#120)."""
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer

HABIT = '(: habit (PlaysTennis Bob) (STV 0.9 0.8))'
BRIDGE = '(Implication (PlaysTennis Bob) (PlayingTennisNow Bob))'


def answers(handler, goal):
    return handler.query_many_refs([f'(: $p {goal} $tv)'], steps=1000)[0]


def tv(handler, goal):
    rows = answers(handler, goal)
    assert len(rows) == 1, rows
    return rows[0].tv


def isolated(*atoms):
    handler = PeTTaChainer()
    handler.add_atoms_no_check(list(atoms))
    return handler


class WeightedAssumptionTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        janus.consult(str(Path(__file__).with_name('context_overlay_probe.pl')))
        janus.query_once('overlay_probe_install(none)')

    def assertNoMainLeak(self):
        self.assertEqual(janus.query_once('overlay_probe_main_leaks(Kb,Rows)', {'Kb': self.h.kb})['Rows'], [])

    def test_direct_weighted_fact_reads_its_own_value(self):
        goal = '(PlayingTennisNow Bob)'
        self.assertEqual(tv(self.h, f'(Assuming {goal} {goal})'), ['STV', 1.0, 1.0])
        rows = answers(self.h, f'(Assuming (: bridge {goal} (STV 0.12 0.2)) {goal})')
        self.assertEqual(len(rows), 1, rows)
        self.assertEqual(rows[0].tv, ['STV', 0.12, 0.2])
        self.assertEqual(rows[0].statement[1], [':', 'bridge', ['PlayingTennisNow', 'Bob'], ['STV', 0.12, 0.2]])
        self.assertEqual(tv(self.h, f'(Assuming (: n (Not {goal}) (STV 0.7 0.6)) {goal})')[1:],
                         [1.0 - 0.7, 0.6])
        self.assertEqual(answers(self.h, goal), [])
        self.assertNoMainLeak()

    def test_weighted_implication_consumes_a_main_fact_as_an_isolated_kb_rule(self):
        self.h.add_atoms_no_check([HABIT])
        for rule_tv in ('(STV 0.12 0.2)', '(CTV (STV 0.12 0.2) (STV 0.01 0.5))'):
            with self.subTest(rule_tv=rule_tv):
                expected = tv(isolated(HABIT, f'(: bridge {BRIDGE} {rule_tv})'), '(PlayingTennisNow Bob)')
                self.assertLess(expected[2], 0.3)
                rows = answers(self.h, f'(Assuming (: bridge {BRIDGE} {rule_tv}) (PlayingTennisNow Bob))')
                self.assertEqual(len(rows), 1, rows)
                self.assertEqual(rows[0].tv, expected)
                self.assertIn('habit', self.h.expand_proof(rows[0].proof))
        self.assertEqual(answers(self.h, '(PlayingTennisNow Bob)'), [])
        self.assertNoMainLeak()

    def test_several_weighted_and_bare_assumptions_keep_their_values(self):
        facts = '(And (A x) (: wb (B x) (STV 0.3 0.9)) (: wc (C x) (STV 0.6 0.5)))'
        for goal, value in (('(A x)', [1.0, 1.0]), ('(B x)', [0.3, 0.9]), ('(C x)', [0.6, 0.5])):
            with self.subTest(goal=goal):
                self.assertEqual(tv(self.h, f'(Assuming {facts} {goal})')[1:], value)
        both = tv(self.h, f'(Assuming {facts} (And (B x) (C x)))')
        self.assertAlmostEqual(both[1], 0.3 * 0.6)
        for goal in ('(A x)', '(B x)', '(C x)'):
            self.assertEqual(answers(self.h, goal), [])
        self.assertNoMainLeak()

    def test_weighted_fact_on_a_main_key_is_one_more_stored_report(self):
        main = ['(: main (P a) (STV 0.2 0.8))',
                '(: r (Implication (P a) (Q a)) (CTV (STV 0.9 0.9) (STV 0.1 0.9)))']
        self.h.add_atoms_no_check(main)
        before = {goal: tv(self.h, goal) for goal in ('(P a)', '(Q a)')}
        reference = isolated(*main, '(: w (P a) (STV 0.9 0.9))')
        for goal in ('(P a)', '(Q a)'):
            with self.subTest(goal=goal):
                self.assertEqual(tv(self.h, f'(Assuming (: w (P a) (STV 0.9 0.9)) {goal})'), tv(reference, goal))
        self.assertEqual(tv(self.h, '(Assuming (P a) (Q a))')[1], 0.9)
        self.assertEqual({goal: tv(self.h, goal) for goal in before}, before)
        self.assertNoMainLeak()

    def test_unsupported_annotations_are_rejected(self):
        for annotation in (
                '(: b (P a))', '(: b (P a) $tv)', '(: $name (P a) (STV 0.5 0.5))',
                '(: b (P a) (STV 1.5 0.2))', '(: b (P a) foo)', '(: b (P a) (CTV (STV 1 1) (STV 0 1)))',
                '(: b (P $x) (STV 0.5 0.5))', '(: b (And (P a) (Q a)) (STV 0.5 0.5))',
                '(: b (Exists ($x) (P $x)) (STV 0.5 0.5))', '(: b (Compute f (1) -> $r) (STV 0.5 0.5))',
                '(: b (Implication (P a) (Q a)) (PointMass 1.0))', '(: b (Not (P a)) (CTV (STV 1 1) (STV 0 1)))',
                '(: b (Height bob) (PointMass 170.0))'):
            with self.subTest(annotation=annotation):
                with self.assertRaisesRegex(janus.PrologError, 'weighted_assumption'):
                    answers(self.h, f'(Assuming (And (P a) {annotation}) (P a))')

        for query in ('(Implication (: w (P a) (STV 0.9 0.9)) (Q a))',
                      '(And (P a) (: q (Implication (P a) (Q a)) (STV 0.5 0.5)))',
                      '(Assuming (And (P a) (And (: w (K a) (STV 0.9 0.9)))) (K a))'):
            with self.subTest(query=query):
                with self.assertRaisesRegex(janus.PrologError, 'weighted_assumption'):
                    answers(self.h, query)

    def test_assuming_below_the_root_is_rejected(self):
        # One world per query: a nested Assuming used to answer with its
        # unevaluated ContextQuery marker (#125).
        for query in ('(Assuming (P a) (Assuming (Q a) (R a)))',
                      f'(Assuming {HABIT} (Assuming (Q a) (R a)))',
                      '(Assuming (Assuming (P a) (Q a)) (R a))',
                      '(And (Assuming (P a) (P a)) (Q a))',
                      '(Not (Assuming (P a) (P a)))'):
            with self.subTest(query=query):
                with self.assertRaisesRegex(janus.PrologError, 'nested_assuming'):
                    answers(self.h, query)
        for query in ('(Assuming (P a))', '(Assuming (P a) (Q a) (R a))'):
            with self.subTest(query=query):
                with self.assertRaisesRegex(janus.PrologError, 'assuming_arguments'):
                    answers(self.h, query)

    def test_population_reads_stay_mains(self):
        # #124: a variable STV rule's base-rate branch reads MAIN's population,
        # which does not count the weighted fact, unlike an isolated KB.
        main = ['(: m (P a) (STV 0.2 0.8))', '(: mb (P b) (STV 0.9 0.8))', '(: qb (Q b) (STV 0.7 0.8))',
                '(: mc (P c) (STV 0.1 0.8))', '(: qc (Q c) (STV 0.2 0.8))',
                '(: r (Implication (P $x) (Q $x)) (STV 0.8 0.6))']
        self.h.add_atoms_no_check(main)
        assumed = tv(self.h, '(Assuming (: w (P a) (STV 0.9 0.9)) (Q a))')
        self.assertAlmostEqual(assumed[1], 0.6458417372510326, delta=1e-9)
        self.assertAlmostEqual(assumed[2], 0.017130300623693237, delta=1e-9)
        self.assertNotAlmostEqual(assumed[1], tv(isolated(*main, '(: w (P a) (STV 0.9 0.9))'), '(Q a)')[1])
        self.assertNoMainLeak()

    def assertAssumedRulesMatchIsolated(self, main, rules, goal):
        self.h.add_atoms_no_check(main)
        for rule in rules:
            with self.subTest(rule=rule):
                self.assertEqual(tv(self.h, f'(Assuming {rule} {goal})'), tv(isolated(*main, rule), goal))
        self.assertNoMainLeak()

    def test_assumed_rule_also_stated_in_main(self):
        # #123: an assumed STV or CTV rule combines with MAIN's statement of it as two stored rules do.
        self.assertAssumedRulesMatchIsolated(
            ['(: h (P a) (STV 0.9 0.8))', '(: o (Q a) (STV 0.4 0.7))',
             '(: r (Implication (P a) (Q a)) (STV 0.7 0.5))'],
            ['(: w (Implication (P a) (Q a)) (STV 0.99 0.99))',
             '(: w (Implication (P a) (Q a)) (STV 0.01 0.99))',
             '(: w (Implication (P a) (Q a)) (CTV (STV 0.99 0.99) (STV 0.0 0.99)))'],
            '(Q a)')

    def test_assumed_schematic_rule_also_stated_in_main(self):
        self.assertAssumedRulesMatchIsolated(
            ['(: h (P a) (STV 0.9 0.8))', '(: hb (P b) (STV 0.3 0.8))', '(: o (Q a) (STV 0.4 0.7))',
             '(: r (Implication (P $x) (Q $x)) (STV 0.7 0.5))'],
            ['(: w (Implication (P $x) (Q $x)) (STV 0.9 0.9))',
             '(: w (Implication (P $x) (Q $x)) (CTV (STV 0.9 0.9) (STV 0.1 0.9)))'],
            '(Q a)')

    def test_main_and_assumption_state_one_rule_with_different_ctvs(self):
        self.assertAssumedRulesMatchIsolated(
            ['(: h (P a) (STV 0.9 0.8))', '(: o (Q a) (STV 0.4 0.7))',
             '(: r (Implication (P a) (Q a)) (CTV (STV 0.7 0.5) (STV 0.3 0.5)))'],
            ['(: w (Implication (P a) (Q a)) (CTV (STV 0.95 0.9) (STV 0.1 0.9)))',
             '(: w (Implication (P a) (Q a)) (CTV (STV 0.2 0.6) (STV 0.6 0.6)))'],
            '(Q a)')

if __name__ == '__main__':
    unittest.main()
