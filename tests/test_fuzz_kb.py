"""The differential fuzzer's generator and translations (docs/metta/fuzzing.md).

These tests run no chainer: they check that generated KBs are deterministic
and inside the shared semantics, and that the ProbLog translation agrees with
exact enumeration of the same model. The fuzz campaign itself is
``scripts/fuzz_vs_problog.py``.
"""

from __future__ import annotations

import os
import unittest

from tests.fuzz.generator import FEATURES, generate
from tests.fuzz.kb import KB, Antecedent, Fact, Literal, Rule, metta, problog
from tests.fuzz.run import PROBLOG_PYTHON, oracle


class GeneratorTest(unittest.TestCase):
    def test_deterministic_and_valid(self):
        for seed in range(60):
            features = list(FEATURES) if seed % 2 else ["chain", "and", "or", "not", "evidence", "observe", "latent"]
            kb = generate(seed, features)
            self.assertEqual(kb.problems(), [])
            self.assertEqual(kb.to_json(), generate(seed, features).to_json())
            self.assertLessEqual(len(kb.rules) + len(kb.facts), 15)

    def test_learned_rule_axiom_is_evidence_under_the_count_law(self):
        """The stated two counts and the Beta(1,1) prior each enter once."""
        kb = KB(["a"], {"A": 0.5}, [Rule("rB", "B", Antecedent("lit", (Literal("A"),)), 0.9, 0.1, learned=True)], [],
                history=[Fact("A", "h0", 1.0), Fact("B", "h0", 1.0), Fact("A", "h1", 1.0), Fact("B", "h1", 0.0), Fact("A", "h2", 0.0), Fact("B", "h2", 0.0)],
                queries=[("B", "a")])
        self.assertEqual(kb.rates(kb.rules[0]), ((1 + 2) / (2 + 4), (0 + 2) / (1 + 4)))
        self.assertIn("(CTV (STV 0.5 0.2857142857) (STV 0.5 0.2857142857))", metta(kb, 5.0).statements[0])

    def test_five_negative_samples_are_beta_two_seven(self):
        # Full benchmark seed 22000165: the old oracle used 1/7. The axiom
        # contributes n=2, ns=1, five failures give n=7, ns=1, and the
        # uniform prior makes Beta(2,7). ProbLog must use the mean 2/9.
        kb = KB(["a"], {"D": 0.5}, [Rule("rE", "E", Antecedent("lit", (Literal("D"),)), .5, .5, learned=True)], [],
                history=[f for i in range(5) for f in (Fact("D", f"h{i}", 0), Fact("E", f"h{i}", 0))])
        self.assertEqual(kb.rates(kb.rules[0]), (0.5, 2/9))


@unittest.skipUnless(os.path.exists(PROBLOG_PYTHON), "ProbLog interpreter not installed")
class TranslationTest(unittest.TestCase):
    def test_problog_prior_matches_enumeration(self):
        kbs = [generate(seed, list(FEATURES)) for seed in range(40)]
        for kb, exact in zip(kbs, oracle(kbs)):
            self.assertNotIn("error", exact, problog(kb))
            for (pred, _ind), prior in zip(kb.queries, exact["prior"]):
                self.assertAlmostEqual(prior, kb.model_prior(pred), places=9, msg=problog(kb, evidence=False))


if __name__ == "__main__":
    unittest.main()
