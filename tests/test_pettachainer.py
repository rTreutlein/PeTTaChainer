import unittest

from pettachainer import PeTTaChainer


class TestPeTTaChainer(unittest.TestCase):
    def test_forward_chain_derives_fact_visible_to_backward_query(self):
        handler = PeTTaChainer()
        handler.add_atom("(: edge_ab (Edge A B) (STV 1.0 1.0))")
        handler.add_atom("(: edge_bc (Edge B C) (STV 1.0 1.0))")
        handler.add_atoms_no_check([
            "(: edge_to_path (Implication (Premises (Edge $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))",
            "(: path_step (Implication (Premises (Path $x $y) (Edge $y $z)) (Conclusions (Path $x $z))) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))",
        ])

        result = handler.forward_chain(["(Edge A B)", "(Edge B C)"], steps=50)

        self.assertIn("Path A C", str(result))
        proofs = handler.query("(: $prf (Path A C) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)

    def test_forward_chain_can_start_from_selected_term(self):
        handler = PeTTaChainer()
        handler.add_atom("(: high_fact (HighPriority) (STV 1.0 1.0))")
        handler.add_atom("(: low_fact (LowPriority) (STV 1.0 0.8))")
        handler.add_atoms_no_check([
            "(: low_to_goal (Implication (Premises (LowPriority)) (Conclusions (DeltaGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        ])

        result = handler.forward_chain("(LowPriority)", steps=1)

        self.assertIn("DeltaGoal", str(result))
        proofs = handler.query("(: $prf (DeltaGoal) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)
        self.assertEqual(handler.forward_chain("(LowPriority)", steps=1), [])

    def test_forward_chain_can_start_from_selected_facts(self):
        handler = PeTTaChainer()
        handler.add_atom("(: high_fact (HighPriority) (STV 1.0 1.0))")
        handler.add_atom("(: low_fact (LowPriority) (STV 1.0 0.8))")
        handler.add_atoms_no_check([
            "(: low_to_goal (Implication (Premises (LowPriority)) (Conclusions (FactSeedGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        ])

        result = handler.forward_chain_from_facts(["(LowPriority)"], steps=1)

        self.assertIn("FactSeedGoal", str(result))
        proofs = handler.query("(: $prf (FactSeedGoal) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)

    def test_forward_chain_sequence_term_uses_selected_facts(self):
        handler = PeTTaChainer()
        handler.add_atom("(: high_fact (HighPriority) (STV 1.0 1.0))")
        handler.add_atom("(: low_fact (LowPriority) (STV 1.0 0.8))")
        handler.add_atoms_no_check([
            "(: low_to_goal (Implication (Premises (LowPriority)) (Conclusions (FactSeedGoal2))) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        ])

        result = handler.forward_chain(["(LowPriority)"], steps=1)

        self.assertIn("FactSeedGoal2", str(result))
        proofs = handler.query("(: $prf (FactSeedGoal2) $tv)", steps=10, timeout_sec=0)
        self.assertTrue(proofs)

    def test_forward_chain_outputs_can_seed_the_next_run(self):
        handler = PeTTaChainer()
        handler.add_atom("(: seed (A) (STV 1.0 1.0))")
        handler.add_atoms_no_check([
            "(: a_to_b (Implication (Premises (A)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))",
            "(: b_to_c (Implication (Premises (B)) (Conclusions (C))) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))",
        ])

        first_changes = handler.forward_chain("(A)", steps=1)
        second_changes = handler.forward_chain(first_changes, steps=1)

        self.assertIn("(B)", str(first_changes))
        self.assertIn("(C)", str(second_changes))

    def test_forward_chain_from_facts_returns_false_for_missing_seed(self):
        handler = PeTTaChainer()

        result = handler.forward_chain_from_facts(["(MissingSeed)"], steps=1)

        self.assertEqual(result, ["false"])

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
