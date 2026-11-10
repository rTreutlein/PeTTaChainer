"""Derived conjunctions must not recycle a witness or starve conditioning (#180)."""
import unittest

from pettachainer import PeTTaChainer


CTV = '(CTV (STV 1 0.99) (STV 0 0.001))'
RULES = [f'(: {name} (Implication {antecedent} {consequent}) {CTV})' for name, antecedent, consequent in (
    ('g_son', '(Kin son $x $y)', '(Kin child $x $y)'),
    ('g_daughter', '(Kin daughter $x $y)', '(Kin child $x $y)'),
    ('conv', '(Kin child $x $y)', '(Kin parent $y $x)'),
    ('male_son', '(Kin son $x $y)', '(Member $x male)'),
    ('sib', '(And (Kin child $x $y) (Kin parent $y $z))', '(Kin sibling $x $z)'),
    ('au', '(And (Kin sibling $x $y) (Kin parent $y $z))', '(Kin aunt_or_uncle $x $z)'),
    ('uncle', '(And (Kin aunt_or_uncle $x $y) (Member $x male))', '(Kin uncle $x $y)'),
)]
FACTS = [f'(: s{i} (Kin {kind} {child} {parent}) (STV 1 0.99))'
         for i, kind, child, parent in ((1, 'son', 'elliott', 'stanley'),
                                       (2, 'daughter', 'valerie', 'stanley'),
                                       (3, 'daughter', 'annie', 'valerie'))]
CYCLE = [f'(: brother_special (Implication (And (Kin sibling $x $y) (Member $x male)) '
         f'(Kin brother $x $y)) {CTV})',
         f'(: brother_general (Implication (Kin brother $x $y) (Kin sibling $x $y)) {CTV})']
AU = '(: $p (Kin aunt_or_uncle elliott annie) $tv)'
CONJUNCTION = '(: $p (And (Kin aunt_or_uncle elliott annie) (Member elliott male)) $tv)'
UNCLE = '(: $p (Kin uncle elliott annie) $tv)'


def engine(atoms=FACTS + RULES):
    h = PeTTaChainer()
    h.add_atoms_no_check(atoms)
    h.set_query_metrics(True)
    return h


class DerivedKinshipTests(unittest.TestCase):
    def test_cases_three_to_five_keep_the_premise_confidence(self):
        # Separate engines, as in the report: a premise query must not warm
        # the engine used for the conclusion. The rule costs about .01.
        for case, atoms in ((3, FACTS + ['(: m1 (Member elliott male) (STV 1 0.99))'] + RULES),
                            (4, FACTS + RULES), (5, FACTS + RULES + CYCLE)):
            with self.subTest(case=case):
                conjunction = engine(atoms).query_many_refs([CONJUNCTION], steps=2000)[0]
                h = engine(atoms)
                uncle = h.query_many_refs([UNCLE], steps=2000)[0]
                self.assertEqual(len(conjunction), 1)
                self.assertEqual(len(uncle), 1)
                self.assertGreater(uncle[0].tv[1], .99)
                self.assertGreater(uncle[0].tv[2], .85)
                self.assertAlmostEqual(uncle[0].tv[2], conjunction[0].tv[2], delta=.02)
                if case == 5:
                    self.assertGreater(h.last_query_metrics()['conditioned_evaluations'], 12)
                    # Two formulas cost one unit; the fallback ceiling is 256.
                    self.assertLessEqual(h.last_query_metrics()['representative_reads'], 512)

    def test_case_six_matches_case_four_and_requeries(self):
        cold = engine().query_many_refs([UNCLE], steps=2000)[0][0].tv
        h = engine()
        au = h.query_many_refs([AU], steps=2000)[0][0]
        self.assertAlmostEqual(au.tv[2], .9082473136598535, delta=1e-10)
        for repeat in range(3):
            with self.subTest(repeat=repeat):
                warm = h.query_many_refs([UNCLE], steps=2000)[0][0].tv
                self.assertAlmostEqual(warm[1], cold[1], delta=1e-12)
                self.assertAlmostEqual(warm[2], cold[2], delta=1e-12)

    def test_generated_witness_requires_an_independent_observation(self):
        for independent in (False, True):
            with self.subTest(independent=independent):
                h = engine(['(: s (Son elliott stanley) (STV 1 0.99))',
                            f'(: r (Implication (Son $x $y) (Male $x)) {CTV})'] +
                           (['(: m (Male elliott) (STV 1 0.99))'] if independent else []))
                result = h.query_many_refs(
                    ['(: $p (Son elliott (exists r 0 (elliott))) $tv)'], steps=2000)[0]
                self.assertEqual(len(result), 1)
                proof = h.expand_proof(result[0].proof)
                if independent:
                    self.assertIn('inverted r', proof)
                    self.assertIn(' m)', proof)
                    self.assertNotIn('(by r s)', proof)
                else:
                    self.assertIn('population-prior', proof)
                    self.assertNotIn('inverted', proof)
