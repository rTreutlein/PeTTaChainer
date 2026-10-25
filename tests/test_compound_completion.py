"""A completion of a connective's part is conditioned on the connective's own
evidence (#142): a stored compound screens the consequence off from its
parts, so the completion gives the part's posterior given the compound. G and
H have pinned rates 0.6 throughout."""
import unittest

from pettachainer import PeTTaChainer

RULE_TV = '(CTV (STV 0.9 0.9) (STV 0.2 0.9))'


def answers(facts, query='(: $p (G) $tv)'):
    h = PeTTaChainer()
    h.handler.process_metta_string(f'!(set-base-rate {h.kb} (G) (STV 0.6 1.0))')
    h.handler.process_metta_string(f'!(set-base-rate {h.kb} (H) (STV 0.6 1.0))')
    h.add_atoms_no_check(facts)
    return [answer.tv for answer in h.query_many_refs([query], steps=100)[0]]


class TestCompoundCompletion(unittest.TestCase):
    def assertStrength(self, tvs, strength):
        self.assertEqual(len(tvs), 1, tvs)
        self.assertAlmostEqual(tvs[0][1], strength, delta=1e-6)

    def test_negated_conjunction_with_stored_compound(self):
        """A1: P(G | not (G and H)) = 0.24 / 0.64; the rule's prediction of Y
        from the stored compound tells nothing more."""
        self.assertStrength(answers([
            '(: g (And (G) (H)) (STV 0 1))',
            f'(: rn (Implication (Not (And (G) (H))) (Y)) {RULE_TV})']), 0.375)

    def test_negated_conjunction_with_observed_consequence(self):
        """B1: Y observed independently; the stored compound screens Y off
        from G."""
        self.assertStrength(answers([
            '(: g (And (G) (H)) (STV 0 1))',
            '(: y (Y) (STV 1 1))',
            f'(: rn (Implication (Not (And (G) (H))) (Y)) {RULE_TV})']), 0.375)

    def test_negated_disjunction_with_stored_compound(self):
        """B6: P(G | G or H) = 0.6 / 0.84."""
        self.assertStrength(answers([
            '(: g (Or (G) (H)) (STV 1 1))',
            f'(: rn (Implication (Not (Or (G) (H))) (Y)) {RULE_TV})']), 0.6 / 0.84)

    def test_conjunction_with_stored_compound(self):
        """B2: the completion of G reads H apart from the stored compound,
        which it is conditioned on."""
        self.assertStrength(answers([
            '(: g (And (G) (H)) (STV 0 1))',
            '(: y (Y) (STV 1 1))',
            f'(: rn (Implication (And (G) (H)) (Y)) {RULE_TV})']), 0.375)


if __name__ == '__main__':
    unittest.main()
