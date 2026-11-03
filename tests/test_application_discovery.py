"""Application bindings are shared by discovery clients and retained by rows."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestApplicationDiscovery(unittest.TestCase):
    def test_clients_preserve_the_same_bound_application(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: (no_inverse r) (Implication (A $x) (B $x)) (CTV (STV 0.9 0.8) (STV 0.1 0.8)))',
            '(: a (A a) (STV 1 1))',
        ])
        result = janus.query_once(
            "_Scope=[Kb,'MAIN','Nil'], "
            "once((ccls_index(_C,_Id,_P), _C=[['B',_],_Scope,_Proof,_], "
            " 'rule-application-proof?'(_Proof,true))), "
            "_Goal=[['B',a],_Scope,_,_], "
            "findall(_Plan,('sk-rule-match'(_Goal,_Plan),_Plan=['sk-match',_Id,_,_]),_Backward), "
            "findall(_Plan,'discover-application'(_Id,_C,_P,_Goal,_Plan),_Late), "
            "'forward-premise-keys'([['A',a],_Scope,_,_],[_Trigger,_]), "
            "findall(_Plan,('discover-triggered-applications'(['sk-key',['A',a],_Scope],_Trigger,_Plan), "
            " _Plan=['sk-match',_Id,_,_]),_Forward), "
            "_Backward=[_B],_Late=[_L],_Forward=[_F], "
            "(attribute_free_variant(_B,_L), attribute_free_variant(_L,_F) -> Same=true ; Same=false), "
            "_B=['sk-match',_Id,_Inputs,[['B',Bound],_,_,_]], "
            "member([['A',Bound],_,_,_],_Inputs)", {'Kb': h.kb})
        self.assertTrue(result['truth'], result)
        self.assertEqual(result['Same'], 'true')
        self.assertEqual(result['Bound'], 'a')

    def test_late_rules_and_facts_keep_open_answers(self):
        late = PeTTaChainer()
        cold = PeTTaChainer()
        rule = '(: (no_inverse r) (Implication (A $x) (B $x)) (CTV (STV 0.9 0.8) (STV 0.1 0.8)))'
        facts = ['(: a (A a) (STV 1 1))', '(: b (A b) (STV 1 1))']
        late.add_atoms_no_check(facts)
        self.assertEqual(late.query('(: $p (B $x) $tv)', steps=80, timeout_sec=None), [])
        late.add_atoms_no_check([rule])
        cold.add_atoms_no_check([rule, *facts])
        for h in (late, cold):
            rows = h.query_many_refs(['(: $p (B $x) $tv)'], steps=80)[0]
            self.assertEqual(sorted(r.statement for r in rows), [['B', 'a'], ['B', 'b']])
            for row in rows:
                self.assertAlmostEqual(row.tv[1], .9)
                self.assertAlmostEqual(row.tv[2], .8)
        for h in (late, cold):
            h.add_atoms_no_check(['(: c (A c) (STV 1 1))'])
        self.assertEqual(late.query('(: $p (B $x) $tv)', steps=80, timeout_sec=None),
                         cold.query('(: $p (B $x) $tv)', steps=80, timeout_sec=None))

    def test_completion_plan_preserves_its_output_binding(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a (A i) (STV 1 1))', '(: c (C i) (STV 1 1))',
            '(: r (Implication (And (A $x) (B $x)) (C $x)) (CTV (STV 0.9 1) (STV 0.1 1)))',
        ])
        h._call('set-base-rate', [f'{h.kb} (B $x) (STV 0.3 0.9)'])
        self.assertTrue(h.query('(: $p (B i) $tv)', steps=200, timeout_sec=None))
        result = janus.query_once(
            "once(('&sk_row'(_,_,_,['sk-row',['sk-ident',_Id,_,_],_Conclusion,_Premises,_]), "
            " _Conclusion=[['B',i],[Kb,'MAIN','Nil'],_,_RowTV], "
            " 'application-read-plan'(_Id,_Conclusion,_Premises, "
            "   ['application-inputs',_,_,_,_,['completion-inputs',_Compound,_,_Observed,_After,_]]))), "
            "_Observed=[['C',i],_,_,_], _Compound=['sk-key',['And'|_],[Kb,'MAIN','Nil']], "
            "last(_After,['CPU',_,_,_Output]), (_Output==_RowTV -> Linked=true ; Linked=false)",
            {'Kb': h.kb})
        self.assertTrue(result['truth'], result)
        self.assertEqual(result['Linked'], 'true')
    def test_transported_proof_policy_waits_for_premise_binding(self):
        h = PeTTaChainer()
        result = janus.query_once(
            "'application-read-plan'(-1,[['Transported'],[Kb,'MAIN','Nil'],_Proof,['STV',0.9,0.8]],[], "
            " ['application-inputs',false,false,false,_Policy,_]), "
            "var(_Proof), _Proof=[by,r,a], 'proof-input-entanglement?'(_Policy,Entangles)",
            {'Kb': h.kb})
        self.assertTrue(result['truth'], result)
        self.assertEqual(result['Entangles'], 'true')
    def test_late_fact_selector_binds_the_conclusion_through_its_premise(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: (no_inverse r) (Implication (A $x) (B $x)) (CTV (STV 0.9 0.8) (STV 0.1 0.8)))',
        ])
        result = janus.query_once(
            "_Scope=[Kb,'MAIN','Nil'], "
            "once((ccls_index([['B',_],_Scope,_Proof,_],_Id,_), "
            " 'rule-application-proof?'(_Proof,true))), "
            "'statement-prefix-hashes'(['A',a],_Hashes), 'index-hash'('A',_Head), "
            "findall(_Key,(member(_Hash,[_Head|_Hashes]),'prefix-key'(Kb,_Hash,_Key)),_Prefixes), "
            "findall(_Subject,(member(_Prefix,_Prefixes), "
            " 'sk-premise-rules-step'(['A',a],_Scope,_Prefix,[],_Plans), "
            " member(['sk-match',_Id,_,[['B',_Subject],_Scope,_,_]],_Plans), "
            " ground(_Subject)),Subjects)", {'Kb': h.kb})
        self.assertTrue(result['truth'], result)
        self.assertEqual(result['Subjects'], ['a'])
