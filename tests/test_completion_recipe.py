"""Completion roles are rule metadata; instances reuse their executable inputs."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class CompletionRecipeTests(unittest.TestCase):
    def test_coincident_sibling_and_consequence_use_observation_policy(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: r (Implication (And (A $x) (C $x)) (C $x)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            '(: cd (Implication (C $x) (D $x)) (CTV (STV 0.8 1) (STV 0.2 1)))',
            '(: d (D i) (STV 1 1))',
        ])
        for statement, rate in (('(A $x)', 0.3), ('(C $x)', 0.4)):
            h._call('set-base-rate', [f'{h.kb} {statement} (STV {rate} 0.9)'])
        answers = h.query_many_refs(['(: $p (A i) $tv)'], steps=2000)[0]
        self.assertEqual(len(answers), 1)
        # Master 80ea5628: both C reads admit the inversion of cd from d.
        # Sibling exclusions instead suppress the completion, returning A's prior.
        self.assertEqual(answers[0].tv, ['STV', 0.5010040747520484, 0.9667304990543287])

    def test_rule_recipe_is_ground_and_inputs_share_refined_truth(self):
        h = PeTTaChainer()
        h._call('set-rule-refinement', [f'{h.kb} true'])
        h.add_atom('(: r (Implication (And (A $x) (B $x)) (C $x)) (STV 0.9 0.8))')
        result = janus.query_once(
            "_Scope=[Kb,'MAIN','Nil'], "
            "rules('runtime-rule-row',_Id,[['B',_X],_Scope,_,_],_Ps), "
            "'&completion_recipe'(_Id,Recipe), ground(Recipe), "
            "Recipe=['completion-recipe',Index,0,Opening], "
            "'rule-contextual-premise'(0,_Ps,['CPU','CompoundEvidence',[_Kb,_Compound,_,_RecipeScope],_]), "
            "exclude([_P]>>(_P=['CPU'|_]),_Ps,[_Truth,_A,_C]), "
            "(_Compound==['And',['A',_X],['B',_X]],_RecipeScope==_Scope, "
            " _A=[['A',_AX],_,_,_],_C=[['C',_CX],_,_,_],_AX==_X,_CX==_X -> Shared=true;Shared=false), "
            "_Truth=[['RuleTruth',_],_TruthScope,_,_], "
            "('&sk_rule_truth'(_Id,_,_,_RegisteredScope),_RegisteredScope==_TruthScope -> Registered=true;Registered=false)",
            {'Kb': h.kb},
        )
        self.assertEqual(result['Shared'], 'true')
        self.assertEqual(result['Registered'], 'true')
        self.assertEqual(result['Index'], 2)
        self.assertEqual(result['Opening'], 'true')

    def test_raw_ingestion_prepares_the_same_recipe_and_answer(self):
        for connective in ('And', 'Or'):
            for negated in (False, True):
                with self.subTest(connective=connective, negated=negated):
                    part = '(Not (B $x))' if negated else '(B $x)'
                    antecedent = f'({connective} (A $x) {part})'
                    source = (f'(: r (Implication {antecedent} (C $x)) '
                              '(CTV (STV 0.9 1) (STV 0.1 1)))')
                    compiled, raw = PeTTaChainer(), PeTTaChainer()
                    for h in (compiled, raw):
                        h.add_atoms_no_check([
                            f'(: a (A i) (STV {1 if connective == "And" else 0} 1))',
                            '(: c (C i) (STV 1 1))',
                        ])
                        h._call('set-base-rate', [f'{h.kb} (B $x) (STV 0.3 0.9)'])
                    compiled.add_atom(source)
                    result = janus.query_once(
                        "(Negated=true -> _Part=['Not',['B',_X]];_Part=['B',_X]), "
                        "_Source=[':',r,['Implication',[Connective,['A',_X],_Part],['C',_X]], "
                        " ['CTV',['STV',0.9,1],['STV',0.1,1]]], "
                        "'mm2compile'(Kb,_Source,_Plan), "
                        "'source-plan-addition'(_Plan,['rules',[_Premises,'|-',_Conclusion]]), "
                        "_Conclusion=[['B',_X],_,_,_], "
                        "_Premises=[['CPU','ReadLikelihoodContext',Recipe,_]|_Executable], "
                        "forall('mm2compile'(Kb,_Source,_Addition),'add-to-kb'(_Addition,_)), "
                        "rules('runtime-rule-row',_Id,_Conclusion,_Stored), "
                        "'&completion_recipe'(_Id,_Prepared), "
                        "(Recipe==_Prepared -> Same=true;Same=false)",
                        {'Kb': raw.kb, 'Connective': connective, 'Negated': 'true' if negated else 'false'},
                    )
                    self.assertEqual(result['Same'], 'true')
                    expected = compiled.query('(: $p (B i) $tv)', steps=200, timeout_sec=None)
                    self.assertTrue(expected)
                    self.assertEqual(raw.query('(: $p (B i) $tv)', steps=200, timeout_sec=None), expected)
                    # Neither retained rows nor proofs contain a recipe copy.
                    prepared = janus.query_once(
                        "'&sk_row'(_,_,_,['sk-row',['sk-ident',_Id,_,_],[['B',i],_,_,_RowTV],_Premises,_]), "
                        "'&completion_recipe'(_Id,['completion-recipe',_Index,_,_]), "
                        "'rule-completion-inputs'(_Id,_Premises,['completion-inputs',_,_,[['C',i],_,_,_],_After,_]), "
                        "last(_After,['CPU',_,_,_Output]), _Output==_RowTV, "
                        "findall(_Recipe,'&completion_recipe'(_Id,_Recipe),[_Only]),ground(_Only), "
                        "'&sk_row'(_,_,_,['sk-row',['sk-ident',_Id,_,_], "
                        " [['B',i],_,['population-prior'|_],_],_Prior,_]), "
                        "'rule-completion-inputs'(_Id,_Prior,'no-completion-inputs'), "
                        "\\+ (sub_term(_Term,_Premises),nonvar(_Term),_Term=[_Head|_],_Head=='completion-recipe')",
                    )
                    self.assertTrue(prepared['truth'])

    def test_instances_share_one_rule_recipe(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: ai (A i) (STV 1 1))', '(: ci (C i) (STV 1 1))',
            '(: aj (A j) (STV 1 1))', '(: cj (C j) (STV 1 1))',
            '(: r (Implication (And (A $x) (B $x)) (C $x)) (CTV (STV 0.9 1) (STV 0.1 1)))',
        ])
        h._call('set-base-rate', [f'{h.kb} (B $x) (STV 0.3 0.9)'])
        for member in ('i', 'j'):
            self.assertTrue(h.query(f'(: $p (B {member}) $tv)', steps=200, timeout_sec=None))
        result = janus.query_once(
            "rules('runtime-rule-row',_Id,[['B',_],[Kb,'MAIN','Nil'],_,_],_), "
            "findall(_Plan,'&completion_recipe'(_Id,_Plan),[_Only]),ground(_Only), "
            "aggregate_all(count,('&sk_row'(_,_,_,['sk-row',['sk-ident',_Id,_,_],_,_Ps,_]), "
            " 'rule-completion-inputs'(_Id,_Ps,['completion-inputs'|_])),Rows)",
            {'Kb': h.kb},
        )
        self.assertGreaterEqual(result['Rows'], 2)


if __name__ == '__main__':
    unittest.main()
