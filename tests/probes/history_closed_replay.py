"""Issue #54: branch reuse must converge and stop work on an unchanged KB."""
import json
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class ClosedHistoryReplayTests(unittest.TestCase):
    def test_u4_round12_warm_and_cold_reach_a_quiet_fixed_point(self):
        tests = Path(__file__).resolve().parents[1]
        record = json.loads((tests / 'data/history_u4_r12.json').read_text())
        janus.consult(str(tests / 'branch_cache_probe.pl'))
        janus.query_once('branch_probe_install')
        work_counters = ('branch_builds', 'row_computes', 'conditioned_evaluations', 'conditions_unpaid')
        for budget in (2000, 20000):
            fixed_points = []
            for warm in (True, False):
                with self.subTest(budget=budget, warm=warm):
                    h = PeTTaChainer()
                    h.set_query_metrics(True)
                    at = 0
                    for snap in record['snaps']:
                        for name, args in record['calls'][at:snap['n']]:
                            getattr(h, name)(*args)
                        at = snap['n']
                        if warm:
                            h.query_many_refs(snap['goals'], steps=2000)
                            self.assertEqual(janus.query_once('branch_probe_invalid(Rows)')['Rows'], [])
                    goals = snap['goals']
                    position = goals.index('(: $prf (Degraded power-plant t13) $tv)')
                    for _ in range(16):
                        answer = h.query_many_refs(goals, steps=budget)[position][0]
                        metrics = h.last_query_metrics()
                        self.assertEqual(janus.query_once('branch_probe_invalid(Rows)')['Rows'], [])
                        if all(metrics[counter] == 0 for counter in work_counters):
                            break
                    else:
                        self.fail(f'Unchanged KB did not become quiet: {metrics}')
                    # #68: retaining semantic evidence through negation also
                    # admits the observed production at t12. Its degradation
                    # is exactly zero (odds updates preserve endpoints), so one step yields
                    # D13 = 0.05 + 0.7*D12, rather than skipping that observation
                    # and taking two steps from the t11 update (about 0.085).
                    self.assertAlmostEqual(answer.tv[1], 0.05, places=12)
                    self.assertIn('producing-power-plant-t12', h.expand_proof(answer.proof))
                    fixed_points.append(answer.tv[1])
                    for _ in range(3):
                        repeated = h.query_many_refs(goals, steps=budget)[position][0]
                        self.assertEqual(repeated.tv, answer.tv)
                        metrics = h.last_query_metrics()
                        for counter in work_counters:
                            self.assertEqual(metrics[counter], 0, (counter, metrics))
                        self.assertEqual(janus.query_once('branch_probe_invalid(Rows)')['Rows'], [])
                    self.assertEqual(janus.query_once(
                        "findall([_K,_E],'&sk_branch_wanted'(_,_H,_K,_,_E),Rows)"
                    )['Rows'], [])
            self.assertEqual(len(fixed_points), 2)
            self.assertEqual(fixed_points[0], fixed_points[1])
        self.assertGreater(janus.query_once(
            'aggregate_all(count,branch_probe_context(_,_,_,_,_),Publications)'
        )['Publications'], 0)


if __name__ == '__main__':
    unittest.main()
