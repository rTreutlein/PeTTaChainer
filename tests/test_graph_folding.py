"""Co-occurring roots preserve the enumerated posterior and its moment bound."""
import itertools
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer


class GraphFoldingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = PeTTaChainer()

    def compare(self, parent, goal, extra='[]', width=4):
        roots = list('abcdefghi'[:width])
        models = ','.join(f'model({t},root,[])' for t in roots)
        variables = ','.join(f'{t}-beta({i+1},{i+2})' for i, t in enumerate(roots))
        case = (f'input([{models},model(r,conditional({parent},[],[\'STV\',0.8,0.4],'
                f'[\'STV\',0.1,0.6]),[])],[[r,s,rep,[\'STV\',0.9,0.8]]|{extra}],'
                f'{goal},[{variables},branch(r,1)-beta(3,2),branch(r,0)-beta(1,4)])')
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
                self.assertEqual(self.compare(parent, 'a'), 3)
                self.assertEqual(self.compare(parent, parent), 2)

    def test_nested_paths_separate_connectives(self):
        self.assertEqual(self.compare("['Or',['And',a,b],['And',c,d]]", 'r'), 3)

    def test_separate_reports_and_mixed_occurrences_prevent_folding(self):
        self.assertEqual(self.compare("['And',a,b,c,d]", 'a', "[[b,s,other,['STV',0.2,0.9]]]"), 4)
        self.assertEqual(self.compare("['And',['Or',a,b],['And',a,b],c,d]", 'r'), 4)

    def test_repeated_and_reordered_literals_remain_one_event(self):
        self.assertEqual(self.compare("['And',d,b,a,c,b,a]", "['And',a,b,c,d]"), 2)

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
