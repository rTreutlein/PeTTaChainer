"""A completion of a connective's part is conditioned on the connective's own
evidence e_K (#142): K = (op G H) screens the consequence off from its parts,
so the completion gives the part's posterior given e_K and the consequence.
G and H have pinned rates 0.6 unless a case says otherwise; the exact values
are enumerations over G and H, with e_K read as K's belief (Jeffrey)."""
import unittest

from pettachainer import PeTTaChainer

RULE_TV = '(CTV (STV 0.9 0.9) (STV 0.2 0.9))'
RULE = '(CTV (STV 0.9 1) (STV 0.2 1))'
AND, OR = '(And (G) (H))', '(Or (G) (H))'


def answers(facts, before=(), rates=True, query='(: $p (G) $tv)'):
    h = PeTTaChainer()
    if rates:
        h.handler.process_metta_string(f'!(set-base-rate {h.kb} (G) (STV 0.6 1.0))')
        h.handler.process_metta_string(f'!(set-base-rate {h.kb} (H) (STV 0.6 1.0))')
    h.add_atoms_no_check(facts)
    for earlier in before:
        h.query_many_refs([earlier], steps=100)
    return [answer.tv for answer in h.query_many_refs([query], steps=100)[0]]


def rule(antecedent, consequent='(Y)', tv=RULE, name='r'):
    return f'(: {name} (Implication {antecedent} {consequent}) {tv})'


class TestCompoundCompletion(unittest.TestCase):
    def assertStrength(self, tvs, strength, delta=1e-6):
        self.assertEqual(len(tvs), 1, tvs)
        self.assertAlmostEqual(tvs[0][1], strength, delta=delta)

    def test_hard_compound(self):
        """A1, B1, B6, B2: a certain K decides the part's posterior given K,
        P(G | not (G and H)) = 0.24 / 0.64, P(G | G or H) = 0.6 / 0.84."""
        for facts, exact in (
                (['(: g (And (G) (H)) (STV 0 1))', rule(f'(Not {AND})', tv=RULE_TV)], 0.375),
                (['(: g (And (G) (H)) (STV 0 1))', '(: y (Y) (STV 1 1))', rule(f'(Not {AND})', tv=RULE_TV)], 0.375),
                (['(: g (Or (G) (H)) (STV 1 1))', rule(f'(Not {OR})', tv=RULE_TV)], 0.6 / 0.84),
                (['(: g (And (G) (H)) (STV 0 1))', '(: y (Y) (STV 1 1))', rule(AND, tv=RULE_TV)], 0.375)):
            with self.subTest(facts=facts):
                self.assertStrength(answers(facts), exact)

    def test_compound_deciding_the_part_adds_no_view(self):
        """A4, A6, A8: K true decides G. The completion adds no view, so
        G keeps the projection's certainty and confidence."""
        for facts, rates in (
                (['(: g (And (G) (H)) (STV 1 1))', rule(f'(Not {AND})', tv=RULE_TV)], True),
                (['(: g (And (G) (H)) (STV 1 1))', rule(f'(Not {AND})', tv=RULE_TV)], False),
                (['(: g (And (G) (H)) (STV 1 1))', rule(AND, tv=RULE_TV), '(: y (Y) (STV 0 1))'], True)):
            with self.subTest(facts=facts, rates=rates):
                tvs = answers(facts, rates=rates)
                self.assertStrength(tvs, 1.0, delta=0)
                self.assertGreater(tvs[0][2], 0.999)

    def test_soft_compound(self):
        """A stored (STV s 1) compound is K's belief, set over the prior its
        parts give it. C2, C2n, C2b, C3, C3n, C3b, C4: both routes, negated
        (De Morgan) ones included, and SIB with a sibling of its own."""
        for k, consequent, antecedent, exact in (
                ('(: k (And (G) (H)) (STV 0.7 1))', '(STV 1 1)', AND, 0.945652),
                ('(: k (And (G) (H)) (STV 0.7 1))', '(STV 1 1)', f'(Not {AND})', 0.588415),
                ('(: k (And (G) (H)) (STV 0.7 1))', '(STV 0 1)', AND, 0.516129),
                ('(: k (Or (G) (H)) (STV 0.7 1))', '(STV 1 1)', OR, 0.652174),
                ('(: k (Or (G) (H)) (STV 0.7 1))', '(STV 1 1)', f'(Not {OR})', 0.243902),
                ('(: k (Or (G) (H)) (STV 0.3 1))', '(STV 0 1)', OR, 0.036320),
                ('(: k (And (G) (H)) (STV 0.3 1))', '(STV 1 1)', f'(Not {AND})', 0.429348)):
            with self.subTest(k=k, consequent=consequent, antecedent=antecedent):
                self.assertStrength(answers([k, f'(: y (Y) {consequent})', rule(antecedent)]), exact)
        self.assertStrength(answers(['(: hh (H) (STV 0.8 1))', '(: k (And (G) (H)) (STV 0.7 1))',
                                     '(: y (Y) (STV 1 1))', rule(AND)]), 0.933110)

    def test_completions_sharing_compound_evidence(self):
        """C6: two consequences of a certain K. C6S: of an uncertain K, the
        two completions combine over the one prior P(G | e_K). Each reads H
        at its prior as if the other consequence did not move it, the
        approximation master makes without e_K (0.9029 against an exact
        0.9194), so C6S gives 0.97695 against an exact 0.97845."""
        two = [rule(AND), rule(AND, '(Z)', '(CTV (STV 0.8 1) (STV 0.3 1))', 'r2'),
               '(: y (Y) (STV 1 1))', '(: z (Z) (STV 1 1))']
        self.assertStrength(answers(['(: k (And (G) (H)) (STV 0 1))'] + two), 0.375)
        self.assertStrength(answers(['(: k (And (G) (H)) (STV 0.7 1))'] + two), 0.978448, delta=0.002)

    def test_derived_compound_evidence_reads_the_same_in_any_order(self):
        """C5Y, W6A, hist: K's evidence from a rule over a derived premise
        reaches the completion whatever was queried before (R7)."""
        derived = ['(: w (W) (STV 1 1))', '(: r3 (Implication (W) (X)) (STV 1 1))',
                   '(: rx (Implication (X) (And (G) (H))) (STV 0.1 1))', '(: y (Y) (STV 1 1))', rule(AND)]
        for before in ((), ('(: $q (X) $tv)',), ('(: $q (W) $tv)',), ('(: $q (X) $tv)', f'(: $q {AND} $tv)')):
            with self.subTest(before=before):
                self.assertStrength(answers(derived, before), 0.583333)
        self.assertStrength(answers(['(: x (X) (STV 1 1))', '(: y (Y) (STV 1 1))',
                                     '(: rx (Implication (X) (And (G) (H))) (STV 0.1 1))', rule(AND)]), 0.583333)
        self.assertStrength(answers(['(: w (W) (STV 1 1))', '(: rw (Implication (W) (X)) (STV 0.5 1))',
                                     '(: y (Y) (STV 1 1))',
                                     '(: rx (Implication (X) (And (G) (H))) (CTV (STV 0.1 1) (STV 0.5 1)))',
                                     rule(AND)]), 0.786585)


if __name__ == '__main__':
    unittest.main()
