"""Issue #54: a settled exclusion branch must be reusable in its own context."""
import json
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class ClosedHistoryReplayTests(unittest.TestCase):
    def test_u4_round12_warm_and_cold_converge_without_invalid_cache_entries(self):
        tests = Path(__file__).resolve().parents[1]
        record = json.loads((tests / 'data/history_u4_r12.json').read_text())
        warm = PeTTaChainer()
        warm.set_query_metrics(True)
        janus.consult(str(tests / 'branch_cache_probe.pl'))
        janus.query_once('branch_probe_install')
        at = 0
        for snap in record['snaps']:
            for name, args in record['calls'][at:snap['n']]:
                getattr(warm, name)(*args)
            at = snap['n']
            warm.query_many_refs(snap['goals'], steps=2000)
            self.assertEqual(janus.query_once('branch_probe_invalid(Rows)')['Rows'], [])
        goals = snap['goals']
        position = goals.index('(: $prf (Degraded power-plant t13) $tv)')
        # Match the review probe: refresh at 2000, then at 20000. Needed
        # readers held stale during a query refresh on the following query.
        warm.query_many_refs(goals, steps=2000)
        warm_answer = warm.query_many_refs(goals, steps=20000)[position]
        self.assertEqual(janus.query_once('branch_probe_invalid(Rows)')['Rows'], [])
        self.assertGreater(janus.query_once(
            'aggregate_all(count,branch_probe_context(_,_,_,_,_),Publications)'
        )['Publications'], 0)
        self.assertEqual(janus.query_once(
            "findall([_K,_E],'&sk_branch_wanted'(_,_H,_K,_,_E),Rows)"
        )['Rows'], [])
        cold = PeTTaChainer()
        for name, args in record['calls']:
            getattr(cold, name)(*args)
        cold_answer = cold.query_many_refs(goals, steps=20000)[position]
        self.assertEqual(janus.query_once('branch_probe_invalid(Rows)')['Rows'], [])
        self.assertAlmostEqual(warm_answer[0].tv[1], 0.12665, places=12)
        self.assertAlmostEqual(warm_answer[0].tv[1], cold_answer[0].tv[1], places=12)
        # Re-querying also refines population estimates. The reviewed round-2
        # cold build changes to this same value; neither history may get stuck
        # at a different value when the estimates subsequently refresh.
        for _ in range(3):
            warm_answer = warm.query_many_refs(goals, steps=20000)[position]
            cold_answer = cold.query_many_refs(goals, steps=20000)[position]
            self.assertAlmostEqual(warm_answer[0].tv[1], cold_answer[0].tv[1], places=12)
            self.assertEqual(janus.query_once('branch_probe_invalid(Rows)')['Rows'], [])


if __name__ == '__main__':
    unittest.main()
