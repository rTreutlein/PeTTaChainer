import os
import re
import unittest
import warnings
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from pettachainer import PeTTaChainer


class TestPeTTaChainer(unittest.TestCase):
    def test_base_rate_smoothing_applies_in_process_and_to_timed_queries(self):
        handler = PeTTaChainer()
        handler.set_evidence_confidence_k(1)
        self.addCleanup(handler.set_evidence_confidence_k, 800)
        handler.set_base_rate_smoothing(True)
        handler.add_atoms_no_check(
            ["(: sensor (Implication (Leak $u) (Alarm $u)) (CTV (STV 0.9 1.0) (STV 0.2 1.0)))"]
            + [f"(: l{i} (Leak u{i}) (STV 0 1))" for i in range(1, 5)]
            + [f"(: a{i} (Alarm u{i}) (STV {1 if i == 3 else 0} 1))" for i in range(1, 5)]
            + ["(: aq (Alarm q) (STV 1 1))"]
        )
        # No leak among four units: the smoothed leak rate keeps a leak on
        # the alarmed unit q possible, live and in a timed query.
        for timeout_sec in (0, 30):
            with self.subTest(timeout_sec=timeout_sec):
                self.assertEqual(
                    handler.query("(: $prf (Leak q) $tv)", steps=400, timeout_sec=timeout_sec),
                    ["(: ((inverted sensor with cpu cpu) aq) (Leak q) "
                     "(STV 0.21599999999999994 0.43979285736925194))"],
                )

    def test_rule_refinement_applies_in_process_and_to_timed_queries(self):
        handler = PeTTaChainer()
        handler.set_rule_refinement(True)
        handler.add_atoms_no_check([
            "(: a1 (A a) (STV 1.0 0.9))",
            "(: a2 (A b) (STV 1.0 0.9))",
            "(: b1 (B a) (STV 1.0 0.9))",
            "(: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0)))",
        ])
        # The instance a revises the rule's stated truth, live and in the
        # subprocess a timed query spawns.
        for timeout_sec in (0, 30):
            with self.subTest(timeout_sec=timeout_sec):
                result = handler.query(
                    "(: $prf (B b) $tv)", steps=400, timeout_sec=timeout_sec
                )
                self.assertEqual(
                    result,
                    ["(: (by ab a2) (B b) (STV 0.8000224974690348 0.9000097638542305))"],
                )

    def test_evidence_confidence_k_applies_in_process_and_to_timed_queries(self):
        handler = PeTTaChainer()
        handler.set_evidence_confidence_k(1)
        self.addCleanup(handler.set_evidence_confidence_k, 800)
        handler.add_atoms_no_check([
            "(: n-1 (Member h1 Normal) (STV 1 1))",
            "(: l-1 (Member h1 Leak) (STV 1 1))",
            "(: n-2 (Member h2 Normal) (STV 1 1))",
            "(: l-2 (Member h2 Leak) (STV 0 1))",
        ])
        # Two observed members give confidence 2/(2+k) with k = 1, both live
        # and in the subprocess that a timed query spawns.
        for timeout_sec in (0, 30):
            with self.subTest(timeout_sec=timeout_sec):
                result = handler.query(
                    "(: $prf (Inheritance Normal Leak) $tv)",
                    steps=100,
                    timeout_sec=timeout_sec,
                )
                self.assertEqual(len(result), 1)
                self.assertIn("(STV 0.5 0.6666666666666666)", result[0])

    def test_bayes_prior_count_applies_in_process_and_to_timed_queries(self):
        handler = PeTTaChainer()
        handler.set_bayes_prior_count(1e6)
        self.addCleanup(handler.set_bayes_prior_count, 0.2)
        handler.add_atoms_no_check(
            ["(: sensor (Implication (Leak $u) (Alarm $u)) (CTV (STV 0.9 0.01) (STV 0.2 1.0)))"]
            + [f"(: l{i} (Leak u{i}) (STV {1 if i == 1 else 0} 1))" for i in range(1, 5)]
            + ["(: aq (Alarm q) (STV 1 1))"]
        )
        # A prior this strong outweighs the weakly supported likelihood, so
        # the alarm says nothing and the leak rate of one in four stands, live
        # and in the subprocess that a timed query spawns.
        for timeout_sec in (0, 30):
            with self.subTest(timeout_sec=timeout_sec):
                result = handler.query("(: $prf (Leak q) $tv)", steps=400, timeout_sec=timeout_sec)
                self.assertEqual(len(result), 1)
                strength = float(re.search(r"\(STV ([^ ]+) [^)]+\)\)$", result[0]).group(1))
                self.assertAlmostEqual(strength, 0.25, delta=1e-5)

    def test_rule_search_ignores_base_rate_strength(self):
        answers = []
        for rate in (None, 0.0, 1.0):
            with self.subTest(rate=rate):
                handler = PeTTaChainer()
                handler.add_atoms_no_check([
                    "(: low (LowInput) (STV 0.0 1.0))",
                    "(: high (HighInput) (STV 1.0 1.0))",
                    "(: lowRule (Implication (LowInput) (PriorityGoal)) "
                    "(CTV (STV 1.0 0.9) (STV 0.0 1.0)))",
                    "(: highRule (Implication (HighInput) (PriorityGoal)) "
                    "(CTV (STV 1.0 0.8) (STV 0.0 1.0)))",
                ])
                if rate is not None:
                    handler.handler.process_metta_string(
                        f"!(set-base-rate {handler.kb} (LowInput) (STV {rate} 1.0))"
                    )
                    handler.handler.process_metta_string(
                        f"!(set-base-rate {handler.kb} (HighInput) (STV {1 - rate} 1.0))"
                    )
                result = handler.query(
                    "(: $proof (PriorityGoal) $tv)", steps=2, timeout_sec=0
                )
                answers.append(result)
                # Stored-fact premises cost no expansion, so both rules
                # answer within the budget whatever the base rates are.
                self.assertEqual(len(result), 1)
                self.assertIn("(by lowRule low)", result[0])
                self.assertIn("(by highRule high)", result[0])
        self.assertEqual(answers[0], answers[1])
        self.assertEqual(answers[0], answers[2])

    def test_loads_caller_owned_metta_module(self):
        with TemporaryDirectory() as directory:
            module = Path(directory) / "application_formula.metta"
            module.write_text("(= (application-formula) 42)\n", encoding="utf-8")
            handler = PeTTaChainer()

            handler.load_metta_file(module)

            self.assertEqual(
                handler.evaluate_statement("(application-formula)"),
                "42",
            )

    def test_remove_statement_is_deprecated(self):
        handler = PeTTaChainer()
        handler.add_atom("(: deprecated_remove (DeprecatedRemove) (STV 1.0 1.0))")

        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            handler.remove_statement("deprecated_remove")

        self.assertEqual(len(caught), 1)
        self.assertIs(caught[0].category, DeprecationWarning)
        self.assertIn("does not forget durable proofs", str(caught[0].message))

    def test_query_metrics_env_skips_timed_queries_with_warning(self):
        with TemporaryDirectory() as directory:
            metrics_path = Path(directory) / "query-metrics.jsonl"
            with patch.dict(
                os.environ,
                {"PETTACHAINER_QUERY_METRICS_PATH": str(metrics_path)},
            ):
                handler = PeTTaChainer()
            handler.add_atom("(: timed_m (TimedMetric) (STV 1.0 1.0))")

            with warnings.catch_warnings(record=True) as caught:
                warnings.simplefilter("always")
                results = handler.query(
                    "(: $prf (TimedMetric) $tv)", steps=3, timeout_sec=30
                )

            self.assertEqual(
                results,
                ["(: timed_m (TimedMetric) (STV 1.0 1.0))"],
            )
            self.assertTrue(
                any("query metrics skipped" in str(w.message) for w in caught)
            )
            self.assertFalse(metrics_path.exists())

    def test_query_metric_rows_are_parsed_exactly(self):
        self.assertEqual(
            PeTTaChainer._parse_query_metric_rows(
                [
                    "(query-metric agenda-pops 7)",
                    "(query-metric candidate-comparisons 2.5e1)",
                ]
            ),
            {"agenda_pops": 7, "candidate_comparisons": 25},
        )

        malformed_results = [
            [],
            "(query-metric agenda-pops 1)",
            ["(query-metric agenda-pops nan)"],
            ["(query-metric Agenda-pops 1)"],
            ["(query-metric agenda-pops 1) trailing"],
            ["(query-metric agenda-pops 1)", 2],
            [
                "(query-metric agenda-pops 1)",
                "(query-metric agenda-pops 2)",
            ],
        ]
        for rows in malformed_results:
            with self.subTest(rows=rows):
                with self.assertRaises(RuntimeError):
                    PeTTaChainer._parse_query_metric_rows(rows)

    def test_query_and_query_many_record_the_same_metric_schema(self):
        handler = PeTTaChainer()
        handler.add_atom("(: metric_schema (MetricSchema) (STV 1.0 1.0))")
        handler.set_query_metrics(True)

        single = handler.query(
            "(: $prf (MetricSchema) $tv)", steps=3, timeout_sec=0
        )
        single_metrics = handler.last_query_metrics()
        batch = handler.query_many(
            ["(: $prf (MetricSchema) $tv)"], steps=3, timeout_sec=0
        )
        batch_metrics = handler.last_query_metrics()

        self.assertEqual(single, batch[0])
        self.assertEqual(set(single_metrics), set(batch_metrics))
        self.assertEqual(single_metrics["kind"], "query")
        self.assertEqual(batch_metrics["kind"], "query_many")
        self.assertEqual(single_metrics["roots"], 1)
        self.assertEqual(batch_metrics["roots"], 1)
        self.assertEqual(single_metrics["steps"], 3)
        self.assertEqual(batch_metrics["steps"], 3)
        self.assertGreaterEqual(single_metrics["wall_seconds"], 0.0)
        self.assertGreaterEqual(batch_metrics["wall_seconds"], 0.0)

    def test_no_check_ingestion_rejects_malformed_tv_loudly(self):
        handler = PeTTaChainer()

        with self.assertRaises(Exception) as ctx:
            handler.add_atoms_no_check(["(: bad_tv (Cat tom) (stv 0.9 0.9))"])

        self.assertIn("Type mismatch", str(ctx.exception))

    def test_query_many_preserves_order_and_empty_roots(self):
        handler = PeTTaChainer()
        handler.add_atom("(: batch_a (BatchA) (STV 1.0 1.0))")
        handler.add_atom("(: batch_b (BatchB) (STV 0.5 0.8))")
        handler.add_atom("(: batch_c1 (BatchC one) (STV 1.0 1.0))")
        handler.add_atom("(: batch_c2 (BatchC two) (STV 1.0 1.0))")

        results = handler.query_many(
            [
                "(: $prf (BatchA) $tv)",
                "(: $prf (BatchB) $tv)",
                "(: $prf (BatchMissing) $tv)",
                "(: $prf (BatchC $x) $tv)",
            ],
            steps=3,
            timeout_sec=0,
        )

        self.assertEqual(len(results), 4)
        self.assertEqual(results[0], ["(: batch_a (BatchA) (STV 1.0 1.0))"])
        self.assertEqual(results[1], ["(: batch_b (BatchB) (STV 0.5 0.8))"])
        self.assertEqual(results[2], [])
        self.assertEqual(
            results[3],
            [
                "(: batch_c1 (BatchC one) (STV 1.0 1.0))",
                "(: batch_c2 (BatchC two) (STV 1.0 1.0))",
            ],
        )
        self.assertEqual(handler.query_many([], timeout_sec=0), [])

    def test_query_metrics_are_opt_in_and_reset_per_query(self):
        handler = PeTTaChainer()
        handler.add_atom("(: metric_a (MetricA) (STV 1.0 1.0))")
        handler.set_query_metrics(True)

        first = handler.query_many(
            ["(: $prf (MetricA) $tv)"], steps=5, timeout_sec=0
        )
        first_metrics = handler.last_query_metrics()
        second = handler.query_many(
            ["(: $prf (MetricA) $tv)"], steps=0, timeout_sec=0
        )
        second_metrics = handler.last_query_metrics()

        self.assertEqual(first, second)
        self.assertGreater(
            first_metrics["skeleton_nodes_after"],
            first_metrics["skeleton_nodes_before"],
        )
        self.assertEqual(
            second_metrics["skeleton_nodes_before"],
            first_metrics["skeleton_nodes_after"],
        )
        self.assertEqual(first_metrics["expansions"], 1)
        self.assertEqual(second_metrics["expansions"], 0)
        self.assertEqual(second_metrics["roots"], 1)
        self.assertEqual(second_metrics["steps"], 0)

    def test_query_many_materialization_saves_derived_proof_trees(self):
        handler = PeTTaChainer()
        handler.add_atom("(: materialize_seed (MaterializeSeed) (STV 1.0 1.0))")
        handler.add_atom(
            "(: materialize_middle_rule "
            "(Implication (MaterializeSeed) (MaterializeMiddle)) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        handler.add_atom(
            "(: materialize_root_rule "
            "(Implication (MaterializeMiddle) (MaterializeRoot)) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )

        with self.assertRaises(ValueError):
            handler.select_facts(["(MaterializeMiddle)", "(MaterializeRoot)"])

        queries = [
            "(: $prf (MaterializeRoot) $tv)",
            "(: $prf (MaterializeMissing) $tv)",
        ]
        results = handler.query_many_materialization(queries, steps=2000)

        self.assertEqual(len(results), 2)
        self.assertIn("(MaterializeRoot)", results[0][0])
        self.assertEqual(results[1], [])
        self.assertEqual(len(handler.select_facts("(MaterializeMiddle)")), 1)
        self.assertEqual(len(handler.select_facts("(MaterializeRoot)")), 1)

        for steps in (10, 100):
            repeated = handler.query_many_materialization(queries, steps=steps)
            self.assertIn("(MaterializeRoot)", repeated[0][0])
            self.assertEqual(repeated[1], [])

        self.assertEqual(handler.query_many_materialization([], steps=20), [])

    def test_refined_materialization_replaces_zero_budget_incumbent(self):
        handler = PeTTaChainer()
        root = (
            "(: $proof "
            "(Inheritance (PressureNormal old oxygen-scrubber) "
            "(SealLeak old oxygen-scrubber)) $tv)"
        )

        def add_states(target, rows):
            statements = []
            terms = []
            for name, leak, normal in rows:
                state_terms = [
                    f"(Inheritance (State {name}) "
                    "(EquipmentState old oxygen-scrubber))",
                    f"(Inheritance (State {name}) "
                    "(SealLeak old oxygen-scrubber))",
                    f"(Inheritance (State {name}) "
                    "(PressureNormal old oxygen-scrubber))",
                ]
                statements.extend(
                    [
                        f"(: {name}-equipment {state_terms[0]} (STV 1 1))",
                        f"(: {name}-leak {state_terms[1]} (STV {leak} 1))",
                        f"(: {name}-normal {state_terms[2]} (STV {normal} 1))",
                    ]
                )
                terms.extend(state_terms)
            target.add_atoms_no_check(statements)
            seeds = target.select_facts(terms)
            target.forward_chain(seeds, steps=2 * len(seeds))

        initial_states = [("s1", 1, 0), ("s2", 0, 1), ("s3", 0, 1)]
        added_states = [("s4", 1, 1)]
        add_states(handler, initial_states)
        original = handler.query_many_materialization([root], steps=100)
        self.assertEqual(
            handler.query_many_materialization([root], steps=0), original
        )

        add_states(handler, added_states)
        refined = handler.query_many_materialization([root], steps=100)

        fresh = PeTTaChainer()
        add_states(fresh, initial_states + added_states)
        fresh_result = fresh.query_many_materialization([root], steps=100)

        self.assertNotEqual(refined, original)
        self.assertEqual(len(refined[0]), 1)
        self.assertEqual(len(fresh_result[0]), 1)
        self.assertEqual(
            handler.query_many_materialization([root], steps=0), refined
        )

        # The refined incumbent equals the fresh KB's answer: the same proof
        # and truth value. A base rate does not count members derived through
        # it, so nothing is left to settle by re-querying.
        requery = handler.query_many_materialization([root], steps=200)

        # Context sample numbers in proof labels are per-query counters, and a
        # subproof printed once as (shared N P) and later as (shared N) is the
        # same proof as P written out each time.
        def inline_shared(text):
            tokens = re.findall(r"\(|\)|[^\s()]+", text)
            pos = 0

            def parse():
                nonlocal pos
                token = tokens[pos]
                pos += 1
                if token != "(":
                    return token
                items = []
                while tokens[pos] != ")":
                    items.append(parse())
                pos += 1
                return items

            shared = {}

            def inline(term):
                if not isinstance(term, list):
                    return term
                if term and term[0] == "shared":
                    if len(term) == 3:
                        shared[term[1]] = inline(term[2])
                    return shared[term[1]]
                return [inline(item) for item in term]

            def show(term):
                return term if not isinstance(term, list) else "(" + " ".join(map(show, term)) + ")"

            return show(inline(parse()))

        def proof_shape(answers):
            return [
                [
                    re.sub(
                        r"\(STV [^ ]+ [^)]+\)\)$",
                        "(STV _ _))",
                        re.sub(r"\(ctx proof \d+\)", "(ctx proof _)", inline_shared(row.strip())),
                    )
                    for row in batch
                ]
                for batch in answers
            ]

        def tv(answers):
            return map(float, re.findall(r"\(STV ([^ ]+) ([^)]+)\)\)$", answers[0][0].strip())[-1])

        # Truth values compare up to summation order.
        for answers, reference in ((refined, fresh_result), (requery, refined)):
            self.assertEqual(proof_shape(answers), proof_shape(reference))
            for value, expected in zip(tv(answers), tv(reference)):
                self.assertAlmostEqual(value, expected, delta=1e-12)

    def test_completed_proofs_survive_query_search_reset(self):
        handler = PeTTaChainer()
        handler.add_atom("(: durable_a (DurableA) (STV 1.0 0.8))")
        handler.add_atom("(: durable_x (DurableX) (STV 1.0 0.8))")
        handler.add_atom(
            "(: durable_ax_rule "
            "(Implication (And (DurableA) (DurableX)) (DurableGoal)) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        query = ["(: $proof (DurableGoal) $tv)"]

        first = handler.query_many(query, steps=100, timeout_sec=0)
        self.assertTrue(first[0])
        self.assertEqual(
            handler.query_many(query, steps=0, timeout_sec=0),
            first,
        )

        handler.add_atom("(: durable_y (DurableY) (STV 1.0 0.8))")
        handler.add_atom(
            "(: durable_ay_rule "
            "(Implication (And (DurableA) (DurableY)) (DurableGoal)) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        refined = handler.query_many(query, steps=100, timeout_sec=0)

        self.assertTrue(refined[0])
        self.assertNotEqual(refined, first)
        self.assertEqual(
            handler.query_many(query, steps=0, timeout_sec=0),
            refined,
        )

    def test_materialized_shared_evidence_keeps_reconstructible_proofs(self):
        handler = PeTTaChainer()
        for name in ("Shared", "Left", "Right"):
            handler.add_atom(
                f"(: materialized_{name.lower()} ({name}) (STV 1.0 0.8))"
            )
        for side in ("Left", "Right"):
            handler.add_atom(
                f"(: materialized_{side.lower()}_rule "
                f"(Implication (And (Shared) ({side})) (MaterializedSharedGoal)) "
                f"(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
            )
        query = ["(: $proof (MaterializedSharedGoal) $tv)"]

        materialized = handler.query_many_materialization(query, steps=200)

        self.assertTrue(materialized[0])
        self.assertEqual(
            handler.query_many(query, steps=0, timeout_sec=0),
            materialized,
        )
        self.assertEqual(
            handler.query_many_materialization(query, steps=10),
            materialized,
        )

    def test_forward_chain_derives_fact_visible_to_backward_query(self):
        handler = PeTTaChainer()
        handler.add_atom("(: edge_ab (Edge A B) (STV 1.0 1.0))")
        handler.add_atom("(: edge_bc (Edge B C) (STV 1.0 1.0))")
        handler.add_atom(
            "(: edge_to_path (Implication (Edge $x $y) (Path $x $y)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        handler.add_atom(
            "(: path_step (Implication (And (Path $x $y) (Edge $y $z)) (Path $x $z)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )

        seeds = handler.select_facts(["(Edge A B)", "(Edge B C)"])
        result = handler.forward_chain(seeds, steps=50)

        self.assertIn("Path A C", str(result))
        proofs = handler.query("(: $prf (Path A C) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)

    def test_select_facts_builds_an_initial_forward_seed(self):
        handler = PeTTaChainer()
        handler.add_atom("(: high_fact (HighPriority) (STV 1.0 1.0))")
        handler.add_atom("(: low_fact (LowPriority) (STV 1.0 0.8))")
        handler.add_atom(
            "(: low_to_goal (Implication (LowPriority) (DeltaGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )

        seed = handler.select_facts("(LowPriority)")
        # One step computes the goal's row and the other builds on it.
        result = handler.forward_chain(seed, steps=2)

        self.assertIn("DeltaGoal", str(result))
        proofs = handler.query("(: $prf (DeltaGoal) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)
        self.assertEqual(handler.forward_chain(seed, steps=2), [])

    def test_forward_chain_accepts_canonical_facts(self):
        handler = PeTTaChainer()
        handler.add_atom("(: high_fact (HighPriority) (STV 1.0 1.0))")
        handler.add_atom("(: low_fact (LowPriority) (STV 1.0 0.8))")
        handler.add_atom(
            "(: low_to_goal (Implication (LowPriority) (FactSeedGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )

        canonical_fact = handler.select_facts("(LowPriority)")[0]
        result = handler.forward_chain(canonical_fact, steps=2)

        self.assertIn("FactSeedGoal", str(result))
        proofs = handler.query("(: $prf (FactSeedGoal) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)

    def test_all_facts_supports_full_kb_forward_chaining(self):
        handler = PeTTaChainer()
        handler.add_atom("(: high_fact (HighPriority) (STV 1.0 1.0))")
        handler.add_atom("(: low_fact (LowPriority) (STV 1.0 0.8))")
        handler.add_atom(
            "(: low_to_goal (Implication (LowPriority) (FactSeedGoal2)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )

        result = handler.forward_chain(handler.all_facts(), steps=2)

        self.assertIn("FactSeedGoal2", str(result))
        proofs = handler.query("(: $prf (FactSeedGoal2) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)

    def test_forward_chain_outputs_can_seed_the_next_run(self):
        handler = PeTTaChainer()
        handler.add_atom("(: seed (A) (STV 1.0 1.0))")
        handler.add_atom(
            "(: a_to_b (Implication (A) (B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        handler.add_atom(
            "(: b_to_c (Implication (B) (C)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )

        first_changes = handler.forward_chain(handler.select_facts("(A)"), steps=2)
        second_changes = handler.forward_chain(first_changes, steps=2)

        self.assertIn("(B)", str(first_changes))
        self.assertIn("(C)", str(second_changes))

    def test_select_facts_rejects_a_missing_seed(self):
        handler = PeTTaChainer()

        with self.assertRaises(ValueError):
            handler.select_facts("(MissingSeed)")

    def test_default_logic_keeps_pln_or_semantics(self):
        handler = PeTTaChainer()
        handler.add_atom("(: a (A) (STV 1.0 1.0))")

        proofs = handler.query(
            "(: $prf (Or (A) (B)) $tv)", steps=20, timeout_sec=30
        )

        self.assertEqual(proofs, [])

    def test_stv_rule_query_patterns_preserve_variable_headed_terms(self):
        rules = [
            "(: morebydiff (Implication (MoreBy $s $x $y $n $u) (More $s $x $y)) (STV 1.0 0.99))",
            "(: pole_more (Implication (And (ScaleOpposite $a $b) (More $a $x $y)) (More $b $y $x)) (STV 1.0 0.99))",
            "(: pole_moreby_more (Implication (And (ScaleOpposite $a $b) (MoreBy $a $x $y $n $u)) (More $b $y $x)) (STV 1.0 0.99))",
            "(: opposite (ScaleOpposite light heavy) (STV 1.0 0.99))",
            "(: gap (MoreBy light pony horse 30 kilogram) (STV 1.0 0.99))",
        ]
        handler = PeTTaChainer()
        for rule in rules:
            handler.add_atom(rule)

        proofs = handler.query("(: $prf (More heavy horse pony) $tv)", steps=100, timeout_sec=0)

        # Both derivations use the same two facts through STV rules, which
        # lifting cannot factor: the more confident derivation stands.
        self.assertEqual(len(proofs), 1)
        self.assertIn("by pole_moreby_more ", proofs[0])

    def test_conjunction_frontier_keeps_individual_derivations(self):
        handler = PeTTaChainer()
        for statement in [
            "(: e_paint (Member event paint) (STV 1.0 0.99))",
            "(: e_agent (Agent event dario) (STV 1.0 0.99))",
            "(: e_past (Past event) (STV 1.0 0.99))",
            "(: e_name (Name dario Dario) (STV 1.0 0.99))",
            "(: e_denial (And (Member event paint) (Agent event dario)) (STV 0.0 0.99))",
        ]:
            handler.add_atom(statement)

        present = handler.query(
            "(: $prf (And (Member $e paint) (Agent $e dario)) $tv)",
            steps=100,
            timeout_sec=0,
        )
        past = handler.query(
            "(: $prf (And (Member $e paint) (Agent $e $d) (Name $d Dario) (Past $e)) $tv)",
            steps=100,
            timeout_sec=0,
        )

        self.assertEqual(len(present), 1)
        self.assertIn("merge/revision", present[0])
        self.assertIn("e_denial", present[0])
        self.assertIn("conjunction e_paint e_agent", present[0])
        self.assertTrue(past)

    def test_map_dist_lambda_survives_python_validation_and_compilation(self):
        handler = PeTTaChainer()
        handler.add_atom(
            "(: foot_to_meter "
            "(Implication "
            "(MapDist (|-> ($x) (* $x 0.3048)) (Measure $e $s $d foot) $d -> $out) "
            "(Measure $e $s $out meter)) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        handler.add_atom(
            "(: measured (Measure alice tall (ParticleFromPairs ((6.0 1.0))) foot) (STV 1.0 1.0))"
        )

        proofs = handler.query(
            "(: $prf (Measure alice tall $distance meter) $tv)",
            steps=20,
            timeout_sec=0,
        )

        self.assertEqual(len(proofs), 1)
        self.assertIn("(by foot_to_meter measured)", proofs[0])
        self.assertIn("ParticleDist", proofs[0])

    def test_rule_proof_names_are_data_in_by_constructor(self):
        for name in ("ordinary_rule", "flip", "empty", "match"):
            with self.subTest(name=name):
                handler = PeTTaChainer()
                handler.add_atom("(: premise (A) (STV 1.0 1.0))")
                handler.add_atom(
                    f"(: {name} (Implication (A) (B)) "
                    "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
                )

                proofs = handler.query("(: $prf (B) $tv)", steps=10, timeout_sec=0)

                self.assertEqual(len(proofs), 1)
                self.assertIn(f"(by {name} premise)", proofs[0])

    def test_predicate_logic_config_or_introduction(self):
        handler = PeTTaChainer(logic_config="predicate_logic")
        handler.add_atom("(: a (A) (STV 1.0 1.0))")

        proofs = handler.query("(: $prf (Or (A) (B)) $tv)", steps=20, timeout_sec=0)

        self.assertTrue(proofs)


if __name__ == "__main__":
    unittest.main()
