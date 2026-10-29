import unittest

from pettachainer import PeTTaChainer
from pettachainer.metta_syntax import parse_term


class BayesPriorTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_evidence_confidence_k(1)
        self.h.set_bayes_prior_count(0.2)

    def tearDown(self):
        self.h.set_evidence_confidence_k(800)
        self.h.set_bayes_prior_count(0.2)

    def weight(self, confidence):
        return float(self.h._call("bayes-prior-weight", [str(confidence)])[0])

    def formula(self, name, args):
        return parse_term(self.h._call(name, [args])[0])

    def read(self, raw, centre='(STV 0.5 1)'):
        return self.h._call('read-likelihoods', [f'{raw} (CTV {centre} {centre}) test-support'])[0]

    def test_variance_sum_weight_and_boundaries(self):
        # At kappa=.2, n_g <= 5 yields zero after the required clamp.
        for confidence in (0, 0.01, 0.7, 5 / 6):
            self.assertAlmostEqual(self.weight(confidence), 0, places=14)
        # n_g=9 => a=1/(1/10 + 1/1.2)-1 = 1/14.
        self.assertAlmostEqual(self.weight(0.9), 1 / 14)
        self.assertAlmostEqual(self.weight(0.99), 47 / 253)
        self.assertAlmostEqual(self.weight(1 - 1e-12), 0.2, places=10)
        self.assertEqual(self.weight(1), 0.2)
        self.h.set_bayes_prior_count(0)
        for confidence in (0, 0.9, 1):
            self.assertEqual(self.weight(confidence), 0)

    def test_weak_centre_limits_weight_to_its_count(self):
        # n_g=1 is weak relative to kappa=10^6: a approaches n_g.
        self.h.set_bayes_prior_count(1e6)
        self.assertAlmostEqual(self.weight(0.5), 1, delta=4e-6)
        self.assertEqual(self.weight(1), 1e6)

    def test_centre_count_is_k_scaled(self):
        self.h.set_evidence_confidence_k(800)
        # Same c=.7 as the zero-weight k=1 case, now n_g=5600/3.
        self.assertAlmostEqual(self.weight(0.7), 5585 / 28033)

    def test_inversion_uses_consequent_centre_confidence(self):
        for centre_c, expected in ((0.2, 0.42), (0.9, 0.40838709677419355)):
            with self.subTest(centre_c=centre_c):
                centre = f'(STV 0.5 {centre_c})'
                read = self.read('(CTV (STV 0.7 0.4) (STV 0.1 0.4))', centre)
                tv = self.formula("CTVInversionFormula", f"(STV 0.3 0.8) {centre} {read}")
                self.assertAlmostEqual(float(tv[1][1]), expected)
                self.assertAlmostEqual(float(tv[2][1]), 0.6 - expected)

    def test_bayes_without_provenance_uses_neutral_centres(self):
        # Branch names alone do not certify disjoint data. Each finite rate
        # reads the structural .5 centre with kappa, not its own pooled count.
        for kappa, expected in ((0.2, 38 / 77), (10, 913 / 3409)):
            self.h.set_bayes_prior_count(kappa)
            for prior_c in (0.1, 0.9):
                tv = self.formula("CTVBayesFormula",
                    f"(STV 0.25 {prior_c}) {self.read('(CTV (STV 0.8 0.4) (STV 0.2 0.5))')}")
                self.assertAlmostEqual(float(tv[1][1]), expected)

    def test_certain_branch_is_not_automatically_a_centre(self):
        self.h.set_bayes_prior_count(1e6)
        tv = self.formula("CTVBayesFormula",
            f"(STV 0.25 0.8) {self.read('(CTV (STV 0.8 0.4) (STV 0.2 1))')}")
        # The certain .2 remains stated; unknown shared provenance means the
        # other branch shrinks towards neutral .5, not towards that .2.
        self.assertAlmostEqual(float(tv[1][1]), 0.4545455537189293, places=12)

    def test_certain_likelihood_and_rate_are_unchanged(self):
        self.assertEqual(self.formula("bayes-shrink", "0.9 1 0.1 0.9"), "0.9")
        self.assertEqual(self.formula("population-prior-tv", "(STV 0.9 1)"),
                         ["STV", "0.9", "1"])
        # The population centre 0.5 is given, so still has weight kappa.
        tv = self.formula("population-prior-tv", "(STV 0 0.5)")
        self.assertAlmostEqual(float(tv[1]), 1 / 12)
        self.assertEqual(float(tv[2]), 0.5)
        for centre_c in (0.2, 0.9, 1):
            centre = f'(STV 0.5 {centre_c})'
            read = self.read('(CTV (STV 0.7 1) (STV 0.1 1))', centre)
            tv = self.formula("CTVInversionFormula", f"(STV 0.3 0.8) {centre} {read}")
            self.assertAlmostEqual(float(tv[1][1]), 0.42)
        tv = self.formula("CTVBayesFormula",
            f"(STV 0.25 0.8) {self.read('(CTV (STV 0.8 1) (STV 0.2 1))')}")
        self.assertAlmostEqual(float(tv[1][1]), 4 / 7)

    def test_zero_evidence_is_neutral_even_with_zero_weight(self):
        self.assertEqual(float(self.h._call("bayes-shrink", ["0.9 0 0.1 0"])[0]), 0.5)
        self.h.set_bayes_prior_count(0)
        self.assertEqual(float(self.h._call("bayes-shrink", ["0.9 0 0.1 1"])[0]), 0.5)
