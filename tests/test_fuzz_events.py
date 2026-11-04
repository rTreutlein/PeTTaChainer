"""Independent checks of the fuzzer, including deliberately broken answers."""
import math
import unittest

from tests.fuzz.event_oracle import reference
from tests.fuzz.generator import event_cases, mutate_event
from tests.fuzz.kb import EventKB, formula_text
from tests.fuzz.run import Settings, event_evaluate, event_judge
from tests.fuzz.shrink import shrink_event


class EventReferenceTests(unittest.TestCase):
    def test_count_and_view_are_distinct(self):
        from tests.fuzz.event_oracle import distribution
        self.assertAlmostEqual(distribution(1, .001, 'count', 800)[0], 1.8008008008/2.8008008008)
        self.assertAlmostEqual(distribution(1, .001, 'view', 800)[0], 1, places=10)
        self.assertAlmostEqual(distribution(.2, 0, 'count', 800)[0], .5)
        self.assertEqual(distribution(.2, 0, 'view', 800)[:2], (.2, .2))

    def test_neutral_exact_finite_world_reference(self):
        kb = next(event_cases())
        rows = reference(kb)['rows']
        n = 800*.001/.999
        prior = (n+1)/(n+2)
        m = (7200*.9+1)/7202
        l1, l0 = .9*m+.1*(1-m), .1*m+.9*(1-m)
        expected = prior*l1/(prior*l1+(1-prior)*l0)
        self.assertAlmostEqual(rows[0]['s'], expected, places=13)
        self.assertAlmostEqual(rows[0]['s'], .8912891216043766, places=13)
        neutral = reference(mutate_event(kb, 'neutral'))['rows']
        for a, b in zip(rows, neutral):
            self.assertAlmostEqual(a['s'], b['s'], places=13)
            self.assertLessEqual(a['variance_lower'], a['variance']+1e-12)

    def test_origin_family_matches_closed_form(self):
        for kb in event_cases():
            if not kb.name.startswith('origins'):
                continue
            u = math.prod(1-v[0] for v in kb.roots.values())
            rows = reference(kb)['rows']
            self.assertAlmostEqual(rows[0]['s'], 1-u/2, places=11)
            self.assertAlmostEqual(rows[2]['s'], 1-3*u/4, places=11)
            self.assertEqual(rows[0]['variance_status'], 'exact-polynomial')
            self.assertAlmostEqual(rows[0]['variance'], rows[0]['variance_lower'], places=11)

    def test_impossible_and_forced_worlds(self):
        a = '(A e)'
        kb = EventKB('zero', {a: (.4, .5, 'count')}, [], [(('Not', a), 1, 1)], [a])
        row = reference(kb)['rows'][0]
        self.assertEqual((row['s'], row['variance']), (0, 0))
        kb.reports.append((a, 1, 1))
        self.assertEqual(reference(kb)['status'], 'impossible')

    def test_not_or_repeats_share_one_event(self):
        a, b = '(A e)', '(B e)'
        kb = EventKB('logic', {a: (.3, 1, 'count'), b: (.4, 1, 'count')}, [], [],
                     [('And', a, a), ('Or', a, ('Not', a)), ('And', a, ('Not', a)), ('Or', a, b)])
        self.assertEqual([round(r['s'], 12) for r in reference(kb)['rows']], [.3, 1, 0, .58])

    def test_seeded_variation_roundtrip(self):
        for seed in (1, 2, 17):
            a = [k.to_json() for k in event_cases(seed)]
            self.assertEqual(a, [k.to_json() for k in event_cases(seed)])
            for data in a:
                kb = EventKB.from_json(data)
                self.assertEqual(kb.to_json(), data)
                self.assertTrue(kb.program().queries)


class EventGateTests(unittest.TestCase):
    settings = Settings((30, 500), 800, .001, 45)

    def answers(self, kb, s=.5, c=.9):
        p = kb.program() if isinstance(kb, EventKB) else kb
        return {'answers': {b: [[[s, c, 'test']] for _ in p.queries] for b in self.settings.budgets}}

    def test_analytic_overconfidence_and_budget_loss(self):
        kb = next(k for k in event_cases() if k.name.startswith('origins-1-'))
        exact = reference(kb)
        bad = self.answers(kb, s=exact['rows'][0]['s'], c=1)
        flags, _ = event_judge(kb, exact, bad, self.settings)
        self.assertIn('overconfident_variance', [f['invariant'] for f in flags])
        bad['answers'][500][0] = []
        flags, _ = event_judge(kb, exact, bad, self.settings)
        self.assertIn('lost_answer', [f['invariant'] for f in flags])

    def test_flip_detects_a_frozen_answer_without_reference_dependency(self):
        kb = next(k for k in event_cases() if k.name.startswith('leaf-report-And'))
        result = event_evaluate(kb, self.settings, lambda k: self.answers(k, .4))
        self.assertIn('flip', [f['invariant'] for f in result['flags']])

    def test_false_constraint_rejects_positive_support(self):
        kb = next(k for k in event_cases() if k.name.startswith('identity-ground'))
        result = event_evaluate(kb, self.settings, lambda k: self.answers(k, 1))
        self.assertIn('false', [f['invariant'] for f in result['flags']])

    def test_cost_inferences_classify_quadratic_work(self):
        kb = next(k for k in event_cases() if k.probe)
        flags, _ = event_judge(kb, {}, {'probe': [{'n': n, 'inferences': n*n} for n in kb.probe]}, self.settings)
        self.assertEqual(flags[0]['invariant'], 'bounded_work')

    def test_shrinker_keeps_same_failure_and_reports_fixed_point(self):
        kb = next(k for k in event_cases() if k.name.startswith('identity-ground'))
        flag = {'invariant': 'false', 'severity': 'BLOCKER', 'query': 0}
        small, _, _, minimal = shrink_event(kb, flag, self.settings, lambda k: self.answers(k, 1), 50)
        self.assertTrue(minimal)
        self.assertFalse(small.raw)
        self.assertTrue(small.reports)


if __name__ == '__main__':
    unittest.main()
