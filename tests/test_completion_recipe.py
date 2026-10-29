"""Completion roles survive compilation, raw ingestion and row preparation."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class CompletionRecipeTests(unittest.TestCase):
    def test_open_recipe_shares_inputs_and_retains_refined_truth_registration(self):
        h = PeTTaChainer()
        h._call('set-rule-refinement', [f'{h.kb} true'])
        h.add_atom('(: r (Implication (And (A $x) (B $x)) (C $x)) (STV 0.9 0.8))')
        result = janus.query_once(
            "_Scope=[Kb,'MAIN','Nil'], "
            "rules('runtime-rule-row',_Id,[['B',_X],_Scope,_,_],_Ps), "
            "_Ps=[['CPU','ReadLikelihoodContext',_Recipe,_]|_], "
            "exclude([_P]>>(_P=['CPU'|_]),_Ps,[_Truth,_A,_C]), "
            "_Recipe=['completion-recipe',_Target,_Compound,_RecipeScope,Index,Opening], "
            "(_Target==['B',_X],_Compound==['And',['A',_X],['B',_X]],_RecipeScope==_Scope, "
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
                        "'mm2compile'(Kb,_Source,['rules',[_Premises,'|-',_Conclusion]]), "
                        "_Conclusion=[['B',_X],_,_,_], "
                        "_Premises=[['CPU','ReadLikelihoodContext',_Recipe,_]|_Executable], "
                        "'add-to-kb'(['rules',[_Executable,'|-',_Conclusion]],_), "
                        "rules('runtime-rule-row',_,_Conclusion,[['CPU','ReadLikelihoodContext',_Prepared,_]|_]), "
                        "(_Recipe =@= _Prepared -> Same=true;Same=false)",
                        {'Kb': raw.kb, 'Connective': connective, 'Negated': 'true' if negated else 'false'},
                    )
                    self.assertEqual(result['Same'], 'true')
                    expected = compiled.query('(: $p (B i) $tv)', steps=200, timeout_sec=None)
                    self.assertTrue(expected)
                    self.assertEqual(raw.query('(: $p (B i) $tv)', steps=200, timeout_sec=None), expected)
                    # Ground CPU operations may be removed from the stored row.
                    # The positional recipe still names its observation correctly.
                    prepared = janus.query_once(
                        "'&sk_row'(_,_,_,['sk-row',_,[['B',i],_,_,_],_Premises,_]), "
                        "_Premises=[['CPU','ReadLikelihoodContext',_Recipe,_]|_], "
                        "_Recipe=['completion-recipe',_,_,_,Index,_], "
                        "exclude([_P]>>(_P=['CPU'|_]),_Premises,_Inputs), "
                        "nth0(Index,_Inputs,[['C',i],_,_,_])",
                    )
                    self.assertTrue(prepared['truth'])


if __name__ == '__main__':
    unittest.main()
