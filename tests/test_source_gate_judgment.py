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

    # C is the Jeffrey update of the predicted And(B, C), B unknown, from C's
    # uniform prior: the prediction revised with the parts' own estimate
    # (n = 20/7 from their exact variance 7/144, P(K) = .25), C = P* + (1 - P*)(1/3).
    # A certain rule's prediction (n = 800 c/(1 - c) for its c .99983) leaves
    # 1 - 3e-7 (variance 1.17e-13 against s(1 - s) = 2.98e-7: n = 2.55e6,
    # c .99991 under the public clipped-mean variance decoder); at .8 (c .6, or .5455 wrapped in the Metadata conjunction)
    # P* = .7987, C = .8658 (.8656).
    GATED = {False: (0.8657957244652751, 0.04001674008863015), True: (0.8655786350145539, 0.03980772466060817)}

    def test_observed_gate_fresh_and_warm(self):
        for wrapped in (False, True):
            for tv, strength, confidence in (
                ('(STV 1 1)', 0.9999997023811048, 0.9999065647289087),
                ('(STV 0.8 0.6)', *self.GATED[wrapped]),
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
                    strength, confidence = self.GATED[wrapped]
                    for repeat in range(2):
                        with self.subTest(repeat=repeat):
                            self.assertEqual(self.answers(h, statement), [])
                            self.assert_judgment(h, gated, strength, confidence, False)
                            # A previous hypothetical gate never accepts the source.
                            self.assertEqual(self.answers(h, statement), [])
                            self.assert_no_main_leakage(h, False)
                    # A late stored gate must wake previously empty judgments.
                    h.add_atoms_no_check(['(: accepted (AcceptSource S) (STV 1 1))'])
                    for repeat in range(2):
                        with self.subTest(late_repeat=repeat):
                            self.assert_judgment(h, statement, strength, confidence, True)
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
