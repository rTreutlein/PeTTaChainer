"""Tracker #49: whole-family separator odds and explicit overlap uncertainty."""
import itertools
import math
import unittest

from pettachainer import PeTTaChainer
from pettachainer.query_diagnostics import _parse, _render


class SiblingSeparatorTests(unittest.TestCase):
    def tearDown(self):
        self.h.set_evidence_confidence_k(800)
        self.h.set_bayes_prior_count(0.2)

    @staticmethod
    def rule(name, parts, strength, confidence=0.99, negative=0.1):
        terms = [f"({p} $x)" for p in parts]
        condition = terms[0] if len(terms) == 1 else f"(And {' '.join(terms)})"
        return (f"(: {name} (Implication {condition} (T $x)) "
                f"(CTV (STV {strength} {confidence}) (STV {negative} {confidence})))")

    def setup_case(self, rules, inputs=None, kappa=0):
        self.h = PeTTaChainer()
        self.h.set_evidence_confidence_k(800)
        self.h.set_bayes_prior_count(kappa)
        # Exactly population=.25, independent of which rules finish first.
        self.h._call("add-space-atom!", [
            f"&combination_tally (make-space-row4 (index-hash (quote ({self.h.kb} T))) "
            f"{self.h.kb} T (combination-tally 98 24 0 0 0))"
        ])
        self.h.add_atoms_no_check(list(rules))
        self.h.add_atoms_no_check([
            f"(: input-{p} ({p} fresh) (STV {s} 1))"
            for p, s in (inputs or {"A": 1, "B": 1, "C": 1, "D": 1}).items()
        ])
        return self.answer()

    def answer(self):
        answers = self.h.query_many_refs(["(: $p (T fresh) $tv)"], steps=1000)[0]
        self.assertEqual(len(answers), 1)
        return answers[0]

    def test_shared_live_class_all_six_orders_and_view_orders(self):
        rules = [self.rule("ab", "AB", .8), self.rule("bc", "BC", .6),
                 self.rule("b", "B", .5)]
        for order in itertools.permutations(rules):
            with self.subTest(order=order):
                answer = self.setup_case(order)
                self.assertAlmostEqual(float(answer.tv[1]), 6 / 7, places=12)
                proof = self.h.expand_proof(answer.proof)
                for name in ("ab", "bc", "b"):
                    self.assertIn(name, proof)
                self.assertIn("prior (STV 0.5", proof)
                key = f"(sk-key (T fresh) ({self.h.kb} MAIN Nil))"
                khash = self.h._call("index-hash", [key])[0]
                views = _parse(self.h._call("sk-admitted", [f"{khash} {key} sk-any-filter ()"])[0])
                for permutation in itertools.permutations(views):
                    merged = _parse(self.h._call("sk-merge-key", [
                        f"{khash} {key} sk-any-filter () () {_render(list(permutation))}"
                    ])[0])
                    self.assertAlmostEqual(float(merged[1][3][1]), 6 / 7, places=12)
                    for view in views:
                        self.assertEqual(self.h._call("deps-within?", [f"{view[3]} {merged[3]}"]), ["true"])

    def test_shared_denominator_variance(self):
        answer = self.setup_case([self.rule("ab", "AB", .8), self.rule("bc", "BC", .6),
                                  self.rule("b", "B", .5, .2)])
        # The same live shared prior controls strength AND variance.
        variance = lambda s, c: 1 / ((800 * c / (1 - c) + 1) * s * (1 - s))
        vp = variance(.5, .2)
        v = vp + max(0, variance(.8, .99) - vp) + max(0, variance(.6, .99) - vp)
        strength = 6 / 7
        n = max(0, 1 / (strength * (1 - strength) * v) - 1)
        self.assertAlmostEqual(float(answer.tv[1]), strength, places=12)
        self.assertAlmostEqual(float(answer.tv[2]), min(.99, n / (n + 800)), places=10)

    def test_same_condition_general_revision_and_single_shrink(self):
        rules = [self.rule("ab", "AB", .8, .1), self.rule("bc", "BC", .6, .2),
                 self.rule("b1", "B", .2, .8), self.rule("b2", "B", .8, .9)]
        ng = 800 * (.8 / .2 + .9 / .1)
        g = (.2 * 4 + .8 * 9) / 13
        weight = max(0, 1 / (1 / (ng + 1) + 1 / 1.2) - 1)
        shrunk = lambda s, c: (s * 800 * c / (1 - c) + weight * g) / (800 * c / (1 - c) + weight)
        sa, sb = shrunk(.8, .1), shrunk(.6, .2)
        odds = sa / (1 - sa) * sb / (1 - sb) / (g / (1 - g))
        for order in (rules, list(reversed(rules))):
            answer = self.setup_case(order, kappa=.2)
            self.assertAlmostEqual(float(answer.tv[1]), odds / (1 + odds), delta=1e-9)
            proof = self.h.expand_proof(answer.proof)
            for name in ("ab", "bc", "b1", "b2"):
                self.assertIn(name, proof)

    def test_three_siblings_with_one_common_class(self):
        rules = [self.rule("ab", "AB", .8), self.rule("bc", "BC", .6),
                 self.rule("bd", "BD", .7), self.rule("b", "B", .5)]
        for order in (rules, list(reversed(rules))):
            answer = self.setup_case(order)
            self.assertAlmostEqual(float(answer.tv[1]), 14 / 15, places=12)

    def test_triangle_population_strength_and_model_discount(self):
        rules = [self.rule("ab", "AB", .7), self.rule("bc", "BC", .8),
                 self.rule("ac", "AC", .9), self.rule("a", "A", .4),
                 self.rule("b", "B", .5), self.rule("c", "C", .6)]
        for order in (rules, list(reversed(rules))):
            answer = self.setup_case(order)
            self.assertAlmostEqual(float(answer.tv[1]), 756 / 757, places=12)
            # Population variance survives the first canonical pair (.7,.9);
            # the original conservative intermediate confidence cap remains.
            first = 63 / 64
            n = 1 / (first * (1 - first) / (99 * .25 * .75)) - 1
            population_confidence = n / (n + 800)
            self.assertAlmostEqual(float(answer.tv[2]), population_confidence / (1 + math.log(27) ** 2), places=10)
            for name in ("ab", "bc", "ac", "a", "b", "c"):
                self.assertIn(name, self.h.expand_proof(answer.proof))

    def test_mixed_polarity_keeps_population_strength(self):
        rules = [self.rule("ab", "AB", .8), self.rule("bc", "BC", .6, negative=.3),
                 self.rule("b", "B", .5)]
        answer = self.setup_case(rules, {"A": 1, "B": 1, "C": 0})
        self.assertAlmostEqual(float(answer.tv[1]), 36 / 43, places=12)
        strength = 36 / 43
        variance = 1 / (99 * .25 * .75)
        n = 1 / (strength * (1 - strength) * variance) - 1
        population_confidence = n / (n + 800)
        self.assertAlmostEqual(float(answer.tv[2]), population_confidence / (1 + math.log(3) ** 2), places=10)

    def test_negative_siblings_keep_population_strength(self):
        answer = self.setup_case([self.rule("ab", "AB", .8, negative=.2),
                                  self.rule("bc", "BC", .6, negative=.3)],
                                 {"A": 0, "B": 1, "C": 0})
        self.assertAlmostEqual(float(answer.tv[1]), 9 / 37, places=12)
        strength = 9 / 37
        n = 1 / (strength * (1 - strength) / (99 * .25 * .75)) - 1
        self.assertAlmostEqual(float(answer.tv[2]), n / (n + 800) / 2, places=10)

    def test_uncertain_shared_input_is_conditioned(self):
        rules = [self.rule("ab", "AB", .8, negative=.1),
                 self.rule("bc", "BC", .6, negative=.1),
                 self.rule("b", "B", .5, negative=.1)]
        answer = self.setup_case(rules, {"A": 1, "B": .6, "C": 1})
        # B=true uses its class. With B=false its general negative branch
        # is the specific complement and remains .1.
        self.assertAlmostEqual(float(answer.tv[1]), .6 * (6 / 7) + .4 * .1, places=12)
        self.assertIn("conditioned", self.h.expand_proof(answer.proof))


if __name__ == "__main__":
    unittest.main()
