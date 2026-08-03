import unittest

from pettachainer import PeTTaChainer


class TestPeTTaChainer(unittest.TestCase):
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

    def test_predicate_logic_config_or_introduction(self):
        handler = PeTTaChainer(logic_config="predicate_logic")
        handler.add_atom("(: a (A) (STV 1.0 1.0))")

        proofs = handler.query("(: $prf (Or (A) (B)) $tv)", steps=20, timeout_sec=0)

        self.assertTrue(proofs)


if __name__ == "__main__":
    unittest.main()
