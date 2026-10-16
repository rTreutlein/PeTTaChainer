"""Disconnected populations have a Cartesian rate, not a free joint prior."""
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
