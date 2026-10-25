"""A completion of a connective's part never reads the connective's own
evidence as an observation (#142). G and H have pinned rates 0.6 throughout.

Completing a part when the connective's key has evidence of its own needs that
evidence as an observation (runtime_design_assumptions.md, "Known limits").
Until then such a part gets no confident value."""
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
    def assertNoConfidentValue(self, tvs):
        for tv in tvs:
            self.assertLess(tv[2], 1e-6, tv)

    def test_negated_conjunction_with_stored_compound(self):
        """A1: exact P(G | not (G and H)) = 0.375; the rule's own prediction
        of Y from the stored compound is no observation."""
        self.assertNoConfidentValue(answers([
            '(: g (And (G) (H)) (STV 0 1))',
            f'(: rn (Implication (Not (And (G) (H))) (Y)) {RULE_TV})']))

    def test_negated_conjunction_with_observed_consequence(self):
        """B1: Y observed independently; exact 0.375, as the stored compound
        screens Y off from G."""
        self.assertNoConfidentValue(answers([
            '(: g (And (G) (H)) (STV 0 1))',
            '(: y (Y) (STV 1 1))',
            f'(: rn (Implication (Not (And (G) (H))) (Y)) {RULE_TV})']))

    def test_negated_disjunction_with_stored_compound(self):
        """B6: exact P(G | G or H) = 0.6 / 0.84."""
        self.assertNoConfidentValue(answers([
            '(: g (Or (G) (H)) (STV 1 1))',
            f'(: rn (Implication (Not (Or (G) (H))) (Y)) {RULE_TV})']))

    @unittest.expectedFailure
    def test_conjunction_with_stored_compound(self):
        """B2, also on master: the completion of G reads H's projection of the
        stored compound and gives G its prior 0.6 instead of the exact 0.375."""
        tvs = answers([
            '(: g (And (G) (H)) (STV 0 1))',
            '(: y (Y) (STV 1 1))',
            f'(: rn (Implication (And (G) (H)) (Y)) {RULE_TV})'])
        self.assertEqual(len(tvs), 1)
        self.assertAlmostEqual(tvs[0][1], 0.375, delta=1e-6)


if __name__ == '__main__':
    unittest.main()
