"""Known outcomes retire search work without retiring their history or samples."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestSearchRetirement(unittest.TestCase):
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
        janus.query_once("'sk-keep-child!'(O,N,C,_), 'sk-add-child!'(O,N,1.0,_)",
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
        janus.query_once("'sk-keep-child!'(O,N,O,_), 'sk-add-child!'(O,N,1.0,_)",
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
            "forall(between(1,5,_),assertz('&sk_wait'(H,[['Watched',x],Ctx,_,_],"
            "['sk-partial',O,1,O,[],[[['Watched',x],Ctx,_,_]],[]]))),"
            "'sk-add-child!'(O,[['Watched',x],Ctx,_,_],1.0,_)",
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
