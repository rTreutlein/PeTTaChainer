"""Rule-set sharing and retirement checks after many epoch changes."""
import unittest

from pettachainer import PeTTaChainer


class TestRuleRetirement(unittest.TestCase):
    def test_repeated_withdrawals_check_only_the_epoch_delta(self):
        import janus_swi

        PeTTaChainer()
        # A long derivation shares its set among many proof refs. Each stale
        # memo checks one new retirement, rather than all earlier retirements.
        stats = janus_swi.query_once(
            "findall(_S, (between(200000001, 200004096, _R), rule_set_leaf(_R, _S)), _Leaves), "
            "rule_sets_join(_Leaves, _Set), "
            "_Flags is _Set << 1, "
            "forall(between(2000000000, 2000000063, _P), assertz(user:'&proof'(_P, [], ['ev-set', 0], _Flags))), "
            "flag(withdraw_epoch, _Epoch, _Epoch), rule_set_live(_Set, _Epoch), "
            "findall(_Cost, (between(1, 128, _I), _R is 210000000 + _I, 'withdraw-rule!'(_R, _), "
            " flag(withdraw_epoch, _E, _E), statistics(inferences, _Before), rule_set_live(_Set, _E), "
            " statistics(inferences, _After), _Cost is _After-_Before), _Costs), "
            "max_list(_Costs, Max), min_list(_Costs, Min), "
            "rule_set_leaf(230000000, _Leaf), rule_sets_join([_Set, _Leaf], _Fresh), "
            "flag(withdraw_epoch, _Current, _Current), statistics(inferences, _Start), "
            "rule_set_live(_Fresh, _Current), statistics(inferences, _End), FirstRead is _End-_Start, "
            "aggregate_all(count, proof_rules(_, _Set), Shared), "
            "retractall(user:'&proof'(_, [], ['ev-set', 0], _Flags)), rule_sets_gc, "
            "(proof_live_memo(_Set, _, _) -> Collected = 0 ; Collected = 1)"
        )
        self.assertEqual(stats["Shared"], 64)
        self.assertEqual(stats["Collected"], 1)
        # Cost stays bounded when the retirement log grows from 1 to 128.
        # Mask collisions affect set membership but do not revisit that log.
        self.assertLess(stats["Max"], 500)
        self.assertLess(stats["Min"], 100)
        self.assertLess(stats["FirstRead"], 100)

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
