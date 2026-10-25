"""Disconnected populations have a Cartesian rate, not a free joint prior,
and a negation's rate is its statement's complement."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestJointBaseRate(unittest.TestCase):
    def test_disconnected_joint_is_rejected_before_cache_mutation(self):
        h = PeTTaChainer()
        h.handler.process_metta_string(f'!(set-base-rate {h.kb} (P $x) (STV 0.5 1))')
        h.handler.process_metta_string(f'!(set-base-rate {h.kb} (Q $y) (STV 0.5 1))')
        with self.assertRaisesRegex(janus.PrologError, 'disconnected_base_rate'):
            h.handler.process_metta_string(
                f'!(set-base-rate {h.kb} (And (P $x) (Q $y)) (STV 0.4 1))')
        self.assertEqual(janus.query_once(
            "aggregate_all(count,('&base_rate_cache'(_, ['base-rate',Kb,_Pattern,_,user,_]),"
            " nonvar(_Pattern), _Pattern=['And'|_]),N)", {'Kb': h.kb})['N'], 0)
        # Sharing a variable describes a real joint population and is supported.
        h.handler.process_metta_string(
            f'!(set-base-rate {h.kb} (And (P $x) (Q $x)) (STV 0.4 1))')
        rate = h.handler.process_metta_string(
            f'!(cached-base-rate {h.kb} (And (P $y) (Q $y)))')
        self.assertIn('0.4', str(rate))

    def test_disconnected_or_is_rejected(self):
        h = PeTTaChainer()
        with self.assertRaisesRegex(janus.PrologError, 'disconnected_base_rate'):
            h.handler.process_metta_string(
                f'!(set-base-rate {h.kb} (Or (P $x) (Q $y)) (STV 0.4 1))')
        h.handler.process_metta_string(
            f'!(set-base-rate {h.kb} (Or (P $x) (Q $x)) (STV 0.4 1))')
        rate = h.handler.process_metta_string(
            f'!(cached-base-rate {h.kb} (Or (P $y) (Q $y)))')
        self.assertIn('0.4', str(rate))

    def test_pin_inside_a_negation_is_honoured(self):
        """A negated antecedent's prior is the complement of its statement's,
        so a rate set on the statement or on its negation is the same pin."""
        facts = [f'(: b{i} (Bird e{i}) (STV {0.9 if i % 3 else 0.1} 0.9))' for i in range(30)]
        facts += [f'(: q{i} (Q e{i}) (STV {0.8 if i % 2 else 0.3} 0.9))' for i in range(15)]
        facts += ['(: rule (Implication (Not (Bird $x)) (Q $x)) (STV 0.7 0.9))']
        values = []
        for pin in ('(Bird $x) (STV 0.1 0.99)', '(Not (Bird $x)) (STV 0.9 0.99)'):
            h = PeTTaChainer()
            h.add_atoms_no_check(facts)
            h.handler.process_metta_string(f'!(set-base-rate {h.kb} {pin})')
            self.assertEqual(str(h.handler.process_metta_string(
                f'!(cached-base-rate {h.kb} (Not (Bird $x)))')), "['()']")
            answer = h.query_many_refs(['(: $p (Q e20) $tv)'], steps=200)[0]
            values.append(answer[0].tv)
        self.assertEqual(values[0][0], 'STV')
        self.assertAlmostEqual(values[0][1], 0.09973382001653103, places=12)
        self.assertAlmostEqual(values[1][1], values[0][1], places=12)
