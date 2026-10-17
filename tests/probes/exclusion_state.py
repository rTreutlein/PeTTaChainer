"""Exclusion-cache soundness and interruption probes in an isolated runtime."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class ExclusionStateTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        janus.query_once(
            "retractall('&sk_branch_cuts'(_,_,_)), retractall('&sk_reading'(_,_,_)), "
            "'change-state!'(sk_branch_at,0,_)"
        )

    def assert_rejection_restricts_reuse(self, setup, rejection):
        result = janus.query_once(
            setup + ", assertz('&sk_branch_cuts'(987654,[Excluded],[])), "
            "'change-state!'(sk_branch_at,987654,_), " + rejection + ", "
            "'&sk_branch_cuts'(987654,_,Cuts), 'change-state!'(sk_branch_at,0,_), "
            "_Owner=['sk-key',['Cached'],[Kb,'MAIN','Nil']], 'index-hash'(_Owner,_Hash), "
            "'index-hash'([_Hash,987654],_Slot), "
            "'sk-cache-branch!'(_Slot,_Hash,_Owner,987654,[],Cuts,true,'sk-none',_), "
            "'sk-branch-values'(_Slot,_Owner,987654,[],true,Weaker)",
            {"Kb": self.h.kb},
        )
        self.assertTrue(result['truth'])
        self.assertEqual(result['Rejected'], 'sk-none')
        self.assertIn(result['Excluded'], result['Cuts'])
        self.assertEqual(result['Weaker'], [])

    def test_rejected_older_view_records_cut(self):
        self.assert_rejection_restricts_reuse(
            "Excluded=987601, 'deps-key'(Excluded,_Deps), "
            "_View=['sk-val',[['Older'],[Kb,'MAIN','Nil'],mf,['STV',1,0.8]],['ev-set',0],_Deps]",
            "'sk-admit-older'('sk-any-filter',[Excluded],'sk-none',_View,Rejected)",
        )

    def test_excluded_direct_leaf_records_cut(self):
        self.assert_rejection_restricts_reuse(
            "Excluded=987608, _Fact=[['Leaf'],[Kb,'MAIN','Nil'],mf,['STV',0,1]]",
            "'sk-leaf-step'(Excluded,false,[Excluded],[],_Fact,_Leaves), "
            "(_Leaves=[] -> Rejected='sk-none' ; Rejected=admitted)",
        )

    def test_excluded_complete_read_records_cut(self):
        self.h.set_complete_predicate('Closed')
        self.h.query('(: $p (Closed a) $tv)', steps=200, timeout_sec=0)
        self.assert_rejection_restricts_reuse(
            "_Key=['sk-key',['Closed',a],[Kb,'MAIN','Nil']], 'index-hash'(_Key,Excluded)",
            "'sk-closed-read'([],[],[Excluded],_Key,'sk-any-filter',Rejected)",
        )

    def test_local_completion_exclusions_do_not_replace_the_original_branch_context(self):
        self.h.set_complete_predicate('LocallyClosed')
        self.h.query('(: $p (LocallyClosed a) $tv)', steps=200, timeout_sec=0)
        result = janus.query_once(
            "assertz('&sk_branch_cuts'(987654,[987609],[])), "
            "'change-state!'(sk_branch_at,987654,_), "
            "_Fact=[['LocalLeaf'],[Kb,'MAIN','Nil'],mf,['STV',0,1]], "
            "'sk-leaf-step'(987610,false,[987610],[],_Fact,Leaves), "
            "_Key=['sk-key',['LocallyClosed',a],[Kb,'MAIN','Nil']], 'index-hash'(_Key,_Local), "
            "'sk-closed-read'([],[],[_Local],_Key,'sk-any-filter',Closed), "
            "'&sk_branch_cuts'(987654,Original,Cuts), 'change-state!'(sk_branch_at,0,_)",
            {'Kb': self.h.kb},
        )
        self.assertTrue(result['truth'])
        self.assertEqual(len(result['Leaves']), 1)
        self.assertNotEqual(result['Closed'], 'sk-none')
        self.assertEqual((result['Original'], result['Cuts']), ([987609], []))

    def test_impossible_closed_branch_settles_empty_and_next_read_hits(self):
        for name in ('A', 'K', 'X'):
            self.h.set_complete_predicate(name)
        self.h.add_atoms_no_check([
            '(: xf (X a) (STV 0 1))',
            '(: (no_inverse xk) (Implication (X a) (K a)) (CTV (STV 1 1) (STV 0 1)))',
            '(: (no_inverse ka) (Implication (K a) (A a)) (CTV (STV 1 1) (STV 0 1)))',
        ])
        self.h.query('(: $p (A a) $tv)', steps=200, timeout_sec=0)
        self.h.set_query_metrics(True)
        result = janus.query_once(
            "_Key=['sk-key',['A',a],[Kb,'MAIN','Nil']], 'index-hash'(_Key,_H), "
            "_X=['sk-key',['X',a],[Kb,'MAIN','Nil']], 'index-hash'(_X,_Excluded), "
            "once('&sk_row'(_H,_Key,_R,_)), 'index-hash'([_H,_R],_Slot), "
            "assertz('&sk_branch_wanted'(_Slot,_H,_Key,_R,[_Excluded])), "
            "'change-state!'(sk_eval_budget,1000,_), 'change-state!'(sk_branch_budget,100,_), "
            "'sk-build-wanted!'(true), "
            "findall(true,'&sk_branch_wanted'(_Slot,_H,_Key,_R,[_Excluded]),Wanted), "
            "'&sk_branch'(_Slot,_Key,_R,Cuts,true,View), "
            "'sk-view-deps-step'(0,View,_Deps), 'deps-meet?'([_Excluded],_Deps,ExcludedDependency), "
            "'begin-backward-query-metrics!'(_), "
            "'sk-rebuild-view'(true,_H,_Key,_R,[_Excluded],Next), "
            "'query_metric_value'('branch-cache-hits',Hits), "
            "'query_metric_value'('branch-builds',Builds), "
            "forall(('&sk_row'(_KH,_K,_RH,_Row), _K=['sk-key',_,[Kb,'MAIN','Nil']]), "
            " 'sk-drop-row!'(_KH,_K,_RH,_Row,_))", {'Kb': self.h.kb}
        )
        self.assertTrue(result['truth'])
        self.assertEqual(result['Wanted'], [])
        self.assertTrue(result['Cuts'])
        self.assertEqual((result['View'], result['Next']), ('sk-none', 'sk-none'))
        self.assertEqual(result['ExcludedDependency'], 'false')
        self.assertEqual((result['Hits'], result['Builds']), (1, 0))

    def test_rejected_conditioned_reread_records_cut(self):
        self.assert_rejection_restricts_reuse(
            "_Key=['sk-key',['Conditioned'],[Kb,'MAIN','Nil']], 'index-hash'(_Key,Excluded), "
            "'deps-key'(987602,_GivenDeps), "
            "_View=['sk-val',[['Conditioned'],[Kb,'MAIN','Nil'],mf,['STV',1,0.8]],['ev-set',0],_GivenDeps], "
            "_Row=['sk-row',['sk-ident',-1,[],_Key],[['Conditioned'],[Kb,'MAIN','Nil'],mf,['STV',1,0.8]],[],987602], "
            "assertz('&sk_row'(Excluded,_Key,987602,_Row))",
            "'sk-given-view'([['sk-given',987602,['sk-key',['Given'],[Kb,'MAIN','Nil']],true]], "
            "[Excluded],Excluded,_Key,['sk-version',0,987602,_View],Rejected)",
        )

    def test_rejected_left_out_view_records_cut(self):
        self.h._call('set-rule-refinement', [f'{self.h.kb} true'])
        self.h.add_atoms_no_check([
            '(: a1 (A a) (STV 1 0.9))',
            '(: b1 (B a) (STV 1 0.9))',
            '(: ab (Implication (A $x) (B $x)) (STV 0.8 0.9))',
        ])
        self.h.query('(: $p (RuleTruth (Implication (A $x) (B $x))) $tv)', steps=400, timeout_sec=0)
        self.assert_rejection_restricts_reuse(
            "once(('&sk_instance_tally'(Excluded,['sk-fold',_Args],_), _Args=[Kb|_])), "
            "once('&sk_instance_read'(_Read,Excluded,_,_)), sort([Excluded,_Read],_Exclusions)",
            "'sk-left-out-view'(Excluded,['sk-fold',_Args],'sk-any-filter',_Exclusions,0,Rejected)",
        )

    def test_query_clears_interrupted_rebuild_frame_and_reader(self):
        interrupted = janus.query_once(
            "_Key=['sk-key',['Interrupt'],[Kb,'MAIN','Nil']], 'index-hash'(_Key,_Hash), "
            "_Row=['sk-row',['sk-ident',-1,[],_Key],[['Interrupt'],[Kb,'MAIN','Nil'],mf,['STV',1,0.8]],"
            "[],987603], assertz('&sk_row'(_Hash,_Key,987603,_Row)), "
            "assertz('&sk_reading'(_Hash,_Key,987603)), 'change-state!'(sk_eval_budget,1,_), "
            # Interrupt the real rebuild when it reads its newly opened cut
            # frame. Erase the injected fault; leave the abandoned data intact.
            "asserta(('&sk_branch_cuts'(_,_,_) :- flag(exclusion_probe_interrupt,_,1), "
            " throw(interrupted_rebuild)), _Trap), "
            "catch(('sk-rebuild-view'(true,_Hash,_Key,987603,[-1],_) -> true ; true), "
            " interrupted_rebuild, true), erase(_Trap), flag(exclusion_probe_interrupt,Interrupted,0), "
            "'search-id-value'(sk_branch_at,Frame), aggregate_all(count,'&sk_reading'(_,_,_),Readers)",
            {'Kb': self.h.kb},
        )
        self.assertEqual(interrupted['Interrupted'], 1)
        self.assertNotEqual(interrupted['Frame'], 0)
        self.assertEqual(interrupted['Readers'], 1)
        self.h.query('(: $p (Unrelated) $tv)', steps=0, timeout_sec=0)
        cleaned = janus.query_once(
            "'search-id-value'(sk_branch_at,Frame), "
            "aggregate_all(count,'&sk_branch_cuts'(_,_,_),Frames), "
            "aggregate_all(count,'&sk_reading'(_,_,_),Readers)"
        )
        self.assertEqual((cleaned['Frame'], cleaned['Frames'], cleaned['Readers']), (0, 0, 0))

    def test_deferred_misses_survive_queries_and_obey_the_tier_ceiling(self):
        self.h.set_query_metrics(True)
        queued = janus.query_once(
            "'begin-backward-query-metrics!'(_), 'change-state!'(sk_eval_budget,1000,_), "
            "forall(between(1,10,_I), "
            " (_Key=['sk-key',['Queued',_I],[Kb,'MAIN','Nil']], 'index-hash'(_Key,_H), "
            "  _Fact=[['Queued',_I],[Kb,'MAIN','Nil'],cpu,['STV',0.5,0.8]], "
            "  _Row=['sk-row',['sk-ident',-1,[],_Key],_Fact,[],_I], "
            "  assertz('&sk_row'(_H,_Key,_I,_Row)), 'deps-key'(987604,_D), "
            "  'sk-admit-step'(_H,_Key,'sk-any-filter',[987604],[], "
            "     ['sk-version',_I,_I,['sk-val',_Fact,['ev-set',0],_D]],[]))), "
            "'search-id-value'(sk_eval_budget,Left), "
            "'query_metric_value'('branch-builds',Builds), "
            "aggregate_all(count,'&sk_branch_wanted'(_,_,_,_,_),Wanted)",
            {'Kb': self.h.kb},
        )
        self.assertEqual((queued['Left'], queued['Builds'], queued['Wanted']), (1000, 0, 10))
        bounded = janus.query_once(
            "'change-state!'(sk_branch_budget,3,_), empty_heap(_Empty), "
            "'sk-work-off!'(0,['sk-work',_Empty,_Empty],_), "
            "'search-id-value'(sk_eval_budget,Left), "
            "'query_metric_value'('branch-builds',Builds), "
            "aggregate_all(count,'&sk_branch_wanted'(_,_,_,_,_),Wanted)"
        )
        self.assertEqual((bounded['Left'], bounded['Builds'], bounded['Wanted']), (997, 3, 7))
        # Neither evaluation reset nor a zero-budget query discards the queue.
        janus.query_once("'sk-evaluate!'(_)")
        self.h.query('(: $p (Unrelated) $tv)', steps=0, timeout_sec=0)
        self.assertEqual(janus.query_once(
            "aggregate_all(count,'&sk_branch_wanted'(_,_,_,_,_),Wanted)"
        )['Wanted'], 7)
        # Retiring a row removes its unbuilt request too (no cache owner yet).
        janus.query_once(
            "once('&sk_branch_wanted'(_, _H,_Key,_R,_)), "
            "'&sk_row'(_H,_Key,_R,_Row), 'sk-drop-row!'(_H,_Key,_R,_Row,_)"
        )
        self.h.query('(: $p (Unrelated) $tv)', steps=200, timeout_sec=0)
        self.assertEqual(janus.query_once(
            "aggregate_all(count,'&sk_branch_wanted'(_,_,_,_,_),Wanted)"
        )['Wanted'], 0)
        self.assertEqual(self.h.last_query_metrics()['branch_builds'], 6)

    def test_deferred_c1_records_hits_and_input_driven_refreshes(self):
        self.h.add_atoms_no_check([
            '(: mf (M a) (STV 1 0.8))', '(: xf (X a) (STV 1 0.8))',
            '(: (no_inverse xm) (Implication (X a) (M a)) (CTV (STV 1 1) (STV 0 1)))',
            '(: (no_inverse mb) (Implication (M a) (B a)) (CTV (STV 1 1) (STV 0 1)))',
        ])
        for goal in ('M', 'B'):
            self.h.query(f'(: $p ({goal} a) $tv)', steps=200, timeout_sec=0)
        self.h.add_atoms_no_check([
            '(: (no_inverse bx) (Implication (B a) (X a)) (CTV (STV 1 1) (STV 0 1)))',
        ])
        self.h.set_query_metrics(True)
        expected = ['(: (merge/revision xf (by (no_inverse bx) (by (no_inverse mb) mf))) '
                    '(X a) (STV 1.0 0.888849375588311))']
        self.assertEqual(self.h.query('(: $p (X a) $tv)', steps=200, timeout_sec=0), expected)
        metrics = self.h.last_query_metrics()
        self.assertGreater(metrics['branch_cache_misses'], 0)
        self.assertGreater(metrics['branch_builds'], 0)
        self.assertLessEqual(metrics['branch_builds'], 50)
        self.assertGreater(metrics['branch_cache_hits'], 0)
        self.h.add_atoms_no_check(['(: mf2 (M a) (STV 0 0.8))'])
        self.h.query('(: $p (X a) $tv)', steps=200, timeout_sec=0)
        metrics = self.h.last_query_metrics()
        self.assertGreater(metrics['branch_cache_refreshes'], 0)
        self.assertLessEqual(metrics['branch_builds'], 50)
        # Retire this fixture's rows so its unrelated deferred work cannot
        # consume the synthetic queue test's deliberately tiny allowance.
        janus.query_once(
            "forall(('&sk_row'(_H,_Key,_R,_Row), _Key=['sk-key',_,[Kb,'MAIN','Nil']]), "
            " 'sk-drop-row!'(_H,_Key,_R,_Row,_))", {'Kb': self.h.kb}
        )

    def test_branch_invalidation_requires_an_input_value_change(self):
        # Row evaluation captures proof identity before view publication.
        # Publish distinct references to the same value to test that boundary.
        result = janus.query_once(
            "_Input=['sk-key',['Input'],[Kb,'MAIN','Nil']], 'index-hash'(_Input,_IH), "
            "'deps-key'(_IH,_ID), "
            "_Same=['sk-val',[['Input'],[Kb,'MAIN','Nil'],cpu,['STV',0.5,0.8]],['ev-set',0],_ID], "
            "_Owner=['sk-key',['Owner'],[Kb,'MAIN','Nil']], 'index-hash'(_Owner,_OH), "
            "'index-hash'([_OH,987612],_Slot), 'deps-key'(_OH,_OD), "
            "_Value=['sk-val',[['Owner'],[Kb,'MAIN','Nil'],cpu,['STV',0.7,0.8]],['ev-set',0],_OD], "
            "'sk-cache-branch!'(_Slot,_OH,_Owner,987612,[_Input],[],true,'sk-none',_), "
            "'sk-reference-view'(-1,_Same,_First), 'sk-store-view!'(_IH,_Input,987611,987611,_First,_), "
            "findall(true,'&sk_branch_dirty'(_Slot),AfterFirst), "
            "'sk-cache-branch!'(_Slot,_OH,_Owner,987612,[_Input],[],true,_Value,_), "
            "'sk-reference-view'(-1,_Same,_Second), 'sk-store-view!'(_IH,_Input,987611,987611,_Second,_), "
            "(_First == _Second -> NewProof=false ; NewProof=true), "
            "findall(true,'&sk_branch_dirty'(_Slot),AfterProof), "
            "'sk-drop-merged!'(_Input,_), findall(true,'&sk_branch_dirty'(_Slot),AfterMemo), "
            "'sk-stale-key!'(_Input,_), findall(true,'&sk_branch_dirty'(_Slot),AfterStale), "
            "'sk-branch-values'(_Slot,_Owner,987612,[],true,BeforeChange), "
            "_Changed=['sk-val',[['Input'],[Kb,'MAIN','Nil'],cpu,['STV',0.6,0.8]],['ev-set',0],_ID], "
            "'sk-reference-view'(-1,_Changed,_ChangedRef), 'sk-store-view!'(_IH,_Input,987611,987611,_ChangedRef,_), "
            "findall(true,'&sk_branch_dirty'(_Slot),AfterChange), "
            "'sk-branch-values'(_Slot,_Owner,987612,[],true,ChangedReuse), "
            "'sk-cache-branch!'(_Slot,_OH,_Owner,987612,[_Input],[],true,_Value,_), "
            "'sk-drop-row-views!'(_IH,_Input,987611,_), "
            "findall(true,'&sk_branch_dirty'(_Slot),AfterRemoval), "
            "'sk-drop-branch!'([],_Slot,_)", {'Kb': self.h.kb}
        )
        self.assertTrue(result['truth'])
        self.assertEqual(result['NewProof'], 'true')
        self.assertEqual(result['AfterFirst'], ['true'])
        for field in ('AfterProof', 'AfterMemo', 'AfterStale'):
            self.assertEqual(result[field], [], field)
        self.assertEqual(result['AfterChange'], ['true'])
        self.assertEqual(result['AfterRemoval'], ['true'])
        self.assertEqual(len(result['BeforeChange']), 1)
        self.assertEqual(result['ChangedReuse'], [])

    def test_unfinished_positive_branch_is_retained_without_settled_reuse(self):
        self.h.set_query_metrics(True)
        result = janus.query_once(
            "'begin-backward-query-metrics!'(_), "
            "_Key=['sk-key',['Partial'],[Kb,'MAIN','Nil']], 'index-hash'(_Key,_H), "
            "'index-hash'([_H,987605],_Slot), "
            "_Fact=[['Partial'],[Kb,'MAIN','Nil'],cpu,['STV',0.5,0.8]], "
            "_Row=['sk-row',['sk-ident',-1,[],_Key],_Fact, "
            " [['CPU','sk-wait!',[_H,987605,2,'sk-none'],'sk-none']],987605], "
            "assertz('&sk_row'(_H,_Key,987605,_Row)), "
            "assertz('&sk_given_pending'(_H,987605,1)), "
            "'change-state!'(sk_eval_budget,1,_), "
            "'sk-rebuild-view'(true,_H,_Key,987605,[987606],Built), "
            "'&sk_branch'(_Slot,_Key,987605,Cuts,Fresh,Built), "
            "'sk-branch-values'(_Slot,_Key,987605,[987606],false,Stale), "
            "'sk-branch-values'(_Slot,_Key,987605,[987606],true,Settled), "
            "'sk-branch-values'(_Slot,_Key,987605,[],false,Weaker), "
            "'sk-drop-row!'(_H,_Key,987605,_Row,_)", {'Kb': self.h.kb}
        )
        self.assertTrue(result['truth'])
        self.assertNotEqual(result['Built'], 'sk-none')
        self.assertEqual(result['Cuts'], [987606])
        self.assertEqual(result['Fresh'], 'false')
        self.assertEqual(result['Stale'], [result['Built']])
        self.assertEqual((result['Settled'], result['Weaker']), ([], []))
        self.assertEqual(janus.query_once(
            "'query_metric_value'('branch-cache-refreshes',Refreshes)"
        )['Refreshes'], 0)

    def test_branch_pays_conditioning_outside_the_ordinary_need_closure(self):
        self.h.add_atoms_no_check([
            '(: sf (S a) (STV 0.7 0.8))',
            '(: (no_inverse sa) (Implication (S a) (A a)) (CTV (STV 1 1) (STV 0 1)))',
            '(: (no_inverse sb) (Implication (S a) (B a)) (CTV (STV 1 1) (STV 0 1)))',
            '(: (no_inverse abc) (Implication (And (A a) (B a)) (C a)) (CTV (STV 1 1) (STV 0 1)))',
        ])
        self.h.query('(: $p (C a) $tv)', steps=200, timeout_sec=0)
        self.h.set_query_metrics(True)
        result = janus.query_once(
            "_Key=['sk-key',['C',a],[Kb,'MAIN','Nil']], 'index-hash'(_Key,_H), "
            "once('&sk_row'(_H,_Key,_R,_Row)), 'index-hash'([_H,_R],_Slot), "
            "'sk-drop-branch!'([],_Slot,_), retractall('&sk_needed'(_H,_Key,_)), "
            "retractall('&sk_given_granted'(_H,_R)), "
            "retractall('&sk_given_pending'(_H,_R,_)), "
            # This debt belongs to the ordinary view, not this exclusion read.
            "assertz('&sk_given_pending'(_H,_R,999)), "
            "'begin-backward-query-metrics!'(_), 'change-state!'(sk_eval_budget,100,_), "
            "'sk-rebuild-view'(true,_H,_Key,_R,[-1],Built), "
            "'&sk_branch'(_Slot,_Key,_R,_,Fresh,Built), "
            "'search-id-value'(sk_eval_budget,Left), 'sk-needed?'(_H,_Key,Needed), "
            "'&sk_given_pending'(_H,_R,Debt), "
            "findall(true,'&sk_given_granted'(_H,_R),Grants), "
            "retractall('&sk_given_pending'(_H,_R,_)), "
            "forall(('&sk_row'(_KH,_K,_RH,_Row0), _K=['sk-key',_,[Kb,'MAIN','Nil']]), "
            " 'sk-drop-row!'(_KH,_K,_RH,_Row0,_))", {'Kb': self.h.kb}
        )
        self.assertTrue(result['truth'])
        self.assertEqual(result['Fresh'], 'true')
        self.assertEqual((result['Needed'], result['Grants'], result['Debt']), ('false', [], 999))
        self.assertGreater(result['Left'], 0)
        self.assertLess(result['Left'], 99)
        self.assertGreater(janus.query_once(
            "'query_metric_value'('conditioned-evaluations',Count)"
        )['Count'], 0)

    def test_deferred_arrival_only_wakes_its_exclusion_readers(self):
        result = janus.query_once(
            "_Owner=['sk-key',['NotifyOwner'],[Kb,'MAIN','Nil']], 'index-hash'(_Owner,_H), "
            "forall(between(1,2,_I), "
            " (_Key=['sk-key',['NotifyReader',_I],[Kb,'MAIN','Nil']], 'index-hash'(_Key,_RH), "
            "  _Fact=[['NotifyReader',_I],[Kb,'MAIN','Nil'],cpu,['STV',0.5,0.8]], "
            "  _Row=['sk-row',['sk-ident',-1,[],_Key],_Fact,[],_I], "
            "  assertz('&sk_row'(_RH,_Key,_I,_Row)), assertz('&sk_needed'(_RH,_Key,0)), "
            "  assertz('&sk_reader'(_H,_Owner,_RH,_I)))), "
            "_Reader=['sk-key',['NotifyReader',1],[Kb,'MAIN','Nil']], 'index-hash'(_Reader,_R1), "
            "_Fact=[['NotifyOwner'],[Kb,'MAIN','Nil'],cpu,['STV',0.5,0.8]], "
            "_Row=['sk-row',['sk-ident',-1,[],_Owner],_Fact,[],987607], "
            "assertz('&sk_row'(_H,_Owner,987607,_Row)), "
            "assertz('&sk_reading'(_R1,_Reader,1)), 'change-state!'(sk_holding,1,_), "
            "'deps-key'(_R1,_D), 'sk-admit-step'(_H,_Owner,'sk-any-filter',[_R1],[], "
            " ['sk-version',987607,987607,['sk-val',_Fact,['ev-set',0],_D]],[]), "
            "retractall('&sk_reading'(_,_,_)), 'change-state!'(sk_eval_budget,1,_), "
            "'change-state!'(sk_branch_budget,1,_), 'sk-build-wanted!'(true), "
            "findall(_I, (between(1,2,_I), _K=['sk-key',['NotifyReader',_I],[Kb,'MAIN','Nil']], "
            " 'index-hash'(_K,_KH), '&sk_restale'(_KH,_I)), Ready), "
            # A request can remain queued after a nested rebuild settled it.
            # Serving that fresh entry must not notify its reader again.
            "retractall('&sk_restale'(_,_)), 'index-hash'([_H,987607],_Slot), "
            "assertz('&sk_branch_wanted'(_Slot,_H,_Owner,987607,[_R1])), "
            "'change-state!'(sk_eval_budget,1,_), 'change-state!'(sk_branch_budget,1,_), "
            "'sk-build-wanted!'(true), "
            "findall(_I, (between(1,2,_I), _K=['sk-key',['NotifyReader',_I],[Kb,'MAIN','Nil']], "
            " 'index-hash'(_K,_KH), '&sk_restale'(_KH,_I)), AlreadySettledReady), "
            # An input-driven refresh with identical value must not generate
            # another forced proof publication and invalidate itself in a cycle.
            "retractall('&sk_restale'(_,_)), 'index-hash'([_H,987607],_Slot), "
            "'sk-stale-branch!'([],_Slot,_), assertz('&sk_reading'(_R1,_Reader,1)), "
            "'sk-admit-step'(_H,_Owner,'sk-any-filter',[_R1],[], "
            " ['sk-version',987607,987607,['sk-val',_Fact,['ev-set',0],_D]],_), "
            "retractall('&sk_reading'(_,_,_)), 'change-state!'(sk_eval_budget,1,_), "
            "'change-state!'(sk_branch_budget,1,_), 'sk-build-wanted!'(true), "
            "findall(_I, (between(1,2,_I), _K=['sk-key',['NotifyReader',_I],[Kb,'MAIN','Nil']], "
            " 'index-hash'(_K,_KH), '&sk_restale'(_KH,_I)), UnchangedReady), "
            "'change-state!'(sk_holding,0,_), "
            "forall(('&sk_row'(_KH,_K,_R,_Row0), _K=['sk-key',_,[Kb,'MAIN','Nil']]), "
            " 'sk-drop-row!'(_KH,_K,_R,_Row0,_))", {'Kb': self.h.kb}
        )
        self.assertTrue(result['truth'])
        self.assertEqual(result['Ready'], [1])
        self.assertEqual(result['AlreadySettledReady'], [])
        self.assertEqual(result['UnchangedReady'], [])


if __name__ == '__main__':
    unittest.main()
