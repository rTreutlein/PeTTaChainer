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
    def check_uncle_keeps_the_premise_confidence(self, atoms):
        # Separate engines, as in the report: a premise query must not warm
        # the engine used for the conclusion. The rule costs about .01.
        conjunction = engine(atoms).query_many_refs([CONJUNCTION], steps=2000)[0]
        uncle = engine(atoms).query_many_refs([UNCLE], steps=2000)[0]
        self.assertEqual(len(conjunction), 1)
        self.assertEqual(len(uncle), 1)
        self.assertGreater(uncle[0].tv[1], .99)
        self.assertGreater(uncle[0].tv[2], .85)
        self.assertAlmostEqual(uncle[0].tv[2], conjunction[0].tv[2], delta=.02)

    def test_cases_three_and_four_keep_the_premise_confidence(self):
        for case, atoms in ((3, FACTS + ['(: m1 (Member elliott male) (STV 1 0.99))'] + RULES),
                            (4, FACTS + RULES)):
            with self.subTest(case=case):
                self.check_uncle_keeps_the_premise_confidence(atoms)

    @unittest.expectedFailure  # #180 case 5: the roots' waiting-answer reconstruction spends the allowance before conditioning, so both roots answer []
    def test_case_five_answers_beside_an_unrelated_cycle(self):
        self.check_uncle_keeps_the_premise_confidence(FACTS + RULES + CYCLE)

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


# The second rule's inverse loses $c. LivesIn holds only the first rule's
# prediction, which is independent evidence for the second rule's witness,
# with the city literal or a retained variable.
def lost_part(city):
    return ['(: v (Visits alice eiffel) (STV 0.9 0.9))',
            '(: l (Located eiffel paris) (STV 0.9 0.9))',
            f'(: r1 (Implication (And (Visits $x $l) (Located $l {city})) (LivesIn $x {city})) {CTV})',
            f'(: r2 (Implication (And (Works $x $c) (Located $c {city})) (LivesIn $x {city})) {CTV})']


class InverseWitnessTests(unittest.TestCase):
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

    def test_another_rules_prediction_supports_the_inverse(self):
        target = '(And (Works alice $w) (Located $w paris))'
        for city in ('paris', '$city'):
            for mode in ('cold', 'forward', 'assuming'):
                with self.subTest(city=city, mode=mode):
                    h = engine(lost_part(city))
                    if mode == 'forward':
                        h.forward_chain(h.all_facts(), steps=2000)
                    query = f'(Assuming (Extra yes) {target})' if mode == 'assuming' else target
                    result = h.query_many_refs([f'(: $p {query} $tv)'], steps=2000)[0]
                    self.assertEqual(len(result), 1)
                    proof = h.expand_proof(result[0].proof)
                    self.assertIn('inverted r2', proof)
                    self.assertIn('(by r1 ', proof)
                    # Master's value, before the witness exclusion.
                    self.assertAlmostEqual(result[0].tv[1], .7364173867544236, delta=1e-9)
                    self.assertAlmostEqual(result[0].tv[2], .007249011528317821, delta=1e-9)

    def test_inverse_retaining_no_variable_rejects_its_own_prediction(self):
        atoms = ['(: s (Son elliott stanley) (STV 0.9 0.9))',
                 f'(: r (Implication (Son elliott $y) (Male elliott)) {CTV})']
        for steps in (2000, 20000):
            with self.subTest(steps=steps):
                h = engine(atoms)
                answer, = h.query_many_refs(['(: $p (Son elliott (exists r 0 ())) $tv)'], steps=steps)[0]
                self.assertNotIn('inverted', h.expand_proof(answer.proof))
        h = engine(atoms)
        out = h.forward_chain(h.all_facts(), steps=2000)
        self.assertFalse(any('(exists ' in f for f in out))

    def test_variable_headed_forward_inverse_rejects_its_own_prediction(self):
        # The forward row's context is open while (P alice bob) is in MAIN.
        # (Q P alice) holds only r's prediction, so r's inverse has nothing to
        # invert.
        h = engine(['(: s (P alice bob) (STV 0.9 0.9))',
                    f'(: r (Implication ($pred $x $y) (Q $pred $x)) {CTV})'])
        out = h.forward_chain(h.all_facts(), steps=2000)
        self.assertFalse(any(f.startswith('((P ') for f in out))


if __name__ == '__main__':
    unittest.main()
