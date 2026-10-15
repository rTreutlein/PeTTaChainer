"""Immutable input keys close subscriptions without changing retained samples."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestFunctionalPredicates(unittest.TestCase):
    def test_conflicts_reject_before_publishing_and_keep_existing_value(self):
        h = PeTTaChainer()
        h.set_functional_predicate('At', 3, (1, 3))
        h.set_functional_predicate('At', 3, (1, 3))
        h.add_atom('(: first (At ball left t1) (STV 1 1))')
        h.add_atom('(: same (At ball left t1) (STV 1 1))')
        for fact in ('(At ball right t1) (STV 1 1)',
                     '(At ball left t2) (STV 0.9 1)',
                     '(At ball left t2) (STV 0 1)',
                     '(At ball left $t) (STV 1 1)',
                     '(At ball left t2 extra) (STV 1 1)'):
            with self.subTest(fact=fact), self.assertRaises(janus.PrologError):
                h.add_atoms_no_check([f'(: rejected {fact})'])
        self.assertEqual(janus.query_once(
            "aggregate_all(count,'&kb'(_, [Kb,'MAIN','Nil'], rejected, _),N)",
            {'Kb': h.kb})['N'], 0)
        accepted = '(: accepted (At ball left t3) (STV 1 1))'
        rejected = '(: conflict (At ball right t1) (STV 1 1))'
        with self.assertRaises(janus.PrologError):
            h.add_atoms_no_check([accepted, rejected])
        self.assertIn(accepted, h._added_atoms)
        self.assertNotIn(rejected, h._added_atoms)
        h.add_atom('(: other (At bat right t1) (STV 1 1))')
        h.add_atom('(: later (At ball right t2) (STV 1 1))')
        self.assertEqual(h.query_many_refs(['(: $p (At ball left t1) $tv)'], steps=0)[0][0].tv,
                         ['STV', 1, 1])
        other = PeTTaChainer()
        other.set_functional_predicate('At', 3, (1, 3))
        other.add_atom('(: independent (At ball right t1) (STV 1 1))')

    def test_declaration_order_and_derived_values_are_rejected(self):
        h = PeTTaChainer()
        h.add_atom('(: first (Next a b) (STV 1 1))')
        with self.assertRaises(janus.PrologError):
            h.set_functional_predicate('Next', 2, (1,))
        h = PeTTaChainer()
        h.set_functional_predicate('Next', 2, (1,))
        with self.assertRaises(janus.PrologError):
            h.add_atom('(: r (Implication (Source $x $y) (Next $x $y)) (STV 1 1))')
        self.assertEqual(janus.query_once(
            "aggregate_all(count,rules('runtime-rule-row',_,[['Next'|_],[Kb,'MAIN','Nil']|_],_),N)",
            {'Kb': h.kb})['N'], 0)
        self.assertEqual(janus.query_once(
            "aggregate_all(count,'&kb'(_, [Kb,'MAIN','Nil'],r,_),N)", {'Kb': h.kb})['N'], 0)
        with self.assertRaises(janus.PrologError):
            h.add_atom('(: compound (And (Next c d) (Next c e)) (STV 1 1))')
        self.assertEqual(janus.query_once(
            "aggregate_all(count,'&kb'(_, [Kb,'MAIN','Nil'],compound,_),N)", {'Kb': h.kb})['N'], 0)
        for positions in ((), (0,), (3,), (1, 1), (2, 1), (1, 2)):
            with self.subTest(positions=positions), self.assertRaises(ValueError):
                h.set_functional_predicate('Bad', 2, positions)

    def test_late_value_delivers_before_retiring_matching_and_conflicting_waiters(self):
        h = PeTTaChainer()
        h.set_functional_predicate('At', 2, (2,))
        h.add_atoms_no_check([
            '(: seed (Start t1) (STV 1 1))',
            '(: old (At left t0) (STV 1 1))',
            '(: other (At right t2) (STV 1 1))',
            '(: left (Implication (And (Start $t) (At left $t)) (SeenLeft $t)) (STV 1 0.9))',
            '(: right (Implication (And (Start $t) (At right $t)) (SeenRight $t)) (STV 1 0.9))',
        ])
        h.query_many_refs(['(: $p (SeenLeft $t) $tv)', '(: $p (SeenRight $t) $tv)'], steps=60)
        before = janus.query_once(
            "aggregate_all(count,(sk_wait_payload(_,[[At,_Value,_T],[Kb,'MAIN','Nil']|_],_,_),_T==t1),N)",
            {'Kb': h.kb, 'At': 'At'})['N']
        self.assertGreater(before, 0)
        h.add_atom('(: observed (At right t1) (STV 1 1))')
        left, right = h.query_many_refs(['(: $p (SeenLeft t1) $tv)', '(: $p (SeenRight t1) $tv)'], steps=80)
        self.assertFalse(left)
        self.assertTrue(right)
        self.assertEqual(right[0].tv[1], 1)
        self.assertEqual(janus.query_once(
            "aggregate_all(count,(sk_wait_payload(_,[[At,_Value,_T],[Kb,'MAIN','Nil']|_],_,_),_T==t1),N)",
            {'Kb': h.kb, 'At': 'At'})['N'], 0)
        self.assertEqual(janus.query_once(
            "aggregate_all(count,(sk_search_clause(_,_,_,_R),clause_property(_R,erased)),N)")['N'], 0)

    def test_open_value_waiter_closes_only_after_reading_the_unique_answer(self):
        h = PeTTaChainer()
        h.set_functional_predicate('Next', 2, (1,))
        h.add_atom('(: r (Implication (Next $p $t) (Linked $p $t)) (STV 1 0.9))')
        h.query_many_refs(['(: $p (Linked a $t) $tv)'], steps=40)
        h.add_atom('(: n (Next a b) (STV 1 1))')
        answers = h.query_many_refs(['(: $p (Linked a $t) $tv)'], steps=40)[0]
        self.assertEqual([a.statement for a in answers], [['Linked', 'a', 'b']])
        self.assertEqual(janus.query_once(
            "aggregate_all(count,(sk_wait_payload(_,[[Next,_P,_],[Kb,'MAIN','Nil']|_],_,_),_P==a),N)",
            {'Kb': h.kb, 'Next': 'Next'})['N'], 0)
        # A new reader created after assignment must still expand/read it.
        self.assertTrue(h.query_many_refs(['(: $p (Linked a b) $tv)'], steps=40)[0])

    def test_assignment_retirement_is_sliced_and_leaves_other_keys_live(self):
        h = PeTTaChainer()
        h.set_functional_predicate('At', 2, (2,))
        ctx = [h.kb, 'MAIN', 'Nil']
        janus.query_once(
            "_O=[outcome,Ctx,_,_],_P=[['At',_,_],Ctx,_,_],"
            "assertz(rules('runtime-rule-row',9999004,_O,[_P])),"
            "forall(between(1,600,_I),(_N=[['At',_I,t1],Ctx,_,_],"
            "'sk-node-hash'(_N,_H),'sk-store-wait!'(777,_H,_N,"
            "['sk-partial',_O,9999004,_O,[],[_N],[]],_))),"
            "forall(between(1,10,_I),(_N=[['At',_I,t2],Ctx,_,_],"
            "'sk-node-hash'(_N,_H),'sk-store-wait!'(778,_H,_N,"
            "['sk-partial',_O,9999004,_O,[],[_N],[]],_)))", {'Ctx': ctx})
        h.add_atom('(: value (At unique t1) (STV 1 1))')
        query = ("aggregate_all(count,sk_wait_payload(_,[[At,_,t1],Ctx|_],_,_),Closed),"
                 "aggregate_all(count,sk_wait_payload(_,[[At,_,t2],Ctx|_],_,_),Open)")
        first = janus.query_once("'sk-retire-searches!'(_)," + query, {'Ctx': ctx, 'At': 'At'})
        self.assertGreater(first['Closed'], 0)
        self.assertLess(first['Closed'], 600)
        self.assertEqual(first['Open'], 10)
        second = janus.query_once("'sk-retire-searches!'(_)," + query, {'Ctx': ctx, 'At': 'At'})
        self.assertEqual((second['Closed'], second['Open']), (0, 10))
