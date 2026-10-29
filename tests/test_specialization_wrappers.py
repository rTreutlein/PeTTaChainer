"""Specialization must preserve ForAll parameters and WithPrior sources."""
import unittest

from pettachainer import PeTTaChainer


class SpecializationWrappersTests(unittest.TestCase):
    def answers(self, rule, facts, goal, trigger_first):
        h = PeTTaChainer()
        h._call('set-specializing-predicate', ['Structural'])
        h.add_atoms_no_check(facts)
        trigger = '(: tag (Structural Cause) (STV 1 1))'
        for atom in ([trigger, rule] if trigger_first else [rule, trigger]):
            h.add_atom(atom)
        return h, h.query_many_refs([f'(: $p {goal} $tv)'], steps=400)[0]

    def test_forall_conclusion_parameter_matches_ground_control(self):
        wrapped = ('(: sensor (ForAll ($c) (Implication '
                   '(And (Structural $r) ($r $x)) (Result $c $x))) '
                   '(CTV (STV 0.8 0.9) (STV 0.1 0.9)))')
        control = ('(: sensor (Implication '
                   '(And (Structural Cause) (Cause $x)) (Result cohort $x)) '
                   '(CTV (STV 0.8 0.9) (STV 0.1 0.9)))')
        facts = ['(: cause (Cause a) (STV 0.9 0.9))']
        for trigger_first in (False, True):
            with self.subTest(trigger_first=trigger_first):
                _, expected = self.answers(control, facts, '(Result cohort a)', trigger_first)
                h, actual = self.answers(wrapped, facts, '(Result cohort a)', trigger_first)
                self.assertEqual(len(expected), 1)
                self.assertAlmostEqual(float(expected[0].tv[1]), 0.73)
                self.assertEqual([a.tv for a in actual], [a.tv for a in expected])
                other = h.query_many_refs(['(: $p (Result other a) $tv)'], steps=400)[0]
                self.assertEqual([a.tv for a in other], [a.tv for a in expected])
                self.assertIn('sensor', h.expand_proof(other[0].proof))

    def test_instance_prior_matches_ground_control(self):
        for quantified in (False, True):
            # A certain structural conjunct leaves the instance prior and the
            # likelihood unchanged: .9*.1 / (.9*.1 + .2*.9) = 1/3.
            body = ('(WithPrior (Predicted $x) (Implication '
                    '(And (Structural $r) ($r $x)) (Alarm $x)))')
            if quantified:
                body = f'(ForAll ($c) {body.replace("(Alarm $x)", "(Alarm $c $x)")})'
                body = body.replace('(Predicted $x)', '(Predicted $c $x)')
            wrapped = f'(: sensor {body} (CTV (STV 0.9 1) (STV 0.2 1)))'
            control = wrapped.replace('$r', 'Cause')
            facts = (['(: prior (Predicted cohort m) (STV 0.1 1))',
                      '(: alarm (Alarm cohort m) (STV 1 1))'] if quantified else
                     ['(: prior (Predicted m) (STV 0.1 1))',
                      '(: alarm (Alarm m) (STV 1 1))'])
            for trigger_first in (False, True):
                with self.subTest(quantified=quantified, trigger_first=trigger_first):
                    goal = '(And (Structural Cause) (Cause m))'
                    _, expected = self.answers(control, facts, goal, trigger_first)
                    h, actual = self.answers(wrapped, facts, goal, trigger_first)
                    self.assertEqual(len(expected), 1)
                    self.assertAlmostEqual(float(expected[0].tv[1]), 1 / 3, places=5)
                    self.assertEqual([a.tv for a in actual], [a.tv for a in expected])
                    self.assertIn('prior', h.expand_proof(actual[0].proof))

    def test_forall_population_prior_is_per_parameter(self):
        wrapped = ('(: sensor (ForAll ($c) (Implication '
                   '(And (Structural $r) ($r $c $x)) (Alarm $c $x))) '
                   '(CTV (STV 0.9 0.9) (STV 0.2 0.9)))')
        facts = [f'(: cause-{c}-{i} (Cause {c} u{i}) (STV {int(i < count)} 1))'
                 for c, count in [('old', 2), ('new', 1)] for i in range(4)]
        facts += [f'(: alarm-{c} (Alarm {c} q) (STV 1 1))' for c in ('old', 'new')]
        for trigger_first in (False, True):
            with self.subTest(trigger_first=trigger_first):
                strengths = []
                for cohort in ('old', 'new'):
                    # Fixing the parameter in a plain rule must give the same
                    # population inversion as that instance of a ForAll rule.
                    control = ('(: sensor (Implication '
                               f'(And (Structural Cause) (Cause {cohort} $x)) '
                               f'(Alarm {cohort} $x)) '
                               '(CTV (STV 0.9 0.9) (STV 0.2 0.9)))')
                    goal = f'(And (Structural Cause) (Cause {cohort} q))'
                    _, expected = self.answers(control, facts, goal, trigger_first)
                    _, actual = self.answers(wrapped, facts, goal, trigger_first)
                    self.assertEqual(len(expected), 1)
                    self.assertEqual([a.tv for a in actual], [a.tv for a in expected])
                    strengths.append(float(actual[0].tv[1]))
                self.assertGreater(strengths[0], strengths[1])

    def test_withdrawal_removes_wrapped_templates_and_completed_jobs(self):
        rule = ('(: sensor (ForAll ($c) (Implication '
                '(And (Structural $r) ($r $x)) (Result $c $x))) '
                '(CTV (STV 0.8 0.9) (STV 0.1 0.9)))')
        trigger = '(: tag (Structural Cause) (STV 1 1))'
        goal = '(: $p (Result cohort a) $tv)'
        for emitted in (False, True):
            with self.subTest(emitted=emitted):
                h = PeTTaChainer()
                h._call('set-specializing-predicate', ['Structural'])
                h.add_atoms_no_check(['(: cause (Cause a) (STV 0.9 0.9))', rule])
                if emitted:
                    h.add_atom(trigger)
                    self.assertEqual(len(h.query_many_refs([goal], steps=400)[0]), 1)
                h._call('withdraw-named-rules!', ['sensor'])
                if not emitted:
                    h.add_atom(trigger)
                self.assertEqual(h.query_many_refs([goal], steps=400)[0], [])
                h.add_atom(rule)
                restored = h.query_many_refs([goal], steps=400)[0]
                self.assertEqual(len(restored), 1)
                self.assertAlmostEqual(float(restored[0].tv[1]), 0.73)


if __name__ == '__main__':
    unittest.main()
