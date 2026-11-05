"""Members of one population share its rate in the event graph (issue #168).

References are independent: a member's rate is one latent theta, integrated once
over its Beta law (rising factorials, or Gauss-Jacobi quadrature for the exact
variance target). The count law gives each law: n = k c/(1-c), Beta(ns+1, n(1-s)+1).
"""
import itertools
import unittest
from fractions import Fraction as F

import numpy as np

from pettachainer import PeTTaChainer
from tests.tv_calibration_oracles import gauss_jacobi

K = 2
CARRIER = '(: priorCarrier (Implication (P $x) (Aux $x)) (CTV (STV 0.5 1) (STV 0.5 1)))'
MEMBERS = [f'(P m{i})' for i in range(10)]


def moment(a, b, t, f=0):
    """E[theta^t (1-theta)^f] under Beta(a, b)."""
    out = F(1)
    for i in range(t):
        out *= F(a + i, 1) / (a + b + i)
    for i in range(f):
        out *= F(b + i, 1) / (a + b + t + i)
    return out


def confidence(s, v):
    n = s * (1 - s) / v - 1
    return n / (n + K)


def claimed_variance(s, c):
    """The variance a published STV claims at k = 2."""
    return s * (1 - s) / (K * c / (1 - c) + 1)


def chainer(atoms, base_rate=None, kappa=None):
    h = PeTTaChainer()
    h.set_evidence_confidence_k(K)
    if kappa is not None:
        h.set_bayes_prior_count(kappa)
    if base_rate:
        h.handler.process_metta_string(f'!(set-base-rate {h.kb} (P $x) {base_rate})')
    h.add_atoms_no_check([CARRIER] + atoms)
    return h


def report(goal, pos, neg):
    return [f'(: obsRule (Implication {goal} (Report now)) (CTV (STV {pos} 1) (STV {neg} 1)))',
            '(: report (Report now) (STV 1 1))']


def answers(h, goals, steps=1000):
    return [[r.tv for r in rows] for rows in h.query_many_refs([f'(: $p {g} $tv)' for g in goals], steps=steps)]


