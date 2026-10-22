"""Assumed implications with variables are rules of the query world, as stored rules are (#127)."""
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer

MAIN = ['(: hb (AlwaysPlayedTennis Bob) (STV 0.9 0.8))',
        '(: ha (AlwaysPlayedTennis Ann) (STV 0.6 0.9))',
        '(: ca (Member Ann Club) (STV 1 0.9))']
BRIDGE = '(Implication (AlwaysPlayedTennis $x) (PlayingTennisNow $x))'
WEIGHTED = f'(: bridge {BRIDGE} (STV 0.12 0.2))'
BUSY = '(: busy (Implication (PlayingTennisNow $x) (Busy $x)) (STV 0.9 0.6))'


def answers(handler, goal):
    rows = handler.query_many_refs([f'(: $p {goal} $tv)'], steps=2000)[0]
    return sorted((str(row.statement[2] if row.statement[0] == 'Assuming' else row.statement), row.tv)
                  for row in rows)


class SchematicAssumptionTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.add_atoms_no_check(MAIN)
        janus.consult(str(Path(__file__).with_name('context_overlay_probe.pl')))
        janus.query_once('overlay_probe_install(none)')

    def assertAssumedAsStored(self, rules, goal, assumed=None):
        reference = PeTTaChainer()
        reference.add_atoms_no_check(MAIN + rules)
        expected = answers(reference, goal)
        self.assertNotEqual(expected, [])
        facts = assumed or (rules[0] if len(rules) == 1 else '(And ' + ' '.join(rules) + ')')
        self.assertEqual(answers(self.h, f'(Assuming {facts} {goal})'), expected)
        self.assertEqual(answers(self.h, goal), [])
        self.assertEqual(janus.query_once('overlay_probe_main_leaks(Kb,Rows)', {'Kb': self.h.kb})['Rows'], [])

    def test_weighted_rule_consumes_main_facts_as_a_stored_rule(self):
        for tv in ('(STV 0.12 0.2)', '(CTV (STV 0.12 0.2) (STV 0.01 0.5))'):
            with self.subTest(tv=tv):
                self.assertAssumedAsStored([f'(: bridge {BRIDGE} {tv})'], '(PlayingTennisNow Bob)')

    def test_bare_rule_is_a_certain_stored_rule(self):
        self.assertAssumedAsStored([f'(: bridge {BRIDGE} (CTV (STV 1 1) (STV 0 1)))'], '(PlayingTennisNow Bob)',
                                   assumed=BRIDGE)

    def test_rule_variables_stay_local(self):
        for goal in ('(PlayingTennisNow $y)', '(PlayingTennisNow $x)',
                     '(And (PlayingTennisNow $x) (PlayingTennisNow Ann))'):
            with self.subTest(goal=goal):
                self.assertAssumedAsStored([WEIGHTED], goal)
        row = self.h.query_many_refs([f'(: $p (Assuming {WEIGHTED} (PlayingTennisNow $x)) $tv)'], steps=2000)[0][0]
        _, (_, _, (_, (_, antecedent), (_, consequent)), _), _ = row.statement
        self.assertTrue(antecedent.startswith('$') and antecedent == consequent, row.statement)

    def test_applications_to_several_entities_are_independent(self):
        self.assertAssumedAsStored([WEIGHTED], '(And (PlayingTennisNow Bob) (PlayingTennisNow Ann))')

    def test_intermediate_rules_and_joins(self):
        self.assertAssumedAsStored([WEIGHTED, BUSY], '(Busy $y)')
        self.assertAssumedAsStored(
            ['(: club (Implication (And (Member $x Club) (AlwaysPlayedTennis $x)) (PlayingTennisNow $x)) (STV 0.7 0.5))'],
            '(PlayingTennisNow Ann)')
        self.assertAssumedAsStored(
            ['(: active (Implication (Exists ($z) (And (Member $z Club) (AlwaysPlayedTennis $z))) (ClubActive Club))'
             ' (STV 0.8 0.5))'],
            '(ClubActive Club)')

    def test_free_variable_facts_and_open_values_stay_rejected(self):
        for annotation in ('(: b (AlwaysPlayedTennis $x) (STV 0.5 0.5))', f'(: b {BRIDGE} $tv)',
                           f'(: b {BRIDGE} (STV 1.5 0.2))', f'(: b {BRIDGE})'):
            with self.subTest(annotation=annotation):
                with self.assertRaisesRegex(janus.PrologError, 'weighted_assumption'):
                    answers(self.h, f'(Assuming {annotation} (PlayingTennisNow Bob))')


if __name__ == '__main__':
    unittest.main()
