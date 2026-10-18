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

    def test_reading_removal_preserves_an_open_colliding_key(self):
        result = janus.query_once(
            "_Open=['sk-key',[goal,_X],[fixture,'MAIN','Nil']],"
            "_Ground=['sk-key',[goal,1],[fixture,'MAIN','Nil']],"
            "setup_call_cleanup("
            "(assertz('&sk_reading'(-7003,_Open,7)),"
            " assertz('&sk_reading'(-7003,_Ground,7)),"
            " assertz('&sk_reading'(-7003,_Ground,7))),"
            "('remove-variant-row!'('&sk_reading',[-7003,_Ground,7],_),"
            " findall(_IsGround,('&sk_reading'(-7003,_Key,7),"
            "                   (ground(_Key)->_IsGround=true;_IsGround=false)),AfterGround),"
            " 'remove-variant-row!'('&sk_reading',"
            "    [-7003,['sk-key',[goal,_Y],[fixture,'MAIN','Nil']],7],_),"
            " findall(_IsGround,('&sk_reading'(-7003,_Key,7),"
            "                   (ground(_Key)->_IsGround=true;_IsGround=false)),AfterOpen),"
            " (var(_X),var(_Y)->Unbound=true;Unbound=false)),"
            " retractall('&sk_reading'(-7003,_,7)))")
        self.assertEqual(result['AfterGround'], ['false', 'true'])
        self.assertEqual(result['AfterOpen'], ['true'])
        self.assertEqual(result['Unbound'], 'true')

    def test_ground_removal_rejects_an_open_unifying_fact(self):
        result = janus.query_once(
            "setup_call_cleanup("
            "(assertz(prof95_variant_row(7,_X)),assertz(prof95_variant_row(7,value))),"
            "('remove-variant-row!'(prof95_variant_row,[7,value],_),"
            " aggregate_all(count,prof95_variant_row(7,_),Count),"
            " prof95_variant_row(7,_Remaining),"
            " (var(_Remaining)->Open=true;Open=false)),"
            "retractall(prof95_variant_row(_,_)))")
        self.assertEqual(result['Count'], 1)
        self.assertEqual(result['Open'], 'true')


if __name__ == '__main__':
    unittest.main()
