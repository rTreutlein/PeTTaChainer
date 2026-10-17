"""T8 report conditioning against independent finite-state enumeration (#81)."""
from fractions import Fraction as F
import itertools
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


def exact_t8(periods):
    # Storm t1 is a supplied probability, held fixed by Jeffrey conditioning.
    # Reports are observations (their confidence is evidence weight, not noise).
    result = F(0)
    for initial, weight in ((1, F(3, 5)), (0, F(2, 5))):
        states = {(initial, 0): F(1)}
        for t in range(1, periods + 1):
            following = {}
            for (previous_storm, previous_degraded), mass in states.items():
                for storm, degraded, fuelled in itertools.product((0, 1), repeat=3):
                    if t == 1 and storm != initial:
                        continue
                    ps = F(7, 10) if previous_storm else F(3, 10)
                    pd = F(3, 4) if previous_degraded else F(1, 20)
                    pf = F(1, 5) if storm else F(9, 10)
                    if (fuelled and not degraded) != bool(t % 2):
                        continue
                    p = mass * (pd if degraded else 1 - pd) * (pf if fuelled else 1 - pf)
                    if t > 1:
                        p *= ps if storm else 1 - ps
                    following[storm, degraded] = following.get((storm, degraded), F(0)) + p
            states = following
        result += weight * sum(p for (_, d), p in states.items() if d) / sum(states.values())
    return result


def plant(handler, periods):
    handler.add_atoms_no_check([
        '(: storm-t1 (Storm t1) (STV 0.6 1))',
        '(: persist-storm (Implication (And (NextPeriod $p $t) (Storm $p)) (Storm $t)) (CTV (STV 0.7 1) (STV 0.3 1)))',
        '(: fuel (Implication (Storm $t) (Fuelled plant $t)) (CTV (STV 0.2 1) (STV 0.9 1)))',
        '(: runs-plant (Implication (And (Fuelled plant $t) (Not (Degraded plant $t))) (Producing plant $t)) (CTV (STV 1 1) (STV 0 1)))',
        '(: persist-degraded (Implication (And (NextPeriod $p $t) (Degraded plant $p)) (Degraded plant $t)) (CTV (STV 0.75 1) (STV 0.05 1)))',
        '(: sound-t0 (Degraded plant t0) (STV 0 1))',
    ] + [atom for t in range(1, periods + 1) for atom in (
        f'(: next-t{t} (NextPeriod t{t-1} t{t}) (STV 1 1))',
        f'(: rep-t{t} (Producing plant t{t}) (STV {t % 2} 0.9))',
    )])
    handler._call('set-base-rate', [f'{handler.kb} (Degraded plant $t) (STV 0.25 0.9)'])
    handler._call('set-base-rate', [f'{handler.kb} (Storm $t) (STV 0.4 0.9)'])


class DeepConditioningTests(unittest.TestCase):
    def test_pin_rebuilds_latest_view_before_selecting_an_older_compatible_view(self):
        handler = PeTTaChainer()
        handler.add_atoms_no_check([
            '(: z (Z a) (STV 0.6 0.9))',
            '(: zw (Implication (Z a) (W a)) (CTV (STV 0.7 1) (STV 0.2 1)))',
            '(: wx (Implication (W a) (X a)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            '(: report (X a) (STV 0.3 0.8))',
            '(: xb (Implication (X a) (B a)) (CTV (STV 0.8 1) (STV 0.2 1)))',
        ])
        handler.query_many_refs(['(: $p (B a) $tv)'], steps=1000)
        result = janus.query_once(
            "_Key=['sk-key',['B',a],[Kb,'MAIN','Nil']], "
            "_Pin=['sk-key',['W',a],[Kb,'MAIN','Nil']], "
            "_Z=['sk-key',['Z',a],[Kb,'MAIN','Nil']], "
            "'index-hash'(_Pin,_P), 'index-hash'(_Z,_E), "
            "'change-state!'(sk_eval_budget,1000,_), "
            "setup_call_cleanup('sk-open-claim!'(_), ("
            "'sk-given-value'([['sk-given',_P,_Pin,true]],_Key,'sk-any-filter',[_E], "
            " ['sk-val',[_,_,_,['STV',Strength,_]],_,_Deps]), "
            "'deps-meet?'([_E],_Deps,ReadsExcluded)), 'sk-close-claim!'(_))",
            {'Kb': handler.kb},
        )
        # The old selection returned B=.38 through the report alone. Pinning W
        # removes the current prediction's Z dependency, making it admissible.
        self.assertAlmostEqual(result['Strength'], .7398560565537888)
        self.assertEqual(result['ReadsExcluded'], 'false')

    def check_plant(self, periods, budget):
        handler = PeTTaChainer()
        plant(handler, periods)
        handler.set_query_metrics(True)
        rows = handler.query_many_refs([f'(: $p (Degraded plant t{periods}) $tv)'], steps=budget)[0]
        self.assertEqual(len(rows), 1)
        with self.subTest('posterior'):
            self.assertAlmostEqual(rows[0].tv[1], float(exact_t8(periods)), delta=1e-8)
        with self.subTest('settlement'):
            self.assertEqual(handler.last_query_metrics()['conditions_unpaid'], 0)
        with self.subTest('report evidence'):
            proof = handler.expand_proof(rows[0].proof)
            self.assertIn(f'rep-t{periods}', proof)
        with self.subTest('report not revised with its prediction'):
            self.assertNotIn('(merge/revision (by runs-plant', handler.expand_proof(rows[0].proof))
        with self.subTest('report evidence keeps its scoped identity'):
            entries = janus.query_once(
                "_Key=['sk-key',['Degraded',plant,Period],[Kb,'MAIN','Nil']], "
                "'sk-value'(_Key,'sk-any-filter',[],['sk-val',_Fact,_Ev,_Deps]), "
                "'evidence-entries'(_Ev,Entries)",
                {'Kb': handler.kb, 'Period': f't{periods}'},
            )['Entries']
            # An inline negative proof must not replace fact-ev(KB, proof,
            # statement) with bare proof names that can count independently.
            aliases = [entry for entry in entries if
                       (isinstance(entry, str) and entry.startswith('rep-t')) or
                       (isinstance(entry, list) and entry[:1] == ['not-ev'] and
                        isinstance(entry[1], str) and entry[1].startswith('rep-t'))]
            self.assertEqual(aliases, [])

    def test_two_period_reports(self):
        self.check_plant(2, 20000)

    def test_five_period_reports(self):
        self.check_plant(5, 20000)
