"""Repeated queries on an unchanged KB go quiet, and facts added mid-run give a fresh KB's answer.

Oracles for the work-queue core (bench/results/fresh-design/workqueue-design.md,
section 7). The expected failures are master's known gaps; the step that closes
one turns its test into an ordinary pass.
"""
import unittest

from pettachainer import PeTTaChainer
from test_deep_conditioning import plant, plant_atoms


def handler(periods, omit=(), extra=()):
    h = PeTTaChainer()
    plant(h, periods, omit=omit)
    if extra:
        h.add_atoms_no_check(list(extra))
    h.set_query_metrics(True)
    return h


def ask(h, goal, steps):
    rows = h.query_many_refs([f'(: $p {goal} $tv)'], steps=steps)[0]
    metrics = h.last_query_metrics()
    return rows[0].tv if rows else None, metrics['row_computes'], metrics['conditioned_evaluations']


STORM_DEGRADES = '(: storm-deg (Implication (Storm $t) (Degraded plant $t)) (CTV (STV 0.3 1) (STV 0.05 1)))'


class RepeatedQueryTests(unittest.TestCase):
    @unittest.expectedFailure  # work-queue step 1: unpaid rows are staled and recomputed by every query
    def test_budget_limited_root_goes_quiet(self):
        h = handler(4, extra=[STORM_DEGRADES])
        answers = [ask(h, '(Degraded plant t4)', 300) for _ in range(6)]
        self.assertEqual({tv for tv, _, _ in answers}, {answers[0][0]})
        self.assertEqual(answers[-1][1:], (0, 0))

    @unittest.expectedFailure  # work-queue steps 1 and 4: rows and the t4 root claim repeat in every round
    def test_round_robin_roots_go_quiet(self):
        h = handler(6)
        rounds = [[ask(h, f'(Degraded plant t{t})', 3000) for t in (6, 5, 4)] for _ in range(3)]
        self.assertEqual([tv for tv, _, _ in rounds[-1]], [tv for tv, _, _ in rounds[-2]])
        self.assertEqual([cost for _, *cost in rounds[-1]], [[0, 0]] * 3)

    def test_repeated_assuming_goes_quiet(self):
        # Quiet within five queries, with one answer throughout. The bound moved
        # from four to five with the component split (R1, user-approved Oct 21):
        # merged values keep the direct claims and the update, so their larger
        # dependency sets meet more exclusions, and the deferred tier drains
        # rebuilds at 1/8 of each query's allowance. After an earlier test in
        # the process it costs 1876, 914, 875, 247, then 0 rows. Work-queue
        # steps 1/2 should tighten it.
        h = handler(6)
        answers = [ask(h, '(Assuming (Storm t4) (Degraded plant t6))', 3000) for _ in range(5)]
        self.assertEqual([tv for tv, _, _ in answers], [answers[0][0]] * 5)
        self.assertEqual(answers[-1][1:], (0, 0))


class FactAdditionTests(unittest.TestCase):
    """A fact added after earlier queries gives the answer of a KB that had it from the start."""

    def check_addition(self, periods, budget, omit=(), extra=()):
        fresh = handler(periods, extra=extra)
        expected = [ask(fresh, f'(Degraded plant t{periods})', budget) for _ in range(2)][-1][0]
        h = handler(periods, omit=omit)
        for _ in range(2):
            ask(h, f'(Degraded plant t{periods})', budget)
        h.add_atoms_no_check([atom for atom in plant_atoms(periods) if atom.split()[1] in omit] + list(extra))
        answers = [ask(h, f'(Degraded plant t{periods})', budget) for _ in range(4)]
        self.assertEqual(answers[-1][0], expected)
        self.assertEqual(answers[-1][1:], (0, 0))

    def test_additions_near_the_root_or_on_a_premise(self):
        for omit, extra in ((('next-t3',), ()), (('rep-t3',), ()),
                            ((), ('(: rep2-t1 (Producing plant t1) (STV 1 0.9))',)),
                            ((), ('(: storm-obs (Storm t3) (STV 0.9 0.8))',))):
            with self.subTest(omit=omit, extra=extra):
                self.check_addition(4, 3000, omit, extra)

    @unittest.expectedFailure  # #110 M1, work-queue step 2: a deep reader of the new report is never refreshed
    def test_deep_report_addition(self):
        self.check_addition(4, 3000, ('rep-t1',))


if __name__ == '__main__':
    unittest.main()
