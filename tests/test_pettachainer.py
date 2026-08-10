import unittest

from pettachainer import PeTTaChainer


class TestPeTTaChainer(unittest.TestCase):
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

        results = handler.query_many_materialization(
            [
                "(: $prf (MaterializeRoot) $tv)",
                "(: $prf (MaterializeMissing) $tv)",
            ],
            steps=20,
        )

        self.assertEqual(len(results), 2)
        self.assertIn("(MaterializeRoot)", results[0][0])
        self.assertEqual(results[1], [])
        self.assertEqual(len(handler.select_facts("(MaterializeMiddle)")), 1)
        self.assertEqual(len(handler.select_facts("(MaterializeRoot)")), 1)
        self.assertEqual(handler.query_many_materialization([], steps=20), [])

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
        result = handler.forward_chain(seed, steps=1)

        self.assertIn("DeltaGoal", str(result))
        proofs = handler.query("(: $prf (DeltaGoal) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)
        self.assertEqual(handler.forward_chain(seed, steps=1), [])

    def test_forward_chain_accepts_canonical_facts(self):
        handler = PeTTaChainer()
        handler.add_atom("(: high_fact (HighPriority) (STV 1.0 1.0))")
        handler.add_atom("(: low_fact (LowPriority) (STV 1.0 0.8))")
        handler.add_atom(
            "(: low_to_goal (Implication (LowPriority) (FactSeedGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )

        canonical_fact = handler.select_facts("(LowPriority)")[0]
        result = handler.forward_chain(canonical_fact, steps=1)

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

        first_changes = handler.forward_chain(handler.select_facts("(A)"), steps=1)
        second_changes = handler.forward_chain(first_changes, steps=1)

        self.assertIn("(B)", str(first_changes))
        self.assertIn("(C)", str(second_changes))

    def test_select_facts_rejects_a_missing_seed(self):
        handler = PeTTaChainer()

        with self.assertRaises(ValueError):
            handler.select_facts("(MissingSeed)")

    def test_default_logic_keeps_pln_or_semantics(self):
        handler = PeTTaChainer()
        handler.add_atom("(: a (A) (STV 1.0 1.0))")

        proofs = handler.query("(: $prf (Or (A) (B)) $tv)", steps=20)

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

        self.assertEqual(len(proofs), 1)
        self.assertIn("merge/revision", proofs[0])
        self.assertIn("by pole_more ", proofs[0])
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
