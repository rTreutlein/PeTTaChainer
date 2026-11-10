"""Issue #181: forward publication retains admissible, shared-evidence values."""
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer
from pettachainer.metta_syntax import parse_term, render


RULES = {
    'g_son': '(Kin son $x $y) (Kin child $x $y)',
    'male_son': '(Kin son $x $y) (Member $x male)',
    's_son': '(And (Kin child $x $y) (Member $x male)) (Kin son $x $y)',
    'cp': '(Kin child $x $y) (Kin parent $y $x)',
    'pc': '(Kin parent $x $y) (Kin child $y $x)',
    'sib': '(And (Kin child $x $y) (Kin parent $y $z)) (Kin sibling $x $z)',
    'sym': '(Kin sibling $x $y) (Kin sibling $y $x)',
}
CASES = (
    (['(: f1 (Kin son elliott stanley) (STV 0.8 0.9))'],
     ['g_son', 'male_son', 's_son'],
     ['(Kin child elliott stanley)', '(male elliott)']),
    (['(: f1 (Kin child annie valerie) (STV 0.8 0.9))'],
     ['cp', 'pc'], ['(Kin parent valerie annie)']),
    (['(: f1 (Kin child elliott stanley) (STV 0.8 0.9))',
      '(: f2 (Kin child valerie stanley) (STV 1.0 0.99))'],
     ['cp', 'pc', 'sib', 'sym'], ['(Kin sibling elliott valerie)']),
)


def make_case(case, negative):
    facts, names, _ = case
    h = PeTTaChainer()
    for atom in facts:
        h.add_atom(atom)
    for name in names:
        h.add_atom(f'(: {name} (Implication {RULES[name]}) '
                   f'(CTV (STV 1.0 0.99) (STV 0.0 {negative})))')
    return h


class ForwardCycleTests(unittest.TestCase):
    def test_reported_cycles_match_backward_without_changing_observations(self):
        # Finite .99 rule parameters cost a small amount of confidence. The
        # tolerance covers that propagation, not the reported .914/.004 drift.
        for i, case in enumerate(CASES, 1):
            for negative in (.001, 1):
                with self.subTest(case=i, negative=negative):
                    h = make_case(case, negative)
                    targets = case[2]
                    queries = [f'(: $p {t} $tv)' for t in targets]
                    cold = make_case(case, negative).query_many_refs(queries, steps=2000)
                    out = {render(t): tuple(map(float, tv[1:]))
                           for t, _, _, tv in map(parse_term, h.forward_chain(h.all_facts(), steps=2000))}
                    for target, answers in zip(targets, cold):
                        expected, = answers
                        self.assertIn(target, out)
                        strength, confidence = out[target]
                        self.assertAlmostEqual(strength, .8, delta=.001)
                        self.assertAlmostEqual(confidence, .9, delta=.001)
                        for actual, backward in zip(out[target], expected.tv[1:]):
                            self.assertAlmostEqual(actual, backward, delta=.001)
                    # Repeated saturation must not turn its own stored copies
                    # into fresh observations. Check zero-budget reads too.
                    for _ in range(3):
                        for steps in (0, 2000):
                            for target, answers in zip(targets, h.query_many_refs(queries, steps=steps)):
                                answer, = answers
                                for actual, initial in zip(answer.tv[1:], out[target]):
                                    self.assertAlmostEqual(actual, initial, delta=.001)
                        for atom in case[0]:
                            _, name, statement, tv = parse_term(atom)
                            stored = [row for row in map(parse_term, h.all_facts())
                                      if row[0] == statement and row[2] == name]
                            self.assertEqual(len(stored), 1)
                            self.assertEqual(stored[0][3], tv)
                        self.assertFalse(any('(exists ' in render(parse_term(f)[0]) for f in h.all_facts()))
                        h.forward_chain(h.all_facts(), steps=2000)

    def test_nonseed_fact_in_forward_join_keeps_dependency_identity(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: start (Start a) (STV 1 1))',
            '(: source (P a) (STV 0.8 0.9))',
            '(: (no_inverse pq) (Implication (And (Start $x) (P $x)) (Q $x)) '
            '(CTV (STV 1 1) (STV 0 1)))',
            '(: (no_inverse qr) (Implication (And (Q $x) (P $x)) (R $x)) '
            '(CTV (STV 1 1) (STV 0 1)))',
        ])
        seeds = [f for f in h.all_facts() if parse_term(f)[2] == 'start']
        out = {render(t): tuple(map(float, tv[1:]))
               for t, _, _, tv in map(parse_term, h.forward_chain(seeds, steps=2000))}
        self.assertIn('(R a)', out)
        for actual, expected in zip(out['(R a)'], (.8, .9)):
            self.assertAlmostEqual(actual, expected, delta=.001)

    def test_inverse_witness_requires_evidence_outside_its_antecedent(self):
        h = make_case(CASES[0], .001)
        h.forward_chain(h.all_facts(), steps=2000)
        witness = '(Kin son elliott (exists male_son 0 (elliott)))'
        # The inverse's missing variable is not a distinct new individual
        # justified by male_son's own prediction from the known son.
        self.assertFalse(any(witness in f for f in h.all_facts()))
        prior, = h.query_many_refs([f'(: $p {witness} $tv)'], steps=2000)[0]
        self.assertEqual(prior.proof[0], 'population-prior')
        h.add_atom('(: observed_male (male elliott) (STV 0.8 0.9))')
        h.forward_chain(h.all_facts(), steps=2000)
        self.assertTrue(any(witness in f for f in h.all_facts()))
        answers = h.query_many_refs([f'(: $p {witness} $tv)'], steps=2000)[0]
        self.assertTrue(answers)
        self.assertIn('observed_male', h.expand_proof(answers[0].proof))

    def test_inverse_cycle_pattern_preserves_bindings_and_variable_heads(self):
        h = make_case(CASES[0], .001)
        result = janus.query_once(
            "source_catalog_application(Id,_,_,[Output,Scope],"
            "['reverse-source',male_son,_,_],_,_), "
            "Scope=[Kb,'MAIN','Nil'], "
            "Output=['Kin',son,elliott,[exists,male_son,0,[elliott]]], "
            "'rule-cycle-key'(Id,['sk-key',Output,Scope],_Cycle), "
            "_Cycle=['sk-key',['Kin',son,elliott,_Parent],Scope], var(_Parent), "
            "'rule-cycle-key'(-1,['sk-key',[_Head,a],Scope],_Other), var(_Head)",
            {'Kb': h.kb})
        self.assertTrue(result['truth'])


if __name__ == '__main__':
    unittest.main()
