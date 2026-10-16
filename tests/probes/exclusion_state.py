"""Context-node soundness, publication and interruption in a fresh runtime."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class ExclusionStateTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_query_metrics(True)

    def node(self, name, cuts=(), deps=(), strength=.4, kind='key'):
        key = ['sk-key', [name], [self.h.kb, 'MAIN', 'Nil']]
        if kind == 'fold':
            key = ['sk-fold', [self.h.kb, [name, 'x'], 'extract-tv', ['BaseRateEvidence', 0.0, 0.0], 'BaseRateAcc', 'base-rate', 'result-tv']]
        return janus.query_once(
            "'index-hash'(Key,H),cn_digest(Key,0,_D),sort(Cuts,_Cuts),cn_id('&sk_context',_D,_Cuts,Id), "
            "'deps-join'(Deps,_Deps), "
            "(Key=['sk-key',_Type,_Scope] -> _V=['sk-val',[_Type,_Scope,old,['STV',Strength,0.8]],['ev-set',0],_Deps] "
            "; _V=['sk-goal-val',['CPU','FoldAllCompiled',_Args,['STV',Strength,0.8]],old,['ev-set',0],_Deps],Key=['sk-fold',_Args]), "
            "cn_add('&sk_context',[_D,Id,H,Key,0,0,_Cuts,_Cuts,_Deps,_V,true]), "
            "cn_add('&sk_context_id',[Id,'&sk_context',_D])",
            dict(Key=key, Cuts=list(cuts), Deps=list(deps), Strength=strength)) | {'Key': key}

    def test_exact_reuse_requires_cuts_and_disjoint_dependencies(self):
        # Reuse sees recorded cuts, including empty values, rather than E equality.
        dep = janus.query_once("'deps-key'(771,Dep)")['Dep']
        n = self.node('Reuse', [772], [dep])
        for exclusion, expected in (([772], True), ([772, 773], True), ([], False), ([771, 772], False)):
            r = janus.query_once(
                "cn_digest(Key,0,_D),cn_reusable('&sk_context',_D,Key,E,Id,_V)",
                dict(H=n['H'], Key=n['Key'], Id=n['Id'], E=exclusion))
            self.assertEqual(r['truth'], expected, exclusion)

    def test_distinct_keys_with_the_same_index_hash_have_distinct_nodes(self):
        result = janus.query_once(
            "A=['sk-key',['CollisionA'],[Kb,'MAIN','Nil']], "
            "B=['sk-key',['CollisionB'],[Kb,'MAIN','Nil']], "
            "cn_ensure('&sk_context',123,A,0,0,[],AI), "
            "cn_ensure('&sk_context',123,B,0,0,[],BI), AI\\==BI, "
            "cn_node(AI,_,[_,_,123,A|_]),cn_node(BI,_,[_,_,123,B|_])",
            dict(Kb=self.h.kb))
        self.assertTrue(result['truth'])

    def test_miss_is_pending_without_inline_row_evaluation(self):
        result = janus.query_once(
            "_Key=['sk-key',['Missing'],[Kb,'MAIN','Nil']], "
            "'begin-backward-query-metrics!'(_), 'sk-value'(_Key,'sk-any-filter',[],V), "
            "'query_metric_value'('row-computes',Computes), "
            "cn_rows('&sk_context_merge',[_D,_Id,_H,_Key,-1,-1,[],[],0,'sk-none',State])",
            dict(Kb=self.h.kb))
        self.assertEqual((result['V'], result['Computes'], result['State']), ('sk-none', 0, 'pending'))

    def test_identical_republication_does_not_dirty_reader(self):
        producer, reader = self.node('Producer'), self.node('Reader')
        result = janus.query_once(
            "cn_edge(P,R),cn_node(P,_,[_,_,_,Key,_,_,_,_,D,_V,_]), "
            "Key=['sk-key',T,S],cn_settled(P,['sk-val',[T,S,new_proof,['STV',0.4,0.8]],['ev-set',0],D],[]), "
            "cn_node(R,_,[_,_,_,_,_,_,_,_,_,_,State])",
            dict(P=producer['Id'], R=reader['Id']))
        self.assertEqual(result['State'], 'true')

    def test_dependency_dag_shape_is_not_a_value_change(self):
        producer, reader = self.node('DagShape'), self.node('DagReader')
        result = janus.query_once(
            "'deps-key'(751,A),'deps-key'(752,B),'deps-key'(753,C), "
            "'deps-join'([A,B],AB),'deps-join'([AB,C],OldDeps), "
            "'deps-join'([B,C],BC),'deps-join'([A,BC],NewDeps),OldDeps\\==NewDeps, "
            "cn_node(P,S,Old),Old=[D,P,H,K,RH,Q,E,Cuts,_,_,Fresh],K=['sk-key',T,Scope], "
            "cn_replace(S,Old,[D,P,H,K,RH,Q,E,Cuts,OldDeps,['sk-val',[T,Scope,old,['STV',0.4,0.8]],['ev-set',0],OldDeps],Fresh]), "
            "cn_edge(P,R),cn_settled(P,['sk-val',[T,Scope,new,['STV',0.4,0.8]],['ev-set',0],NewDeps],[]), "
            "cn_node(R,_,[_,_,_,_,_,_,_,_,_,_,State])",
            dict(P=producer['Id'], R=reader['Id']))
        self.assertEqual(result['State'], 'true')

    def test_alias_to_reader_does_not_create_a_self_subscription(self):
        n = self.node('Alias')
        result = janus.query_once(
            "nb_setval(context_node_progress,0),cn_ensure('&sk_context',H,Key,0,0,[701],Pending), "
            "cn_edge(Pending,Canonical),cn_alias(Pending,Canonical), "
            "cn_node(Canonical,_,[_,_,_,_,_,_,_,_,_,_,State]), "
            "aggregate_all(count,cn_rows('&sk_context_reader',[Canonical,Canonical]),SelfEdges)",
            dict(H=n['H'], Key=n['Key'], Canonical=n['Id']))
        self.assertEqual((result['State'], result['SelfEdges']), ('true', 0))

    def test_h1_force_is_consumed_once_per_node_and_cause(self):
        n = self.node('ForceCauses')
        result = janus.query_once(
            "cn_dirty(Id,[781]),cn_node(Id,_,[_,_,_,['sk-key',T,S],_,_,_,_,D,_,_]), "
            "cn_settled(Id,['sk-val',[T,S,new,['STV',0.7,0.8]],['ev-set',0],D],[]), "
            "cn_dirty(Id,[781]),findall(_Cause,cn_rows('&sk_context_forced',[Id,_Cause]),Repeated), "
            "cn_dirty(Id,[782]),findall(_Cause,cn_rows('&sk_context_forced',[Id,_Cause]),Distinct)",
            dict(Id=n['Id']))
        self.assertEqual(result['Repeated'], [])
        self.assertEqual(result['Distinct'], [782])

    def test_changed_publication_only_dirties_subscribers_of_that_node(self):
        a, sibling, reader, other = self.node('Class'), self.node('Class', [778]), self.node('ReadA'), self.node('ReadB')
        result = janus.query_once(
            "cn_edge(A,R),cn_edge(B,O),cn_node(A,_,[_,_,_,['sk-key',T,S],_,_,_,_,D,_,_]), "
            "cn_settled(A,['sk-val',[T,S,new,['STV',0.7,0.8]],['ev-set',0],D],[]), "
            "cn_node(R,_,[_,_,_,_,_,_,_,_,_,_,RS]),cn_node(O,_,[_,_,_,_,_,_,_,_,_,_,OS])",
            dict(A=a['Id'], B=sibling['Id'], R=reader['Id'], O=other['Id']))
        self.assertEqual((result['RS'], result['OS']), ('false', 'true'))

    def test_conditioned_publication_does_not_dirty_an_unsubscribed_fold(self):
        member = self.node('ConditionedMember', [779])
        fold = self.node('UnsubscribedFold', kind='fold')
        result = janus.query_once(
            "cn_node(P,_,[_,_,H,K,_,_,_,_,D,_,_]), "
            "setup_call_cleanup(assertz('&sk_use'(H,K,Fold)), "
            "(K=['sk-key',T,S],cn_settled(P,['sk-val',[T,S,new,['STV',0.7,0.8]],['ev-set',0],D],[779]), "
            "cn_node(F,_,[_,_,_,_,_,_,_,_,_,_,State])),retractall('&sk_use'(H,K,Fold)))",
            dict(P=member['Id'], F=fold['Id'], Fold=fold['Key']))
        self.assertEqual(result['State'], 'true')

    def test_fold_tolerance_compares_value(self):
        producer, reader = self.node('Fold', kind='fold'), self.node('FoldReader')
        for strength, expected in ((.400000001, 'true'), (.7, 'false')):
            result = janus.query_once(
                "cn_edge(P,R),cn_node(P,_,[_,_,_,['sk-fold',Args],_,_,_,_,D,_,_]), "
                "cn_settled(P,['sk-goal-val',['CPU','FoldAllCompiled',Args,['STV',Strength,0.8]],new,['ev-set',0],D],[]), "
                "cn_node(R,_,[_,_,_,_,_,_,_,_,_,_,State])",
                dict(P=producer['Id'], R=reader['Id'], Strength=strength))
            self.assertEqual(result['State'], expected)

    def test_fold_coverage_and_negative_ctv_branch_are_values(self):
        for coverage in (False, True):
            producer = self.node(f'Parameter{coverage}', kind='fold')
            reader = self.node(f'ParameterReader{coverage}')
            result = janus.query_once(
                "cn_edge(P,R),cn_node(P,S,Old),Old=[D,P,H,K,RH,Q,E,C,Deps,_V,F],K=['sk-fold',Args], "
                "(Coverage==true -> _Before=['STV',0.4,0.8],_After=_Before,_Proof=['partial-fold',0,1,cpu] "
                "; _Before=['CTV',['STV',0.4,0.8],['STV',0.2,0.8]], "
                "_After=['CTV',['STV',0.4,0.8],['STV',0.7,0.8]],_Proof=new), "
                "cn_replace(S,Old,[D,P,H,K,RH,Q,E,C,Deps,['sk-goal-val',['CPU','FoldAllCompiled',Args,_Before],old,['ev-set',0],Deps],F]), "
                "cn_settled(P,['sk-goal-val',['CPU','FoldAllCompiled',Args,_After],_Proof,['ev-set',0],Deps],[]), "
                "cn_node(R,_,[_,_,_,_,_,_,_,_,_,_,State])",
                dict(P=producer['Id'], R=reader['Id'], Coverage=coverage))
            self.assertEqual(result['State'], 'false')

    def test_h1_rejected_value_keeps_its_exclusion_class(self):
        dep = janus.query_once("'deps-key'(771,Dep)")['Dep']
        ordinary = self.node('Held', deps=[dep])
        result = janus.query_once(
            "Key=['sk-key',T,S],Row=['sk-row',['sk-ident',-1,[],Key],[T,S,old,['STV',0.4,0.8]],[],0], "
            "cn_add('&sk_support',[H,0,Dep]), "
            "setup_call_cleanup(assertz('&sk_row'(H,Key,0,Row)), "
            "setup_call_cleanup(wrap_predicate('sk-row-view'(_G,_E,_H,_K,_RH,_Row,_View),ctx_class,_Call, "
            "_View=['sk-val',[T,S,new,['STV',0.7,0.8]],['ev-set',0],0]), "
            "(nb_setval(context_node_progress,0),cn_ensure('&sk_context',H,Key,0,0,[771],Id),cn_compute(Id)), "
            "unwrap_predicate('sk-row-view'(_,_,_,_,_,_,_),ctx_class)), "
            "retractall('&sk_row'(H,Key,0,Row))), "
            "cn_digest(Key,0,D),cn_reusable('&sk_context',D,Key,[771],_,Value), "
            "cn_node(Ordinary,_,[_,_,_,_,_,_,[],[],_,Original,_])",
            dict(H=ordinary['H'], Key=ordinary['Key'], Dep=dep, Ordinary=ordinary['Id']))
        self.assertEqual(result['Value'][1][3], ['STV', .7, .8])
        self.assertEqual(result['Original'][1][3], ['STV', .4, .8])

    def test_class_growth_is_visible_without_an_eight_entry_cap(self):
        key = ['sk-key', ['Classes'], [self.h.kb, 'MAIN', 'Nil']]
        result = janus.query_once(
            "'index-hash'(Key,H),forall(between(1,9,_C),cn_ensure('&sk_context',H,Key,0,0,[_C],_)), "
            "cn_digest(Key,0,D),aggregate_all(count,cn_rows('&sk_context',[D,_,_,_,_,_,_,_,_,_,_]),Count), "
            "'sk-context-metrics!'(_),'query_metric_value'('context-classes-max',Maximum)",
            dict(Key=key))
        self.assertEqual(result['Count'], 9)
        self.assertGreaterEqual(result['Maximum'], 9)

    def test_excluded_leaf_records_only_original_request_cuts(self):
        n = self.node('Recorder', [901])
        result = janus.query_once(
            "setup_call_cleanup((nb_setval(context_node_active,Id),nb_setval(context_node_cuts,[])), "
            "('deps-key'(901,_D),'sk-excludes?'([901],_D,true), "
            "'deps-key'(902,_Other),'sk-excludes?'([902],_Other,true),nb_getval(context_node_cuts,Cuts), "
            "cn_node(Id,_,[_,_,_,['sk-key',T,S],_,_,_,_,D,_,_]), "
            "cn_publish(Id,['sk-val',[T,S,old,['STV',0.4,0.8]],['ev-set',0],D]), "
            "cn_node(Id,_,[_,_,_,_,_,_,_,Stored,_,_,_])), "
            "nb_setval(context_node_active,none))",
            dict(Id=n['Id']))
        self.assertEqual(result['Cuts'], [901, 902])
        self.assertEqual(result['Stored'], [901])
        # cn_publish intersects this accumulator with the node's actual E;
        # local closed-read exclusions cannot widen its stored cut class.

    def test_interrupted_compute_clears_active_reader(self):
        self.h.add_atoms_no_check([
            '(: seed (Input a) (STV 1 0.8))',
            '(: (no_inverse rule) (Implication (Input a) (Output a)) (STV 1 1))',
        ])
        self.h.query_many_refs(['(: $p (Output a) $tv)'], steps=200)
        result = janus.query_once(
            "once((cn_rows('&sk_context',[_D,Id,_H,['sk-key',['Output',a],[Kb,'MAIN','Nil']],_R,_Q,[],_,_,_,_]))), "
            "setup_call_cleanup(wrap_predicate('sk-row-view'(_G,_E,_KH,_K,_RH,_Row,_V),ctx_fault,_Call,throw(ctx_interrupted)), "
            "catch(cn_compute(Id),ctx_interrupted,true),unwrap_predicate('sk-row-view'(_,_,_,_,_,_,_),ctx_fault)), "
            "nb_getval(context_node_active,Active)",dict(Kb=self.h.kb))
        self.assertEqual(result['Active'], 'none')
        self.assertTrue(self.h.query_many_refs(['(: $p (Output a) $tv)'], steps=200)[0])


if __name__ == '__main__':
    unittest.main(verbosity=2)
