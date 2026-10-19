"""A negated-antecedent implication query reads the antecedent's instance fold (#108).

The fixture is the labelled history of ChainerGame's conflicting-sources game
(seed 1, size l, 30 rounds) for sources s1 and s4: their claims and the
outcomes of the claimed nodes. A client reads a source's trust CTV from two
implication queries, the claim and its negation; the negation's instances are
the claims stated false."""
import unittest
from pathlib import Path

from pettachainer import PeTTaChainer

FIXTURE = Path(__file__).parent / "data" / "conflict_trust_s1_s4.metta"
# (P(up | claim), P(up | not claim)) per source at 20 steps.
EXPECTED = {
    "s1": ((1.0, 0.8958333333333334), (0.20029775905181096, 0.8570455634800677)),
    "s4": ((0.4584347530556126, 0.9350538802664571), (0.8651723425822995, 0.9468082917343221)),
}


def goals(source):
    claim = f"(Claims {source} (Up $n $t))"
    return [f"(: $p (Implication {claim} (Up $n $t)) $tv)",
            f"(: $p (Implication (Not {claim}) (Up $n $t)) $tv)"]


class NegatedAntecedentInstanceTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_evidence_confidence_k(5)
        self.h.add_atoms_no_check(FIXTURE.read_text().splitlines())

    def tearDown(self):
        self.h.set_evidence_confidence_k(800)

    def branches(self, statements):
        return [tuple(answer.tv[1:]) for answers in self.h.query_many_refs(statements, steps=20)
                for answer in answers]

    def test_both_branches_in_one_batch_then_warm(self):
        """One batch of 20 steps answers both branches, as each query alone
        does: the two queries share the samples and the fold. A warm read of
        either alone repeats its value."""
        for source, expected in EXPECTED.items():
            with self.subTest(source=source):
                self.assertEqual(self.branches(goals(source)), list(expected))
                positive, negative = goals(source)
                self.assertEqual(self.branches([negative]), [expected[1]])
                self.assertEqual(self.branches([positive]), [expected[0]])

    def test_negative_branch_cold_alone(self):
        for source, expected in EXPECTED.items():
            with self.subTest(source=source):
                self.assertEqual(self.branches(goals(source)[1:]), [expected[1]])


if __name__ == "__main__":
    unittest.main()
