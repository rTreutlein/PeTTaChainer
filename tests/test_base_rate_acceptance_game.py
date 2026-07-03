import unittest

from pettachainer.simulations.base_rate_acceptance_game import (
    DEFAULT_PREDICATES,
    PredicateSpec,
    break_even_probability,
    contract_value,
    query_pettachainer_acceptance,
    run_acceptance_game,
)


class TestBaseRateAcceptanceGame(unittest.TestCase):
    def test_query_path_uses_accept_contract_goal(self):
        source_names = query_pettachainer_acceptance.__code__.co_names
        source_consts = " ".join(str(item) for item in query_pettachainer_acceptance.__code__.co_consts)

        self.assertIn("PeTTaChainer", source_consts)
        self.assertIn("query", source_names)
        self.assertIn("AcceptContract", source_consts)
        self.assertNotIn("LikelierThan", source_consts)
        self.assertNotIn("process_metta_string", source_names)
        self.assertNotIn("cached-base-rate", source_consts)

    def test_pettachainer_accepts_profitable_contracts_from_goal_truth(self):
        decisions = query_pettachainer_acceptance(DEFAULT_PREDICATES, sample_count=10)
        by_name = {predicate.name: predicate for predicate in DEFAULT_PREDICATES}
        accepted = {
            name
            for name, (strength, _confidence) in decisions.items()
            if strength >= break_even_probability(by_name[name])
        }

        self.assertIn("Reliable", accepted)
        self.assertIn("Fast", accepted)
        self.assertIn("Cheap", accepted)
        self.assertIn("Local", accepted)
        self.assertIn("HighVolume", accepted)
        self.assertNotIn("Fragile", accepted)

    def test_acceptance_game_scores_downstream_goal_not_estimate_table(self):
        report = run_acceptance_game(sample_counts=(10, 25), include_libpln=True)

        self.assertTrue(report.libpln_fixed_available, report.libpln_fixed_message)
        self.assertTrue(report.libpln_uniform_available, report.libpln_uniform_message)
        self.assertIsNotNone(report.libpln_fixed_total_value)
        self.assertIsNotNone(report.libpln_uniform_total_value)
        self.assertGreater(report.pettachainer_total_value, report.libpln_fixed_total_value)
        self.assertGreater(report.pettachainer_total_value, report.libpln_uniform_total_value)
        self.assertGreater(report.libpln_fixed_total_value, 0.0)
        self.assertEqual(report.libpln_uniform_total_value, 0.0)

    def test_contract_value_uses_hidden_game_payoff(self):
        reliable = PredicateSpec("Reliable", 0.9, success_reward=70.0, failure_cost=25.0, action_cost=20.0)

        self.assertAlmostEqual(contract_value(reliable), 40.5)
        self.assertAlmostEqual(break_even_probability(reliable), 45.0 / 95.0)


if __name__ == "__main__":
    unittest.main()
