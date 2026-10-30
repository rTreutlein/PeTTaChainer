"""The event model is source metadata, independent of execution layout."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class SourceCatalogTests(unittest.TestCase):
    def test_model_and_cohorts_survive_missing_rows_and_reordered_instructions(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a (A a) (STV 0.4 0.9))',
            '(: b (B a) (STV 0.3 0.9))',
            '(: r (Implication (And (A $x) (B $x)) (C $x)) (CTV (STV 0.9 0.9) (STV 0.1 0.9)))',
            '(: c (C a) (STV 0.8 0.9))',
        ])
        result = janus.query_once(
            "_Scope=[Kb,'MAIN','Nil'], _Key=['sk-key',['A',a],_Scope], "
            "graph_plan(_Key,_Before), _Before=graph(_,_,_), "
            "'source-catalog-priors'(['A',a],_Scope,_Priors), _Priors=[_|_], "
            "source_catalog_stamp(Kb,_Generation), "
            "findall(row(_Id,_C,_Ps),(rules('runtime-rule-row',_Id,_C,_Ps),_C=[_,[Kb|_],_,_]),_Rows), "
            "findall(idx(_C,_Id,_Ps),(ccls_index(_C,_Id,_Ps),_C=[_,[Kb|_],_,_]),_Indexes), "
            "setup_call_cleanup(true, "
            " (forall(member(row(_Id,_C,_Ps),_Rows), "
            "   (retractall(rules('runtime-rule-row',_Id,_,_)), "
            "    partition([_P]>>(_P=[_H|_],_H=='CPU'),_Ps,_CPU,_Facts), "
            "    reverse(_CPU,_Reordered),append(_Facts,_Reordered,_New), "
            "    assertz(rules('runtime-rule-row',_Id,_C,_New)))), "
            "  event_graph_reset,graph_plan(_Key,_ReorderedModel),_ReorderedModel==_Before, "
            "  forall(member(row(_Id,_,_),_Rows),retractall(rules('runtime-rule-row',_Id,_,_))), "
            "  retractall(ccls_index([_,[Kb|_],_,_],_,_)), "
            "  retractall('&sk_row'(_,['sk-key',_,[Kb|_]],_,_)), "
            "  event_graph_reset,graph_plan(_Key,_WithoutRows),_WithoutRows==_Before, "
            "  'source-catalog-priors'(['A',a],_Scope,_StillPriors),_StillPriors=@=_Priors, "
            "  source_catalog_stamp(Kb,_Generation)), "
            " (forall(member(row(_Id,_C,_Ps),_Rows), "
            "    (retractall(rules('runtime-rule-row',_Id,_,_)),assertz(rules('runtime-rule-row',_Id,_C,_Ps)))), "
            "  forall(member(idx(_C,_Id,_Ps),_Indexes),assertz(ccls_index(_C,_Id,_Ps))),event_graph_reset))",
            {'Kb': h.kb})
        self.assertTrue(result['truth'])

    def test_raw_products_normalize_to_the_same_model(self):
        for antecedent in ('(A $x)', '(And (A $x) (B $x))', '(Or (A $x) (Not (B $x)))'):
            with self.subTest(antecedent=antecedent):
                h = PeTTaChainer()
                result = janus.query_once(
                    "sread(Source,_Source), "
                    "findall(_Plan,'mm2compile'(Kb,_Source,_Plan),_Plans), "
                    "forall(member(_Plan,_Plans),'add-to-kb'(_Plan,_)), "
                    "_Scope=[Kb,'MAIN','Nil'],source_catalog_template(['C',a],_Scope,_Compiled), "
                    "_Compiled=conditional(_Parent,_,_Pos,_Neg), "
                    "findall(_Id,source_catalog_application(_Id,_,_,[_,[Kb|_]],_,_,_),_Ids), "
                    "forall(member(_Id,_Ids),'source-catalog-remove!'(_Id,true)), "
                    "forall(member(_Plan,_Plans),('source-plan-addition'(_Plan,_Raw),'add-to-kb'(_Raw,_))), "
                    "source_catalog_template(['C',a],_Scope,conditional(_RawParent,_,_Pos,_Neg)), "
                    "node_formula(_Parent,_Formula,[],_Atoms),node_formula(_RawParent,_Formula,[],_Atoms)",
                    {'Kb': h.kb, 'Source': f'(: r (Implication {antecedent} (C $x)) (CTV (STV 0.9 1) (STV 0.1 1)))'})
                self.assertTrue(result['truth'])

    def test_with_prior_is_rejected_without_looking_at_inverse_rows(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a (A a) (STV 0.4 0.9))',
            '(: p (P a) (STV 0.3 0.9))',
            '(: r (WithPrior (P $x) (Implication (A $x) (C $x))) (CTV (STV 0.9 1) (STV 0.1 1)))',
            '(: c (C a) (STV 0.8 0.9))',
        ])
        result = janus.query_once(
            "retractall(rules('runtime-rule-row',_,[_,[Kb|_],_,_],_)), "
            "retractall(ccls_index([_,[Kb|_],_,_],_,_)),event_graph_reset, "
            "graph_plan(['sk-key',['A',a],[Kb,'MAIN','Nil']],none)", {'Kb': h.kb})
        self.assertTrue(result['truth'])

    def test_catalog_cohorts_preserve_existing_prior_order_and_variable_sharing(self):
        for rule in (
            '(: r (Implication (A $x) (C $x)) (STV 0.9 0.8))',
            '(: r (Implication (And (A $x) (B $x)) (C $x)) (CTV (STV 0.9 0.8) (STV 0.1 0.8)))',
            '(: r (Implication (A fixed $x) (C fixed $x)) (STV 0.9 0.8))',
            '(: r (ForAll $group (Implication (A $group $x) (C $group $x))) (STV 0.9 0.8))',
            '(: r (WithPrior (P $x) (Implication (A $x) (C $x))) (CTV (STV 0.9 0.8) (STV 0.1 0.8)))',
        ):
            with self.subTest(rule=rule):
                h = PeTTaChainer()
                h.add_atom(rule)
                result = janus.query_once(
                    "forall(member(_Type, [['A',a],['B',a],['C',a],['A',g,a],['C',g,a],['A',_],['C',_,_]]), "
                    " (findall(_Match,'sk-rule-match'([_Type,[Kb,'MAIN','Nil'],_,_],_Match),_Matches), "
                    "  'sk-prior-folds'(_Type,_Matches,_Old), "
                    "  'source-catalog-priors'(_Type,[Kb,'MAIN','Nil'],_New), _New=@=_Old))",
                    {'Kb': h.kb})
                self.assertTrue(result['truth'])

    def test_instance_prior_admission_does_not_require_inverse_applications(self):
        h = PeTTaChainer()
        result = janus.query_once(
            "sread(Source,_Source), "
            "forall(('mm2compile'(Kb,_Source,_Plan), "
            "        _Plan=['source-plan',_,_Role,_,_,_], "
            "        \\+ (_Role=['reverse-source'|_])), 'add-to-kb'(_Plan,_)), "
            "_Scope=[Kb,'MAIN','Nil'], "
            "\\+ source_catalog_template(['C',a],_Scope,_), "
            "source_catalog_application(_,_,_,[['C',_],_],['forward-source'|_],_,_)",
            {'Kb': h.kb, 'Source': '(: r (WithPrior (P $x) (Implication (A $x) (C $x))) '
                                 '(CTV (STV 0.9 1) (STV 0.1 1)))'})
        self.assertTrue(result['truth'])

    def test_overlapping_outputs_keep_installation_order_across_prefix_buckets(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: r (Implication (A $x) (C $x)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            '(: r (Implication (B a) (C a)) (CTV (STV 0.8 1) (STV 0.2 1)))',
        ])
        result = janus.query_once(
            "source_catalog_template(['C',a],[Kb,'MAIN','Nil'],conditional(['A',a],_,_,_))",
            {'Kb': h.kb})
        self.assertTrue(result['truth'])

    def test_withdrawal_and_temporary_cleanup_release_catalog_owners(self):
        h = PeTTaChainer()
        h.add_atom('(: r (Implication (A $x) (C $x)) (CTV (STV 0.9 1) (STV 0.1 1)))')
        h.query('(: $p (Assuming ((: assumption (A a) (STV 1 1))) (C a)) $tv)', steps=100)
        result = janus.query_once(
            "\\+ source_catalog_application(_,_,temp,_,_,_,_), "
            "\\+ source_catalog_fact(_,_,temp,_), "
            "'withdraw-named-rules!'(r,_), "
            "source_catalog_template(['C',a],[Kb,'MAIN','Nil'],root), "
            "\\+ (source_catalog_descriptor(_,_,_Owner),\\+ source_catalog_refs(_Owner,_))",
            {'Kb': h.kb})
        self.assertTrue(result['truth'])
