"""KE identity worlds: a conjunction's world parts beside a judgment are read as
one compound, and a compound the event graph models has its posterior as its
one value, whoever reads it.

Reference: the three identity parts are uniform roots; the report (STV s .9)
multiplies the all-true world by its predictive mean m = (7200 s + 1)/7202
and the seven others by 1 - m, so P(I) = m / (m + 7 (1 - m)).
"""
import unittest

from pettachainer import PeTTaChainer

PARTS = '(AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit)'
I = f'(And {PARTS})'
J = '(Implication (Implemented Split1) (Not (Dilutes Split1)))'
Q = f'(And {PARTS} {J})'
BRIDGE = '(: bridge (Implication (And (Member $e StockSplit) (Implemented $e)) (Not (Dilutes $e))) (STV 1 0.9))'


def identity(s):
    m = (7200 * s + 1) / 7202
    return m / (m + 7 * (1 - m))


class TestIdentityWorlds(unittest.TestCase):
    def tvs(self, atoms, goal):
        h = PeTTaChainer()
        h.add_atoms_no_check(atoms)
        return [[row.tv for row in h.query_many_refs([f'(: $p {g} $tv)'], steps=300)[0]]
                for g in (goal, I)]

    def test_certain_judgment_reads_the_identity_posterior(self):
        for s in (1, .8, .5, .2):
            with self.subTest(s=s):
                q, i = self.tvs([f'(: report {I} (STV {s} 0.9))', f'(: judgment {J} (STV 1 1))'], Q)
                for rows in (q, i):
                    self.assertEqual(len(rows), 1, rows)
                    self.assertAlmostEqual(rows[0][1], identity(s), delta=1e-10)

    def test_bridge_judgment_stays_within_the_identity(self):
        # The bridge has no template; it is an evidence-free descendant, and a
        # neutral (.5) report on it carries no evidence either.
        for s, extra in ((1, []), (.8, []), (.5, []), (.8, ['(: neutral (Dilutes Split1) (STV 0.5 0.9))']),
                         (.8, ['(: neutral (Not (Dilutes Split1)) (STV 0.5 0.9))'])):
            with self.subTest(s=s, extra=extra):
                q, i = self.tvs([f'(: report {I} (STV {s} 0.9))', BRIDGE] + extra, Q)
                self.assertAlmostEqual(i[0][1], identity(s), delta=1e-10)
                self.assertEqual(len(q), 1, q)
                self.assertLessEqual(q[0][1], identity(s) + 1e-6)
                self.assertLessEqual(q[0][2], .1)

    def test_known_false_identity_supports_no_judgment(self):
        q, i = self.tvs([f'(: report {I} (STV 1 0.9))', BRIDGE, f'(: contra (Not {I}) (STV 1 1))'], Q)
        self.assertEqual([tv[1] for tv in q + i], [0.0, 0.0])
        self.assertEqual(q[0][2], 0.9999)

    def test_computed_world_key_beside_certain_judgment(self):
        # E and the judgment are certain, so Q = I = the world atom's posterior.
        # O/C: P(O | report on C) by enumeration over O and C; A: one certain
        # origin with the consequent's uniform base, (1 + pO) / 2.
        n = 800 * .001 / .999
        o = (n + 1) / (n + 2)
        c1, pc = .9 * o, .9 * o + .1 * (1 - o)
        m = (7200 * .9 + 1) / 7202
        oc = (c1 * m + (o - c1) * (1 - m)) / (pc * m + (1 - pc) * (1 - m))
        pa = (1 + (n * .2 + 1) / (n + 2)) / 2
        tail = ['(: e (E e) (STV 1 1))', '(: judgment (Implication (G) (Y)) (STV 1 1))']
        cases = [(['(: o (O e) (STV 1 0.001))', '(: r (Implication (O e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1)))',
                   '(: report (C e) (STV 0.9 0.9))'], '(O e)', oc),
                 (['(: o (O e) (STV 0.2 0.001))', '(: r (Implication (O e) (A e)) (FTV 1 1))'], '(A e)', pa)]
        for atoms, world, expected in cases:
            with self.subTest(world=world):
                h = PeTTaChainer()
                h.add_atoms_no_check(atoms + tail)
                for goal in (f'(And {world} (E e) (Implication (G) (Y)))', f'(And {world} (E e))', world):
                    rows = h.query_many_refs([f'(: $p {goal} $tv)'], steps=500)[0]
                    self.assertEqual(len(rows), 1, (goal, rows))
                    self.assertAlmostEqual(rows[0].tv[1], expected, delta=1e-10)


if __name__ == '__main__':
    unittest.main()
