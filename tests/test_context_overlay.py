"""Overlay behavior and the boundary that keeps assumptions out of MAIN.

CTX_OVERLAY_BROKEN selects a deliberately broken in-memory implementation for
negative-control runs; normal unittest discovery always uses the real runtime.
"""
import os
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestContextOverlay(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_context_reuse_threshold(0)
        self.addCleanup(self.h.set_context_reuse_threshold, 0.000001)
        janus.consult(str(Path(__file__).with_name("context_overlay_probe.pl")))
        mode = os.environ.get("CTX_OVERLAY_BROKEN", "none")
        janus.query_once("overlay_probe_install(Mode)", {"Mode": mode})

    def answers(self, goal, handler=None):
        return (handler or self.h).query_many_refs([f"(: $p {goal} $tv)"], steps=2000)[0]

    def strength(self, goal, handler=None):
        rows = self.answers(goal, handler)
        self.assertEqual(len(rows), 1, rows)
        return rows[0].tv[1]

    def diagnostic(self, handler):
        handler.add_atoms_no_check([
            '(: diagnostic (Implication (Cause $t) (Effect $t)) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: (no_inverse prediction) (Implication (Action $t) (Effect $t)) (CTV (STV 0.4 1) (STV 0.4 1)))',
            '(: observed-old (Effect old) (STV 1 1))',
            '(: cause-prior (Cause now) (STV 0.3 0.8))',
        ])
        handler._call("set-base-rate", [f"{handler.kb} (Cause $t) (STV 0.3 0.9)"])

    def test_assumption_reaches_cause_through_induction(self):
        self.diagnostic(self.h)
        self.assertAlmostEqual(self.strength("(Cause now)"), .3)
        # Jeffrey update is .2939; the existing MAIN revision yields .294434.
        # Its confidence overcount is intentionally outside this change.
        self.assertAlmostEqual(
            self.strength("(Assuming (Action now) (Cause now))"),
            .294434361302045, delta=1e-6,
        )

    def test_independent_history_has_no_local_rows_or_views(self):
        self.h.add_atoms_no_check([
            '(: h0 (History t0) (STV 0.3 0.8))',
            '(: n0 (Next t0 t1) (STV 1 1))',
            '(: n1 (Next t1 t2) (STV 1 1))',
            '(: (no_inverse persists) (Implication (And (Next $p $t) (History $p)) (History $t)) (CTV (STV 0.7 1) (STV 0.3 1)))',
            '(: (no_inverse outcome) (Implication (And (Action $t) (History $t)) (Outcome $t)) (STV 1 1))',
            # Action reaches History(trigger) through inversion. The same
            # predicate's t0..t2 history has no dependency on that assumption.
            '(: trigger-prior (History trigger) (STV 0.3 0.8))',
            '(: diagnostic (Implication (History trigger) (Signal trigger)) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: (no_inverse signal) (Implication (Action t2) (Signal trigger)) (CTV (STV 0.4 1) (STV 0.4 1)))',
        ])
        expected = self.strength("(History t2)")
        # Keep MAIN's history rows and views, but force a cold merge read.
        # Independent work performed while C reads must warm MAIN, not C.
        janus.query_once(
            "'remove-data-rows!'('&sk_merged',[_H,['sk-key',['History',_T],[Kb,'MAIN','Nil']],_D,_V],_)",
            {"Kb": self.h.kb},
        )
        self.assertAlmostEqual(self.strength("(Assuming (Action t2) (Outcome t2))"), expected)
        local = janus.query_once("overlay_probe_local(Rows)")["Rows"]
        history = [row for space, head, row in local if space in ("&sk_latest", "&sk_view", "&sk_merged") and head == "History"]
        self.assertEqual(history, [])
        self.assertTrue(janus.query_once(
            "once('&sk_merged'(_,['sk-key',['History',t2],[Kb,'MAIN','Nil']],_,_))",
            {"Kb": self.h.kb},
        )["truth"])
        self.assertFalse(janus.query_once("context_entry(_,_, '&sk_row',_,_)")["truth"])

    def test_shared_main_evidence_keeps_conditioning(self):
        self.h.add_atoms_no_check([
            '(: shared (Shared x) (STV 0.3 0.8))',
            '(: (no_inverse copy) (Implication (And (Action x) (Shared x)) (Derived x)) (STV 1 1))',
        ])
        self.strength("(Shared x)")
        self.assertAlmostEqual(
            self.strength("(Assuming (Action x) (And (Shared x) (Derived x)))"),
            .3, delta=1e-6,
        )

    def test_threshold_is_replayed_by_timed_worker(self):
        self.h.add_atoms_no_check([
            '(: (no_inverse effect) (Implication (Action now) (Effect now)) (STV 1 1))',
        ])
        self.h.set_context_reuse_threshold(1e100)
        query = '(: $p (Assuming (Action now) (Effect now)) $tv)'
        self.assertEqual(self.h.query(query, steps=200, timeout_sec=0), [])
        self.assertEqual(self.h.query(query, steps=200, timeout_sec=30), [])
        for invalid in (-1, float("inf"), float("nan")):
            with self.assertRaises(ValueError):
                self.h.set_context_reuse_threshold(invalid)

    def test_cleanup_keeps_only_assumption_independent_main_work(self):
        self.diagnostic(self.h)
        fresh = PeTTaChainer()
        self.diagnostic(fresh)
        alone = self.answers("(Cause now)", fresh)[0].tv
        self.strength("(Assuming (Action now) (Cause now))")
        after = self.answers("(Cause now)")[0].tv
        self.assertEqual(after, alone)
        leaks = janus.query_once("overlay_probe_main_leaks(Kb,Rows)", {"Kb": self.h.kb})["Rows"]
        self.assertEqual(leaks, [])
        self.assertFalse(janus.query_once("context_entry(_,_,_,_,_)")["truth"])
        self.assertFalse(janus.query_once("context_seed(_,_,_)")["truth"])
        self.assertEqual(self.h._call("cached-base-rate", [f"{self.h.kb} (Cause $t)"]), ["((STV 0.3 0.9))"])
