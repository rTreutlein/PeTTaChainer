"""Overlay behavior and the boundary that keeps assumptions out of MAIN.

CTX_OVERLAY_BROKEN selects a deliberately broken in-memory implementation for
negative-control runs; normal unittest discovery always uses the real runtime.
"""
import os
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class OverlayChecks:
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_context_reuse_threshold(self.threshold)
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

    def test_existential_claim_is_local_and_preserves_binder_scope(self):
        self.h.add_atoms_no_check([
            '(: (no_inverse named) (Implication (Exists ($x) (P $x)) (Named F1)) (STV 1 1))',
        ])
        rows = self.answers('(Assuming (Exists ($x) (P $x)) (Named $x))')
        self.assertEqual(len(rows), 1, rows)
        _, (_, binders, (_, body)), goal = rows[0].statement
        self.assertEqual(goal, ['Named', 'F1'])
        self.assertEqual(binders, [body])
        self.assertTrue(body.startswith('$'), rows[0])
        for _ in range(2):
            rows = self.answers('(Assuming (Exists ($x) (P $x)) (Exists ($z) (P $z)))')
            self.assertEqual(len(rows), 1, rows)
            self.assertEqual(rows[0].statement[2][0], 'Exists')
            self.assertEqual(rows[0].tv, ['STV', 1.0, 1.0])
        self.assertEqual(self.answers('(Exists ($x) (P $x))'), [])
        self.assertEqual(self.answers('(P $x)'), [])
        self.assertEqual(janus.query_once('overlay_probe_main_leaks(Kb,Rows)', {'Kb': self.h.kb})['Rows'], [])

    def test_existential_population_overlays_warm_main_folds(self):
        self.h.add_atoms_no_check([
            '(: p-old (P old a) (STV 0.4 0.8))',
            '(: (no_inverse p-action) (Implication (Action $g) (P $g b)) (STV 1 1))',
        ])
        goal = '(Exists ($x) (P $group $x))'
        before = self.answers(goal)
        self.assertEqual([(r.statement[2][1], r.tv) for r in before], [('old', ['STV', .4, .8])])
        rows = self.answers(f'(Assuming (Action new) {goal})')
        groups = {r.statement[2][2][1]: r.tv[1] for r in rows}
        self.assertEqual(groups, {'old': .4, 'new': 1.0})
        self.assertEqual([(r.statement, r.tv) for r in self.answers(goal)], [(r.statement, r.tv) for r in before])
        self.assertEqual(janus.query_once('overlay_probe_main_leaks(Kb,Rows)', {'Kb': self.h.kb})['Rows'], [])

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
            "'remove-data-rows!'('&sk_context_merge',[_D,_Id,_H,['sk-key',['History',_T],[Kb,'MAIN','Nil']],_R,_Q,_E,_C,_Deps,_V,_F],_)",
            {"Kb": self.h.kb},
        )
        self.assertAlmostEqual(self.strength("(Assuming (Action t2) (Outcome t2))"), expected)
        local = janus.query_once("overlay_probe_local(Rows)")["Rows"]
        history = [row for space, head, row in local if space in ("&sk_context", "&sk_context_merge") and head == "History"]
        self.assertEqual(history, [])
        self.assertTrue(janus.query_once(
            "once('&sk_context_merge'(_,_,_,['sk-key',['History',t2],[Kb,'MAIN','Nil']],_,_,[],_,_,_,_))",
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

    def test_dominated_view_reaches_reader_excluding_main_support(self):
        for threshold in (0, .000001):
            with self.subTest(threshold=threshold):
                self.h.set_context_reuse_threshold(threshold)
                result = janus.query_once(
                    "overlay_probe_filtered_change(Kb,Result)", {"Kb": self.h.kb},
                )["Result"]
                self.assertEqual(result["merged"], result["main"])
                self.assertEqual(result["filtered"][1][3], ["STV", .5, .4])
                self.assertEqual(result["propagate"], "true")

    def test_retiring_shared_main_search_is_deterministic(self):
        result = janus.query_once(
            "overlay_probe_retire_shared(Kb,Count,Left)", {"Kb": self.h.kb},
        )
        self.assertEqual((result["Count"], result["Left"]), (1, 0))

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

    def test_assumed_sample_keeps_instance_tally_local(self):
        self.h._call("set-rule-refinement", [f"{self.h.kb} true"])
        self.h._call("set-positive-only-predicate", [f"{self.h.kb} A"])
        self.h.add_atoms_no_check([
            '(: r (Implication (A $x) (B $x)) (STV 0.5 0.02))',
            '(: a (A old) (STV 1 1))',
            '(: b (B old) (STV 0 1))',
        ])
        goal = "(RuleTruth (Implication (A $x) (B $x)))"
        before = self.answers(goal)[0].tv
        changed = self.answers(f"(Assuming (B old) {goal})")[0].tv
        self.assertNotEqual(changed, before)
        self.assertEqual(janus.query_once("overlay_probe_main_leaks(Kb,Rows)",
                                         {"Kb": self.h.kb})["Rows"], [])
        local = janus.query_once("overlay_probe_local(Rows)")["Rows"]
        self.assertTrue(any(space == "&sk_instance_tally" for space, _, _ in local))
        self.assertEqual(self.answers(goal)[0].tv, before)

    def test_each_of_22_contexts_receives_its_evaluation_allowance(self):
        self.diagnostic(self.h)
        self.strength("(Cause now)")
        # Shared structure is already warm. Each context still needs its own
        # induction update. The former shared remainder ran out after 17.
        rows = self.h.query_many_refs(
            ['(: $p (Assuming (Action now) (Cause now)) $tv)'] * 22,
            steps=10,
        )
        self.assertEqual([len(group) for group in rows], [1] * 22)
        for group in rows:
            self.assertAlmostEqual(group[0].tv[1], .294434361302045, delta=1e-6)

    def test_assumed_member_updates_only_local_base_rate(self):
        self.h.add_atoms_no_check([
            '(: r (Implication (P $t) (Q $t)) (CTV (STV 0.8 1) (STV 0.1 1)))',
            '(: old (P old) (STV 0 1))',
            '(: observed (Q now) (STV 0.5 0.8))',
        ])
        self.strength("(P now)")
        before = self.h._call("cached-base-rate", [f"{self.h.kb} (P $t)"])
        self.strength("(Assuming (P now) (Q now))")
        self.assertEqual(janus.query_once("overlay_probe_main_leaks(Kb,Rows)",
                                         {"Kb": self.h.kb})["Rows"], [])
        # MAIN has one false member; C adds one true member: 1 / 2.
        local = janus.query_once("overlay_probe_local(Rows)")["Rows"]
        self.assertTrue(any(space == "&base_rate_cache" and "['STV',0.5," in row
                            for space, _, row in local), local)
        self.assertTrue(any(space == "&forward_aggregate_state" for space, _, _ in local))
        self.assertEqual(self.h._call("cached-base-rate", [f"{self.h.kb} (P $t)"]), before)

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


class TestContextOverlay(OverlayChecks, unittest.TestCase):
    threshold = 0


class TestContextOverlayThreshold(OverlayChecks, unittest.TestCase):
    threshold = .000001


class TestOverlayWriteBoundary(unittest.TestCase):
    def test_context_stores_have_no_raw_metta_writers(self):
        import re
        root = Path(__file__).resolve().parents[1] / "pettachainer" / "metta"
        stores = set(re.findall(r"context_store\('([^']+)'", (root / "prolog/context_overlay.pl").read_text()))
        violations = []
        for path in root.rglob("*.metta"):
            source = re.sub(r";[^\n]*", "", path.read_text())
            for call in re.finditer(r"\((?:add-atom|remove-atom)\s+([^\s()]+)", source):
                if call[1] in stores or call[1].startswith(("$", "&ctx_")):
                    violations.append((str(path.relative_to(root)), call[0]))
        self.assertEqual(violations, [], "Use the scoped write API for overlay stores")
