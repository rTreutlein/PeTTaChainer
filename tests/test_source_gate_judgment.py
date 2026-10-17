"""Tracker #45: an observed source gate is a private judgment co-premise."""
import unittest

from pettachainer import PeTTaChainer


class TestSourceGateJudgment(unittest.TestCase):
    def source(self, wrapped, tv):
        consequent = '(Implication (A $x) (And (B $x) (C $x)))'
        if wrapped:
            consequent = f'(And (Metadata S) {consequent})'
        return f'(: rule (Implication (AcceptSource S) {consequent}) {tv})'

    def answers(self, h, statement):
        return h.query_many_refs([f'(: $p {statement} $tv)'], steps=300)[0]

    def assert_judgment(self, h, statement, strength, confidence, observed_gate):
        rows = self.answers(h, statement)
        self.assertEqual(len(rows), 1, rows)
        self.assertEqual(rows[0].tv[0], 'STV')
        self.assertAlmostEqual(rows[0].tv[1], strength)
        self.assertAlmostEqual(rows[0].tv[2], confidence)
        proof = h.expand_proof(rows[0].proof)
        for token in ('conditional-implication', 'rule', '(ctx proof '):
            self.assertIn(token, proof)
        self.assertEqual('accepted' in proof, observed_gate, proof)

    def assert_no_main_leakage(self, h, observed_gate):
        for statement in ('(A a)', '(B a)', '(C a)'):
            self.assertEqual(self.answers(h, statement), [])
            self.assertEqual(h._call('kb-facts', [f'{statement} ({h.kb} MAIN Nil)']), ['()'])
        gates = self.answers(h, '(AcceptSource S)')
        self.assertEqual(len(gates), int(observed_gate), gates)
        if gates:
            self.assertEqual(gates[0].tv, ['STV', 1, 1])

    def test_observed_gate_fresh_and_warm(self):
        for wrapped in (False, True):
            for tv, strength, confidence in (
                ('(STV 1 1)', 1, 0.9998000399670116),
                ('(STV 0.8 0.6)', 0.8,
                 0.4897959182395719 if wrapped else 0.5454545452961622),
            ):
                for individual in ('$x', 'a'):
                    with self.subTest(wrapped=wrapped, tv=tv, individual=individual):
                        h = PeTTaChainer()
                        h.add_atoms_no_check([
                            '(: accepted (AcceptSource S) (STV 1 1))',
                            self.source(wrapped, tv),
                        ])
                        statement = f'(Implication (A {individual}) (C {individual}))'
                        for repeat in range(2):
                            with self.subTest(repeat=repeat):
                                self.assert_judgment(h, statement, strength, confidence, True)
                                self.assert_no_main_leakage(h, True)

    def test_absent_assumed_then_observed_gate(self):
        for wrapped in (False, True):
            for individual in ('$x', 'a'):
                with self.subTest(wrapped=wrapped, individual=individual):
                    h = PeTTaChainer()
                    h.add_atoms_no_check([self.source(wrapped, '(STV 0.8 0.6)')])
                    statement = f'(Implication (A {individual}) (C {individual}))'
                    gated = f'(Implication (AcceptSource S) {statement})'
                    confidence = 0.4897959182395719 if wrapped else 0.5454545452961622
                    for repeat in range(2):
                        with self.subTest(repeat=repeat):
                            self.assertEqual(self.answers(h, statement), [])
                            self.assert_judgment(h, gated, 0.8, confidence, False)
                            # A previous hypothetical gate never accepts the source.
                            self.assertEqual(self.answers(h, statement), [])
                            self.assert_no_main_leakage(h, False)
                    # A late stored gate must wake previously empty judgments.
                    h.add_atoms_no_check(['(: accepted (AcceptSource S) (STV 1 1))'])
                    for repeat in range(2):
                        with self.subTest(late_repeat=repeat):
                            self.assert_judgment(h, statement, 0.8, confidence, True)
                            self.assert_no_main_leakage(h, True)

    def test_observed_gate_does_not_make_assumption_free_consequence_conditional(self):
        for wrapped in (False, True):
            with self.subTest(wrapped=wrapped):
                h = PeTTaChainer()
                consequent = '(And (B a) (C a))'
                if wrapped:
                    consequent = f'(And (Metadata S) {consequent})'
                h.add_atoms_no_check([
                    '(: accepted (AcceptSource S) (STV 1 1))',
                    f'(: rule (Implication (AcceptSource S) {consequent}) (STV 0.8 0.6))',
                ])
                # Warm MAIN's world-only derivation first. A is never needed.
                self.assertTrue(self.answers(h, '(C a)'))
                for repeat in range(2):
                    with self.subTest(repeat=repeat):
                        self.assertEqual(self.answers(h, '(Implication (A a) (C a))'), [])
                        self.assertEqual(self.answers(h, '(A a)'), [])
