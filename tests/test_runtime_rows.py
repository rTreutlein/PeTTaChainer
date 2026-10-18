"""Native row removal preserves multiplicity, order, and open-variable sharing."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestRuntimeRows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.handler = PeTTaChainer()

    def test_ground_removal_takes_one_fact_and_ignores_missing_rows(self):
        result = janus.query_once(
            "setup_call_cleanup("
            "(assertz(prof95_variant_row(7,left)),"
            " assertz(prof95_variant_row(7,right)),"
            " assertz(prof95_variant_row(7,left)),"
            " assertz((prof95_variant_row(9,rule):-memberchk(a,[a])))),"
            "('remove-variant-row!'(prof95_variant_row,[7,left],_),"
            " 'remove-variant-row!'(prof95_variant_row,[7,missing],_),"
            " 'remove-variant-row!'(prof95_variant_row,[9,rule],_),"
            " findall(_Value,prof95_variant_row(7,_Value),Rows),"
            " aggregate_all(count,clause(prof95_variant_row(9,rule),_),Rules)),"
            "retractall(prof95_variant_row(_,_)))")
        self.assertEqual(result['Rows'], ['right', 'left'])
        self.assertEqual(result['Rules'], 1)

    def test_open_removal_preserves_a_unifying_nonvariant(self):
        result = janus.query_once(
            "setup_call_cleanup("
            "(assertz(prof95_variant_row(7,[pair,_X,_X])),"
            " assertz(prof95_variant_row(7,[pair,_Y,_Z]))),"
            "('remove-variant-row!'(prof95_variant_row,[7,[pair,_A,_A]],_),"
            " aggregate_all(count,prof95_variant_row(7,_),Count),"
            " prof95_variant_row(7,[pair,_Left,_Right]),"
            " (_Left==_Right -> Shared=true;Shared=false),"
            " (var(_A),var(_Left),var(_Right) -> Unbound=true;Unbound=false)),"
            "retractall(prof95_variant_row(_,_)))")
        self.assertEqual((result['Count'], result['Shared'], result['Unbound']), (1, 'false', 'true'))

    def test_forcing_membership_has_evaluation_and_context_lifetimes(self):
        result = janus.query_once(
            "setup_call_cleanup('context-clear!'(_),"
            "('sk-force-causes!'(-7001,-7002,[111,111],_),"
            " 'remove-data-rows!'('&sk_forced',[-7001,-7002,_],_),"
            " nb_setval(context_overlay,prof95_force_context),"
            " 'sk-force-causes!'(-7001,-7002,[111],_),"
            " 'remove-data-rows!'('&sk_forced',[-7001,-7002,_],_),"
            " 'sk-force-reset!'(_),'sk-force-causes!'(-7001,-7002,[111],_),"
            " findall(_C,'&ctx_sk_forced'(-7001,-7002,_C),Overlay),"
            " nb_setval(context_overlay,main),"
            " 'sk-force-causes!'(-7001,-7002,[111],_),"
            " findall(_C,'&ctx_sk_forced'(-7001,-7002,_C),AlreadyUsed),"
            " 'sk-force-reset!'(_),'sk-force-causes!'(-7001,-7002,[111],_),"
            " findall(_C,'&ctx_sk_forced'(-7001,-7002,_C),NextEvaluation),"
            " 'context-clear!'(_),aggregate_all(count,sk_forced_seen(_,_),Handles)),"
            "(nb_setval(context_overlay,main),'context-clear!'(_),"
            " 'remove-data-rows!'('&sk_forced',[-7001,-7002,_],_)))")
        self.assertEqual(result['Overlay'], [111])
        self.assertEqual(result['AlreadyUsed'], [])
        self.assertEqual(result['NextEvaluation'], [111])
        self.assertEqual(result['Handles'], 0)


if __name__ == '__main__':
    unittest.main()
