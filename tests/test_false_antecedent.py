"""Tracker #83: an unstated negative branch supplies no instance evidence."""
import itertools
import unittest

from pettachainer import PeTTaChainer
from pettachainer.query_diagnostics import _parse


class FalseAntecedentTests(unittest.TestCase):
    broad = ('(: broad (Implication (And (Member $c Corridor) '
             '(UndergoingMaintenance $c)) (Closed $c)) (STV 0.5 0.0001))')
    specific = ('(: specific (Implication (And (Member $c Corridor) '
                '(UndergoingMaintenance $c) (UnderSupervision $c)) '
                '(Closed $c)) (STV 0.5 0.0001))')

    def handler(self, supervision, rules, refinement=True):
        h = PeTTaChainer()
        h.set_rule_refinement(refinement)
        h.add_atom('(: corridor (Member Cedar Corridor) (STV 1 1))')
        h.add_atom('(: maintenance (UndergoingMaintenance Cedar) (STV 1 1))')
        if supervision is not None:
            statement = '(UnderSupervision Cedar)'
            if not supervision:
                statement = f'(Not {statement})'
            h.add_atom(f'(: supervision {statement} (STV 1 1))')
        for rule in rules:
            h.add_atom(rule)
        return h

    def answer(self, h):
        answers = h.query_many_refs(['(: $p (Closed Cedar) $tv)'], steps=600)[0]
        self.assertLessEqual(len(answers), 1)
        return answers[0] if answers else None

    def test_full_control_table(self):
        for refinement, supervision, mode in itertools.product(
                (False, True), (None, False, True), ('broad', 'specific', 'both')):
            rules = {'broad': [self.broad], 'specific': [self.specific],
                     'both': [self.broad, self.specific]}[mode]
            for order in (rules, list(reversed(rules))) if mode == 'both' else (rules,):
                with self.subTest(refinement=refinement, supervision=supervision,
                                  mode=mode, order=order):
                    h = self.handler(supervision, order, refinement)
                    answer = self.answer(h)
                    if supervision is None and mode == 'specific':
                        self.assertIsNone(answer)
                    else:
                        self.assertIsNotNone(answer)
                        self.assertAlmostEqual(float(answer.tv[1]), 0.5, places=12)
                        if supervision is False and mode == 'specific':
                            self.assertEqual(float(answer.tv[2]), 0)
                        else:
                            self.assertGreater(float(answer.tv[2]), 0.00009)
                        if supervision is False and mode == 'both':
                            self.assertNotIn('specific', h.expand_proof(answer.proof))

    def test_explicit_negative_antecedent_rule(self):
        negative = ('(: negative (Implication (And (Member $c Corridor) '
                    '(UndergoingMaintenance $c) (Not (UnderSupervision $c))) '
                    '(Closed $c)) (STV 0.8 0.9))')
        for supervision, expected in ((None, None), (False, 0.8), (True, 0.5)):
            for rules in ([self.specific, negative],
                          [self.broad, self.specific, negative]):
                with self.subTest(supervision=supervision, rules=rules):
                    h = self.handler(supervision, rules)
                    answer = self.answer(h)
                    if expected is None and self.broad not in rules:
                        self.assertIsNone(answer)
                    else:
                        self.assertAlmostEqual(float(answer.tv[1]), expected or 0.5,
                                               delta=0.00001)
                        self.assertGreater(float(answer.tv[2]), 0)

    def test_explicit_ctv_negative_branch(self):
        rule = self.specific.replace('(STV 0.5 0.0001)',
                                    '(CTV (STV 0.5 0.9) (STV 0.8 0.9))')
        h = self.handler(False, [rule])
        answer = self.answer(h)
        self.assertAlmostEqual(float(answer.tv[1]), 0.8)
        self.assertGreater(float(answer.tv[2]), 0.89)

    def test_unknown_branch_preserves_non_neutral_applicable_rule(self):
        broad = self.broad.replace('0.5 0.0001', '0.7 0.9')
        specific = self.specific.replace('0.5 0.0001', '0.95 0.9')
        for rules in ([broad], [broad, specific], [specific, broad]):
            with self.subTest(rules=rules):
                h = self.handler(False, rules)
                answer = self.answer(h)
                self.assertAlmostEqual(float(answer.tv[1]), 0.7, places=12)
                self.assertGreater(float(answer.tv[2]), 0.89)
                self.assertNotIn('specific', h.expand_proof(answer.proof))

    def test_missing_or_drained_rates_leave_neutral_branch(self):
        h = PeTTaChainer()
        for rates in ('no-evidence no-evidence', '(STV 0.2 0.9) no-evidence',
                      'no-evidence (STV 0.7 0.9)', '(STV 0 0) (STV 1 0)',
                      '(STV 1 0.001) (STV 1 0.002)'):
            with self.subTest(rates=rates):
                result = _parse(h._call('ImplicationLikelihoodsFormula',
                                       [rates + ' (STV 0.5 0.9) 0.5'])[0])[2]
                self.assertEqual(result[2], ['STV', '0.5', '0.0'])

    def test_informative_rates_still_estimate_negative_branch(self):
        h = PeTTaChainer()
        result = _parse(h._call('ImplicationLikelihoodsFormula',
                               ['(STV 0.25 0.9) (STV 0.5 0.9) (STV 0.8 0.9) 0.5'])[0])[2]
        # #89 reads the raw .4/.225 complement once at neutral .5.
        count = 800 * .225 / (1 - .225)
        self.assertAlmostEqual(float(result[2][1]), (.4 * count + .2 * .5) / (count + .2))
        self.assertAlmostEqual(float(result[2][2]), 0.225)
        h.add_atom('(: a (A x) (STV 0 1))')
        h.add_atom('(: r (Implication (A $x) (B $x)) (STV 0.8 0.9))')
        # An unknown cached branch must acquire its proper contribution when
        # explicit priors arrive, without rebuilding the rule or the chainer.
        before = h.query_many_refs(['(: $p (B x) $tv)'], steps=600)[0][0]
        self.assertEqual(before.tv, ['STV', 0.5, 0.0])
        h._call('set-base-rate', [f'{h.kb} (A $x) (STV 0.25 0.9)'])
        h._call('set-base-rate', [f'{h.kb} (B $x) (STV 0.5 0.9)'])
        answer = h.query_many_refs(['(: $p (B x) $tv)'], steps=600)[0][0]
        self.assertAlmostEqual(float(answer.tv[1]), (.4 * count + .2 * .5) / (count + .2))
        self.assertGreater(float(answer.tv[2]), 0.2)
