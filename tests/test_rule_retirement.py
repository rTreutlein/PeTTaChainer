"""Rule-set sharing and retirement checks after many epoch changes."""
import unittest

from pettachainer import PeTTaChainer


class TestRuleRetirement(unittest.TestCase):
    def test_repeated_withdrawals_check_only_the_epoch_delta(self):
        import janus_swi

        PeTTaChainer()
        # A long derivation shares its set among many proof refs. Retired
        # identities belong to other stored proofs, so this exercises real
        # membership misses, including collisions in the coarse bit mask.
        stats = janus_swi.query_once(
            "rule_set_leaf(230000001, _Unread), "
            "findall(['proof-ref', _P], (between(1, 4096, _I), _P is 2000020000+_I, "
            " _R is 200000000+_I, _F is (_R+1) << 1, assertz(user:'&proof'(_P, [], ['ev-set', 0], _F))), _Refs), "
            "assertz(user:'&proof'(2000025000, [revision|_Refs], ['ev-set', 0], 0)), "
            "proof_rules(2000025000, _Set), "
            "forall(between(2000000000, 2000000063, _P), "
            " (assertz(user:'&proof'(_P, ['proof-ref', 2000025000], ['ev-set', 0], 0)), proof_rules(_P, _Set))), "
            "flag(withdraw_epoch, _Epoch, _Epoch), rule_set_live(_Set, _Epoch), "
            "findall(_Cost, (between(1, 128, _I), _R is 210000000 + _I, rule_set_leaf(_R, _Outside), "
            " _OF is (_R+1) << 1, _OP is 2000000100+_I, assertz(user:'&proof'(_OP, [], ['ev-set', 0], _OF)), "
            " 'withdraw-rule!'(_R, _), "
            " statistics(inferences, _Before), 'proof-live?'(['proof-ref', 2000000000], true), "
            " statistics(inferences, _After), _Cost is _After-_Before, 'proof-live?'(['proof-ref', _OP], false)), _Costs), "
            "max_list(_Costs, Max), min_list(_Costs, Min), "
            "rule_set_leaf(230000000, _Leaf), rule_sets_join([_Set, _Leaf], _Fresh), "
            "flag(withdraw_epoch, _Current, _Current), statistics(inferences, _Start), "
            "rule_set_live(_Fresh, _Current), statistics(inferences, _End), FirstRead is _End-_Start, "
            "statistics(inferences, _LeafStart), rule_set_live(_Unread, _Current), "
            "statistics(inferences, _LeafEnd), LeafRead is _LeafEnd-_LeafStart, "
            "aggregate_all(count, proof_rules_memo(_, _Set), Shared), "
            "forall(between(2000000000, 2000000063, _P), retractall(user:'&proof'(_P, _, _, _))), "
            "forall(between(1, 4096, _I), (_P is 2000020000+_I, retractall(user:'&proof'(_P, _, _, _)))), "
            "retractall(user:'&proof'(2000025000, _, _, _)), "
            "forall(between(1, 128, _I), (_OP is 2000000100+_I, retractall(user:'&proof'(_OP, _, _, _)))), "
            "rule_sets_gc, "
            "(proof_live_memo(_Set, _, _) -> Collected = 0 ; Collected = 1)"
        )
        self.assertEqual(stats["Shared"], 65)
        self.assertEqual(stats["Collected"], 1)
        # Cost stays bounded when the retirement log grows from 1 to 128.
        # Mask collisions affect set membership but do not revisit that log.
        self.assertLess(stats["Max"], 500)
        self.assertLess(stats["Min"], 100)
        self.assertLess(stats["FirstRead"], 100)
        self.assertLess(stats["LeafRead"], 100)

    def test_repeated_and_regrouped_joins_share_one_set(self):
        import janus_swi

        PeTTaChainer()
        stats = janus_swi.query_once(
            "rule_set_leaf(240000001, _A), rule_set_leaf(240000002, _B), "
            "rule_set_leaf(240000003, _C), rule_sets_join([_A, _B], _AB), "
            "rule_sets_join([_AB, _C], Set), rule_sets_join([_C, _B], _BC), "
            "rule_sets_join([_BC, _A], Regrouped), "
            "aggregate_all(count, rule_set(_, _, _, _), Before), "
            "forall(between(1, 1000, _), rule_sets_join([Set, _A, _AB, _BC], Set)), "
            "aggregate_all(count, rule_set(_, _, _, _), After), "
            "_FA is 240000002 << 1, _FB is 240000003 << 1, _FC is 240000004 << 1, "
            "assertz(user:'&proof'(2000000071, [], ['ev-set', 0], _FB)), "
            "assertz(user:'&proof'(2000000072, [], ['ev-set', 0], _FC)), "
            "assertz(user:'&proof'(2000000070, ['by', joined, ['proof-ref', 2000000071], ['proof-ref', 2000000072]], ['ev-set', 0], _FA)), "
            "proof_rules(2000000070, Set), "
            "rule_sets_gc, 'withdraw-rule!'(240000001, _), "
            "'proof-live?'(['proof-ref', 2000000070], Live), "
            "forall(between(2000000070, 2000000072, _P), retractall(user:'&proof'(_P, _, _, _))), rule_sets_gc"
        )
        self.assertEqual(stats["Set"], stats["Regrouped"])
        self.assertEqual(stats["Before"], stats["After"])
        self.assertEqual(stats["Live"], "false")

    def test_provenance_resolves_only_the_proof_dag_read(self):
        import janus_swi

        PeTTaChainer()
        stats = janus_swi.query_once(
            "forall(between(1, 4096, _I), (_P is 2000010000+_I, _Owner is 260000000+_I, "
            " _Flags is (_Owner+1) << 1, assertz(user:'&proof'(_P, [], ['ev-set', 0], _Flags)))), "
            "aggregate_all(count, (proof_rules_memo(_P, _), _P>2000010000, _P=<2000014096), Before), "
            "assertz(user:'&proof'(2000015000, ['by', lazy, ['proof-ref', 2000010001]], ['ev-set', 0], 0)), "
            "proof_rules(2000015000, _Set), rule_set_has(_Set, 260000001), "
            "aggregate_all(count, (proof_rules_memo(_P, _), _P>2000010000, _P=<2000015000), Read), "
            "'withdraw-rule!'(260000001, _), 'proof-live?'(['proof-ref', 2000015000], Dead), "
            "'proof-live?'(['proof-ref', 2000010002], Live), "
            "forall(between(1, 4096, _I), (_P is 2000010000+_I, retractall(user:'&proof'(_P, _, _, _)))), "
            "retractall(user:'&proof'(2000015000, _, _, _)), rule_sets_gc, "
            "aggregate_all(count, (proof_rules_memo(_P, _), _P>2000010000, _P=<2000015000), Collected)"
        )
        self.assertEqual(stats["Before"], 0)
        self.assertEqual(stats["Read"], 2)
        self.assertEqual(stats["Dead"], "false")
        self.assertEqual(stats["Live"], "true")
        self.assertEqual(stats["Collected"], 0)

    def test_sparse_rule_sets_are_canonical_and_exact(self):
        import janus_swi

        PeTTaChainer()
        stats = janus_swi.query_once(
            "_Rules = [250000001, 250000002, 250000007, 250000032, 250000064, 250000512, 250001024, 250004096], "
            "findall(_S, (member(_R, _Rules), rule_set_leaf(_R, _S)), _Leaves), "
            "rule_sets_join(_Leaves, Set), reverse(_Leaves, _Reverse), "
            "foldl(rule_sets_union, _Reverse, 0, Reversed), "
            "forall(member(_R, _Rules), rule_set_has(Set, _R)), "
            "forall(member(_R, [250000003, 250000031, 250000513, 250004097]), "
            " (rule_set_leaf(_R, _), \\+ rule_set_has(Set, _R)))"
        )
        self.assertTrue(stats["truth"])
        self.assertEqual(stats["Set"], stats["Reversed"])

    def test_unresolved_snapshot_keeps_retired_summary_sources_through_gc(self):
        import janus_swi

        PeTTaChainer()
        stats = janus_swi.query_once(
            "_WF is 270000002 << 1, _LF is 270000003 << 1, "
            "assertz(user:'&proof'(2000030001, [], ['ev-set', 0], _WF)), "
            "assertz(user:'&proof'(2000030002, [], ['ev-set', 0], _LF)), "
            "'record-summary-rules!'(280000001, 310001, "
            " [revision, ['proof-ref', 2000030001], ['proof-ref', 2000030002]], _), "
            "_Proof = ['by', snapshot_parent, [forgotten, 280000001, 310001]], "
            "'record-view-rule!'(2000030003, -1, _Proof, _Owner), _Flags is _Owner << 1, "
            "assertz(user:'&proof'(2000030003, _Proof, ['ev-set', 0], _Flags)), "
            "aggregate_all(count, proof_rules_memo(2000030003, _), Before), "
            "retractall(user:'&proof'(2000030001, _, _, _)), retractall(user:'&proof'(2000030002, _, _, _)), "
            "'withdraw-rule!'(270000001, _), rule_sets_gc, "
            "'proof-live?'(['proof-ref', 2000030003], Dead), rule_sets_gc, "
            "aggregate_all(count, summary_rules(280000001, 310001, _), Captured), "
            "'proof-live?'(['proof-ref', 2000030003], StillDead), "
            "retractall(user:'&proof'(2000030003, _, _, _)), rule_sets_gc, "
            "aggregate_all(count, summary_user(280000001, 310001, _), Users)"
        )
        self.assertEqual(stats["Before"], 0)
        self.assertEqual(stats["Dead"], "false")
        self.assertEqual(stats["StillDead"], "false")
        self.assertEqual(stats["Captured"], 0)
        self.assertEqual(stats["Users"], 0)

    def test_zero_is_a_real_rule_identity(self):
        import janus_swi

        PeTTaChainer()
        stats = janus_swi.query_once(
            "'record-view-rule!'(2000031000, 0, [], Code), _Flags is Code << 1, "
            "assertz(user:'&proof'(2000031000, [], ['ev-set', 0], _Flags)), "
            "proof_rules(2000031000, _Set), rule_set_has(_Set, 0), "
            "'record-view-rule!'(2000031001, -1, [], Fold), "
            "'record-view-rule!'(2000031002, 1000000000, [], Temp), "
            "retractall(user:'&proof'(2000031000, _, _, _)), rule_sets_gc"
        )
        self.assertEqual(stats["Code"], 1)
        self.assertEqual(stats["Fold"], 0)
        self.assertEqual(stats["Temp"], 0)

    def test_delivered_retired_waiters_leave_the_index(self):
        import janus_swi

        chainer = PeTTaChainer()
        chainer.add_atoms_no_check([
            "(: waiter-old (Implication (WaitA $t) (WaitB $t)) (CTV (STV 0.9 1) (STV 0 1)))",
            "(: waiter-live (Implication (WaitC $t) (WaitB $t)) (CTV (STV 0.2 1) (STV 0 1)))",
            "(: waiter-a (WaitA warm) (STV 1 1))",
            "(: waiter-c (WaitC warm) (STV 1 1))",
        ])
        chainer.query("(: $p (WaitB warm) $tv)", steps=40, timeout_sec=0)
        ids = janus_swi.query_once("findall(_Id, rule_name_index('waiter-old', _Id), Ids)")["Ids"]
        self.assertTrue(ids)
        chainer._call("withdraw-named-rules!", ["waiter-old"])
        chainer.add_atoms_no_check([
            "(: waiter-fresh-a (WaitA fresh) (STV 1 1))",
            "(: waiter-fresh-c (WaitC fresh) (STV 1 1))",
        ])
        chainer.query("(: $p (WaitB fresh) $tv)", steps=40, timeout_sec=0)
        remaining = janus_swi.query_once(
            "aggregate_all(count, (member(_Id, Ids), "
            " user:'&sk_wait'(_, [['WaitA', fresh], [KB, 'MAIN', 'Nil'], _, _], "
            " ['sk-partial', _, _Id, _, _, _, _])), N)",
            {"Ids": ids, "KB": chainer.kb},
        )["N"]
        self.assertEqual(remaining, 0)
