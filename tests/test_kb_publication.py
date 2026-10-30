"""Exposed copies keep indexes, roles and withdrawal provenance in one lifetime."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestKbPublication(unittest.TestCase):
    def assert_publication_consistent(self, h):
        # Check both directions: a cold indexed read must see exactly the
        # exposed facts, and neither indexes nor catalog may retain dead copies.
        result = janus.query_once(
            "_Ctx=[Kb,'MAIN','Nil'], "
            "forall('&kb'(_T,_Ctx,_P,_V), "
            " ('kb-facts'(_T,_Ctx,_Rows),member([_T,_Ctx,_P,_V],_Rows), "
            "  source_catalog_fact(_,[_T,_Ctx,_P,_V],_,_))), "
            "forall(('&kb_prefix'(_,_T,_Ctx,_P,_V);'&kb_open'(_,_T,_Ctx,_P,_V); "
            "        source_catalog_fact(_,[_T,_Ctx,_P,_V],_,_)), '&kb'(_T,_Ctx,_P,_V))",
            {'Kb': h.kb})
        self.assertTrue(result['truth'])

    def test_materialize_forward_withdraw_and_cold_read(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: seed (A a) (STV 1 1))',
            '(: bridge (Implication (A $x) (B $x)) (CTV (STV 0.8 1) (STV 0 1)))',
            '(: tail (Implication (B $x) (C $x)) (CTV (STV 0.7 1) (STV 0 1)))',
        ])
        self.assertTrue(h.query_many_materialization(['(: $p (B a) $tv)'], steps=40)[0])
        self.assertTrue(h.forward_chain(h.select_facts(['(A a)']), steps=40))
        roles = janus.query_once(
            "source_catalog_fact(_,[['A',a],[Kb,'MAIN','Nil'],seed,_],live,observation), "
            "source_catalog_fact(_,[['B',a],[Kb,'MAIN','Nil'],_,_],live,materialized), "
            "source_catalog_fact(_,[['C',a],[Kb,'MAIN','Nil'],_,_],live,prediction)", {'Kb': h.kb})
        self.assertTrue(roles['truth'])
        self.assert_publication_consistent(h)
        h._call('withdraw-named-rules!', ['bridge'])
        self.assert_publication_consistent(h)
        self.assertTrue(janus.query_once(
            "\\+ '&kb'(['B',a],[Kb,'MAIN','Nil'],_,_), "
            "\\+ '&kb'(['C',a],[Kb,'MAIN','Nil'],_,_), "
            "\\+ stored_rules(_,_,['sk-key',['B',a],[Kb,'MAIN','Nil']],_,_), "
            "\\+ stored_rules(_,_,['sk-key',['C',a],[Kb,'MAIN','Nil']],_,_)", {'Kb': h.kb})['truth'])
        for budget in (0, 40):
            rows = h.query_many_refs(['(: $p (B a) $tv)', '(: $p (C a) $tv)'], steps=budget)
            # The surviving tail can supply B's population prior. That is
            # an estimate of its population, never the retired instance proof.
            for answer in rows[0]:
                self.assertEqual(answer.proof[0], 'population-prior')
            self.assertEqual(rows[1], [])
        self.assertEqual(len(h.select_facts(['(A a)'])), 1)

    def test_summary_removal_thaws_and_rebuilds_live_contributors(self):
        h = PeTTaChainer()
        h.set_forgetting(1, 0.5)
        self.addCleanup(h.set_forgetting, 0, 1.0)
        h.add_atoms_no_check([
            '(: old (Implication (A $x) (B $x)) (CTV (STV 0.9 1) (STV 0 1)))',
            '(: live (Implication (C $x) (B $x)) (CTV (STV 0.2 1) (STV 0 1)))',
            '(: a (A warm) (STV 1 1))',
            '(: c (C warm) (STV 1 1))',
        ])
        self.assertTrue(h.query_many_refs(['(: $p (B warm) $tv)'], steps=40)[0])
        h.advance_epoch()
        h.advance_epoch()
        self.assertTrue(janus.query_once(
            "source_catalog_fact(_,[['B',warm],[Kb,'MAIN','Nil'],[forgotten|_],_],live,summary)",
            {'Kb': h.kb})['truth'])
        self.assert_publication_consistent(h)
        h._call('withdraw-named-rules!', ['old'])
        self.assertTrue(janus.query_once(
            "\\+ source_catalog_fact(_,[['B',warm],[Kb,'MAIN','Nil'],_,_],_,summary), "
            "\\+ '&sk_summary'(_,['sk-key',['B',warm],[Kb,'MAIN','Nil']],_,_,_), "
            "'&sk_thawed'(_,['sk-key',['B',warm],[Kb,'MAIN','Nil']])", {'Kb': h.kb})['truth'])
        self.assert_publication_consistent(h)
        answers = h.query_many_refs(['(: $p (B warm) $tv)'], steps=40)[0]
        self.assertEqual(len(answers), 1)
        self.assertEqual(answers[0].tv[1], 0.2)
        self.assertNotIn('old', h.expand_proof(answers[0].proof))

    def test_temporary_publications_leave_no_facts_indexes_or_catalog(self):
        h = PeTTaChainer()
        h.add_atom('(: rule (Implication (A $x) (B $x)) (CTV (STV 0.8 1) (STV 0 1)))')
        self.assertTrue(h.query_many_refs([
            '(: $p (Assuming (: assumed (A a) (STV 1 1)) (B a)) $tv)'], steps=40)[0])
        self.assertTrue(janus.query_once(
            "\\+ '&temp_query_ref'(clause_ref,_), \\+ source_catalog_fact(_,_,temp,_), "
            "\\+ (('&kb'(_, [Kb,_Ctx,_],_,_); '&kb_prefix'(_,_,[Kb,_Ctx,_],_,_); "
            "      '&kb_open'(_,_,[Kb,_Ctx,_],_,_)),_Ctx\\=='MAIN')", {'Kb': h.kb})['truth'])
        self.assert_publication_consistent(h)
        self.assertEqual(h.query_many_refs(['(: $p (B a) $tv)'], steps=0), [[]])
