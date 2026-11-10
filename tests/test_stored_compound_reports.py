"""#183: a stored compound reads its sources; other keys still use its likelihood."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class StoredCompoundReportTests(unittest.TestCase):
    def test_issue_controls(self):
        clipped = (1 - 1e-6) * 1e-6
        variance = clipped / (79200 + 1)
        joint_variance = 3 * variance + 3 * variance**2 + variance**3
        count = clipped / joint_variance - 1
        for query, strength, confidence, proof in (
            ('(Not A)', 0, .99, '(negated a)'),
            ('(And A B C)', 1, count / (count + 800), '(conjunction a b c)'),
            ('(Not (And A B C))', 0, count / (count + 800), '(negated (conjunction a b c))'),
        ):
            with self.subTest(query=query):
                h = PeTTaChainer()
                for atom in 'ABC':
                    h.add_atom(f'(: {atom.lower()} {atom} (STV 1 0.99))')
                row, = h.query_many_refs([f'(: $p {query} $tv)'], steps=400)[0]
                self.assertEqual(row.tv[1], strength)
                self.assertAlmostEqual(row.tv[2], confidence, delta=1e-12)
                self.assertEqual(h.expand_proof(row.proof), proof)

    def test_reports_read_their_sources_at_zero_and_paid_budgets(self):
        # Both polarities, finite fractional reports, nested connectives and
        # more than four parts use the same source-key rule.
        for compound in ('(And A B C)', '(Or A B)', '(Or (And A B) C)', '(And A B C D E)'):
            for strength in (0, .2, .5, .8, 1):
                for known_a in ((False,) if compound == '(Or A B)' else (False, True)):
                    with self.subTest(compound=compound, strength=strength, known_a=known_a):
                        h = PeTTaChainer()
                        h.add_atom(f'(: report {compound} (STV {strength} 0.99))')
                        if known_a:
                            h.add_atom('(: a A (STV 1 0.99))')
                        for steps in (0, 400, 400, 0):
                            for goal, expected, proof in (
                                (compound, strength, 'report'),
                                (f'(Not {compound})', 1-strength, '(negated report)'),
                            ):
                                row, = h.query_many_refs([f'(: $p {goal} $tv)'], steps=steps)[0]
                                self.assertAlmostEqual(row.tv[1], expected, delta=1e-12)
                                self.assertEqual(row.tv[2], .99)
                                self.assertEqual(h.expand_proof(row.proof), proof)

    def test_negated_report_and_canonical_member_spelling(self):
        h = PeTTaChainer()
        h.add_atom('(: report (Not (And (Member x P) (Q x))) (STV 1 0.99))')
        for query in ('(And (Member x P) (Q x))', '(And (P x) (Q x))',
                      '(Not (Not (And (P x) (Q x))))'):
            row, = h.query_many_refs([f'(: $p {query} $tv)'], steps=400)[0]
            self.assertEqual(row.tv, ['STV', 0.0, .99])

    def test_conflicting_independent_parts_revise_with_the_report(self):
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: report (Not (And A B)) (STV 1 0.99))',
                              '(: a A (STV 1 0.99))', '(: b B (STV 1 0.99))'])
        # Ordinary revision pools the counts, rather than choosing an endpoint.
        clipped = (1 - 1e-6) * 1e-6
        part_variance = clipped / 79201
        joint_count = clipped / (2*part_variance + part_variance**2) - 1
        total = 79200 + joint_count
        row, = h.query_many_refs(['(: $p (And A B) $tv)'], steps=400)[0]
        self.assertAlmostEqual(row.tv[1], joint_count / total, delta=1e-12)
        self.assertAlmostEqual(row.tv[2], total / (total + 800), delta=1e-12)
        self.assertEqual(h.expand_proof(row.proof), '(merge/revision report (conjunction a b))')
        # High confidence describes the pooled frequency near 1/3. It does
        # not assert either conflicting endpoint; 1/3 lies within 2 SD.
        variance = row.tv[1] * (1-row.tv[1]) / (total+1)
        self.assertLess(abs(row.tv[1]-1/3), 2*variance**.5)

    def test_parts_and_other_compounds_keep_graph_evidence(self):
        for goal, strength in (('A', 39601/39602), ('(And A C)', 39601/79204)):
            with self.subTest(goal=goal):
                h = PeTTaChainer()
                h.add_atom('(: report (And A B) (STV 1 0.99))')
                row, = h.query_many_refs([f'(: $p {goal} $tv)'], steps=400)[0]
                self.assertAlmostEqual(row.tv[1], strength, delta=1e-12)
                self.assertLess(row.tv[2], 1e-12)
                self.assertEqual(h.expand_proof(row.proof), '(node (conjunction report))')

    def test_part_rule_and_assuming_keep_the_whole_report(self):
        for extra in ([], ['(: x X (STV 1 0.99))',
                           '(: r (Implication X A) (STV 1 0.99))']):
            h = PeTTaChainer()
            h.add_atoms_no_check(['(: report (Not (And A B)) (STV 1 0.99))'] + extra)
            for query, proof in (('(And A B)', 'report'),
                                 ('(Assuming X (And A B))', '(assuming report)'),
                                 ('(Assuming A (And A B))', '(assuming report)')):
                with self.subTest(extra=extra, query=query):
                    row, = h.query_many_refs([f'(: $p {query} $tv)'], steps=400)[0]
                    self.assertEqual(row.tv, ['STV', 0.0, .99])
                    self.assertEqual(h.expand_proof(row.proof), proof)
            row, = h.query_many_refs(['(: $p (And A B) $tv)'], steps=0)[0]
            self.assertEqual(row.tv, ['STV', 0.0, .99])

    def test_multiple_unknown_parts_produce_one_bound(self):
        PeTTaChainer()
        for head, strength in (('And', 0), ('Or', 1)):
            result = janus.query_once(
                "findall(_TV, 'compound-bounds'([Head,'A','B','C'], ['A','B','C'], "
                "[['STV',S,0.99],'no-evidence','no-evidence'], "
                "[a,'no-evidence','no-evidence'], _TV), Values)",
                {'Head': head, 'S': strength})['Values']
            self.assertEqual(result, [['bound-result', ['STV', strength, .99],
                                       ['conjunction', 'a']]])

    def test_one_decisive_part_revises_independently(self):
        for head, report_s, part_s in (('And', 1, 0), ('Or', 0, 1)):
            for report_c in (0.5, 0.99):
                for late in (False, True):
                    with self.subTest(head=head, report_c=report_c, late=late):
                        h = PeTTaChainer()
                        h.add_atom(f'(: report ({head} A B) (STV {report_s} {report_c}))')
                        if late:
                            row, = h.query_many_refs([f'(: $p ({head} A B) $tv)'], steps=400)[0]
                            self.assertEqual(row.tv, ['STV', report_s, report_c])
                        h.add_atom(f'(: a A (STV {part_s} 0.99))')
                        report_n = report_c / (1 - report_c)
                        total = report_n + 99
                        strength = (report_n * report_s + 99 * part_s) / total
                        for steps in (400, 0, 400):
                            row, = h.query_many_refs([f'(: $p ({head} A B) $tv)'], steps=steps)[0]
                            self.assertAlmostEqual(row.tv[1], strength, delta=1e-12)
                            self.assertAlmostEqual(row.tv[2], total / (total + 1), delta=1e-12)
                            proof = h.expand_proof(row.proof)
                            self.assertIn('(conjunction a)', proof)
                            self.assertEqual(proof.count('report'), 1)

    def test_graded_bounds_read_the_interval_midpoint(self):
        PeTTaChainer()
        for head, part_s, strength, confidence in (
            ('And', .5, .25, .495), ('Or', .5, .75, .495),
            ('And', .2, .1, .792), ('Or', .8, .9, .792),
            ('And', .9, .45, .099), ('Or', .1, .55, .099),
        ):
            with self.subTest(head=head, part_s=part_s):
                result = janus.query_once(
                    "findall(_TV, 'compound-bounds'([Head,'A','B','C'], ['A','B','C'], "
                    "[['STV',S,0.99],'no-evidence','no-evidence'], "
                    "[a,'no-evidence','no-evidence'], _TV), Values)",
                    {'Head': head, 'S': part_s})['Values']
                bound, = result
                self.assertEqual(bound[0], 'bound-result')
                self.assertAlmostEqual(bound[1][1], strength, delta=1e-12)
                self.assertAlmostEqual(bound[1][2], confidence, delta=1e-12)
                self.assertEqual(bound[2], ['conjunction', 'a'])
        for head, part_s in (('And', 1), ('Or', 0)):
            result = janus.query_once(
                "findall(_TV, 'compound-bounds'([Head,'A','B'], ['A','B'], "
                "[['STV',S,0.99],'no-evidence'], [a,'no-evidence'], _TV), Values)",
                {'Head': head, 'S': part_s})['Values']
            self.assertEqual(result, [])  # Width 1 supplies no proof.

    def test_review_graded_reports_revise_with_midpoints(self):
        for report_s, report_c, part_s, expected_s, expected_c in (
            (.5, .1, .5, 1093/3968, 992/1901),
            (.4, .9, .5, 863/2240, 1008/1109),
            (1, .99, .5, 135/136, 10098/10199),
            (.1, .9, .2, .1, 333/359),
            (1, .1, .9, 26039/35840, 1792/9901),
        ):
            with self.subTest(report=(report_s, report_c), part_s=part_s):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    f'(: report (And A B) (STV {report_s} {report_c}))',
                    f'(: a A (STV {part_s} 0.99))',
                ])
                # Bounds [0,part_s]: midpoint part_s/2, c=(1-part_s)*.99.
                # Pool the independent counts c/(1-c) with the report's.
                for steps in (400, 0, 400):
                    row, = h.query_many_refs(['(: $p (And A B) $tv)'], steps=steps)[0]
                    self.assertAlmostEqual(row.tv[1], expected_s, delta=1e-12)
                    self.assertAlmostEqual(row.tv[2], expected_c, delta=1e-12)
                    proof = h.expand_proof(row.proof)
                    self.assertIn('(conjunction a)', proof)
                    self.assertEqual(proof.count('report'), 1)

    def test_graded_bound_and_late_full_parts(self):
        for head, part_s, report_s, expected in (('And', 0.2, 0.8, 0.296),
                                                ('Or', 0.8, 0.2, 0.704)):
            h = PeTTaChainer()
            h.add_atoms_no_check([f'(: report ({head} A B) (STV {report_s} 0.5))',
                                  f'(: a A (STV {part_s} 0.9))'])
            row, = h.query_many_refs([f'(: $p ({head} A B) $tv)'], steps=400)[0]
            # Midpoints .1/.9, d=.8, c=.72; revise with the report at c=.5.
            self.assertAlmostEqual(row.tv[1], expected, delta=1e-12)
            self.assertAlmostEqual(row.tv[2], 0.78125, delta=1e-12)
            h.add_atom('(: b B (STV 0.7 0.9))')
            part_tv = janus.query_once(f"'{head}Formula'(['STV',S,0.9],['STV',0.7,0.9],TV)",
                                      {'S': part_s})['TV']
            n = part_tv[2] / (1 - part_tv[2])
            for _ in range(2):
                row, = h.query_many_refs([f'(: $p ({head} A B) $tv)'], steps=400)[0]
                self.assertAlmostEqual(row.tv[1], (report_s + n*part_tv[1])/(1+n), delta=1e-12)
                self.assertAlmostEqual(row.tv[2], (1+n)/(2+n), delta=1e-12)

    def test_negated_part_and_pattern_use_the_same_bound(self):
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: report (Not (And (Not (P a)) (Q a))) (STV 0 0.5))',
                              '(: p (P a) (STV 1 0.99))'])
        for goal in ('(And (Not (P $x)) (Q $x))', '(And (Not (P a)) (Q a))'):
            row, = h.query_many_refs([f'(: $p {goal} $tv)'], steps=400)[0]
            self.assertAlmostEqual(row.tv[1], 0.01, delta=1e-12)
            self.assertAlmostEqual(row.tv[2], 100/101, delta=1e-12)
            self.assertIn('(negated p)', h.expand_proof(row.proof))

    def test_report_only_part_cannot_return_as_independent_evidence(self):
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: report (Not (And A B)) (STV 1 0.9))',
                              '(: r (Implication (Not (And A B)) (Not A)) (STV 1 0.99))',
                              '(: b B (STV 1 0.99))'])
        for goal in ('A', '(And A B)', '(And A B)'):
            row, = h.query_many_refs([f'(: $p {goal} $tv)'], steps=400)[0]
            if goal == '(And A B)':
                self.assertEqual(row.tv, ['STV', 0, 0.9])
                self.assertEqual(h.expand_proof(row.proof), 'report')

    def test_derived_graded_part_revises_the_report(self):
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: report (Not (And A B)) (STV 1 0.99))',
                              '(: x X (STV 1 0.99))',
                              '(: r (Implication X A) (CTV (STV 0.9 0.99) (STV 0.1 0.99)))'])
        # The derived A=(.9,.98999992983) gives midpoint .45 at
        # c=.098999992983; revision pools its count with the report's 99.
        for goal, strength, confidence in (('(And A B)', .0004988913132159364, .990010975730573),
                                           ('(Assuming X (And A B))', .0004988913132159364, .990010975730573),
                                           ('(Assuming A (And A B))', 0, .99)):
            row, = h.query_many_refs([f'(: $p {goal} $tv)'], steps=400)[0]
            self.assertAlmostEqual(row.tv[1], strength, delta=1e-12)
            self.assertAlmostEqual(row.tv[2], confidence, delta=1e-12)

    def test_two_reports_do_not_duplicate_the_part_proof(self):
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: one (And A B) (STV 1 0.99))',
                              '(: two (And A B) (STV 1 0.99))',
                              '(: a A (STV 0 0.99))'])
        row, = h.query_many_refs(['(: $p (And A B) $tv)'], steps=400)[0]
        self.assertAlmostEqual(row.tv[1], 2/3, delta=1e-12)
        self.assertAlmostEqual(row.tv[2], 297/298, delta=1e-12)

    def test_independent_ids_revise_and_repeated_id_does_not(self):
        for second, confidence, proof in (('report', .99, 'report'),
                                          ('second', 198/199, '(merge/revision second report)')):
            h = PeTTaChainer()
            for name in ('report', second):
                h.add_atom(f'(: {name} (Not (And A B C)) (STV 1 0.99))')
            for _ in range(2):
                row, = h.query_many_refs(['(: $p (And A B C) $tv)'], steps=400)[0]
                self.assertEqual(row.tv[1], 0)
                self.assertAlmostEqual(row.tv[2], confidence, delta=1e-12)
                self.assertEqual(h.expand_proof(row.proof), proof)
            sources = janus.query_once(
                "source_catalog_sources(['And','A','B','C'],[Kb,'MAIN','Nil'],Sources)",
                {'Kb': h.kb})['Sources']
            self.assertEqual(len(sources), 1 if second == 'report' else 2)

    def test_late_report_replaces_the_graph_read_of_its_key(self):
        h = PeTTaChainer()
        h.add_atom('(: first (And A B) (STV 1 0.99))')
        row, = h.query_many_refs(['(: $p (And A C) $tv)'], steps=400)[0]
        self.assertEqual(h.expand_proof(row.proof), '(node (conjunction first))')
        h.add_atom('(: second (And A C) (STV 0.2 0.9))')
        row, = h.query_many_refs(['(: $p (And A C) $tv)'], steps=400)[0]
        self.assertEqual(row.tv, ['STV', .2, .9])
        self.assertEqual(h.expand_proof(row.proof), 'second')


if __name__ == '__main__':
    unittest.main()
