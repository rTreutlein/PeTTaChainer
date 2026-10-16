"""Context-node soundness, publication and interruption in a fresh runtime."""
import json
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class ExclusionStateTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_query_metrics(True)

    def test_fuzzer_22000082_does_not_starve_its_third_root(self):
        fixture = json.loads((Path(__file__).resolve().parents[1] / 'data/context_seed22000082.json').read_text())
        self.h.set_evidence_confidence_k(fixture['k'])
        for head in fixture['complete']:
            self.h.set_complete_predicate(head)
        if fixture['refinement']:
            self.h.set_rule_refinement(True)
        self.h.add_atoms_no_check(fixture['statements'])
        for pattern, tv in fixture['base_rates']:
            self.h.handler.process_metta_string(f'!(set-base-rate {self.h.kb} {pattern} {tv})')
        answers = self.h.query_many_refs(fixture['queries'], steps=2000)
        self.assertTrue(all(answers))
        # ProbLog and master both give .514; Round 1 returned no answer even
        # after quiet repeats. This guards coverage, independently of H1.
        self.assertAlmostEqual(answers[2][0].tv[1], .514, delta=1e-12)

    def node(self, name, cuts=(), deps=(), strength=.4, kind='key'):
        key = ['sk-key', [name], [self.h.kb, 'MAIN', 'Nil']]
        if kind in ('fold', 'aggregate'):
            key = ['sk-fold', [self.h.kb, [name, 'x'], 'extract-tv', ['BaseRateEvidence', 0.0, 0.0], 'BaseRateAcc', 'base-rate' if kind == 'fold' else 'identity', 'result-tv']]
        return janus.query_once(
            "'index-hash'(Key,H),cn_digest(Key,0,_D),sort(Cuts,_Cuts),cn_id('&sk_context',_D,_Cuts,Id), "
            "'deps-join'(Deps,_Deps), "
            "(Key=['sk-key',_Type,_Scope] -> _V=['sk-val',[_Type,_Scope,old,['STV',Strength,0.8]],['ev-set',0],_Deps] "
            "; _V=['sk-goal-val',['CPU','FoldAllCompiled',_Args,['STV',Strength,0.8]],old,['ev-set',0],_Deps],Key=['sk-fold',_Args]), "
            "cn_add('&sk_context',[_D,Id,H,Key,0,0,_Cuts,_Cuts,_Deps,_V,true]), "
            "'search-id-value'(sk_context_order,_Order),_Next is _Order+1,'change-state!'(sk_context_order,_Next,_), "
            "cn_add('&sk_context_id',[Id,'&sk_context',_D,_Order]),cn_settled(Id,_V,_Cuts)",
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

    def test_pending_requests_coalesce_by_support_intersection(self):
        dep = janus.query_once("'deps-key'(771,Dep)")['Dep']
        self.node('Preclass', deps=[dep])
        result = janus.query_once(
            "K=['sk-key',['Preclass'],[Kb,'MAIN','Nil']],'index-hash'(K,H), "
            "'deps-key'(771,S),cn_add('&sk_support',[H,0,S]),cn_digest(K,0,D),cn_add('&sk_ordinary_support',[D,S]), "
            "cn_ensure('&sk_context',H,K,0,0,[771,772],A), "
            "cn_ensure('&sk_context',H,K,0,0,[771,773],B), "
            "cn_digest(K,0,D),aggregate_all(count,cn_rows('&sk_context',[D,_,_,_,_,_,_,_,_,_,_]),N), "
            "cn_node(A,_,[_,_,_,_,_,_,Request,Cuts,_,_,State])", dict(Kb=self.h.kb))
        self.assertEqual(result['A'], result['B'])
        self.assertEqual((result['N'], result['Cuts'], result['State']), (2, [771], 'pending'))
        self.assertEqual(result['Request'], [771, 772])

    def test_ordinary_demand_restarts_a_coalesced_waiting_request(self):
        result = janus.query_once(
            "K=['sk-key',['Promoted'],[Kb,'MAIN','Nil']],'index-hash'(K,H),cn_digest(K,0,D), "
            "FixtureRow=['sk-row',['sk-ident',-1,[],K],[['Promoted'],[Kb,'MAIN','Nil'],cpu,['STV',1,1]],[],0], "
            "assertz('&sk_row'(H,K,0,FixtureRow)), "
            "cn_ensure('&sk_context',H,K,0,0,[771],Id), "
            "cn_node(Id,S,Row),Row=[D,Id,H,K,0,0,_,Cuts,Deps,V,_], "
            "cn_replace(S,Row,[D,Id,H,K,0,0,[771],Cuts,Deps,V,wait(new,[123])]), "
            "cn_ensure('&sk_context',H,K,0,0,[],Id), "
            "cn_node(Id,_,[_,_,_,_,_,_,Request,_,_,_,State])", dict(Kb=self.h.kb))
        self.assertEqual((result['Request'], result['State']), ([], 'pending'))

    def test_provisional_dependencies_do_not_bound_the_missing_inputs(self):
        ordinary = self.node('IncompleteSupport')
        result = janus.query_once(
            "K=Key,K=['sk-key',T,Scope],Other=['sk-key',['LaterInput'],Scope], "
            "'index-hash'(Other,IH),cn_node(Id,S,Old),Old=[D,Id,H,K,0,Q,E,C,Deps,V,_], "
            "cn_replace(S,Old,[D,Id,H,K,0,Q,E,C,Deps,V,wait(old,[123])]), "
            "Row=['sk-row',['sk-ident',-1,[],K],[T,Scope,cpu,['STV',1,1]],[],0], "
            "setup_call_cleanup((assertz('&sk_row'(H,K,0,Row)),cn_add('&sk_row_input',[IH,Other,H,0])), "
            "cn_preclass('&sk_context',D,H,K,0,[IH],Class), "
            "(retractall('&sk_row'(H,K,0,Row)),cn_remove('&sk_row_input',[IH,Other,H,0])))",
            dict(Key=ordinary['Key'], Id=ordinary['Id']))
        self.assertEqual(result['Class'], [result['IH']])

    def test_pending_preclass_is_not_recorded_as_observed_support(self):
        # A pre-class bounds possible cuts; a waiting evaluation has not
        # necessarily cut every key in that request.
        result = janus.query_once(
            "K=['sk-key',['ObservedSupport'],[Kb,'MAIN','Nil']],'index-hash'(K,H), "
            "cn_ensure('&sk_context',H,K,0,0,[771,772],Id), "
            "setup_call_cleanup((nb_setval(context_node_active,Id),nb_setval(context_node_waiting,true), "
            "nb_setval(context_node_missing,[123]),nb_setval(context_node_cuts,[771])), "
            "cn_publish(Id,'sk-none'),nb_setval(context_node_active,none)), "
            "cn_rows('&sk_support',[H,0,Support]),'deps-excluded'([771,772],Support,Observed)", dict(Kb=self.h.kb))
        self.assertEqual(result['Observed'], [771])

    def test_instance_member_cut_cannot_coalesce_with_the_opaque_fold(self):
        # A fold's exposed deps name the parameter, while excluding one of
        # its observations must still select a different leave-one-out class.
        result = janus.query_once(
            "K=['sk-fold',[Kb,sample,extract,init,acc,'implication-instance',mode]], "
            "'index-hash'(K,H),cn_digest(K,0,D),'deps-key'(H,Support), "
            "cn_add('&sk_support',[H,0,Support]),cn_add('&sk_ordinary_support',[D,Support]), "
            "cn_add('&sk_instance_read',[771,H,772,member]), "
            "cn_add('&sk_instance_member',[772,H,member,0,0, "
            "['InstanceEvidence',['BaseRateEvidence',1.0,1.0],['BaseRateEvidence',0.0,0.0]]]), "
            "cn_ensure('&sk_context',H,K,0,0,[],Ordinary), "
            "cn_ensure('&sk_context',H,K,0,0,[771],Excluded), "
            "cn_node(Excluded,_,[_,_,_,_,_,_,_,Cuts,_,_,_])", dict(Kb=self.h.kb))
        self.assertNotEqual(result['Ordinary'], result['Excluded'])
        self.assertEqual(result['Cuts'], [771])

    def test_instance_interim_cannot_restore_the_readers_excluded_sample(self):
        result = janus.query_once(
            "Args=[Kb,sample,extract,init,acc,'implication-instance',mode],K=['sk-fold',Args], "
            "'index-hash'(K,H),cn_digest(K,0,D),'deps-key'(H,Deps), "
            "cn_add('&sk_instance_read',[771,H,772,member]), "
            "cn_add('&sk_instance_member',[772,H,member,0,0, "
            "['InstanceEvidence',['BaseRateEvidence',1.0,1.0],['BaseRateEvidence',0.0,0.0]]]), "
            "cn_ensure('&sk_context',H,K,0,0,[],Id), "
            "cn_settled(Id,['sk-goal-val',['CPU','FoldAllCompiled',Args,['STV',0.4,0.8]],old,['ev-set',0],Deps],[]), "
            "(cn_interim('&sk_context',D,K,[771],_)->Admitted=true;Admitted=false)", dict(Kb=self.h.kb))
        self.assertEqual(result['Admitted'], 'false')

    def test_fresh_class_precedes_a_compatible_deep_stale_snapshot(self):
        ordinary = self.node('FreshPreferred')
        fresh = self.node('FreshPreferred', cuts=[771], strength=.7)
        result = janus.query_once(
            "cn_node(Old,S,Row),Row=[D,Old,H,K,R,Q,E,C,Deps,V,true], "
            "cn_replace(S,Row,[D,Old,H,K,R,Q,E,C,Deps,V,false]), "
            "assertz('&sk_needed'(H,K,4)), "
            "cn_reusable('&sk_context',D,K,[771],Chosen,_)", dict(Old=ordinary['Id']))
        self.assertEqual(result['Chosen'], fresh['Id'])

    def test_deep_stale_fold_is_pending_even_when_its_interim_is_sound(self):
        fold = self.node('StaleFold', kind='fold')
        result = janus.query_once(
            "cn_node(Id,S,Row),Row=[D,Id,H,K,R,Q,E,C,Deps,V,true], "
            "cn_replace(S,Row,[D,Id,H,K,R,Q,E,C,Deps,V,false]), "
            "assertz('&sk_needed'(H,K,4)), "
            "(cn_reusable(S,D,K,[],_,_)->Exact=true;Exact=false), "
            "cn_interim(S,D,K,[],Interim)", dict(Id=fold['Id']))
        self.assertEqual(result['Exact'], 'false')
        self.assertEqual(result['Interim'][1][3], ['STV', .4, .8])

    def test_cached_need_stops_only_at_deep_stale_snapshots(self):
        for state in ('true', 'false', 'pending(old)'):
            row = self.node('DeepNeed' + state)
            source = self.node('DeepInput' + state)
            result = janus.query_once(
                "cn_node(Id,S,Row),Row=[D,Id,H,K,R,Q,E,C,Deps,V,_], "
                "term_string(_State,Text),cn_replace(S,Row,[D,Id,H,K,R,Q,E,C,Deps,V,_State]), "
                "assertz('&sk_needed'(H,K,4)),cn_min_need(Id,4),cn_edge(Source,Id), "
                "cn_need_inputs([Id]),(cn_rows('&sk_context_need',[Source,_])->Walked=true;Walked=false)",
                dict(Id=row['Id'], Source=source['Id'], Text=state))
            self.assertEqual(result['Walked'], 'false' if state == 'false' else 'true', state)

    def test_fold_publication_compares_result_and_coverage(self):
        producer = self.node('AggregateValue', kind='aggregate')
        reader = self.node('AggregateReader')
        result = janus.query_once(
            "cn_edge(Id,Reader),cn_node(Id,_,[_,_,_,['sk-fold',Args]|_]), "
            "'deps-key'(779,D),'evidence-set'([new_evidence],Ev), "
            "cn_settled(Id,['sk-goal-val',['CPU','FoldAllCompiled',Args,['STV',0.4,0.8]],new,Ev,D],[]), "
            "cn_node(Reader,_,[_,_,_,_,_,_,_,_,_,_,State])", dict(Id=producer['Id'],Reader=reader['Id']))
        self.assertEqual(result['State'], 'true')

    def test_invalidated_interim_is_replaced_by_the_exact_publication(self):
        node = self.node('InterimReplacement')
        result = janus.query_once(
            "cn_node(Id,S,Row),Row=[D,Id,H,K,R,Q,E,C,Deps,V,true], "
            "cn_replace(S,Row,[D,Id,H,K,R,Q,E,C,Deps,V,wait(old,[])]), "
            "cn_dirty(Id,false),K=['sk-key',T,Scope], "
            "cn_settled(Id,['sk-val',[T,Scope,exact,['STV',0.7,0.8]],['ev-set',0],Deps],[]), "
            "cn_node(Id,_,[_,_,_,_,_,_,_,_,_,Exact,State])", dict(Id=node['Id']))
        self.assertEqual(result['State'], 'true')
        self.assertEqual(result['Exact'][1][3], ['STV', .7, .8])

    def test_interim_is_sound_and_subscribes_to_the_exact_request(self):
        existing = self.node('Interim', cuts=[771])
        reader = self.node('InterimReader')
        result = janus.query_once(
            "'begin-backward-query-metrics!'(_), "
            "setup_call_cleanup((nb_setval(context_node_active,Reader),nb_setval(context_node_missing,[])), "
            "(cn_row_read(H,Key,0,0,[],V),nb_getval(context_node_missing,Missing), "
            "Missing=[Exact],cn_rows('&sk_context_reader',[Exact,Reader]), "
            "'query_metric_value'('row-computes',Work)),nb_setval(context_node_active,none))",
            dict(H=existing['H'], Key=existing['Key'], Reader=reader['Id']))
        self.assertEqual(result['V'][1][3], ['STV', .4, .8])
        self.assertNotEqual(result['Exact'], existing['Id'])
        self.assertEqual(result['Work'], 0)

    def test_interim_never_bypasses_exclusion_dependencies(self):
        dep = janus.query_once("'deps-key'(772,D)")['D']
        existing = self.node('UnsafeInterim', cuts=[771], deps=[dep])
        result = janus.query_once("cn_row_read(H,Key,0,0,[772],V)",
                                 dict(H=existing['H'], Key=existing['Key']))
        self.assertEqual(result['V'], 'sk-none')

    def test_sound_publication_keeps_its_pending_input_subscription(self):
        reader = self.node('PendingPublication', cuts=[771, 772])
        producer = self.node('PendingPublicationInput')
        result = janus.query_once(
            "cn_node(Id,_,[D,Id,H,K,R,Q,E,_,Deps,_V,_]),K=['sk-key',T,Scope], "
            "cn_edge(Source,Id),cn_dirty(Source,true), "
            "setup_call_cleanup((nb_setval(context_node_active,Id),nb_setval(context_node_waiting,true), "
            "nb_setval(context_node_missing,[Source]),nb_setval(context_node_cuts,[771])), "
            "cn_publish(Id,['sk-val',[T,Scope,interim,['STV',0.7,0.8]],['ev-set',0],Deps]), "
            "nb_setval(context_node_active,none)), "
            "cn_node(Id,_,[_,_,_,_,_,_,E,E,_,_,wait(old,[Source])]), "
            "cn_rows('&sk_context_reader',[Source,Id]), "
            "cn_node(Source,_,[_,_,_,['sk-key',ST,SS],_,_,_,_,SD,_,_]), "
            "cn_settled(Source,['sk-val',[ST,SS,exact,['STV',0.9,0.8]],['ev-set',0],SD],[]), "
            "cn_node(Id,_,[_,_,_,_,_,_,_,_,_,_,pending(old)]), "
            "setup_call_cleanup((nb_setval(context_node_active,Id),nb_setval(context_node_waiting,false), "
            "nb_setval(context_node_cuts,[771])), "
            "cn_publish(Id,['sk-val',[T,Scope,exact,['STV',0.9,0.8]],['ev-set',0],Deps]), "
            "nb_setval(context_node_active,none)), "
            "cn_id('&sk_context',D,[771],Canonical), "
            "cn_node(Canonical,_,[_,_,_,_,_,_,[771],[771],_,_,true])", dict(Id=reader['Id'], Source=producer['Id']))
        self.assertTrue(result['truth'])

    def test_pending_read_does_not_assume_the_interim_nodes_request_cuts(self):
        source = self.node('PartialRead', cuts=[771])
        reader = self.node('PartialReader')
        result = janus.query_once(
            "cn_node(Source,S,Row),Row=[D,Source,H,K,R,Q,E,C,Deps,V,_], "
            "cn_replace(S,Row,[D,Source,H,K,R,Q,E,C,Deps,V,wait(old,[123])]), "
            "setup_call_cleanup((nb_setval(context_node_active,Reader),nb_setval(context_node_waiting,false), "
            "nb_setval(context_node_missing,[]),nb_setval(context_node_cuts,[])), "
            "((cn_reusable(S,D,K,E,Source,_)->LookupExact=true;LookupExact=false),nb_getval(context_node_waiting,LookupPending), "
            "cn_row_read(H,K,R,Q,E,Read),nb_getval(context_node_missing,Missing), "
            "nb_getval(context_node_cuts,ObservedCuts), "
            "cn_rows('&sk_context_reader',[Source,Reader])),nb_setval(context_node_active,none))",
            dict(Source=source['Id'], Reader=reader['Id']))
        self.assertEqual(result['Missing'], [source['Id']])
        self.assertEqual(result['LookupExact'], 'false')
        self.assertEqual(result['LookupPending'], 'false')
        self.assertEqual(result['ObservedCuts'], [])
        self.assertEqual(result['Read'][1][3], ['STV', .4, .8])

    def test_cached_need_walk_revisits_changed_inputs_and_closer_depths(self):
        reader, source = self.node('WalkReader'), self.node('WalkSource')
        result = janus.query_once(
            "cn_min_need(Reader,4),cn_need_inputs([Reader]), "
            "cn_edge(Source,Reader),cn_need_inputs([Reader]),cn_rows('&sk_context_need',[Source,First]), "
            "cn_min_need(Reader,0),cn_need_inputs([Reader]),cn_rows('&sk_context_need',[Source,Closer])",
            dict(Reader=reader['Id'], Source=source['Id']))
        self.assertEqual((result['First'], result['Closer']), (5, 1))

    def test_unpaid_positive_settle_canonicalizes_actual_cuts(self):
        result = janus.query_once(
            "K=['sk-key',['UnpaidClass'],[Kb,'MAIN','Nil']],'index-hash'(K,H), "
            "'deps-key'(771,A),'deps-key'(772,B),'deps-join'([A,B],S),cn_add('&sk_support',[H,0,S]), "
            "cn_ensure('&sk_context',H,K,0,0,[771,772],Id), "
            "K=['sk-key',T,Scope], "
            "setup_call_cleanup((nb_setval(context_node_active,Id),nb_setval(context_node_waiting,false), "
            "nb_setval(context_node_cuts,[771]),cn_add('&sk_given_pending',[Id,0,100])), "
            "cn_publish(Id,['sk-val',[T,Scope,p,['STV',0.4,0.8]],['ev-set',0],0]), "
            "nb_setval(context_node_active,none)), "
            "cn_digest(K,0,D),cn_id('&sk_context',D,[771],Canonical), "
            "cn_node(Canonical,_,[_,_,_,_,_,_,[771],[771],_,_,true]), "
            "cn_rows('&sk_given_pending',[Canonical,0,100])", dict(Kb=self.h.kb))
        self.assertTrue(result['truth'])

    def test_unused_pending_is_retired_but_current_work_is_kept(self):
        result = janus.query_once(
            "K=['sk-key',['Abandoned'],[Kb,'MAIN','Nil']],'index-hash'(K,H), "
            "cn_ensure('&sk_context',H,K,0,0,[771],Dead), "
            "J=['sk-key',['Needed'],[Kb,'MAIN','Nil']],'index-hash'(J,JH), "
            "cn_ensure('&sk_context',JH,J,0,0,[],Keep),cn_min_need(Keep,0),cn_collect, "
            "\\+cn_node(Dead,_,_),cn_node(Keep,_,_)", dict(Kb=self.h.kb))
        self.assertTrue(result['truth'])

    def test_collection_retires_orphan_merges_but_keeps_deep_row_snapshots(self):
        ordinary = self.node('RetainedOrdinary')
        result = janus.query_once(
            "cn_dirty(Ordinary,false), "
            "K=['sk-key',['OrphanMerge'],[Kb,'MAIN','Nil']],'index-hash'(K,H), "
            "cn_ensure('&sk_context_merge',H,K,-1,-1,[],Merge), "
            "cn_settled(Merge,'sk-none',[]),cn_dirty(Merge,false),cn_collect, "
            "\+cn_node(Merge,_,_),cn_node(Ordinary,_,_)", dict(Kb=self.h.kb,Ordinary=ordinary['Id']))
        self.assertTrue(result['truth'])

    def test_pending_subscription_endpoint_of_a_published_reader_is_retained(self):
        reader = self.node('PublishedReader')
        result = janus.query_once(
            "K=['sk-key',['SubscriptionEndpoint'],[Kb,'MAIN','Nil']],'index-hash'(K,H), "
            "cn_ensure('&sk_context_merge',H,K,-1,-1,[],Producer),cn_edge(Producer,Reader), "
            "cn_collect,cn_node(Producer,_,_)", dict(Kb=self.h.kb, Reader=reader['Id']))
        self.assertTrue(result['truth'])

    def test_class_demand_is_below_its_reader_even_when_key_is_a_root(self):
        reader = self.node('DepthReader')
        result = janus.query_once(
            "K=['sk-key',['DepthChild'],[Kb,'MAIN','Nil']],'index-hash'(K,H), "
            "assertz('&sk_needed'(H,K,0)),cn_min_need(Reader,0), "
            "setup_call_cleanup(nb_setval(context_node_active,Reader), "
            "cn_ensure('&sk_context',H,K,0,0,[771],Id),nb_setval(context_node_active,none)), "
            "cn_rows('&sk_context_need',[Id,Depth])", dict(Kb=self.h.kb, Reader=reader['Id']))
        self.assertEqual(result['Depth'], 1)

    def test_republication_preserves_structural_reuse_order(self):
        first = self.node('StableChoice', cuts=[771], strength=.4)
        self.node('StableChoice', cuts=[772], strength=.7)
        result = janus.query_once(
            "cn_node(First,_,[D,First,_,Key,_,_,_,Cuts,_,V,_]),cn_settled(First,V,Cuts), "
            "cn_reusable('&sk_context',D,Key,[771,772],Id,Chosen)", dict(First=first['Id']))
        self.assertEqual(result['Id'], first['Id'])
        self.assertEqual(result['Chosen'][1][3], ['STV', .4, .8])

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
            "nb_setval(context_node_progress,0),'deps-key'(701,_Support),cn_remove('&sk_support',[H,0,_]),cn_add('&sk_support',[H,0,_Support]), "
            "cn_ensure('&sk_context',H,Key,0,0,[701],Pending), "
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
            "cn_edge(A,R),cn_edge(B,O),cn_dirty(A,true),cn_node(A,_,[_,_,_,['sk-key',T,S],_,_,_,_,D,_,_]), "
            "cn_settled(A,['sk-val',[T,S,new,['STV',0.7,0.8]],['ev-set',0],D],[]), "
            "cn_node(R,_,[_,_,_,_,_,_,_,_,_,_,RS]),cn_node(O,_,[_,_,_,_,_,_,_,_,_,_,OS])",
            dict(A=a['Id'], B=sibling['Id'], R=reader['Id'], O=other['Id']))
        self.assertEqual((result['RS'], result['OS']), ('false', 'true'))

    def test_deep_stale_snapshot_keeps_outside_change_notifications(self):
        source, reader = self.node('LateSource'), self.node('LateReader')
        result = janus.query_once(
            "cn_node(Reader,_,[_,_,H,K|_]),assertz('&sk_needed'(H,K,4)),cn_min_need(Reader,4), "
            "cn_edge(Source,Reader),cn_dirty(Reader,false),cn_rows('&sk_context_reader',[Source,Reader]), "
            "cn_node(Source,_,[_,_,_,['sk-key',T,S],_,_,_,_,D,_,_]),cn_dirty(Source,true), "
            "cn_settled(Source,['sk-val',[T,S,new,['STV',0.7,0.8]],['ev-set',0],D],[]), "
            "cn_rows('&sk_context_forced',[Reader,_])", dict(Source=source['Id'], Reader=reader['Id']))
        self.assertTrue(result['truth'])

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
            "'index-hash'(Key,H),findall(_Dep,(between(1,9,_C),'deps-key'(_C,_Dep)),_Deps), "
            "'deps-join'(_Deps,_Support),cn_add('&sk_support',[H,0,_Support]), "
            "forall(between(1,9,_C),cn_ensure('&sk_context',H,Key,0,0,[_C],_)), "
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
