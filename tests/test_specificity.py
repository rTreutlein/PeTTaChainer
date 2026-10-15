import itertools
import unittest

from pettachainer import PeTTaChainer
from pettachainer.query_diagnostics import _parse, _render


class SpecificityTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_evidence_confidence_k(1)

    def tearDown(self):
        self.h.set_evidence_confidence_k(800)
        self.h.set_bayes_prior_count(0.2)

    def answer(self, period="fresh", steps=1000):
        answers = self.h.query_many_refs([f"(: $p (T {period}) $tv)"], steps=steps)[0]
        self.assertEqual(len(answers), 1)
        return answers[0]

    def add_case(self, period, f0, f1, f3, target=None):
        atoms = [f"(: input-{period}-{i} (F{i} {period}) (STV {value} 1))"
                 for i, value in ((0, f0), (1, f1), (3, f3))]
        if target is not None:
            atoms.append(f"(: target-{period} (T {period}) (STV {target} 1))")
        self.h.add_atoms_no_check(atoms)

    def test_authored_containment_precedes_lifting(self):
        rules = [
            "(: general (Implication (F0 $t) (T $t)) (CTV (STV 0.25 0.7) (STV 0 0.7)))",
            "(: specific (Implication (And (F0 $t) (F1 $t)) (T $t)) (CTV (STV 0.99 0.4) (STV 0 0.4)))",
        ]
        for prior, expected in ((0.2, 0.8192307583), (0, 0.99)):
            for order in itertools.permutations(rules):
                self.h = PeTTaChainer()
                self.h.set_bayes_prior_count(prior)
                self.h.add_atoms_no_check(list(order))
                self.add_case("fresh", 1, 1, 0)
                answer = self.answer()
                # Preserve the existing general prior, applied once.
                self.assertAlmostEqual(float(answer.tv[1]), expected, places=7)
                self.assertIn("specializes", self.h.expand_proof(answer.proof))

    def test_same_condition_revises(self):
        self.h.add_atoms_no_check([
            "(: first (Implication (F0 $t) (T $t)) (CTV (STV 0.25 0.7) (STV 0 0.7)))",
            "(: second (Implication (F0 $t) (T $t)) (CTV (STV 0.99 0.4) (STV 0 0.4)))",
        ])
        self.add_case("fresh", 1, 1, 0)
        self.assertAlmostEqual(float(self.answer().tv[1]), 0.4144444444, places=7)

    def test_singles_cannot_hide_in_a_combination(self):
        rules = [
            "(: single0 (Implication (F0 $t) (T $t)) (CTV (STV 0.48 0.99) (STV 0 0.99)))",
            "(: single1 (Implication (F1 $t) (T $t)) (CTV (STV 0.48 0.99) (STV 0 0.99)))",
            "(: exact (Implication (And (F0 $t) (F1 $t)) (T $t)) (CTV (STV 0.9995 0.9999) (STV 0 0.9999)))",
        ]
        self.h.add_atoms_no_check(rules)
        self.add_case("control", 1, 1, 0)
        expected = float(self.answer("control").tv[1])
        strengths = []
        for order in itertools.permutations(rules):
            with self.subTest(order=[r.split()[1] for r in order]):
                self.h = PeTTaChainer()
                self.h.add_atoms_no_check(list(order))
                # Isolate the learned-mode merge boundary. The mining test
                # below obtains its counts and hypotheses through ingestion.
                self.h._call("add-space-atom!", [
                    f"&combination_tally (make-space-row4 (index-hash (quote ({self.h.kb} T))) "
                    f"{self.h.kb} T (combination-tally 100 25 -10 0 -20))"
                ])
                for period in range(3):
                    self.add_case(period, 1, 1, period % 2)
                    strengths.append(float(self.answer(period).tv[1]))
                    self.assertGreater(strengths[-1], 0.999)
                    self.assertAlmostEqual(strengths[-1], expected, places=12)
        self.assertLess(max(strengths) - min(strengths), 1e-12)

    def test_siblings_combine_in_both_polarities_and_all_orders(self):
        cases = [
            (0.9999, 0.674, 1, 0.25),  # seed 7: two applicable positive pairs
            (0.9999, 0.137, 0, 0.25),  # seed 9: applicable negative sibling
            (0.8, 0.6, 1, 0.7),        # moderate estimates, combined between them
        ]
        for specific, sibling, f3, prior in cases:
            rules = [
                f"(: exact (Implication (And (F0 $t) (F1 $t)) (T $t)) (CTV (STV {specific} 0.99) (STV 0.01 0.99)))",
                f"(: sibling (Implication (And (F1 $t) (F3 $t)) (T $t)) (CTV (STV {sibling if f3 else 0.7} 0.9999) (STV {sibling} 0.9999)))",
            ]
            expected_odds = specific / (1 - specific) * sibling / (1 - sibling) / (prior / (1 - prior))
            expected = expected_odds / (1 + expected_odds)
            for order in itertools.permutations(rules):
                with self.subTest(rates=(specific, sibling), f3=f3, order=order):
                    self.h = PeTTaChainer()
                    self.h._call("add-space-atom!", [
                        f"&combination_tally (make-space-row4 (index-hash (quote ({self.h.kb} T))) "
                        f"{self.h.kb} T (combination-tally 98 {100 * prior - 1} 0 0 0))"
                    ])
                    self.h.add_atoms_no_check(list(order))
                    self.add_case("fresh", 1, 1, f3)
                    answer = self.answer()
                    strength = float(answer.tv[1])
                    self.assertAlmostEqual(strength, expected, places=10)
                    if specific < 0.9:
                        self.assertGreater(strength, sibling)
                        self.assertLess(strength, specific)
                    else:
                        self.assertGreater(strength, 0.999)
                    proof = self.h.expand_proof(answer.proof)
                    self.assertIn("exact", proof)
                    self.assertIn("sibling", proof)
                    self.assertLessEqual(float(answer.tv[2]), 0.99)
                    key = f"(sk-key (T fresh) ({self.h.kb} MAIN Nil))"
                    key_hash = self.h._call("index-hash", [key])[0]
                    views = _parse(self.h._call("sk-admitted", [f"{key_hash} {key} sk-any-filter ()"])[0])
                    for permutation in itertools.permutations(views):
                        merged = _parse(self.h._call("sk-merge-key", [
                            f"{key_hash} {key} sk-any-filter () () {_render(list(permutation))}"
                        ])[0])
                        self.assertAlmostEqual(float(merged[1][3][1]), strength, places=12)

    def test_sibling_group_survives_an_independent_rule_in_all_orders(self):
        rules = [
            "(: first (Implication (And (F0 $t) (F1 $t)) (T $t)) (CTV (STV 0.8 0.99) (STV 0.1 0.99)))",
            "(: second (Implication (And (F1 $t) (F3 $t)) (T $t)) (CTV (STV 0.6 0.99) (STV 0.1 0.99)))",
            "(: independent (Implication (F4 $t) (T $t)) (CTV (STV 0.55 0.8) (STV 0.1 0.8)))",
        ]
        expected = None
        for order in itertools.permutations(rules):
            self.h = PeTTaChainer()
            self.h._call("add-space-atom!", [
                f"&combination_tally (make-space-row4 (index-hash (quote ({self.h.kb} T))) "
                f"{self.h.kb} T (combination-tally 98 69 0 0 0))"
            ])
            self.h.add_atoms_no_check(list(order))
            self.add_case("fresh", 1, 1, 1)
            self.h.add_atoms_no_check(["(: f4 (F4 fresh) (STV 1 1))"])
            answer = self.answer()
            strength = float(answer.tv[1])
            if expected is None:
                expected = strength
            self.assertAlmostEqual(strength, expected, places=12)
            self.assertGreater(strength, 0.55)
            self.assertLess(strength, 0.72)
            proof = self.h.expand_proof(answer.proof)
            for name in ("first", "second", "independent"):
                self.assertIn(name, proof)

    def test_same_condition_pool_precedes_sibling_combination(self):
        rules = [
            f"(: same{i} (Implication (And (F0 $t) (F1 $t)) (T $t)) (CTV (STV {strength} 0.99) (STV 0.01 0.99)))"
            for i, strength in enumerate((0.6, 0.7, 0.8))
        ]
        self.h.add_atoms_no_check(rules)
        self.add_case("fresh", 1, 1, 1)
        pooled = float(self.answer().tv[1])
        odds = pooled / (1 - pooled) * 0.65 / 0.35
        expected = odds / (1 + odds)
        rules.append("(: sibling (Implication (And (F1 $t) (F3 $t)) (T $t)) (CTV (STV 0.65 0.99) (STV 0.01 0.99)))")
        for order in (rules, list(reversed(rules))):
            self.h = PeTTaChainer()
            self.h.add_atoms_no_check(order)
            self.add_case("fresh", 1, 1, 1)
            answer = self.answer()
            self.assertAlmostEqual(float(answer.tv[1]), expected, places=10)
            proof = self.h.expand_proof(answer.proof)
            for name in ("same0", "same1", "same2", "sibling"):
                self.assertIn(name, proof)
            key = f"(sk-key (T fresh) ({self.h.kb} MAIN Nil))"
            khash = self.h._call("index-hash", [key])[0]
            views = _parse(self.h._call("sk-admitted", [f"{khash} {key} sk-any-filter ()"])[0])
            for permutation in itertools.permutations(views):
                merged = _parse(self.h._call("sk-merge-key", [f"{khash} {key} sk-any-filter () () {_render(list(permutation))}"])[0])
                self.assertAlmostEqual(float(merged[1][3][1]), expected, places=10)

    def test_unpaid_sibling_overlap_retains_both_rules(self):
        self.h.add_atoms_no_check([
            "(: first (Implication (And (F0 $t) (F1 $t)) (T $t)) (CTV (STV 0.8 0.8) (STV 0.2 0.8)))",
            "(: second (Implication (And (F1 $t) (F3 $t)) (T $t)) (CTV (STV 0.6 0.99) (STV 0.2 0.99)))",
        ])
        self.add_case("fresh", 1, 0.6, 1)
        answer = self.answer()
        # Condition on F1 once; combine the siblings inside each branch.
        self.assertAlmostEqual(float(answer.tv[1]), 0.6 * (6 / 7) + 0.4 / 17, places=12)
        self.assertIn("conditioned", self.h.expand_proof(answer.proof))
        key = f"(sk-key (T fresh) ({self.h.kb} MAIN Nil))"
        key_hash = self.h._call("index-hash", [key])[0]
        views = _parse(self.h._call("sk-admitted", [f"{key_hash} {key} sk-any-filter ()"])[0])
        expected = None
        for order in itertools.permutations(views):
            result = _parse(self.h._call("sk-key-fallback", [f"() {_render(list(order))}"])[0])
            strength = float(result[1][3][1])
            if expected is None:
                expected = strength
            self.assertAlmostEqual(strength, expected, places=12)
            self.assertIn("combination", _render(result))
            proof = self.h.expand_proof(_render(result[1][2]))
            self.assertIn("first", proof)
            self.assertIn("second", proof)
            self.assertLessEqual(float(result[1][3][2]), min(float(v[1][3][2]) for v in views))

    def test_general_priors_do_not_hide_sibling_sample_twins(self):
        controls = []
        for duplicate in (False, True):
            self.h = PeTTaChainer()
            self.h.set_rule_refinement(True)
            self.h.set_rule_change_hazard(0)
            conditions = [("g0", "(F0 $t)"), ("g1", "(F1 $t)"),
                          ("g2", "(F2 $t)"),
                          ("exact", "(And (F0 $t) (F1 $t))"),
                          ("sibling", "(And (F1 $t) (F2 $t))")]
            if duplicate:
                conditions.extend([("g3", "(F3 $t)"), ("twin", "(And (F1 $t) (F3 $t))")])
            self.h.add_atoms_no_check([
                f"(: {name} (Implication {condition} (T $t)) (CTV (STV 0.5 0.01) (STV 0.5 0.01)))"
                for name, condition in conditions
            ])
            for period in range(64):
                f0, f1, f2 = period % 2, (period // 2) % 2, (period // 4) % 2
                self.add_case(period, f0, f1, f2, f0 * f1)
                self.h.add_atoms_no_check([f"(: input-{period}-2 (F2 {period}) (STV {f2} 1))"])
            self.h.query_many_refs([
                f"(: $p (RuleTruth (Implication {condition} (T $t))) $tv)"
                for _, condition in conditions
            ], steps=1000)
            self.h._call("add-space-atom!", [
                f"&combination_tally (make-space-row4 (index-hash (quote ({self.h.kb} T))) "
                f"{self.h.kb} T (combination-tally 98 24 0 0 0))"
            ])
            self.add_case("fresh", 1, 1, 1)
            self.h.add_atoms_no_check(["(: f2 (F2 fresh) (STV 1 1))"])
            answer = self.answer()
            controls.append(float(answer.tv[1]))
            self.assertGreater(controls[-1], 0.99)
            if duplicate:
                proof = self.h.expand_proof(answer.proof)
                self.assertIn("sibling", proof)
                self.assertIn("twin", proof)
                self.assertIn("combination revision", proof)
        self.assertAlmostEqual(controls[0], controls[1], places=12)

    def test_mined_parent_and_child(self):
        self.h.set_hypothesis_mining(8, 16)
        for head in ("F0", "F1", "F3"):
            self.h.set_predicate_time(head, 1, 0)
        self.h.set_predicate_time("T", 1, 1)
        for period in range(64):
            f0, f1, f3 = period % 2, (period // 2) % 2, (period // 4) % 2
            self.add_case(period, f0, f1, f3, f0 * f1)
        self.h.review_hypotheses(steps=100)
        self.h.set_hypothesis_mining(0, 0)
        self.add_case("fresh", 1, 1, 0)
        self.assertGreater(float(self.answer().tv[1]), 0.98)
        self.add_case("fresh-false", 1, 0, 1)
        self.assertLess(float(self.answer("fresh-false").tv[1]), 0.01)


if __name__ == "__main__":
    unittest.main()
