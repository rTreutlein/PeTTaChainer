"""Construction metadata survives explanation changes and shares proof lifetime."""
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer


class ProofSemanticsTests(unittest.TestCase):
    def setUp(self):
        self.chainer = PeTTaChainer()

    def test_prior_and_givens_do_not_decode_a_stored_explanation(self):
        result = janus.query_once(
            "'next-search-id'(proof_id,Pid), "
            "P=[['inverted',r,with,cpu,[prior,['STV',0.3,0.8]]],observation], "
            "'record-proof!'(Pid,-1,P,['ev-set',0],0,[],Ref), "
            "'proof-semantic'(P,Inline), 'proof-semantic'(Ref,Recorded), "
            "'sk-prior-update-of'(kb,Ref,['STV',0.7,0.9],Before), "
            "retract(user:'&proof'(Pid,P,Ev,Flags)), "
            "assertz(user:'&proof'(Pid,new_explanation,Ev,Flags)), "
            "'proof-semantic'(Ref,After), "
            "'sk-prior-update-of'(kb,Ref,['STV',0.7,0.9],PriorAfter), "
            "proof_dag_expand(Ref,Printed), 'proof-given-evidence'(Ref,Given), "
            "forall(clause(user:'&proof'(Pid,_,_,_),true,_C), "
            " refs_gc_erase(proofs,user:'&proof'(Pid,_,_,_),_C)), "
            "(proof_metadata(Pid,_,_,_,_,_,_,_,_,_)->Collected=false;Collected=true)"
        )
        self.assertEqual(result['Inline'], result['Recorded'])
        self.assertEqual(result['Recorded'], result['After'])
        self.assertEqual(result['Before'], result['PriorAfter'])
        self.assertEqual(result['Printed'], 'new_explanation')
        self.assertEqual(result['Given'], ['ev-set', 0])
        self.assertEqual(result['Collected'], 'true')

    def test_dominance_reads_the_stored_route(self):
        result = janus.query_once(
            "J=[['node-joint',spec,source],[conjunction,p,q]], "
            "'next-search-id'(proof_id,Pid), "
            "'record-proof!'(Pid,-1,J,['ev-set',0],0,[],Ref), "
            "'proof-dominates?'(J,[conjunction,p,q],Inline), "
            "'proof-dominates?'(Ref,[conjunction,p,q],Stored), "
            "'proof-dominates?'(source,['conditional-implication',[by,source,[given,true]]],Statement), "
            "forall(clause(user:'&proof'(Pid,_,_,_),true,_C), "
            " refs_gc_erase(proofs,user:'&proof'(Pid,_,_,_),_C))"
        )
        self.assertEqual(result['Inline'], 'true')
        self.assertEqual(result['Stored'], 'true')
        self.assertEqual(result['Statement'], 'true')

    def test_settled_step_stands_for_its_complete_step(self):
        # Or(Stock, Driver) is certain through the stock alone. Its complete
        # step also reads Driver, so a later premise reading Driver would
        # clash with it; the settled step keeps the stock's support only.
        self.chainer.add_atoms_no_check(['(: stock (Stock x) (STV 1 1))', '(: shared (Driver x) (STV 0.6 0.9))'])
        result = janus.query_once(
            "_Scope=[Kb,'MAIN','Nil'], _S=['Stock',x], _X=['Driver',x], _O=['Or',_S,_X], "
            "'index-hash'(['sk-key',_S,_Scope],_SH), 'index-hash'(['sk-key',_X,_Scope],_XH), "
            "'sk-leaf-view'(_SH,[_S,_Scope,stock,['STV',1,1]],['sk-val',_,_SE,_SD]), "
            "'sk-leaf-view'(_XH,[_X,_Scope,shared,['STV',0.6,0.9]],['sk-val',_,_XE,_XD]), "
            "'evidence-union'(_SE,_XE,_FE), 'deps-union'(_SD,_XD,_FD), "
            "_Settled=['sk-val',[_O,_Scope,[settled,stock],['STV',1,1]],_SE,_SD], "
            "_Full=['sk-val',[_O,_Scope,[conjunction,stock,shared],['STV',1,1]],_FE,_FD], "
            "_Views=[_Settled,_Full], 'sk-standing-step'(_Views,[],_Settled,_K1), 'sk-standing-step'(_Views,_K1,_Full,_Kept), "
            "_Kept=[['sk-val',[_,_,Proof,_],_,_]], "
            "'sk-use-premise'(false,['sk-acc',[],_XE,_XD],[_O,_Scope,_,_],_Settled,_Read), "
            "'sk-use-premise'(false,['sk-acc',[],_XE,_XD],[_O,_Scope,_,_],_Full,Clash), "
            "_Read=[Accepted|_]",
            {'Kb': self.chainer.kb},
        )
        self.assertEqual(result['Proof'], ['settled', 'stock'])
        self.assertEqual(result['Accepted'], 'sk-acc')
        self.assertEqual(result['Clash'], 'sk-fail')

    def test_record_captures_catalog_role_result_and_dependencies(self):
        h = self.chainer
        h.add_atoms_no_check([
            '(: source-rule (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.2 0.9)))',
            '(: a (A item) (STV 1 1))',
        ])
        h.query_many_refs(['(: $p (B item) $tv)'], steps=100)
        result = janus.query_once(
            "once((proof_metadata(Pid,Role,Owner,[application,'source-rule',_],_,Deps,_,_,_,_), "
            " user:'&proof_fact'(Pid,Type,TV), "
            " user:'&proof'(Pid,_,Ev,Flags))), "
            "(Role=['forward-source','source-rule',_,_,_,_]->Catalog=true;Catalog=false), "
            "Code is Flags >> 1, (Code=:=Owner->SameOwner=true;SameOwner=false), "
            "'deps-gc!'([],true), (deps_node(Deps,_,_,_)->DepsLive=true;DepsLive=false)"
        )
        self.assertEqual(result['Catalog'], 'true')
        self.assertEqual(result['SameOwner'], 'true')
        self.assertEqual(result['Type'], ['B', 'item'])
        self.assertEqual(result['DepsLive'], 'true')
        self.assertGreater(result['Owner'], 0)

    def test_new_semantic_tags_in_user_proofs_are_opaque(self):
        result = janus.query_once(
            "findall(_S, (member(_P,[[application,r,[p]],['prior-update',inversion,r,cpu,tv,p], "
            " [message,source,likelihood,0,[]]]), 'proof-semantic'(_P,_S)), Semantics), "
            "_P=[_Head,r,p], 'proof-semantic'(_P,_), "
            "'next-search-id'(proof_id,_Pid), "
            "'record-proof!'(_Pid,-1,_P,['ev-set',0],0,[],_), "
            "(var(_Head)->Unbound=true;Unbound=false), "
            "forall(clause(user:'&proof'(_Pid,_,_,_),true,_C), "
            " refs_gc_erase(proofs,user:'&proof'(_Pid,_,_,_),_C))"
        )
        self.assertTrue(all(row[0] == 'opaque-proof' for row in result['Semantics']))
        self.assertEqual(result['Unbound'], 'true')

    def test_application_template_outlives_executable_explanation_layout(self):
        h = self.chainer
        h.add_atom('(: source-template (Implication (A $x) (B $x)) (STV 0.8 0.9))')
        result = janus.query_once(
            "once((rule_name_index('source-template',Id), 'application-rule'(Id,_Before))), "
            "setup_call_cleanup(retract(ccls_index([_T,_S,_P,_V],Id,_Ps)), "
            " ('application-rule'(Id,_After), 'proof-application-name'(Id,Name)), "
            " assertz(ccls_index([_T,_S,_P,_V],Id,_Ps))), "
            "_Before =@= _After, 'source-catalog-remove!'(Id,true), "
            "(proof_template(Id,_,_,_)->Removed=false;Removed=true)"
        )
        self.assertEqual(result['Name'], 'source-template')
        self.assertEqual(result['Removed'], 'true')


if __name__ == '__main__':
    unittest.main()
