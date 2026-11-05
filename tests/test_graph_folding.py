"""Co-occurring roots preserve the enumerated posterior and its moment bound."""
import itertools
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer


class GraphFoldingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = PeTTaChainer()

    def compare(self, parents, goal, extra='[]', width=4):
        roots = list('abcdefghi'[:width])
        models = ','.join([f'model({t},root,[])' for t in roots] + [
            f"model(r{i},conditional({p},[],['STV',0.8,0.4],['STV',0.1,0.6]),[])" for i, p in enumerate(parents)])
        reports = ','.join(f"[r{i},s,rep{i},['STV',0.9,0.8]]" for i in range(len(parents)))
        variables = ','.join([f'{t}-beta({i+1},{i+2})' for i, t in enumerate(roots)] + [
            f'branch(r{i},1)-beta(3,2),branch(r{i},0)-beta(1,4)' for i in range(len(parents))])
        case = f'input([{models}],[{reports}|{extra}],{goal},[{variables}])'
        out = janus.query_once(
            'term_string(input(_M,_F,_G,_V),Text),graph_moments(_M,_F,_G,_V,Before),'
            'graph_fold(_M,_F,_G,_V,_Ms,_Fs,_Gs,_Vs),'
            'graph_moments(_Ms,_Fs,_Gs,_Vs,After),length(_Ms,Size)', {'Text': case})
        self.assertTrue(out['truth'])
        for a, b in zip(out['Before'][1:], out['After'][1:]):
            self.assertAlmostEqual(a, b, delta=1e-12)
        return out['Size']

    def test_signed_and_or_blocks_match_full_world_enumeration(self):
        for head, negative in itertools.product(('And', 'Or'), (False, True)):
            with self.subTest(head=head, negative=negative):
                literals = [f"['Not',{t}]" if negative else t for t in 'abcd']
                parent = f"['{head}',{','.join(literals)}]"
                self.assertEqual(self.compare([parent], 'a'), 3)
                self.assertEqual(self.compare([parent], parent), 2)

    def test_nested_paths_separate_connectives(self):
        self.assertEqual(self.compare(["['Or',['And',a,b],['And',c,d]]"], 'r0'), 3)

    def test_separate_reports_and_mixed_occurrences_prevent_folding(self):
        self.assertEqual(self.compare(["['And',a,b,c,d]"], 'a', "[[b,s,other,['STV',0.2,0.9]]]"), 4)
        self.assertEqual(self.compare(["['And',['Or',a,b],['And',a,b],c,d]"], 'r0'), 4)

    def test_repeated_and_reordered_literals_remain_one_event(self):
        self.assertEqual(self.compare(["['And',d,b,a,c,b,a]"], "['And',a,b,c,d]"), 2)

    def test_partially_overlapping_reports_fold_by_occurrence_signature(self):
        first, second = "['And',a,b,c,d,e]", "['And',c,d,e,f,g]"
        # Blocks: {a,b} only first, {c,d,e} both, {f,g} only second; a goal literal stays its own root.
        for goal, size in (('a', 6), ('c', 6), ('f', 6), ('r0', 5), (first, 5), (f"['And',{first},{second}]", 5)):
            with self.subTest(goal=goal):
                self.assertEqual(self.compare([first, second], goal, width=7), size)
        self.assertEqual(self.compare([first, "['Or',c,d,e,f,g]"], 'a', width=7), 8)
        self.assertEqual(self.compare([first, "['And',['Not',c],d,e,f,g]"], 'a', width=7), 7)

    def test_refined_proof_metadata_does_not_leave_the_numerical_cache_unindexed(self):
        result = janus.query_once(
            "graph_fold([model(a,root,[[a,s,_Source,['STV',0.5,0.5]]]),"
            "model(r,conditional(a,[1-rule],['rule-truth',['RuleTruth',"
            "['Implication',['P',_X],['Q',_X]]]],refined),[])],"
            "[[r,s,_Report,['STV',1,1]]],a,"
            "[a-beta(2,2),branch(r,1)-beta(3,2),branch(r,0)-beta(1,4)],_M,_F,_G,_V),"
            "term_hash(_M-_F-_G-_V,_Hash),(integer(_Hash)->Indexed=1;Indexed=0)")
        self.assertEqual(result['Indexed'], 1)

    def test_nineteen_part_refined_rule_has_a_constituent_and_joint_answer(self):
        values = []
        for refine in (False, True):
            h = PeTTaChainer()
            h.set_rule_refinement(refine)
            parts = [f'(P{i} now)' for i in range(19)]
            parent = '(And ' + ' '.join(parts) + ')'
            h.add_atoms_no_check([
                f'(: likelihood (Implication {parent} (Report now)) (CTV (STV 0.8 0.1) (STV 0.1 0.1)))',
                '(: report (Report now) (STV 1 1))',
            ])
            rows = h.query_many_refs([f'(: $p {q} $tv)' for q in (parts[0], parent)], steps=500)
            self.assertEqual([len(rs) for rs in rows], [1, 1])
            # Independent world sum with uniform roots: m0 + (m1-m0) prod(p).
            n = 800 * .1 / .9
            m1, m0 = (n*.8+1)/(n+2), (n*.1+1)/(n+2)
            z = m0 + (m1-m0)*2**-19
            expected = [(.5*m0+(m1-m0)*2**-19)/z, m1*2**-19/z]
            for rs, strength in zip(rows, expected):
                self.assertAlmostEqual(rs[0].tv[1], strength, delta=1e-12)
            values.append([rs[0].tv for rs in rows])
        self.assertEqual(*values)

    def test_overlapping_reports_above_the_discovery_width_answer_exactly(self):
        # Two reports share six of their sixteen parts: 26 roots, three occurrence blocks after folding.
        first, second = range(16), range(10, 26)
        h = PeTTaChainer()
        conj = lambda parts: '(And ' + ' '.join(f'(P{i} now)' for i in parts) + ')'
        h.add_atoms_no_check([
            f'(: l1 (Implication {conj(first)} (ReportA now)) (CTV (STV 0.8 0.1) (STV 0.1 0.1)))',
            f'(: l2 (Implication {conj(second)} (ReportB now)) (CTV (STV 0.7 0.1) (STV 0.2 0.1)))',
            '(: a (ReportA now) (STV 1 1))',
            '(: b (ReportB now) (STV 1 1))',
        ])
        goals = [{0}, {12}, {20}, set(first), set(first) | set(second)]
        queries = [f'(: $p {conj(sorted(g)) if len(g) > 1 else f"(P{min(g)} now)"} $tv)' for g in goals]
        # Budget zero computes no new posterior.
        self.assertEqual(h.query_many_refs(queries, steps=0), [[]] * len(goals))
        rows = h.query_many_refs(queries, steps=500)
        n = 800 * .1 / .9
        likelihood = [[(n*s+1)/(n+2) for s in pair] for pair in ((.1, .8), (.2, .7))]
        # Uniform roots: enumerate the all-true events of the membership classes.
        def posterior(goal):
            classes = {}
            for i in range(26):
                classes.setdefault((i in first, i in second, i in goal), []).append(i)
            keys = list(classes)
            z = hit = 0.0
            for bits in itertools.product((0, 1), repeat=len(keys)):
                w = 1.0
                for key, b in zip(keys, bits):
                    q = .5 ** len(classes[key])
                    w *= q if b else 1 - q
                holds = lambda j: all(b for key, b in zip(keys, bits) if key[j])
                w *= likelihood[0][holds(0)] * likelihood[1][holds(1)]
                z += w
                hit += w * holds(2)
            return hit / z
        self.assertEqual([len(rs) for rs in rows], [1] * len(goals))
        for rs, goal in zip(rows, goals):
            with self.subTest(goal=sorted(goal)[:3]):
                self.assertAlmostEqual(rs[0].tv[1], posterior(goal), delta=1e-12)

