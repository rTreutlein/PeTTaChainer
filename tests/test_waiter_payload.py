"""Compact continuations preserve sharing and disappear with their consumers."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class TestWaiterPayload(unittest.TestCase):
    def test_contextualized_continuation_round_trip(self):
        h = PeTTaChainer()
        result = janus.query_once(
            "_C=[['Result',_X],[Kb,'MAIN','Nil'],['by',r,_P],_TV],"
            "_A=[['Input',_X],[Kb,'MAIN','Nil'],_P,_TV],"
            "assertz(rules('runtime-rule-row',9999003,_C,[_A])),"
            "_O=[['Result',_],[Kb,'MAIN','Nil'],_,_],"
            "_N=[['Input',i],[Kb,private,'Nil'],_Proof,_Value],"
            "_W=['sk-partial',_O,9999003,[['Result',i],[Kb,private,'Nil'],['by',r,_Proof],_Value],[],[_N],[]],"
            "'sk-store-wait!'(998877,112233,_N,_W,_),"
            "'&sk_wait'(112233,_Stored,_Decoded),"
            "(_Stored-_Decoded =@= _N-_W -> Equal=true;Equal=false),"
            "_Decoded=['sk-partial',_,_,[_,_,['by',r,_DP],_DV],[],[[_,_,_NP,_NV]],[]],"
            "(_DP==_NP,_DV==_NV -> Shared=true;Shared=false),"
            "'remove-variant-row!'('&sk_wait',[112233,_N,_W],_),"
            "aggregate_all(count,sk_wait_payload(112233,_,_,_),Left),"
            "aggregate_all(count,(sk_wait_template(_,_,_Id,_,_),\\+sk_wait_payload(_,_,_Id,_)),Orphans)",
            {'Kb': h.kb})
        self.assertEqual([result[k] for k in ('Equal', 'Shared', 'Left', 'Orphans')], ['true', 'true', 0, 0])

    def test_query_cleanup_keeps_native_reader_and_collects_templates(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: r (Implication (And (_A $x) (B $x)) (_C $x)) (STV 1 0.9))',
            '(: a (_A i) (STV 1 1))',
        ])
        for _ in range(3):
            h.query_many_refs(['(: $p (Assuming (_A i) (_C i)) $tv)'], steps=40)
        result = janus.query_once(
            "aggregate_all(count,(sk_wait_template(_,_,_Id,_,_),\\+sk_wait_payload(_,_,_Id,_)),Orphans),"
            "aggregate_all(count,clause('&sk_wait'(_,_,_),_),Readers)")
        self.assertEqual(result['Orphans'], 0)
        self.assertEqual(result['Readers'], 1)
        h.add_atom('(: b (B i) (STV 1 1))')
        self.assertTrue(h.query_many_refs(['(: $p (_C i) $tv)'], steps=40)[0])
