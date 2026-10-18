"""Member-driven fold checks preserve incumbents and completion provenance."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class FoldRefreshTests(unittest.TestCase):
    def setUp(self):
        self.handler = PeTTaChainer()
        self.handler.add_atoms_no_check([
            '(: c1 (Cand u1) (STV 1 1))',
            '(: c2 (Cand u2) (STV 1 1))',
            '(: a1 (A u1) (STV 1 1))',
            '(: r (Implication (A $x) (Leak $x)) (CTV (STV 0.4 1) (STV 0.1 1)))',
            '(: total (Implication (And '
            '(FoldAllTruth (And (Cand $v) (Leak $v)) (STV $s $_c) 0 0 '
            '(|-> ($acc $elem) (+ $acc $elem)) -> $sum) (Cand $u)) '
            '(Total $u)) (CTV (STV 0.5 1) (STV 0.5 1)))',
        ])

    def test_partial_to_complete_same_value_refreshes_reader(self):
        query = ['(: $p (Total u1) $tv)']
        self.handler.query_many_refs(query, steps=1)
        partial = self.handler.query_many_refs(query, steps=4)[0][0]
        self.assertIn('partial-fold 1 2', self.handler.expand_proof(partial.proof))
        # Hash the actual goal/evidence/dependencies inside Prolog: the CPU
        # arguments contain variables and must not be exported or instantiated.
        snapshot = (
            "once(('&sk_latest'(_,['sk-fold',[Kb|_]],"
            " ['sk-version',0,0,['sk-goal-val',_Goal,_P,_Ev,_Deps]]), "
            " 'sk-step-proof'(_P,Proof))), "
            "variant_sha1([_Goal,_Ev,_Deps],Signature)"
        )
        before = janus.query_once(snapshot, {'Kb': self.handler.kb})
        complete = self.handler.query_many_refs(query, steps=8)[0][0]
        after = janus.query_once(snapshot, {'Kb': self.handler.kb})
        self.assertEqual(before['Signature'], after['Signature'])
        self.assertEqual(before['Proof'][0], 'partial-fold')
        self.assertEqual(after['Proof'][0], 'foldall-proof')
        self.assertEqual(partial.tv[1], complete.tv[1])
        self.assertGreater(complete.tv[2], partial.tv[2] * 1.99)
        self.assertNotIn('partial-fold', self.handler.expand_proof(complete.proof))

    def test_dirty_seed_leaves_unread_fold_without_view(self):
        self.handler.query_many_refs(['(: $p (Total u1) $tv)'], steps=200)
        result = janus.query_once(
            "once(('&sk_latest'(_H,_Fold,['sk-version',0,0,_]), "
            " _Fold=['sk-fold',[Kb|_]])), "
            "'sk-drop-fold-view!'(_Fold,_), "
            "'sk-latest-view'(_H,_Fold,0,'sk-none'), "
            "empty_heap(_Empty), "
            "'sk-dirty-seed'(1000000,['sk-work',_Empty,_Empty],_Fold,_), "
            "'sk-latest-view'(_H,_Fold,0,View)", {'Kb': self.handler.kb},
        )
        self.assertEqual(result['View'], 'sk-none')


class BaseRateReadNotificationTests(unittest.TestCase):
    def setUp(self):
        self.handler = PeTTaChainer()
        self.handler.add_atom('(: pa (P a) (STV 0.2 0.8))')
        # Two distinct folds read the same pattern/mode cache entry.
        self.frame = (
            "_Pattern=['P',_X], _Scope=[Kb,'MAIN','Nil'], "
            "_Args=[Kb,_Pattern,'extract-tv',['BaseRateEvidence',0.0,0.0],"
            " 'BaseRateAcc','base-rate','result-tv'], _Fold=['sk-fold',_Args], "
            "_OtherArgs=[Kb,_Pattern,'extract-tv',['BaseRateEvidence',0.0,1.0],"
            " 'BaseRateAcc','base-rate','result-tv'], _Other=['sk-fold',_OtherArgs], "
            "'index-hash'(_Fold,_H), 'index-hash'(_Other,_OH), "
        )
        self.clean = (
            "'context-remove!'('&sk_dirty',[_H,_Fold],_), "
            "'context-remove!'('&sk_dirty',[_OH,_Other],_), "
        )
        self.dirty = (
            "'space-row-present?'('&ctx_sk_dirty',[_H,_Fold],Own), "
            "'space-row-present?'('&ctx_sk_dirty',[_OH,_Other],Other)"
        )
        janus.query_once(self.frame +
                         "'sk-fold-view'(_H,_Args,_), 'sk-fold-view'(_OH,_OtherArgs,_), " +
                         self.clean + 'true', {'Kb': self.handler.kb})

    def tearDown(self):
        janus.query_once(self.frame + self.clean + 'true', {'Kb': self.handler.kb})

    def test_take_consumes_only_its_new_notification(self):
        result = janus.query_once(self.frame +
            # A cached estimate can predate the current member tally.
            "'store-produced-base-rate!'(Kb,_Pattern,['STV',0.8,0.5],'base-rate',_), " +
            self.clean +
            "'sk-rate-dirty!'(_Fold,['sk-key',['P',a],_Scope],_), "
            "'sk-fold-view'(_H,_Args,['sk-goal-val',"
            " ['CPU','FoldAllCompiled',_,['STV',Strength,_]],_,_,_]), " +
            self.dirty, {'Kb': self.handler.kb})
        self.assertAlmostEqual(result['Strength'], .2)
        self.assertEqual((result['Own'], result['Other']), ('false', 'true'))

    def test_take_preserves_incoming_dirty_work(self):
        result = janus.query_once(self.frame +
            "'store-produced-base-rate!'(Kb,_Pattern,['STV',0.8,0.5],'base-rate',_), "
            "'sk-rate-dirty!'(_Fold,['sk-key',['P',a],_Scope],_), "
            "'sk-fold-view'(_H,_Args,_), " + self.dirty, {'Kb': self.handler.kb})
        self.assertEqual((result['Own'], result['Other']), ('true', 'true'))

    def test_open_key_collision_survives_a_taking_read(self):
        result = janus.query_once(self.frame +
            "'store-produced-base-rate!'(Kb,_Pattern,['STV',0.8,0.5],'base-rate',_), " +
            self.clean +
            # Simulate a coarse-hash collision with a unifiable non-variant
            # key. It must neither count as incoming work for this fold nor
            # disappear when this fold consumes its own new notification.
            "_Alias=['sk-fold',[Kb,_Pattern,'extract-tv',_Init,"
            " 'BaseRateAcc','base-rate','result-tv']], "
            "'context-add!'('&sk_dirty',[_H,_Alias],_), "
            "'sk-rate-dirty!'(_Fold,['sk-key',['P',a],_Scope],_), "
            "'sk-fold-view'(_H,_Args,_), "
            "aggregate_all(count,('&ctx_sk_dirty'(_H,_Own),_Own =@= _Fold),Own), "
            "aggregate_all(count,('&ctx_sk_dirty'(_H,_Kept),_Kept =@= _Alias),Alias), "
            "'remove-variant-row!'('&sk_dirty',[_H,_Alias],_)",
            {'Kb': self.handler.kb})
        self.assertEqual((result['Own'], result['Alias']), (0, 1))

    def test_forward_aggregate_update_notifies_both_folds(self):
        result = janus.query_once(self.frame +
            "'forward-maintain-aggregates!'('aggregate-update',"
            " [['P',a],_Scope,cpu,['STV',0.9,0.8]],_), " +
            self.dirty, {'Kb': self.handler.kb})
        self.assertEqual((result['Own'], result['Other']), ('true', 'true'))

    def test_user_set_and_clear_notify_both_folds(self):
        result = janus.query_once(self.frame +
            "'set-base-rate'(Kb,_Pattern,['STV',0.7,0.5],_), "
            "'sk-fold-view'(_H,_Args,['sk-goal-val',"
            " ['CPU','FoldAllCompiled',_,['STV',Strength,_]],_,_,_]), " +
            self.dirty, {'Kb': self.handler.kb})
        self.assertEqual(result['Strength'], .7)
        self.assertEqual((result['Own'], result['Other']), ('true', 'true'))
        cleared = janus.query_once(self.frame + self.clean +
            "'clear-base-rate'(Kb,_Pattern,_), " + self.dirty, {'Kb': self.handler.kb})
        self.assertEqual((cleared['Own'], cleared['Other']), ('true', 'true'))


if __name__ == '__main__':
    unittest.main()
