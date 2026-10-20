"""Hard observed facts do not correlate views; uncertain reports still do."""
import unittest
import warnings

import janus_swi as janus
from pettachainer import PeTTaChainer


class CertainObservationOverlapTests(unittest.TestCase):
    def test_nested_shared_hard_observation_keeps_t19_report(self):
        # The t18 update reads blocked19 below a negated forward block proof,
        # through storm smoothing. The t19 update reads it directly. Given a
        # hard block observation, the updates are independent. Losing prod19
        # leaves D19=.75 and D20=.575 instead of the exact 1 and .75.
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: persist-storm (Implication (And (NextPeriod $p $t) (Storm $p)) (Storm $t)) (CTV (STV 0.7 1) (STV 0.3 1)))',
            '(: block (Implication (Storm $t) (Blocked rf $t)) (CTV (STV 0.8 1) (STV 0.03 1)))',
            '(: arrives (Implication (And (Producing mine $t) (Not (Blocked rf $t))) (FuelArrived $t)) (CTV (STV 1 1) (STV 0 1)))',
            '(: fuelled (Implication (Or (Stocked $t) (FuelArrived $t)) (Fuelled plant $t)) (CTV (STV 1 1) (STV 0 1)))',
            '(: runs-plant (Implication (And (Fuelled plant $t) (Not (Degraded plant $t))) (Producing plant $t)) (CTV (STV 1 1) (STV 0 1)))',
            '(: persist-degraded (Implication (And (NextPeriod $p $t) (Degraded plant $p)) (Degraded plant $t)) (CTV (STV 0.75 1) (STV 0.05 1)))',
            '(: d17 (Degraded plant t17) (STV 1 1))',
            '(: s17 (Storm t17) (STV 1 1))',
        ] + [f'(: next{t} (NextPeriod t{t-1} t{t}) (STV 1 1))' for t in (18, 19, 20)] + [x for t in (18, 19) for x in (
            f'(: stocked{t} (Stocked t{t}) (STV 1 1))',
            f'(: mine{t} (Producing mine t{t}) (STV 0 1))',
            f'(: prod{t} (Producing plant t{t}) (STV 0 1))',
        )] + ['(: blocked19 (Blocked rf t19) (STV 0 1))'])
        for statement in ('(Degraded plant $t)', '(Storm $t)'):
            h._call('set-base-rate', [f'{h.kb} {statement} (STV 0.3 0.9)'])
        for period, exact in ((18, 1), (19, 1), (20, .75)):
            with self.subTest(period=period):
                row = h.query_many_refs([f'(: $p (Degraded plant t{period}) $tv)'], steps=1000)[0][0]
                self.assertAlmostEqual(row.tv[1], exact, delta=1e-5)
                proof = h.expand_proof(row.proof)
                self.assertIn('blocked19', proof)
                self.assertIn(f'prod{min(period, 19)}', proof)

    def test_certainty_follows_a_removed_and_readded_statement(self):
        # A fact's certainty is read from the live KB, never cached: the same
        # name added again with an uncertain truth value is uncertain evidence.
        h = PeTTaChainer()
        h.add_atom('(: storm (Storm a) (STV 1 1))')
        query = ("Scope=[Kb,'MAIN','Nil'], 'evidence-set'([['fact-ev',Scope,storm,['Storm',a]]],Ev), "
                 "'evidence-uncertain-overlap?'(Ev,Ev,Overlap)")
        self.assertEqual(janus.query_once(query, {'Kb': h.kb})['Overlap'], 'false')
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', DeprecationWarning)
            h.remove_statement('storm')
        h.add_atom('(: storm (Storm a) (STV 0.6 0.9))')
        self.assertEqual(janus.query_once(query, {'Kb': h.kb})['Overlap'], 'true')

    def test_clash_ignores_only_binary_certain_stored_observations(self):
        for strength, confidence, certain in ((0, 1, True), (1, 1, True), (0, .9, False), (.4, 1, False)):
            for negative in (False, True):
                with self.subTest(strength=strength, confidence=confidence, negative=negative):
                    h = PeTTaChainer()
                    h.add_atoms_no_check([
                        f'(: report (Blocked rf t19) (STV {strength} {confidence}))',
                        '(: storm (Storm t19) (STV 0.4 0.9))',
                    ])
                    h.query_many_refs(['(: $p (Storm t19) $tv)'], steps=50)
                    result = janus.query_once(
                        "Scope=[Kb,'MAIN','Nil'], Blocked=['Blocked',rf,t19], "
                        "Storm=['sk-key',['Storm',t19],Scope], "
                        "'index-hash'(Storm,H), 'deps-key'(H,D), "
                        "'evidence-set'([[Tag,Scope,report,Blocked]],Ev), "
                        "'sk-clash-on'([],['sk-acc',[],Ev,[D],[]], "
                        " ['sk-val',[['Goal'],Scope,p,['STV',0.5,0.8]],Ev,D], "
                        " ['sk-clash',Keys,_])",
                        {'Kb': h.kb, 'Tag': 'not-fact-ev' if negative else 'fact-ev'},
                    )
                    expected = [] if certain else [['sk-key', ['Blocked', 'rf', 't19'], [h.kb, 'MAIN', 'Nil']]]
                    self.assertEqual(result['Keys'], expected)

    def test_nested_given_context_survives_reference_collection(self):
        # The given sibling is below a forward prior and a negative proof,
        # rather than among the outer view's own completion witnesses. The
        # completion's own evidence keeps, of the certain facts, only its
        # consequence.
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a (A) (STV 0 1))',
            '(: b (B) (STV 1 1))',
            '(: report (Report) (STV 1 1))',
        ])
        result = janus.query_once(
            "Scope=[Kb,'MAIN','Nil'], "
            "'evidence-set'([['fact-ev',Scope,a,['A']]],EA), "
            "'evidence-set'([['fact-ev',Scope,b,['B']]],EB), "
            "'evidence-set'([['fact-ev',Scope,report,['Report']]],ER), "
            "Part=[['antecedent-completion',r,1,with,cpu,[prior,['STV',0.3,0.9]]], "
            " [conjunction,['fact-source',EA,a],['fact-source',EB,b],['fact-source',ER,report]]], "
            "'sk-store-proof!'(0,Part,['ev-set',0],Inner), "
            "'sk-store-proof!'(0,[by,f,[negated,Inner]],['ev-set',0],Root), "
            "'proof-given-evidence'(Root,Given), 'evidence-entries'(Given,Before), "
            "'evidence-union'(EA,EB,AB), 'evidence-union'(AB,ER,All), "
            "'sk-condition-evidence'(['Report'],Part,[],All,Compared), "
            "'evidence-entries'(Compared,Remaining), "
            # Root the proof, but not its cached context union. The collector
            # must follow the memo for both Root and its child reference.
            "'index-hash'(['sk-key',['CacheProbe'],Scope],H), "
            "setup_call_cleanup(assertz(user:'&sk_merged'(H,['CacheProbe'],probe,Root,false)), "
            " ('stored-refs-gc!'(_), 'stored-refs-gc!'(_), "
            "  'proof-given-evidence'(Root,Given), 'evidence-entries'(Given,After)), retractall(user:'&sk_merged'(H,['CacheProbe'],probe,Root,false))), "
            "Root=['proof-ref',Pid], Inner=['proof-ref',Child], "
            "'stored-refs-gc!'(_), 'stored-refs-gc!'(_), "
            "(proof_given_memo(Pid,_)->RootMemo=true;RootMemo=false), "
            "(proof_given_memo(Child,_)->ChildMemo=true;ChildMemo=false), "
            "'proof-given-evidence'([_Open,one,two],_), (var(_Open)->Unbound=true;Unbound=false)",
            {'Kb': h.kb},
        )
        scope = [h.kb, 'MAIN', 'Nil']
        self.assertCountEqual(result['Before'], [
            ['not-fact-ev', scope, 'a', ['A']],
            ['not-fact-ev', scope, 'b', ['B']],
        ])
        self.assertEqual(result['After'], result['Before'])
        self.assertEqual(result['Remaining'], [['fact-ev', scope, 'report', ['Report']]])
        self.assertEqual((result['RootMemo'], result['ChildMemo']), ('false', 'false'))
        self.assertEqual(result['Unbound'], 'true')
