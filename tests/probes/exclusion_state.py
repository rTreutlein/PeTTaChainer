"""Exclusion-cache soundness and interruption probes in an isolated runtime."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class ExclusionStateTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        janus.query_once(
            "retractall('&sk_branch_cuts'(_,_)), retractall('&sk_reading'(_,_,_)), "
            "'change-state!'(sk_branch_at,0,_)"
        )

    def assert_rejection_restricts_reuse(self, setup, rejection):
        result = janus.query_once(
            setup + ", assertz('&sk_branch_cuts'(987654,[])), "
            "'change-state!'(sk_branch_at,987654,_), " + rejection + ", "
            "'&sk_branch_cuts'(987654,Cuts), 'change-state!'(sk_branch_at,0,_), "
            "_Owner=['sk-key',['Cached'],[Kb,'MAIN','Nil']], 'index-hash'(_Owner,_Hash), "
            "'index-hash'([_Hash,987654],_Slot), "
            "'sk-cache-branch!'(_Slot,_Hash,_Owner,987654,-1,[],Cuts,'sk-none',_), "
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
            "asserta(('&sk_branch_cuts'(_,_) :- flag(exclusion_probe_interrupt,_,1), "
            " throw(interrupted_rebuild)), _Trap), "
            "catch(('sk-rebuild-view'(_Hash,_Key,987603,[-1],_) -> true ; true), "
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
            "aggregate_all(count,'&sk_branch_cuts'(_,_),Frames), "
            "aggregate_all(count,'&sk_reading'(_,_,_),Readers)"
        )
        self.assertEqual((cleaned['Frame'], cleaned['Frames'], cleaned['Readers']), (0, 0, 0))


if __name__ == '__main__':
    unittest.main()
