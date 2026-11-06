"""A producer that can never apply must not change a grounded channel (#169)."""
import itertools
import unittest

from pettachainer import PeTTaChainer

OBSERVED = '(: observed (Affirms claim1) (STV 1 1))'
WEAK = '(CTV (STV 0.5 0.01) (STV 0.5 0.01))'
CHANNEL = f'(: channel (Implication (And (A e) (B e)) (Affirms claim1)) {WEAK})'
# KE's generic report rule for another source: no About, Source, AtomicClaim or
# Ownership fact exists, so its instance for claim1 never holds.
OTHER = ('(: other (Implication (And (About $c (Ownership $a $b)) (Source $c OtherSource) '
         f'(AtomicClaim $c) (Ownership $a $b)) (Affirms $c)) {WEAK})')
SECOND = '(: second (Implication (And (Source claim1 S2) (C e)) (Affirms claim1)) {})'
GATE = '(: s2 (Source claim1 S2) (STV 1 1))'
GOALS = ('(A e)', '(B e)', '(C e)', '(And (A e) (B e))')


def chainer(atoms):
    h = PeTTaChainer()
    h.set_evidence_confidence_k(800)
    for head in ('About', 'Source', 'AtomicClaim'):
        h.set_positive_only_predicate(head)
    h.add_atoms_no_check(atoms)
    return h


def answers(h):
    rows = h.query_many_refs([f'(: $p {goal} $tv)' for goal in GOALS], steps=1000)
    return [[row.tv for row in goal_rows] for goal_rows in rows]


class InapplicableProducerTests(unittest.TestCase):
    def tearDown(self):
        PeTTaChainer().set_evidence_confidence_k(800)

    def test_generic_rule_for_another_source_keeps_the_channel(self):
        baseline = answers(chainer([OBSERVED, CHANNEL]))
        # Exact for the channel alone: A and B at .5 explain the report equally.
        for (row,), strength in zip([baseline[0], baseline[1], baseline[3]], (.5, .5, .25)):
            self.assertAlmostEqual(row[1], strength, delta=1e-6)
        self.assertEqual(baseline[2], [])
        controls = {'added': [OBSERVED, CHANNEL, OTHER], 'reversed': [OTHER, OBSERVED, CHANNEL],
                    'renamed': [OBSERVED, CHANNEL, OTHER.replace('Affirms', 'OtherAffirms')]}
        for name, atoms in controls.items():
            with self.subTest(name):
                self.assertEqual(answers(chainer(atoms)), baseline)

    def test_ground_inapplicable_producer_is_no_producer(self):
        for tv in (WEAK, '(STV 1 1)'):
            with self.subTest(tv=tv):
                channel = CHANNEL.replace(WEAK, tv)
                self.assertEqual(answers(chainer([OBSERVED, channel, SECOND.format(tv)])),
                                 answers(chainer([OBSERVED, channel])))

    def test_applicable_second_producer_joins_the_family(self):
        # Two certain producers: Affirms holds when A and B, or the gate and C,
        # hold, else at the empty-root prior .5; the report is certain.
        def weight(a, b, c):
            return .125 * (1 if (a and b) or c else .5)
        worlds = list(itertools.product((0, 1), repeat=3))
        z = sum(weight(*w) for w in worlds)
        expected = [sum(weight(*w) for w in worlds if test(*w)) / z
                    for test in (lambda a, b, c: a, lambda a, b, c: b, lambda a, b, c: c,
                                 lambda a, b, c: a and b)]
        h = chainer([OBSERVED, CHANNEL.replace(WEAK, '(STV 1 1)'), SECOND.format('(STV 1 1)')])
        self.assertEqual(answers(h)[2], [])
        h.add_atom(GATE)
        for (row,), strength in zip(answers(h), expected):
            self.assertAlmostEqual(row[1], strength, delta=1e-6)


if __name__ == '__main__':
    unittest.main()
