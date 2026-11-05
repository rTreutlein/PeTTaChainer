"""A multi-root query answers each root as the root queried alone does.

The other roots' search adds members to a shared base-rate fold during the
batch's one evaluation, so rows read different values of the one population
base rate. Their updates still factor: each is a likelihood ratio, whatever
value it was read under. Treating the values as different priors revised the
views of Front t2 instead and answered Front t1 at .271 for the exact .642.
"""
from fractions import Fraction as F
from itertools import product
import unittest

from pettachainer import PeTTaChainer

PERIODS = ['h1', 'h2', 'h3', 't1', 't2', 't3', 't4']
ATOMS = [
    '(: persist (Implication (And (NextPeriod $p $t) (Front $p)) (Front $t)) (CTV (STV 0.9 1) (STV 0.05 1)))',
    '(: storm (Implication (Front $t) (Storm $t)) (CTV (STV 0.7 1) (STV 0.05 1)))',
] + [f'(: alarm{i} (Implication (Storm $t) (Alarm a{i} $t)) (CTV (STV 0.6 1) (STV 0.25 1)))' for i in (1, 2)] + [
    atom for i in (1, 2, 3) for atom in (
        f'(: fh{i} (Front h{i}) (STV 0 1))', f'(: sh{i} (Storm h{i}) (STV {1 if i == 1 else 0} 1))')
] + [f'(: n{i} (NextPeriod {a} {b}) (STV 1 1))' for i, (a, b) in enumerate(zip(PERIODS, PERIODS[1:]))] + [
    f'(: a{i}t{t} (Alarm a{i} t{t}) (STV 1 1))' for i in (1, 2) for t in (1, 2, 3, 4)]


def exact_fronts():
    # Front h3 is false; sum out each period's Storm, enumerate the 16 paths.
    alarms = {1: F('.7') * F('.6') ** 2 + F('.3') * F('.25') ** 2,
              0: F('.05') * F('.6') ** 2 + F('.95') * F('.25') ** 2}
    total, fronts = F(0), [F(0)] * 4
    for path in product((0, 1), repeat=4):
        weight, last = F(1), 0
        for front in path:
            stay = F('.9') if last else F('.05')
            weight *= (stay if front else 1 - stay) * alarms[front]
            last = front
        total += weight
        fronts = [n + weight * front for n, front in zip(fronts, path)]
    return [float(n / total) for n in fronts]


class BatchBaseRateSnapshotTests(unittest.TestCase):
    def test_temporal_batch_matches_sequential_and_exact(self):
        goals = [f'(: $p (Front t{t}) $tv)' for t in (1, 2, 3, 4)]
        for steps in (400, 1600, 4000):
            for mode in ('batch', 'sequential'):
                h = PeTTaChainer()
                h.set_evidence_confidence_k(5)
                h.add_atoms_no_check(ATOMS)
                rows = (h.query_many_refs(goals, steps=steps) if mode == 'batch'
                        else [h.query_many_refs([goal], steps=steps)[0] for goal in goals])
                for t, (answers, exact) in enumerate(zip(rows, exact_fronts()), 1):
                    with self.subTest(steps=steps, mode=mode, front=t):
                        self.assertEqual(len(answers), 1)
                        self.assertAlmostEqual(answers[0].tv[1], exact, delta=1e-9)
                        self.assertEqual(answers[0].tv[2], .9999)


if __name__ == '__main__':
    unittest.main()
