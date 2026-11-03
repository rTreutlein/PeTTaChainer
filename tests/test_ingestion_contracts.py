"""wmtm ingestion and disjoint-chain contracts, using the current rule syntax."""
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer


RULES = [
    '(: mem_inh (Implication (And (Member $x $a) (Inheritance $a $b)) '
    '(Member $x $b)) (STV 1 0.99))',
    '(: inh_trans (Implication (And (Inheritance $a $b) (Inheritance $b $c)) '
    '(Inheritance $a $c)) (STV 1 0.99))',
    '(: imp_trans (Implication (And (Implies $a $b) (Implies $b $c)) '
    '(Implies $a $c)) (STV 1 0.99))',
]


class TestIngestionContracts(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()

    def test_legacy_wrappers_reject_at_every_ingress_without_publication(self):
        for statement in (
            '(Implication (Premises (P $x)) (Conclusions (Q $x) (R $x)))',
            '(Implication (P $x) (Conclusions (Q $x)))',
            '(ForAll ($x) (Implication (And (P $x) (Premises (R $x))) (Q $x)))',
            '(Implication (Conclusions (P $x)) (Q $x))',
        ):
            source = f'(: rejected {statement} (STV 1 0.9))'
            for path in ('add_atom', 'add_atoms_no_check', 'compileadd', 'add-to-kb'):
                with self.subTest(statement=statement, path=path):
                    with self.assertRaisesRegex(janus.PrologError, 'Domain error:.*rule_syntax'):
                        if path == 'add_atom':
                            self.h.add_atom(source)
                        elif path == 'add_atoms_no_check':
                            self.h.add_atoms_no_check([source])
                        elif path == 'compileadd':
                            self.h._call(path, [f'{self.h.kb} {source}'])
                        else:
                            self.h._call(path, [f'({statement} ({self.h.kb} MAIN Nil) rejected (STV 1 0.9))'])
                    self.assertNotIn(source, self.h._added_atoms)
        rows = janus.query_once(
            "aggregate_all(count,'&kb'(_, [Kb,'MAIN','Nil'], rejected, _),Facts),"
            "aggregate_all(count,(ccls_index([_,[Kb|_],_Proof,_],_,_),"
            "sub_term(_P,_Proof),_P==rejected),Rules)", {'Kb': self.h.kb})
        self.assertEqual((rows['Facts'], rows['Rules']), (0, 0))

    def test_tv_domains_at_every_ingress(self):
        for value in ('(STV -0.1 0.9)', '(STV 1.1 0.9)', '(STV 0.5 -0.1)',
                      '(STV 1 1.5)', '(STV (/ 3 2) 0.9)',
                      '(CTV (STV 0.8 0.9) (STV 0.1 1.5))',
                      '(CTV (STV -0.1 0.9) (STV 0.1 0.9))'):
            statement = '(Implication (P $x) (Q $x))' if value.startswith('(CTV') else '(P a)'
            source = f'(: rejected {statement} {value})'
            for path in ('add_atom', 'add_atoms_no_check', 'compileadd', 'add-to-kb'):
                with self.subTest(value=value, path=path):
                    with self.assertRaisesRegex(janus.PrologError, 'Domain error:.*truth_value'):
                        if path == 'add_atom':
                            self.h.add_atom(source)
                        elif path == 'add_atoms_no_check':
                            self.h.add_atoms_no_check([source])
                        elif path == 'compileadd':
                            self.h._call(path, [f'{self.h.kb} {source}'])
                        else:
                            self.h._call(path, [f'({statement} ({self.h.kb} MAIN Nil) rejected {value})'])
                    self.assertNotIn(source, self.h._added_atoms)
        self.assertEqual(self.h.query('(: $p (P a) $tv)', steps=0, timeout_sec=0), [])

    def test_explicit_tv_kinds_are_checked_after_canonicalization(self):
        for statement, value in (('(P a)', '(PTV 1 1.5)'),
                                 ('(Implication (P $x) (Q $x))', '(FTV -0.1 0.9)')):
            for add in (self.h.add_atom, lambda a: self.h.add_atoms_no_check([a]),
                        lambda a: self.h._call('compileadd', [f'{self.h.kb} {a}'])):
                with self.subTest(value=value), self.assertRaisesRegex(
                        janus.PrologError, 'Domain error:.*truth_value'):
                    add(f'(: rejected {statement} {value})')

    def test_raw_rules_check_fact_premises_and_conclusions(self):
        scope = f'({self.h.kb} MAIN Nil)'
        for premise, conclusion, error in (
            (f'((Premises (P a)) {scope} p (STV 1 0.9))',
             f'((Q a) {scope} q (STV 1 0.9))', 'rule_syntax'),
            (f'((P a) {scope} p (STV 1 1.5))',
             f'((Q a) {scope} q (STV 1 0.9))', 'truth_value'),
            (f'((P a) {scope} p (STV 1 0.9))',
             f'((Q a) {scope} q (STV 1 1.5))', 'truth_value'),
        ):
            with self.subTest(error=error), self.assertRaisesRegex(janus.PrologError, error):
                self.h._call('add-to-kb', [f'(rules (({premise}) |- {conclusion}))'])
        # An unbound computed branch/field must stay unbound during validation.
        self.assertTrue(janus.query_once(
            "ingestion_tv(['CTV',_Branch,['STV',_S,1]]),var(_Branch),var(_S)")['truth'])

    def test_valid_boundaries_computed_rule_tvs_and_quoted_data(self):
        for i, value in enumerate(('(STV 0 0)', '(STV 1 1)', '(PTV 0 1)', '(STV 0.5 0.999)')):
            self.assertTrue(self.h.add_atom(f'(: f{i} (Value item{i}) {value})'))
        for source in (
            '(: r (Implication (And (P $x) (Compute id (1) -> $s)) (Q $x)) '
            '(CTV (STV $s 1) (STV 0 1)))',
            '(: multi (Implication (P $x) (And (Q $x) (R $x))) (FTV 1 1))',
            '(: quoted (ClaimContent finding (Implication (Premises (P $x)) '
            '(Conclusions (Q $x)))) (STV 1 0.9))',
            '(: custom (Implication (Unregistered $x) (Novel $x)) (STV 1 0.9))',
        ):
            self.assertTrue(self.h.add_atom(source))

    def test_distribution_values_remain_data_not_epistemic_tvs(self):
        for value in ('(PointMass 160)', '(ParticleFromPairs ((160 1) (170 2)))',
                      '(ParticleFromNormal 160 2)', '(PointMass (STV -1 2))'):
            with self.subTest(value=value):
                self.assertTrue(self.h.add_atom(f'(: measure (Measure {value}) (STV 1 0.9))'))
        # The Python syntax checker also lists these historical TV forms, but
        # the pinned compiler's TV union rejects distributions as annotations.
        for value in ('(NatDist ((1 1)))', '(FloatDist ((1.0 1)))',
                      '(PointMass 160)', '(ParticleDist 1 1)',
                      '(ParticleFromNormal 160 2)', '(ParticleFromPairs ((160 1) (170 2)))'):
            with self.subTest(tv=value), self.assertRaisesRegex(janus.PrologError, 'Type mismatch'):
                self.h.add_atom(f'(: unsupported (Measure a) {value})')

    def test_canary_with_inheritance_rules_and_negative_control(self):
        self.h.add_atoms_no_check(RULES + [
            '(: cf (Member grace pilot) (STV 1 0.99))',
            '(: cg (Inheritance pilot person) (STV 1 0.99))',
        ])
        for goal, expected in (('(Member grace person)', True), ('(Member grace robot)', False)):
            answers = self.h.query(f'(: $p {goal} $tv)', steps=30, timeout_sec=0)
            # A population prior is an unknown estimate, not a supporting proof.
            proofs = [a for a in answers if 'population-prior' not in a]
            self.assertEqual(bool(proofs), expected, answers)
            if expected:
                self.assertTrue(any('cf' in a and 'cg' in a for a in proofs), proofs)

    def test_small_disjoint_chain_work_grows_linearly(self):
        work = []
        for size in (4, 8):
            h = PeTTaChainer()
            h.add_atoms_no_check(RULES)
            start = janus.query_once('statistics(inferences,N)')['N']
            for k in range(size):
                if k % 2 == 0:
                    facts = [f'(Member x{k} a{k})', f'(Inheritance a{k} b{k})', f'(Inheritance b{k} c{k})']
                else:
                    facts = [f'(Implies p{k} q{k})', f'(Implies q{k} r{k})', f'(Implies r{k} s{k})']
                h.add_atoms_no_check([f'(: f{k}_{i} {fact} (STV 1 0.9))' for i, fact in enumerate(facts)])
            for k in range(size):
                goal = f'(Member x{k} c{k})' if k % 2 == 0 else f'(Implies p{k} s{k})'
                answers = h.query(f'(: $p {goal} $tv)', steps=30, timeout_sec=0)
                self.assertTrue([a for a in answers if 'population-prior' not in a], (goal, answers))
            work.append(janus.query_once('statistics(inferences,N)')['N'] - start)
        # Deterministic work, not wall time: doubling independent chains must
        # stay below quadratic growth (4x), with room for bounded search overhead.
        self.assertLess(work[1], 2.75 * work[0], work)


if __name__ == '__main__':
    unittest.main()
