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

    def test_retiring_one_cycle_node_preserves_remaining_work(self):
        h = PeTTaChainer()
        ctx = [h.kb, 'MAIN', 'Nil']
        p = [['P', 'x'], ctx, 'proof-p', 'tv-p']
        q = [['Q', 'x'], ctx, 'proof-q', 'tv-q']
        # The first node is the representative of a two-node cycle. Retiring it
        # must keep the remaining node's route to its component, and its work.
        janus.query_once("'sk-link-pending!'(101, P, 102, Q, _), 'sk-link-pending!'(102, Q, 101, P, _)", {'P': p, 'Q': q})
        janus.query_once("'sk-drop-pending!'(101, P, _)", {'P': p})
        self.assertEqual(janus.query_once("'sk-pending?'(102, Q, Pending)", {'Q': q})['Pending'], 'true')
        janus.query_once("'sk-work!'(102, Q, -1, _)", {'Q': q})
        self.assertEqual(janus.query_once("'sk-pending?'(102, Q, Pending)", {'Q': q})['Pending'], 'false')
        janus.query_once("'sk-drop-pending!'(102, Q, _)", {'Q': q})
        self.assertEqual(janus.query_once(
            "aggregate_all(count, pw_id(_, [_, [Kb, 'MAIN', 'Nil']|_], _), N)", {'Kb': h.kb})['N'], 0)
