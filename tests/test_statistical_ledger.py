"""Contribution deltas agree with independent recomputation and scoped reads."""
import random
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer


class StatisticalLedgerTests(unittest.TestCase):
    def setUp(self):
        self.handler = PeTTaChainer()
        self.other = PeTTaChainer()
        self.frame = (
            "_Pattern=['P',_X], _Scope=[Kb,'MAIN','Nil'], "
            "_Identity=['forward-base-rate-identity',Kb,_Pattern], "
            "_Descriptor=['forward-base-rate-descriptor',Kb,_Pattern], "
            "'fa-register!'(_Identity,_Descriptor,[],_), 'fa-id'(_Identity,_Id), "
        )

    def probe(self, goal, **inputs):
        return janus.query_once(self.frame + goal, {'Kb': self.handler.kb, **inputs})

    def test_replace_remove_and_exclude_match_full_recomputation(self):
        rng = random.Random(55)
        members = {}
        for step in range(70):
            member = rng.randrange(9)
            remove = rng.randrange(4) == 0
            strength = rng.choice([0.0, .125, .5, .875, 1.0])
            mass = rng.choice([0.0, .25, .5, 1.0])
            operation = 'fa-remove!' if remove else 'fa-update!'
            if remove:
                members.pop(member, None)
            else:
                members[member] = (strength * mass, mass)
            result = self.probe(
                f"'{operation}'([['P',Member],_Scope,cpu,['STV',S,C]],_Id,_Descriptor,_), "
                "'fa-state'(_Id,['forward-aggregate-state',_,Sum,Mass,Count]), "
                # Independent sum of every retained observation, without deltas.
                "findall(_W-_M,'&ctx_forward_aggregate_observation'(_,[_Id,_],_,_W,_M,_),_Rows), "
                "aggregate_all(sum(_W),member(_W-_,_Rows),FullSum), "
                "aggregate_all(sum(_M),member(_-_M,_Rows),FullMass), "
                "aggregate_all(count,(member(_-_M,_Rows),_M>0),FullCount), "
                "'index-hash'(['sk-key',['P',Member],_Scope],_Read), "
                "'fa-left-out'(_Id,[_Read],_Excluded), 'ledger-read-excluding'(_Id,_Excluded,['forward-aggregate-state',_,LeftSum,LeftMass,LeftCount]), "
                "'fa-state'(_Id,After)", Member=member, S=strength, C=mass,
            )
            total = sum(w for w, _ in members.values())
            weight = sum(m for _, m in members.values())
            count = sum(m > 0 for _, m in members.values())
            for actual, expected in [('Sum', total), ('Mass', weight), ('Count', count),
                                     ('FullSum', total), ('FullMass', weight), ('FullCount', count)]:
                self.assertAlmostEqual(result[actual], expected, msg=(step, actual))
            own_w, own_m = members.get(member, (0.0, 0.0))
            self.assertAlmostEqual(result['LeftSum'], total - own_w)
            self.assertAlmostEqual(result['LeftMass'], weight - own_m)
            self.assertEqual(result['LeftCount'], count - (own_m > 0))
            self.assertEqual(result['After'][2:], [total, weight, count])
            # A user rate in another KB shares the pattern but no ledger state.
            janus.query_once("'set-base-rate'(Other,['P',_],['STV',S,0.8],_)",
                             {'Other': self.other.kb, 'S': strength})
            unchanged = self.probe(
                "'fa-state'(_Id,State), 'base-rate-cache-entries'(Kb,_Pattern,_Cache), "
                "aggregate_all(count,member(['base-rate',_,_,_,user,_],_Cache),UserEntries)")
            self.assertEqual(unchanged['State'], result['After'])
            self.assertEqual(unchanged['UserEntries'], 0)

    def test_instance_replacement_exclusion_and_regime_reset(self):
        frame = (
            "_Scope=[Kb,'MAIN','Nil'], "
            "_Args=[Kb,['ImplicationInstanceSample',['A',_X],['B',_X],_AT,_BT],"
            " 'extract-tv',['InstanceEvidence',['BaseRateEvidence',0.0,0.0],['BaseRateEvidence',0.0,0.0]],"
            " 'identity','implication-instance-ctv','result-tv'], _Fold=['sk-fold',_Args], "
            "'index-hash'(_Fold,_H), "
        )
        janus.query_once("'set-rule-change-hazard'(Kb,0.0,_)", {'Kb': self.handler.kb})
        members = {}
        for member, positive, negative in [
                (1, .25, .75), (2, .5, .5), (1, .875, .125), (3, 1.0, 0.0), (2, 0.0, 0.0)]:
            members[member] = (positive, negative)
            result = janus.query_once(frame +
                "_Member=['sk-key',['ImplicationInstanceSample',['A',Member],['B',Member],['STV',1,1],['STV',1,1]],_Scope], "
                "'sk-instance-tally'(_H,_Fold,Kb,_Tally), "
                "'ledger-replace-instance!'(_H,_Fold,_Member,_Tally,"
                " ['InstanceEvidence',['BaseRateEvidence',P,P],['BaseRateEvidence',N,N]],'sk-none',"
                " ['InstanceEvidence',['BaseRateEvidence',0.0,0.0],['BaseRateEvidence',0.0,0.0]],_), "
                "'sk-instance-tally'(_H,_Fold,Kb,Taken), "
                "Taken=['instance-regimes',_,_,_Pos,_Neg], "
                "'regime-evidence'(0.0,_Pos,['BaseRateEvidence',PW,PM]), "
                "'regime-evidence'(0.0,_Neg,['BaseRateEvidence',NW,NM]), "
                "'index-hash'(['sk-key',['B',Member],_Scope],_Read), "
                "'sk-left-out'(_H,[_Read],_Left), "
                "'ledger-instance-read-excluding'(_H,Taken,_Left,['instance-regimes',_,_,_LP,_LN]), "
                "'regime-evidence'(0.0,_LP,['BaseRateEvidence',LP,_]), "
                "'regime-evidence'(0.0,_LN,['BaseRateEvidence',LN,_]), "
                "'sk-instance-tally'(_H,_Fold,Kb,After)",
                {'Kb': self.handler.kb, 'Member': member, 'P': positive, 'N': negative})
            pw = sum(v[0] for v in members.values())
            nw = sum(v[1] for v in members.values())
            self.assertAlmostEqual(result['PW'], pw)
            self.assertAlmostEqual(result['PM'], pw)
            self.assertAlmostEqual(result['NW'], nw)
            self.assertAlmostEqual(result['NM'], nw)
            self.assertAlmostEqual(result['LP'], pw - positive)
            self.assertAlmostEqual(result['LN'], nw - negative)
            self.assertEqual(result['After'], result['Taken'])
        reset = janus.query_once(frame +
            "'ledger-reset-regime!'(_H,_Fold,_), "
            "'sk-rate-changed'(_H,_Fold,Pending), "
            "findall(_Value,'&ctx_sk_instance_member'(_, _H, _Value,_,_,_),Members), "
            "findall(_Value,'&ctx_sk_instance_tally'(_H,_,_Value),Tallies), "
            "findall(_Value,'&ctx_sk_instance_regime'(_H,_,_Value),Aliases), "
            "findall(_Value,'&ctx_sk_instance_digest'(_H,_Value),Digests), "
            "findall(_Value,'&ctx_sk_instance_sig'(_, _H,_Value),Signatures), "
            "findall(_Value,'&ctx_sk_instance_read'(_, _H,_,_Value),Reads)", {'Kb': self.handler.kb})
        self.assertEqual([m[1][1][1] for m in reset['Pending']], [1, 2, 3])
        for name in ['Members', 'Tallies', 'Aliases', 'Digests', 'Signatures', 'Reads']:
            self.assertEqual(reset[name], [], name)


if __name__ == '__main__':
    unittest.main()
