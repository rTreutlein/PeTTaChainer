"""Known outcomes retire search work without retiring their history or samples."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestSearchRetirement(unittest.TestCase):
    def test_dropped_component_clears_retirement_debt(self):
        h = PeTTaChainer()
        node = [['Dropped', 'x'], [h.kb, 'MAIN', 'Nil'], 'proof', ['STV', 0.5, 0.1]]
        counts = janus.query_once(
            "sk_search_init, 'sk-node-hash'(N,H), pw_node(H,N,R),"
            "assertz(sk_child_debt(R,999999999)), assertz(sk_retire_component(R)),"
            "'sk-drop-pending!'(H,N,_),"
            "aggregate_all(count,sk_child_debt(R,_),Debt),"
            "aggregate_all(count,sk_retire_component(R),Queued)", {'N': node})
        self.assertEqual([counts[k] for k in ('Debt', 'Queued')], [0, 0])

    def test_uncertain_conclusion_checks_retirement_once(self):
        h = PeTTaChainer()
        h.add_atom('(: observed (Uncertain x) (STV 0.5 0.9))')
        ctx = [h.kb, 'MAIN', 'Nil']
        owner = [['Uncertain', 'x'], ctx, 'root', ['STV', 0.5, 0.9]]
        premise = [['Missing', 'x'], ctx, 'premise', ['STV', 0.5, 0.1]]
        result = janus.query_once(
            "'sk-node-hash'(N,H),'link-digest'(['sk-child-link',O,N],D),"
            "forall(between(1,100,_),'sk-store-wait!'(D,H,N,['sk-partial',O,1,O,[],[N],[]],_)),"
            "use_module(library(prolog_profile)),"
            "'$profile'('sk-retire-known!'(['Uncertain',x],Ctx,_),cputime,false,500.0),"
            "findall(_Count,(profile_procedure_data(user:'sk-known-conclusion?'/2,_Stats),"
            "get_dict(call,_Stats,_Count)),Counts)", {'O': owner, 'N': premise, 'Ctx': ctx})
        self.assertEqual(result['Counts'], [1])

    def test_closed_outcome_stops_history_join_growth(self):
        h = PeTTaChainer()
        h.set_rule_refinement(True)
        h.set_positive_only_predicate('Next')
        h.set_positive_only_predicate('At')
        rule = '(Implication (And (Next $p $t) (Next $t $u) (At left $p) (At right $t)) (Ball right $u))'
        h.add_atoms_no_check([
            f'(: r {rule} (STV 0.5 0.01))',
            '(: link1 (Next d1 d2) (STV 1 1))',
            '(: at1 (At left d1) (STV 1 1))',
            '(: at2 (At right d2) (STV 1 1))',
        ])
        h.query_many_refs(['(: $p (Ball right d3) $tv)'], steps=100)
        count = "aggregate_all(count, '&sk_wait'(_, _, ['sk-partial', _, _, [['Ball', right, d3], [Kb, 'MAIN', 'Nil']|_]|_]), N)"
        self.assertGreater(janus.query_once(count, {'Kb': h.kb})['N'], 0)
        h.add_atom('(: closed (Ball right d3) (STV 0 1))')
        truth = f'(: $p (RuleTruth {rule}) $tv)'
        h.query_many_refs([truth], steps=0)
        self.assertEqual(janus.query_once(count, {'Kb': h.kb})['N'], 0)
        for n in range(4, 104):
            h.add_atom(f'(: link{n} (Next d{n-1} d{n}) (STV 1 1))')
            h.query_many_refs([truth], steps=0)
        self.assertEqual(janus.query_once(count, {'Kb': h.kb})['N'], 0)
        answer = h.query_many_refs(['(: $p (Ball right d3) $tv)'], steps=0)[0][0]
        self.assertEqual(answer.proof, 'closed')
        self.assertEqual(answer.tv, ['STV', 0, 1])
        # The historical input and the registered rule's sample machinery stay.
        answer = h.query_many_refs(['(: $p (Next d1 d2) $tv)'], steps=0)[0][0]
        self.assertEqual(answer.proof, 'link1')
        self.assertEqual(answer.tv, ['STV', 1, 1])
        self.assertEqual(janus.query_once(
            "aggregate_all(count, pw_id(_, [['Ball', right, d3], [Kb, 'MAIN', 'Nil']|_], _), N)",
            {'Kb': h.kb})['N'], 0)

    def test_bound_join_retirement_preserves_shared_open_search(self):
        h = PeTTaChainer()
        h.set_positive_only_predicate('Next')
        h.set_positive_only_predicate('At')
        h.add_atoms_no_check([
            '(: r (Implication (And (Next $p $t) (Next $t $u) (At left $p) (At right $t)) (Ball right $u)) (STV 1 0.9))',
            '(: n1 (Next d1 d2) (STV 1 1))',
            '(: n2 (Next d2 d3) (STV 1 1))',
            '(: n3 (Next d2 d4) (STV 1 1))',
            '(: a1 (At left d1) (STV 1 1))',
        ])
        h.query_many_refs(['(: $p (Ball right $u) $tv)'], steps=100)
        # Two bound conclusions share their open owner and the At right d2
        # child. Closing d3 must release only d3's lease on that child.
        h.add_atom('(: closed (Ball right d3) (STV 0 1))')
        h.query_many_refs(['(: $p (Ball right d3) $tv)'], steps=0)
        h.add_atom('(: a2 (At right d2) (STV 1 1))')
        answer = h.query_many_refs(['(: $p (Ball right d4) $tv)'], steps=100)[0][0]
        self.assertGreater(answer.tv[1], 0.9)
        self.assertGreater(answer.tv[2], 0.1)
        self.assertEqual(h.query_many_refs(['(: $p (Ball right d3) $tv)'], steps=0)[0][0].proof, 'closed')

    def test_known_premise_keeps_parked_delivery_for_other_consumers(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: p1 (Implication Z1 P1) (CTV (STV 1 0.9) (STV 0 0.9)))',
            '(: p2 (Implication Z2 P2) (CTV (STV 1 0.9) (STV 0 0.9)))',
            '(: other (Implication P2 (Other found)) (CTV (STV 1 0.9) (STV 0 0.9)))',
        ] + [f'(: fan{i} (Implication P1 (Fan f{i})) (CTV (STV 1 0.9) (STV 0 0.9)))' for i in range(40)])
        h.query_many_refs(['(: $p (Other $x) $tv)'], steps=100)
        h.query_many_refs(['(: $p (Fan $x) $tv)'], steps=100)
        h.add_atoms_no_check(['(: observed1 P1 (STV 1 1))', '(: observed2 P2 (STV 1 1))'])
        # The first delivery uses the ingestion allowance; P2's answer is
        # parked. It is work for Other's consumer, although P2 is now known.
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        self.assertGreater(janus.query_once(
            "aggregate_all(count, '&sk_parked'(_, _, ['sk-delivery', [P2, [Kb, 'MAIN', 'Nil']|_], _]), N)",
            {'Kb': h.kb, 'P2': 'P2'})['N'], 0)
        answers = h.query_many_refs(['(: $p (Other $x) $tv)'], steps=50)[0]
        self.assertTrue(answers)
        self.assertEqual(answers[0].statement, ['Other', 'found'])
        self.assertGreater(answers[0].tv[1], 0.9)

    def test_withdrawal_and_known_conclusion_retirement_share_join_indexes(self):
        for withdraw_first in (False, True):
            with self.subTest(withdraw_first=withdraw_first):
                h = PeTTaChainer()
                h.set_positive_only_predicate('Next')
                h.set_positive_only_predicate('At')
                h.add_atoms_no_check([
                    '(: obsolete (Implication (And (Next $p $t) (Next $t $u) (At left $p) (At right $t)) (Ball right $u)) (STV 1 0.9))',
                    '(: alternative (Implication (Other $t) (Ball right $t)) (CTV (STV 0.2 1) (STV 0 1)))',
                    '(: n1 (Next d1 d2) (STV 1 1))',
                    '(: n2 (Next d2 d3) (STV 1 1))',
                    '(: a1 (At left d1) (STV 1 1))',
                ])
                h.query_many_refs(['(: $p (Ball right d3) $tv)'], steps=100)
                ctx = [h.kb, 'MAIN', 'Nil']
                before = janus.query_once(
                    "'link-digest'(['sk-key',['Ball',right,d3],Ctx],D),"
                    "aggregate_all(count,'&sk_join_link'(D,_),Joins),"
                    "aggregate_all(count,'&sk_wait'(_,_,['sk-partial',_,_,[['Ball',right,d3],Ctx|_]|_]),Waiters)",
                    {'Ctx': ctx})
                self.assertGreater(before['Joins'], 0)
                self.assertGreater(before['Waiters'], 0)
                if withdraw_first:
                    h._call('withdraw-named-rules!', ['obsolete'])
                    # A late delivery removes the withdrawn waiter before
                    # known-conclusion retirement encounters the same owner.
                    h.add_atom('(: a2 (At right d2) (STV 1 1))')
                    h.query_many_refs(['(: $p (Ball right d3) $tv)'], steps=40)
                h.add_atom('(: closed (Ball right d3) (STV 0 1))')
                h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
                if not withdraw_first:
                    h._call('withdraw-named-rules!', ['obsolete'])
                # Settle the shared premises before checking link retirement.
                h.query_many_refs(['(: $p (At left d1) $tv)', '(: $p (At right d2) $tv)'], steps=100)
                h.add_atoms_no_check([
                    '(: later (Next d2 d4) (STV 1 1))',
                    '(: other (Other d4) (STV 1 1))',
                ])
                answer = h.query_many_refs(['(: $p (Ball right d4) $tv)'], steps=100)[0][0]
                self.assertEqual(answer.tv[1], 0.2)
                closed = h.query_many_refs(['(: $p (Ball right d3) $tv)'], steps=0)[0][0]
                self.assertEqual((closed.proof, closed.tv), ('closed', ['STV', 0, 1]))
                after = janus.query_once(
                    "'link-digest'(['sk-key',['Ball',right,d3],Ctx],D),"
                    "aggregate_all(count,'&sk_join_link'(D,_),Joins),"
                    "aggregate_all(count,sk_search_clause(_, [['Ball',right,d3],Ctx],_,_),Indexed),"
                    "aggregate_all(count,(sk_search_clause(_,_,_,_Ref),clause_property(_Ref,erased)),Orphans),"
                    "aggregate_all(count,(sk_child_users(_,_Ref),clause_property(_Ref,erased)),Leases),"
                    "aggregate_all(count,(sk_child_edge(_,_Ref),clause_property(_Ref,erased)),Edges),"
                    "aggregate_all(count,(pw_work(_,_Work),_Work<0),Negative),"
                    "aggregate_all(count,'&sk_child'(_, [['Ball',right,d3],Ctx|_],_,_),Children)", {'Ctx': ctx})
                self.assertEqual([after[k] for k in ('Joins', 'Indexed', 'Orphans', 'Leases', 'Edges', 'Negative', 'Children')], [0]*7)

    def test_summary_thaw_removes_retirement_indexes_and_replays_live_joins(self):
        h = PeTTaChainer()
        h.set_forgetting(1)
        h.add_atoms_no_check([
            '(: old (Implication (A $t) (B $t)) (STV 0.9 1))',
            '(: live (Implication (C $t) (B $t)) (STV 0.2 1))',
            '(: a (A warm) (STV 1 1))',
            '(: c (C warm) (STV 1 1))',
        ])
        h.query_many_refs(['(: $p (B warm) $tv)'], steps=40)
        h.advance_epoch()
        h.advance_epoch()
        ctx = [h.kb, 'MAIN', 'Nil']
        count = ("aggregate_all(count,sk_search_clause(_, [['B',warm],Ctx],'&sk_join_link',_),N)")
        self.assertGreater(janus.query_once(count, {'Ctx': ctx})['N'], 0)
        h._call('withdraw-named-rules!', ['old'])
        self.assertEqual(janus.query_once(count, {'Ctx': ctx})['N'], 0)
        for budget in (40, 200):
            answer = h.query_many_refs(['(: $p (B warm) $tv)'], steps=budget)[0][0]
            self.assertEqual(answer.tv[1], 0.2)
        self.assertGreater(janus.query_once(count, {'Ctx': ctx})['N'], 0)

    def test_atomic_statement_is_known_too(self):
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: a A (STV 1 1))', '(: b B (STV 0 1))'])
        self.assertEqual(janus.query_once(
            "'sk-known-conclusion?'([A, [Kb, 'MAIN', 'Nil']], Known)",
            {'Kb': h.kb, 'A': 'A'})['Known'], 'true')
        self.assertEqual(janus.query_once(
            "'sk-known-conclusion?'([B, [Kb, 'MAIN', 'Nil']], Known)",
            {'Kb': h.kb, 'B': 'B'})['Known'], 'true')

    def test_known_owner_keeps_child_claimed_by_another_conclusion(self):
        h = PeTTaChainer()
        ctx = [h.kb, 'MAIN', 'Nil']
        owner = [['Closed', 'x'], ctx, 'owner-proof', ['STV', 0.5, 0.1]]
        child = [['LiveChild', 'x'], ctx, 'child-proof', ['STV', 0.5, 0.1]]
        conclusion = [['LiveConclusion', 'x'], ctx, 'conclusion-proof', ['STV', 0.5, 0.1]]
        janus.query_once("'link-digest'(['sk-child-link',O,N],D),'sk-keep-child!'(D,C,_),'sk-add-child!'(O,N,1.0,D,_)",
                         {'O': owner, 'N': child, 'C': conclusion})
        h.add_atom('(: observed (Closed x) (STV 1 1))')
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        self.assertEqual(janus.query_once(
            "aggregate_all(count, '&sk_child'(_,O,N,_), Count)",
            {'O': owner, 'N': child})['Count'], 1)
        # It leaves when its actual conclusion closes, rather than its owner.
        h.add_atom('(: result (LiveConclusion x) (STV 0 1))')
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        # Its unexpanded premise is still shared search work. Keep the
        # traversal until that work finishes, even after the join closes.
        self.assertEqual(janus.query_once(
            "aggregate_all(count, '&sk_child'(_,O,N,_), Count)",
            {'O': owner, 'N': child})['Count'], 1)
        janus.query_once("'sk-work!'(H,N,-1,_)", {'H': janus.query_once(
            "'sk-node-hash'(N,H)", {'N': child})['H'], 'N': child})
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        self.assertEqual(janus.query_once(
            "aggregate_all(count, '&sk_child'(_,O,N,_), Count)",
            {'O': owner, 'N': child})['Count'], 0)

    def test_pending_child_retirement_follows_component_merge(self):
        h = PeTTaChainer()
        ctx = [h.kb, 'MAIN', 'Nil']
        owner = [['Closed', 'x'], ctx, 'owner', ['STV', 0.5, 0.1]]
        child = [['Child', 'x'], ctx, 'child', ['STV', 0.5, 0.1]]
        peer = [['Peer', 'x'], ctx, 'peer', ['STV', 0.5, 0.1]]
        extra = [['Extra', 'x'], ctx, 'extra', ['STV', 0.5, 0.1]]
        janus.query_once("'link-digest'(['sk-child-link',O,N],D),'sk-keep-child!'(D,O,_),'sk-add-child!'(O,N,1.0,D,_)",
                         {'O': owner, 'N': child})
        h.add_atom('(: observed (Closed x) (STV 1 1))')
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        janus.query_once("'sk-node-hash'(N,NH),'sk-node-hash'(P,PH),'sk-node-hash'(E,EH),"
                         "'sk-link-pending!'(PH,P,EH,E,_),'sk-link-pending!'(EH,E,PH,P,_),"
                         "'sk-link-pending!'(NH,N,PH,P,_),'sk-link-pending!'(PH,P,NH,N,_),"
                         "'sk-work!'(NH,N,-1,_),'sk-work!'(PH,P,-1,_),'sk-work!'(EH,E,-1,_)",
                         {'N': child, 'P': peer, 'E': extra})
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        self.assertEqual(janus.query_once(
            "aggregate_all(count, '&sk_child'(_,O,N,_), Count)",
            {'O': owner, 'N': child})['Count'], 0)
        self.assertEqual(janus.query_once(
            "aggregate_all(count, sk_child_debt(_,D), Count)",
            {'D': janus.query_once("'link-digest'(['sk-child-link',O,N],D)",
                                  {'O': owner, 'N': child})['D']})['Count'], 0)

    def test_closed_outcome_keeps_shared_premise_search_until_it_finishes(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: (no_inverse r) (Implication P0 Closed) (CTV (STV 1 0.9) (STV 0 0.9)))',
            '(: observed P20 (STV 1 1))',
        ] + [f'(: (no_inverse r{i}) (Implication P{i+1} P{i}) (CTV (STV 1 0.9) (STV 0 0.9)))'
             for i in range(20)])
        h.query_many_refs(['(: $p Closed $tv)'], steps=4)
        self.assertGreater(janus.query_once(
            "aggregate_all(count, '&sk_wait'(_,_,['sk-partial',_,_,[Closed,[Kb,'MAIN','Nil']|_]|_]), N)",
            {'Kb': h.kb, 'Closed': 'Closed'})['N'], 0)
        h.add_atom('(: closed Closed (STV 1 1))')
        # This query can still complete the earlier shared premise search.
        # Its answer is known, but P0's pending work is not obsolete.
        h.query_many_refs(['(: $p Closed $tv)'], steps=80)
        self.assertGreater(janus.query_once(
            "aggregate_all(count, '&sk_expanded'(_, [P0,[Kb,'MAIN','Nil']|_]), N)",
            {'Kb': h.kb, 'P0': 'P0'})['N'], 0)
        # Evaluation has its own allowance, even after search finishes.
        answers = h.query_many_refs(['(: $p P0 $tv)'], steps=40)[0]
        self.assertTrue(answers)
        self.assertGreater(answers[0].tv[1], 0.9)

    def test_retired_waiters_keep_one_late_fact_subscription_until_expansion(self):
        h = PeTTaChainer()
        h.add_atom('(: (no_inverse r) (Implication Missing (Watched x)) (CTV (STV 1 0.9) (STV 0 0.9)))')
        ctx = [h.kb, 'MAIN', 'Nil']
        owner = [['Closed', 'x'], ctx, 'owner', ['STV', 0.5, 0.1]]
        janus.query_once(
            "'sk-known-conclusion?'(O,_),'sk-node-hash'([['Watched',x],Ctx,_,_],H),"
            "_N=[['Watched',x],Ctx,_,_],copy_term_nat(_N,_Child),'link-digest'(['sk-child-link',O,_Child],D),"
            "forall(between(1,5,_),'sk-store-wait!'(D,H,_N,['sk-partial',O,1,O,[],[_N],[]],_)),"
            "'sk-add-child!'(O,_Child,1.0,D,_)",
            {'Ctx': ctx, 'O': owner})
        h.add_atom('(: closed (Closed x) (STV 1 1))')
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        count_watch = "aggregate_all(count, '&sk_fact_watch'(_,_,[['Watched',x],Ctx|_]), N)"
        self.assertEqual(janus.query_once(count_watch, {'Ctx': ctx})['N'], 1)
        h.add_atom('(: observed (Watched x) (STV 1 1))')
        h.query_many_refs(['(: $p Unrelated $tv)'], steps=0)
        self.assertGreater(janus.query_once(
            "aggregate_all(count, '&sk_answer'(_, [['Watched',x],Ctx|_],_), N)",
            {'Ctx': ctx})['N'], 0)
        h.query_many_refs(['(: $p (Watched x) $tv)'], steps=10)
        self.assertEqual(janus.query_once(count_watch, {'Ctx': ctx})['N'], 0)

    def test_query_adapter_reading_a_known_statement_stays_live(self):
        h = PeTTaChainer()
        h.add_atom('(: a A (STV 1 1))')
        self.assertEqual(janus.query_once(
            "'sk-known-conclusion?'([A,[Kb,'MAIN','Nil'],[_,token],_],Known)",
            {'Kb': h.kb, 'A': 'A'})['Known'], 'false')