class SharedPopulationRateTests(unittest.TestCase):
    def test_many_uses_keep_their_powers(self):
        # Pinned Beta(2,2) shared by n members: E[theta^n] = 6/((n+2)(n+3)); Or by symmetry.
        for n, head, informative in itertools.product((3, 6, 10), ('And', 'Or'), (False, True)):
            with self.subTest(n=n, head=head, informative=informative):
                goal = f'({head} ' + ' '.join(MEMBERS[:n]) + ')'
                pos, neg = (F(4, 5), F(1, 10)) if informative else (F(1, 2), F(1, 2))
                h = chainer(report(goal, float(pos), float(neg)), base_rate='(STV 0.5 0.5)')
                [[whole], [part]] = answers(h, [goal, MEMBERS[0]])
                p = moment(2, 2, n) if head == 'And' else 1 - moment(2, 2, 0, n)
                z = pos * p + neg * (1 - p)
                self.assertAlmostEqual(whole[1], float(pos * p / z), delta=1e-12)
                # A member: And holds only with it; Or holds with it whatever the others.
                hit = pos * moment(2, 2, n) + neg * (moment(2, 2, 1) - moment(2, 2, n)) if head == 'And' \
                    else pos * moment(2, 2, 1)
                self.assertAlmostEqual(part[1], float(hit / z), delta=1e-12)
                self.assertNoOverclaim(whole, n, head, pos, neg)
                if not informative:
                    v = moment(2, 2, 2 * n) - moment(2, 2, n) ** 2
                    self.assertAlmostEqual(whole[2], float(confidence(p, v)), delta=1e-9)

    def assertNoOverclaim(self, tv, n, head, pos, neg):
        """The claimed variance is at least the exact E[N^2/Z]/E[Z] - s^2 over theta ~ Beta(2,2)."""
        x, w = gauss_jacobi(2.0, 2.0, 80)
        p = x ** n if head == 'And' else 1 - (1 - x) ** n
        N, Z = float(pos) * p, float(pos) * p + float(neg) * (1 - p)
        s = (w @ N) / (w @ Z)
        exact = (w @ (N * N / Z)) / (w @ Z) - s * s
        self.assertGreaterEqual(claimed_variance(tv[1], tv[2]), exact * (1 - 1e-9))

    def test_learned_rate_is_the_population_centre_whatever_kappa(self):
        # Three positive, one negative training member at k=2: n=4, the centre g ~ Beta(4,2).
        # Two members share g: E[g^2] = 10/21, V = E[g^4] - E[g^2]^2. kappa is the
        # ordinary reader's shrink; the graph reads the centre itself.
        training = ['(: t1 (P t1) (STV 1 1))', '(: t2 (P t2) (STV 1 1))', '(: t3 (P t3) (STV 1 1))',
                    '(: t0 (P t0) (STV 0 1))']
        goal = '(And (P a) (P b))'
        s, v = moment(4, 2, 2), moment(4, 2, 4) - moment(4, 2, 2) ** 2
        for kappa in (None, 5.0):
            with self.subTest(kappa=kappa):
                [[tv]] = answers(chainer(training + report(goal, 0.5, 0.5), kappa=kappa), [goal])
                self.assertAlmostEqual(tv[1], float(s), delta=1e-12)
                self.assertAlmostEqual(tv[2], float(confidence(s, v)), delta=1e-9)

    def test_refined_rule_uses_share_its_branch_rate(self):
        # Ten applications of one refined rule with certain antecedents: one branch-1 rate.
        # Training (one success, one failure) at k=2 refines it to Beta(3,3).
        for n, informative in itertools.product((6, 10), (False, True)):
            with self.subTest(n=n, informative=informative):
                members = [f'(P a{i})' for i in range(n)]
                goal = '(And ' + ' '.join(members) + ')'
                pos, neg = (F(4, 5), F(1, 10)) if informative else (F(1, 2), F(1, 2))
                h = PeTTaChainer()
                h.set_evidence_confidence_k(K)
                h.set_rule_refinement(True)
                h.add_atoms_no_check(
                    ['(: shared (Implication (U $x) (P $x)) (CTV (STV 0.5 0.5) (STV 0.5 0.5)))',
                     '(: ut1 (U train1) (STV 1 1))', '(: ut0 (U train0) (STV 1 1))',
                     '(: pt1 (P train1) (STV 1 1))', '(: pt0 (P train0) (STV 0 1))']
                    + [f'(: u{i} (U a{i}) (STV 1 1))' for i in range(n)] + report(goal, float(pos), float(neg)))
                [[tv]] = answers(h, [goal])
                p = moment(3, 3, n)
                self.assertAlmostEqual(tv[1], float(pos * p / (pos * p + neg * (1 - p))), delta=1e-12)
                if not informative:
                    self.assertAlmostEqual(tv[2], float(confidence(p, moment(3, 3, 2 * n) - p * p)), delta=1e-9)

    def test_revised_certain_sources_are_billed_as_their_law(self):
        # Two certain sources revise to the point .6: a varying bit, not a fixed one. Each
        # certain report fixes its own bit, so twelve pairs enumerate twelve bits:
        # P(A_i | B_i) = .54/.58 = 27/29, independent across pairs.
        n = 12
        roots = [f'(A{i} now)' for i in range(n)]
        h = PeTTaChainer()
        h.set_evidence_confidence_k(K)
        h.add_atoms_no_check([a for i, r in enumerate(roots) for a in (
            f'(: one{i} {r} (STV 1 1))', f'(: fraction{i} {r} (STV 0.2 1))',
            f'(: rule{i} (Implication {r} (B{i} now)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            f'(: report{i} (B{i} now) (STV 1 1))')])
        [[tv]] = answers(h, ['(And ' + ' '.join(roots) + ')'])
        self.assertAlmostEqual(tv[1], float(F(27, 29) ** n), delta=1e-12)

    def test_independent_components_integrate_apart(self):
        # Twelve independent 16-root conjunctions, each with its own certain .9/.1 channel:
        # one bit per component, so the moments multiply instead of expanding 3^12 products.
        n, width = 12, 16
        groups, atoms = [], []
        for i in range(n):
            roots = [f'(P{i}_{j} now)' for j in range(width)]
            groups.append('(And ' + ' '.join(roots) + ')')
            atoms += [f'(: prior{i}_{j} {r} (STV 0.5 0.5))' for j, r in enumerate(roots)]
            atoms += [f'(: channel{i} (Implication {groups[-1]} (R{i} now)) (CTV (STV 0.9 1) (STV 0.1 1)))',
                      f'(: obs{i} (R{i} now) (STV 1 1))']
        h = PeTTaChainer()
        h.add_atoms_no_check(atoms)
        [[tv]] = answers(h, ['(And ' + ' '.join(groups) + ')'], steps=100)
        prior = F(1, 2) ** width
        self.assertAlmostEqual(tv[1] / float((9 * prior / (1 + 8 * prior)) ** n), 1, delta=1e-9)

    def test_equal_shapes_and_repeated_events_do_not_alias(self):
        # Two populations with equal Beta(2,2) laws stay independent: s=1/4, V=11/400.
        h = PeTTaChainer()
        h.set_evidence_confidence_k(K)
        for pattern in ('(P $x)', '(R $x)'):
            h.handler.process_metta_string(f'!(set-base-rate {h.kb} {pattern} (STV 0.5 0.5))')
        h.add_atoms_no_check([CARRIER, '(: rCarrier (Implication (R $x) (RAux $x)) (CTV (STV 0.5 1) (STV 0.5 1)))']
                             + report('(And (P a) (R b))', 0.5, 0.5))
        [[tv]] = answers(h, ['(And (P a) (R b))'])
        self.assertAlmostEqual(tv[1], 0.25, delta=1e-12)
        self.assertAlmostEqual(tv[2], float(confidence(F(1, 4), F(11, 400))), delta=1e-9)
        # One event read twice is one bit: s=1/2, V=1/20.
        h = chainer(report('(And (P a) (P a))', 0.5, 0.5), base_rate='(STV 0.5 0.5)')
        [[tv]] = answers(h, ['(And (P a) (P a))'])
        self.assertAlmostEqual(tv[1], 0.5, delta=1e-12)
        self.assertAlmostEqual(tv[2], float(confidence(F(1, 2), F(1, 20))), delta=1e-9)

    def test_batch_equals_sequential_and_budget_zero_does_no_graph_work(self):
        goal = '(And (P a) (P b) (P c))'
        goals = [goal, '(P a)', '(P b)']
        atoms = report(goal, 0.8, 0.1)
        cold = chainer(atoms, base_rate='(STV 0.5 0.5)')
        cold.set_query_metrics(True)
        answers(cold, goals, steps=0)
        self.assertEqual(cold.last_query_metrics()['graph_evaluations'], 0)
        batch = answers(chainer(atoms, base_rate='(STV 0.5 0.5)'), goals)
        h = chainer(atoms, base_rate='(STV 0.5 0.5)')
        self.assertEqual([answers(h, [g])[0] for g in goals], batch)
        p = moment(2, 2, 3)
        self.assertAlmostEqual(batch[0][0][1], float(F(4, 5) * p / (F(4, 5) * p + F(1, 10) * (1 - p))), delta=1e-12)


if __name__ == '__main__':
    unittest.main()
