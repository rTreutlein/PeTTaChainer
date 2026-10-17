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


if __name__ == '__main__':
    unittest.main()
