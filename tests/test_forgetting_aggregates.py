"""Idle aggregate caches are evicted and replay current observations on demand."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestForgettingAggregates(unittest.TestCase):
    def setUp(self):
        self.control = PeTTaChainer()
        self.control.set_forgetting(1, 0.5)
        self.addCleanup(self.control.set_forgetting, 0, 1.0)

    def check_incremental(self, rules, first, later, goal):
        old = PeTTaChainer()
        old.add_atoms_no_check(rules + first)
        before = self.values(old, goal)
        self.assertTrue(before)
        old.advance_epoch()
        old.advance_epoch()
        old.add_atoms_no_check(later)
        actual = self.values(old, goal)
        # The oracle has all observations before its first query, and has
        # never crossed an epoch boundary. Compare values, not proof wrappers.
        fresh = PeTTaChainer()
        fresh.add_atoms_no_check(rules + first + later)
        expected = self.values(fresh, goal)
        self.assertNotEqual(before, expected)
        self.assertEqual(actual, expected)
        for _ in range(3):
            old.advance_epoch()
        self.assertEqual(self.values(old, goal), expected)

    @staticmethod
    def values(h, goal):
        def value(term):
            if isinstance(term, list):
                # Particle stores allocate opaque ids; compare their contents.
                if term and term[0] == 'ParticleDist':
                    return janus.query_once("'ParticlePairs'(D,Pairs)", {'D': term})['Pairs']
                return [value(part) for part in term]
            return term
        return [(value(a.statement), a.tv) for a in h.query_many_refs([goal], steps=200)[0]]

    def test_foldall_reader_matches_fresh_kb(self):
        self.check_incremental([
            '(: (no_inverse sum) (Implication '
            '(FoldAll (Score $x $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total) '
            '(LiveSum)) (CTV (STV $total 1) (STV $total 1)))',
        ], ['(: first (Score a 0.2) (STV 1 1))'],
            ['(: later (Score b 0.6) (STV 1 1))'], '(: $p (LiveSum) $tv)')

    def test_foldall_truth_reader_matches_fresh_kb(self):
        self.check_incremental([
            '(: (no_inverse sum) (Implication '
            '(FoldAllTruth (Belief $x) (STV $s $_c) $s 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total) '
            '(LiveSum)) (CTV (STV $total 1) (STV $total 1)))',
        ], ['(: first (Belief a) (STV 0.2 1))'],
            ['(: later (Belief b) (STV 0.6 1))'], '(: $p (LiveSum) $tv)')

    def test_foldall_value_reader_matches_fresh_kb(self):
        self.check_incremental([
            '(: (no_inverse distribution) (Implication '
            '(FoldAllValue (Belief $x) (ParticleFromPairs ((0 1.0))) '
            'ParticleAddBernoulliFromSTV -> $dist) (LiveDistribution $dist)) '
            '(CTV (STV 1 1) (STV 0 1)))',
        ], ['(: first (Belief a) (STV 0.2 1))'],
            ['(: later (Belief b) (STV 0.6 1))'], '(: $p (LiveDistribution $dist) $tv)')

    def test_aggregate_index_follows_row_retirement(self):
        h = PeTTaChainer()
        h.set_forgetting(0)
        h.add_atoms_no_check([
            '(: sum (Implication '
            '(FoldAll (Score $x $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total) '
            '(LiveSum)) (CTV (STV $total 1) (STV $total 1)))',
            '(: first (Score a 0.2) (STV 1 1))',
        ])
        goal = '(: $p (LiveSum) $tv)'
        self.values(h, goal)
        count = "aggregate_all(count,'&sk_aggregate_row'(_,['sk-key',['LiveSum'],[Kb,'MAIN','Nil']],_),N)"
        self.assertEqual(janus.query_once(count, {'Kb': h.kb})['N'], 1)
        # Rows built while forgetting is disabled are still registered.
        h.set_forgetting(1, 0.5)
        self.values(h, goal)
        h.advance_epoch()
        h.advance_epoch()
        self.assertEqual(janus.query_once(count, {'Kb': h.kb})['N'], 0)
        h.add_atom('(: later (Score b 0.6) (STV 1 1))')
        self.assertEqual(self.values(h, goal)[0][1][1], 0.8)
        h._call('withdraw-named-rules!', ['sum'])
        self.assertFalse(self.values(h, goal))
        self.assertEqual(janus.query_once(count, {'Kb': h.kb})['N'], 0)

    def test_base_rate_reader_matches_fresh_kb(self):
        self.check_incremental([
            '(: rule (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9)))',
        ], ['(: qa (Q alice) (STV 0.9 0.8))', '(: pb (P bob) (STV 0.7 0.8))'],
            ['(: pc (P carol) (STV 0.3 0.8))'], '(: $p (P alice) $tv)')

    def test_base_rate_idle_cycles_do_not_retain_search_history(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: sensor (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9)))',
            '(: qa (Q alice) (STV 0.9 0.8))', '(: pb (P bob) (STV 0.7 0.8))',
        ])
        counts = []
        for n in range(100):
            h.add_atom(f'(: p{n} (P i{n}) (STV 0.3 0.8))')
            self.assertTrue(self.values(h, '(: $p (P alice) $tv)'))
            h.advance_epoch()
            h.advance_epoch()
            for name, arity in [('&sk_row', 4), ('&sk_summary', 5), ('&sk_aggregate_row', 3)]:
                head = f"'{name}'(_,['sk-key',_,[Kb,'MAIN','Nil']]," + ','.join(['_'] * (arity - 2)) + ')'
                self.assertEqual(janus.query_once(f'aggregate_all(count,{head},N)', {'Kb': h.kb})['N'], 0)
            counts.append(janus.query_once("aggregate_all(count,sk_wait_payload(_,_,_,_),N)")['N'])
        # Replaying a root reuses its subscription, rather than adding one
        # waiter per query. Other KBs are quiescent throughout this loop.
        self.assertEqual(counts[10:], [counts[10]] * 90)

    def test_exact_fold_idle_cycles_leave_no_views(self):
        h = PeTTaChainer()
        h.add_atom('(: (no_inverse count) (Implication '
                   '(FoldAll (Measurement $x) 1 0 (|-> ($acc $elem) (+ $acc $elem)) -> $n) '
                   '(LiveCount $n)) (CTV (STV 1 1) (STV 0 1)))')
        for n in range(100):
            h.add_atom(f'(: m{n} (Measurement i{n}) (STV 1 1))')
            self.assertEqual(self.values(h, '(: $p (LiveCount $n) $tv)')[0][0], ['LiveCount', n + 1])
            h.advance_epoch()
            h.advance_epoch()
            self.assertEqual(janus.query_once(
                "aggregate_all(count,'&sk_frozen'(_,['sk-key',_,[Kb,'MAIN','Nil']]),N)",
                {'Kb': h.kb})['N'], n + 1)
            for name, arity in [('&sk_latest', 3), ('&sk_view', 4)]:
                for key in ["['sk-key',_,[Kb,'MAIN','Nil']]", "['sk-fold',[Kb|_]]"]:
                    head = f"'{name}'(_,{key}," + ','.join(['_'] * (arity - 2)) + ')'
                    self.assertEqual(janus.query_once(f'aggregate_all(count,{head},N)', {'Kb': h.kb})['N'], 0)

    def test_evidence_join_interns_only_the_final_union(self):
        result = janus.query_once(
            "findall(_S,(between(1,100,_I),'evidence-set'([[join_probe,_I]],_S)),Sets),"
            "aggregate_all(count,ev_set(_,_,_,_,_),Before),"
            "'evidence-join'(Sets,Joined),'evidence-entries'(Joined,Entries),"
            "aggregate_all(count,ev_set(_,_,_,_,_),After),Delta is After-Before")
        self.assertEqual(result['Entries'], [['join_probe', i] for i in range(1, 101)])
        self.assertEqual(result['Delta'], 1)
