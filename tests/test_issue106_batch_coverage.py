"""#106: a clashing sink key keeps a coarse answer when its conditioning cannot finish.

The fixture is the authored public prefix of the SupplyNet timed history (stage 3,
seed 3) through operation 115, with k=800 and KE's 200 steps per batch. The
Producing plants are complete sink predicates: no population prior, a row whose
premises share history evidence, and conditioning over 14-35 statements that
no budget completes. References are the KB-as-authored exact Pearl posterior of
the authored prefix (dp-106 Revision 1 reference program, k=800, Fraction).
"""
import json
import math
import unittest
from pathlib import Path

import janus_swi as janus
from pettachainer import PeTTaChainer

FIXTURE = Path(__file__).parent / 'fixtures' / 'issue106_timed_prefix.json'
# plant-a t6 at operation 83 and plant-a t14 at operation 115.
REFERENCE = {'(Producing plant-a t6)': 2.2896127309368948e-10, '(Producing plant-a t14)': 1.740300622792284e-17}


def law(tv, k=800):
    """Mean and standard deviation of the count law STV(s, c) states."""
    _, s, c = tv
    n = k * c / (1 - c)
    a, b = n * s + 1, n * (1 - s) + 1
    return a / (a + b), math.sqrt(a * b / ((a + b) ** 2 * (a + b + 1)))


class Issue106BatchCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        h = PeTTaChainer()
        cls.answers = {}
        for op in json.loads(FIXTURE.read_text()):
            result = getattr(h, op['method'])(*op['args'], **op['kwargs'])
            if op['method'] == 'query_many_refs':
                for query, group in zip(op['args'][0], result):
                    statement = query[len('(: $prf '):-len(' $tv)')]
                    if statement in REFERENCE:
                        cls.answers[statement] = [a.tv for a in group]

    def test_repeated_claim_batch_answers_its_sink_key(self):
        # Operation 83: the consumers' identical pinned claims used the whole
        # allowance and left plant-a t6 with no answer.
        tv, = self.answers['(Producing plant-a t6)']
        self.assertLess(abs(tv[1] - REFERENCE['(Producing plant-a t6)']), .05)

    def test_unsettling_nested_claim_no_longer_takes_the_batch(self):
        # Operation 115: one inline pinned claim over 29 statements spent the
        # whole allowance at every budget; the deferred read leaves plant-a t14
        # an honest coarse answer.
        tv, = self.answers['(Producing plant-a t14)']
        mean, sd = law(tv)
        self.assertLessEqual(abs(mean - REFERENCE['(Producing plant-a t14)']), 2 * sd)

    def test_waiting_answer_without_independent_read_takes_the_minimum_range(self):
        # No independent read to bound the representative: R = 1, c/(1+R^2).
        result = janus.query_once(
            "'sk-discounted'(['sk-val',[['P',a],ctx,proof,['STV',0.3,0.8]],ev,0],'sk-none',0.8,"
            "['sk-val',[_,_,_,['STV',S,C]],_,_])")
        self.assertTrue(result['truth'])
        self.assertEqual(result['S'], .3)
        self.assertAlmostEqual(result['C'], .4, delta=1e-12)


if __name__ == '__main__':
    unittest.main()
