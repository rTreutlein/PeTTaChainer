"""Regress #71: a cold instance fold must publish its final refinement.

Run from the repository root through bench/capped, with PYTHONPATH=.
Previously the cold query reached 0.7459165 even at 5000 steps, while a
repeat or warming B first reached 0.74999998. Check both histories and both
300/5000-step budgets. No negation or shared-source revision is involved.
"""
import argparse
import unittest

from pettachainer import PeTTaChainer


class EmpiricalConditionalHistoryTests(unittest.TestCase):
    def check_history(self, steps, warm_b):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a1 (A x) (STV 1 0.9))',
            '(: b1 (B x) (STV 0.7 0.9))',
            '(: c1 (C x) (STV 1 0.9))',
            '(: (no_inverse r1) (Implication (C $v) (B $v)) (STV 0.8 0.9))',
        ])
        if warm_b:
            print('warm B:', h.query_many_refs(['(: $p (B x) $tv)'], steps=steps), flush=True)
        for repeat in range(3):
            rows = h.query_many_refs(['(: $p (Implication (A x) (B x)) $tv)'], steps=steps)[0]
            print(f'{warm_b=} {repeat=}:',
                  [(row.tv, h.expand_proof(row.proof)) for row in rows], flush=True)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0].tv, ['STV', 0.903225806451613, 0.0010153078491320258])
            self.assertEqual(h.expand_proof(rows[0].proof), '(implication-instance-fold cpu)')

    def test_cold_repeat_and_warm_at_both_budgets(self):
        for steps in (300, 5000):
            for warm_b in (False, True):
                with self.subTest(steps=steps, warm_b=warm_b):
                    self.check_history(steps, warm_b)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--steps', type=int)
    args = parser.parse_args()
    if args.steps is None:
        unittest.main(argv=[__file__])
    else:
        case = EmpiricalConditionalHistoryTests()
        for warm_b in (False, True):
            case.check_history(args.steps, warm_b)
