"""Execution owns hypothetical lifetimes, including failed and aborted runs."""
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestExecutionScope(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        janus.consult(str(Path(__file__).with_name('execution_scope_probe.pl')))
        self.addCleanup(janus.query_once, 'execution_scope_probe_clear')
        self.h.add_atoms_no_check([
            '(: (no_inverse r) (Implication (Action x) (Effect x)) (CTV (STV 0.9 0.8) (STV 0.1 0.8)))',
            '(: world (Recorded x) (STV 0.7 0.8))',
        ])

    def assert_closed(self):
        result = janus.query_once('execution_scope_probe_closed')
        self.assertTrue(result['truth'], result)

    def test_compilation_returns_an_inert_scope_declaration(self):
        compiled = self.h.handler.process_metta_string(
            f'!(collapse (mm2compileQuery {self.h.kb} '
            '(: $p (Assuming (Action x) (Effect x)) $tv)))'
        )
        self.assertIn('query-scope', str(compiled))
        self.assert_closed()
        self.assertEqual(self.h.query_many_refs(['(: $p (Effect x) $tv)'], steps=100), [[]])

    def test_exception_and_failure_close_the_world_before_the_next_call(self):
        for mode in ('throw', 'fail'):
            with self.subTest(mode=mode):
                janus.query_once('execution_scope_probe_install(Mode)', {'Mode': mode})
                if mode == 'throw':
                    with self.assertRaisesRegex(janus.PrologError, 'execution_scope_probe'):
                        self.h.query_many_refs(['(: $p (Assuming (Action x) (Effect x)) $tv)'], steps=100)
                else:
                    self.assertEqual(self.h.query_many_refs(
                        ['(: $p (Assuming (Action x) (Effect x)) $tv)'], steps=100), [[]])
                self.assert_closed()
                self.assertTrue(janus.query_once("'search-id-value'(sk_claim_state,-1)")['truth'])
                janus.query_once('execution_scope_probe_clear')
                rows = self.h.query_many_refs([
                    '(: $p (Effect x) $tv)',
                    '(: $p (Assuming (Action x) (Effect x)) $tv)',
                    '(: $p (Recorded x) $tv)',
                ], steps=100)
                self.assertEqual(rows[0], [])
                self.assertEqual(len(rows[1]), 1)
                self.assertAlmostEqual(rows[1][0].tv[1], .9)
                self.assertAlmostEqual(rows[1][0].tv[2], .8)
                self.assertEqual([r.tv for r in rows[2]], [['STV', .7, .8]])
                self.assert_closed()

    def test_repeated_mixed_worlds_have_independent_allowances(self):
        goals = [
            '(: $p (Recorded x) $tv)',
            '(: $p (Assuming (Action x) (Effect x)) $tv)',
            '(: $p (Assuming (Not (Action x)) (Action x)) $tv)',
            '(: $p (Effect x) $tv)',
        ]
        for budget in (0, 1, 20, 0, 20):
            for order in (goals, list(reversed(goals))):
                rows = self.h.query_many_refs(order, steps=budget)
                tvs = {goal: [r.tv for r in answer] for goal, answer in zip(order, rows)}
                self.assertEqual(tvs[goals[0]], [['STV', .7, .8]])
                self.assertEqual(tvs[goals[2]], [['STV', 0, 1]])
                self.assertEqual(tvs[goals[3]], [])
                if budget >= 20:
                    self.assertEqual(len(tvs[goals[1]]), 1)
                    self.assertAlmostEqual(tvs[goals[1]][0][1], .9)
                    self.assertAlmostEqual(tvs[goals[1]][0][2], .8)
                self.assert_closed()
