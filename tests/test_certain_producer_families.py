"""R1 references: independent stored-count enumeration in the correctness design.

For certain producers, let q be the product of the antecedents' false
probabilities. Independent uniform consequent fallbacks give P(A)=1-q/2
and P(A and B)=1-3q/4. These pins do not come from chainer output.
"""
import unittest

from pettachainer import PeTTaChainer


class CertainProducerFamilyTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_evidence_confidence_k(800)

    def origins(self, strengths, confidence, rule_tv='FTV 1 1'):
        for i, strength in enumerate(strengths):
            self.h.add_atoms_no_check([
                f'(: origin{i} (Origin{i} e) (STV {strength} {confidence}))',
                f'(: toA{i} (Implication (Origin{i} e) (A e)) ({rule_tv}))',
                f'(: toB{i} (Implication (Origin{i} e) (B e)) ({rule_tv}))',
            ])

    def expect(self, goal, strength):
        rows = self.h.query_many_refs([f'(: $p {goal} $tv)'], steps=500)[0]
        self.assertEqual(len(rows), 1, goal)
        self.assertAlmostEqual(rows[0].tv[1], strength, delta=1e-12, msg=goal)

    def test_issue_167_marginals_joint_and_repeat(self):
        for rule_tv in ('FTV 1 1', 'STV 1.0 1.0', 'FTV 1.0 1.0'):
            with self.subTest(rule_tv=rule_tv):
                self.h = PeTTaChainer()
                self.h.set_evidence_confidence_k(800)
                self.origins([.8, .6], .5, rule_tv)
                # q = (161/802)(321/802).
                self.expect('(A e)', .9598253431259756)
                self.expect('(B e)', .9598253431259756)
                self.expect('(And (A e) (B e))', .9397380146889633)
                self.expect('(And (A e) (A e))', .9598253431259756)
                self.expect('(A e)', .9598253431259756)

    def test_one_origin_uses_counts_and_eight_origins_stay_exact(self):
        self.origins([.8], .5)
        self.expect('(A e)', .8996259351620948)
        self.expect('(And (A e) (B e))', .8494389027431422)
        self.h = PeTTaChainer()
        self.h.set_evidence_confidence_k(800)
        self.origins([.80, .72, .64, .56, .48, .40, .32, .24], .01)
        self.expect('(A e)', .9989943852221346)
        self.expect('(And (A e) (B e))', .998491577833202)

    def test_explicit_base_survives_inactive_producer_and_child_report(self):
        self.h.add_atoms_no_check([
            '(: o (O e) (STV 0.8 0.5))',
            '(: r (Implication (O e) (A e)) (STV 1 1))',
        ])
        self.h.handler.process_metta_string(f'!(set-base-rate {self.h.kb} (A e) (STV 0.2 1))')
        # 641/802 + (161/802)*.2.
        self.expect('(A e)', .8394014962593517)
        self.h.add_atoms_no_check([
            '(: z (Z e) (STV 0 1))',
            '(: inactive (Implication (Z e) (A e)) (FTV 1 1))',
        ])
        self.expect('(A e)', .8394014962593517)
        self.h.add_atoms_no_check([
            '(: ac (Implication (A e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            '(: report (C e) (STV 0.9 0.9))',
        ])
        self.expect('(A e)', .9596712898313778)
        self.expect('(C e)', .968105629056865)

    def test_neutral_descendant_does_not_change_posterior(self):
        self.h.add_atoms_no_check([
            '(: o (O e) (STV 1 0.001))',
            '(: rc (Implication (O e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            '(: report (C e) (STV 0.9 0.9))',
        ])
        self.expect('(O e)', .8912891216043767)
        self.expect('(C e)', .9347284013035543)
        self.h.add_atoms_no_check([
            '(: unused (Implication (O e) (Unused e)) (FTV 1 1))',
            '(: neutral (Unused e) (STV 0.5 0.9))',
        ])
        self.expect('(O e)', .8912891216043767)
        self.expect('(C e)', .9347284013035543)

    def test_distinct_redundant_rule_does_not_count_antecedent_twice(self):
        self.h.add_atoms_no_check([
            '(: o (O e) (STV 0.2 0.001))',
            '(: r0 (Implication (O e) (A e)) (FTV 1 1))',
        ])
        self.expect('(A e)', .7071122230164403)
        self.h.add_atom('(: r1 (Implication (O e) (A e)) (FTV 1 1))')
        self.expect('(A e)', .7071122230164403)

    def test_duplicate_compound_children_preserve_answer(self):
        self.h.add_atoms_no_check([
            '(: o (O e) (STV 0.54 0.5))',
            '(: b (B e) (STV 0.6 1))',
        ])
        self.expect('(And (B e) (O e))', .324)
        for connective in ('And', 'Or'):
            self.expect(f'({connective} (And (B e) (O e)) (And (B e) (O e)))', .324)
        self.expect('(And (Not (B e)) (Not (B e)))', .4)

    def test_repeated_nested_goal_discovers_the_same_ctv_reports(self):
        # Independent event-oracle strengths, quick seed 1's CTV fixtures.
        for origin, connective, report, expected in (
            (.5415223248933274, 'And', 0, .4021098863865393),
            (.27075122220263664, 'Or', .5, .20381353495738336),
        ):
            with self.subTest(connective=connective):
                self.h = PeTTaChainer()
                self.h.set_evidence_confidence_k(800)
                self.h.add_atoms_no_check([
                    f'(: o (O e) (STV {origin} 0.5))',
                    '(: b (B e) (STV 0.6 1))',
                    '(: ra (Implication (O e) (A e)) (CTV (STV 0.85 0.5) (STV 0.15 1)))',
                    f'(: report ({connective} (A e) (Not (B e))) (STV {report} 0.9))',
                ])
                self.expect('(And (A e) (B e))', expected)
                for outer in ('And', 'Or'):
                    self.expect(f'({outer} (And (A e) (B e)) (And (A e) (B e)))', expected)


if __name__ == '__main__':
    unittest.main()
