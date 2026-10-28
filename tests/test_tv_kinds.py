"""Explicit truth-value kinds: (PTV s c) for a ground statement, (FTV s c) for a rule
(LANGUAGE_SPEC, "PTV and FTV"). Each reads as the STV its statement takes by default, the
kind of what the compiler builds of it."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer

RULE = '(Implication (A $x) (B $x))'

# Statements the compiler builds rules of, and so take an FTV.
RULES = (RULE, f'(Not {RULE})', f'(Not (Not {RULE}))', '(BiImplication (A $x) (B $x))',
         '(BiImplication (A a) (B a))', '(Not (Inheritance Dog Animal))', '(Inheritance Dog Animal)')


def answer(atoms, goal):
    h = PeTTaChainer()
    for atom in atoms:
        h.add_atom(atom)
    return [r.tv for r in h.query_many_refs([f'(: $p {goal} $tv)'], steps=200)[0]]


class TvKindTests(unittest.TestCase):
    def test_an_explicit_kind_reads_as_the_stv_its_statement_takes(self):
        stated = answer(['(: fa (A a) (STV 0.7 0.9))', f'(: r {RULE} (STV 0.8 0.9))'], '(B a)')
        kinded = answer(['(: fa (A a) (PTV 0.7 0.9))', f'(: r {RULE} (FTV 0.8 0.9))'], '(B a)')
        self.assertEqual(kinded, stated)
        self.assertEqual(answer(['(: fa (A a) (PTV 0.7 0.9))'], '(A a)'), [['STV', 0.7, 0.9]])

    def test_rules_take_an_ftv_and_facts_a_ptv(self):
        for statement in RULES:
            with self.subTest(statement=statement):
                PeTTaChainer().add_atom(f'(: r {statement} (FTV 0.8 0.9))')
                with self.assertRaisesRegex(janus.PrologError, 'tv_kind'):
                    PeTTaChainer().add_atom(f'(: r {statement} (PTV 0.8 0.9))')
        for statement in ('(A a)', '(Not (A a))', '(Not (Not (A a)))'):
            with self.subTest(statement=statement):
                PeTTaChainer().add_atom(f'(: fa {statement} (PTV 0.7 0.9))')
                with self.assertRaisesRegex(janus.PrologError, 'tv_kind'):
                    PeTTaChainer().add_atom(f'(: fa {statement} (FTV 0.7 0.9))')

    def test_an_unbound_head_is_no_kind(self):
        out = janus.query_once("tv_canon(['A', a], [_K, 0.7, 0.9], _C), ( var(_K) -> Free = true ; Free = false )")
        self.assertEqual(out['Free'], 'true')

    def test_weighted_assumptions_take_kinds_too(self):
        h = PeTTaChainer()
        rows = h.query_many_refs(['(: $p (Assuming (And (: fa (A a) (PTV 0.3 0.9)) (: fb (B a) (STV 0.4 0.9))) (A a)) $tv)'],
                                 steps=200)[0]
        self.assertEqual([r.tv for r in rows], [['STV', 0.3, 0.9]])
        h.query_many_refs([f'(: $p (Assuming (And (A a) (: r (Not {RULE}) (FTV 0.8 0.9))) (B a)) $tv)'], steps=200)
        for bad in ('(: fa (A a) (FTV 0.3 0.9))', f'(: r (Not {RULE}) (PTV 0.8 0.9))'):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(janus.PrologError, 'tv_kind'):
                    h.query_many_refs([f'(: $p (Assuming (And (A a) {bad}) (B a)) $tv)'], steps=200)


if __name__ == '__main__':
    unittest.main()
