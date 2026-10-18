"""T8 report conditioning against independent finite-state enumeration (#81)."""
from fractions import Fraction as F
import itertools
import json
from pathlib import Path
import subprocess
import sys
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


def bk_t8(periods, *, branched=True):
    """Enumerate one slice, then project its joint onto independent marginals.

    Branched holds each supplied Storm-t1 outcome fixed until the final
    Jeffrey mix (FR). Pinned holds only its marginal at .6 after slice one.
    Neither calculation calls the chainer or copies its merge formulas.
    """
    result = F(0)
    for initial, weight in (((1, F(3, 5)), (0, F(2, 5))) if branched else ((None, F(1)),)):
        storm_rate, degraded_rate = F(3, 5), F(0)
        for t in range(1, periods + 1):
            following = {}
            for ps, pd, storm, degraded, fuelled in itertools.product((0, 1), repeat=5):
                if t == 1 and initial is not None and storm != initial:
                    continue
                if (fuelled and not degraded) != bool(t % 2):
                    continue
                mass = (storm_rate if ps else 1-storm_rate) * (degraded_rate if pd else 1-degraded_rate)
                qs = (F(initial) if initial is not None else F(3, 5)) if t == 1 else (F(7, 10) if ps else F(3, 10))
                qd, qf = (F(3, 4) if pd else F(1, 20)), (F(1, 5) if storm else F(9, 10))
                p = mass * (qs if storm else 1-qs) * (qd if degraded else 1-qd) * (qf if fuelled else 1-qf)
                following[storm, degraded] = following.get((storm, degraded), F(0)) + p
            total = sum(following.values())
            storm_rate = sum(p for (storm, _), p in following.items() if storm) / total
            degraded_rate = sum(p for (_, degraded), p in following.items() if degraded) / total
            if t == 1 and not branched:
                storm_rate = F(3, 5)
        result += weight * degraded_rate
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
    def test_product_filter_error_bound(self):
        for periods in range(2, 13):
            with self.subTest(periods=periods):
                self.assertLessEqual(abs(bk_t8(periods)-exact_t8(periods)), F(11, 10000))
        self.assertEqual(bk_t8(2), exact_t8(2))
        self.assertAlmostEqual(float(bk_t8(4)), .11925470162726076, delta=1e-12)
        self.assertAlmostEqual(float(bk_t8(2, branched=False)), .09918666931164452, delta=1e-12)

    def test_near_shared_requires_two_near_views(self):
        PeTTaChainer()
        result = janus.query_once(
            "'deps-key'(11,A), 'deps-key'(22,B), 'deps-key'(33,C), "
            "'deps-key'(44,D), 'deps-key'(55,E), "
            "'deps-join'([A,B],AB), 'deps-join'([AB,C],ABC), "
            "'deps-join'([ABC,D],Deep), 'deps-join'([A,E],Near), "
            "'deps-near-shared'([Deep,Near],Filtered), "
            "'deps-entangled'([Deep,Near],Entangled), "
            "'deps-near-shared'([AB,Near],Shared), "
            "'deps-near-shared'([AB],Single)"
        )
        self.assertEqual(result['Filtered'], [])
        self.assertEqual(result['Entangled'], [11])
        self.assertEqual(result['Shared'], [11])
        self.assertEqual(result['Single'], [])

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
        # This checks an exact probability oracle, without regularizing the
        # finite intermediate instance predictions (#89 is tested separately).
        handler.set_bayes_prior_count(0)
        self.addCleanup(handler.set_bayes_prior_count, .2)
        plant(handler, periods)
        handler.set_query_metrics(True)
        rows = handler.query_many_refs([f'(: $p (Degraded plant t{periods}) $tv)'], steps=budget)[0]
        self.assertEqual(len(rows), 1)
        with self.subTest('posterior'):
            self.assertAlmostEqual(rows[0].tv[1], float(exact_t8(periods)), delta=1e-8)
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
        self.assertLessEqual(handler.last_query_metrics()['conditioned_evaluations'], 4 * budget)
        return handler.last_query_metrics()

    def test_claim_debt_metric_counts_needed_readable_requests(self):
        handler = PeTTaChainer()
        # The original exhausted-turn regression: two needed root cuts share
        # one slice. A sleeping cut is still debt, even when it is not queued.
        plant(handler, 8)
        handler.set_query_metrics(True)
        handler.query_many_refs(['(: $p (Degraded plant t6) $tv)',
                                 '(: $p (Degraded plant t8) $tv)'], steps=3000)
        # Inspect the request relation without depending on its payload layout.
        debt = janus.query_once(
            "current_predicate('&sk_given_pending'/_Arity), "
            "functor(_Request,'&sk_given_pending',_Arity), "
            "findall(true,(call(_Request),arg(1,_Request,_H),arg(2,_Request,_R), "
            " (_R == -1 -> '&sk_keys'(_H,_K),_Readable=true "
            " ; '&sk_row'(_H,_K,_R,['sk-row',_,_,_Premises,_]), "
            "   'sk-readable-row?'(_H,_K,_Premises,_Readable)), "
            " _Readable == true, 'sk-needed?'(_H,_K,true)), _Needed), "
            "findall(true, ('&ctx_sk_root_exhausted'(_DH,_DK,_), "
            " 'sk-root-claim?'([],_DH,_DK,true), "
            " \\+ '&ctx_sk_given_pending'(_DH,-1,_)), _Dormant), "
            "append(_Needed,_Dormant,_Debt),length(_Debt,Count)"
        )['Count']
        self.assertGreater(debt, 1)  # The exhausted-turn metric reported only one.
        self.assertEqual(handler.last_query_metrics()['conditions_unpaid'], debt)
        # This fixture deliberately leaves unfinished reads. Release its
        # branch requests so they cannot spend another KB's deferred tier.
        janus.query_once(
            "forall(('&ctx_sk_branch_owner'(_Slot,_,['sk-key',_,[Kb,'MAIN','Nil']],_,_)), "
            " 'sk-drop-branch!'([],_Slot,_)), "
            "retractall('&sk_branch_wanted'(_,_,['sk-key',_,[Kb,'MAIN','Nil']],_,_)), "
            "retractall('&sk_branch_hold'(_,_,['sk-key',_,[Kb,'MAIN','Nil']],_,_))", {'Kb': handler.kb})

    def test_two_period_reports(self):
        self.assertEqual(self.check_plant(2, 20000)['conditions_unpaid'], 0)

    def test_dead_claim_pruning_costs_26_rows_and_requery_zero(self):
        handler = PeTTaChainer()
        plant(handler, 2)
        handler.set_query_metrics(True)
        query = ['(: $p (Degraded plant t2) $tv)']
        first = handler.query_many_refs(query, steps=20000)[0][0].tv
        # Default κ reads each finite report/instance prior once before updates.
        self.assertEqual(first, ['STV', 0.1071952240649727, 0.999894142365972])
        self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 26)
        second = handler.query_many_refs(query, steps=20000)[0][0].tv
        self.assertEqual(first, second)
        self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 0)
        self.assertEqual(handler.last_query_metrics()['conditions_unpaid'], 0)

    def test_three_period_second_query_is_quiescent(self):
        handler = PeTTaChainer()
        plant(handler, 3)
        handler.set_query_metrics(True)
        query = ['(: $p (Degraded plant t3) $tv)']
        answers, work = [], []
        for _ in range(3):
            answers.append(handler.query_many_refs(query, steps=20000)[0][0].tv)
            metrics = handler.last_query_metrics()
            work.append(metrics['conditioned_evaluations'])
            if len(answers) > 1:
                for name in ('conditioned_evaluations', 'row_computes',
                             'branch_builds', 'conditions_unpaid'):
                    with self.subTest(query=len(answers), metric=name):
                        self.assertEqual(metrics[name], 0)
        self.assertEqual(answers, [answers[0]] * 3)
        self.assertEqual(work, [0, 0, 0])

    def test_repeated_query_preserves_later_different_root_answer(self):
        answers = []
        for repeats in (1, 2):
            handler = PeTTaChainer()
            plant(handler, 3)
            for _ in range(repeats):
                handler.query_many_refs(['(: $p (Degraded plant t3) $tv)'], steps=20000)
            # One step observes the reusable state without paying for another
            # conditioning turn. The removed repeat policy changed this TV.
            answers.append([row.tv for row in handler.query_many_refs(
                ['(: $p (Fuelled plant t3) $tv)'], steps=1)[0]])
        self.assertEqual(len(answers[0]), 1)
        self.assertEqual(answers[0], answers[1])

    def test_rate_takes_completed_fold_independent_members_when_demanded(self):
        handler = PeTTaChainer()
        plant(handler, 3)
        handler.query_many_refs(['(: $p (Degraded plant t3) $tv)'], steps=20000)
        # Deep conditioning used to discover these takes incidentally. Demand
        # the member keys through ordinary queries so their changed values wake
        # the rate and its excluded branches through the normal reader path.
        handler.query_many_refs([
            '(: $p (Fuelled plant t2) $tv)',
            '(: $p (Fuelled plant t3) $tv)',
        ], steps=20000)
        # Storm predictions: .3+.4*.6=.54, then .516; fuel is .9-.7*s.
        members = janus.query_once(
            "findall([_T,_S], '&ctx_forward_aggregate_observation'(_,_,"
            " ['forward-base-rate-observation-value',"
            "  [['Fuelled',plant,_T],[Kb,'MAIN','Nil'],_,['STV',_S,_]]],_,_,_), Members)",
            {'Kb': handler.kb},
        )['Members']
        self.assertIn(['t2', .522], members)
        self.assertIn(['t3', .5388], members)
        self.assertEqual(janus.query_once(
            "findall(1,'&ctx_sk_branch_hold'(_,_,_,_,_), Holds)"
        )['Holds'], [])

    def test_three_period_work_is_deterministic_across_processes(self):
        # Separate processes give the KB different random identities. Work
        # ordering must not fall back to their exclusion-key hashes.
        program = """
import json
from test_deep_conditioning import plant
from pettachainer import PeTTaChainer
handler = PeTTaChainer()
plant(handler, 3)
handler.set_query_metrics(True)
rows = handler.query_many_refs(['(: $p (Degraded plant t3) $tv)'], steps=3000)[0]
metrics = {k: v for k, v in handler.last_query_metrics().items() if not k.endswith('_seconds')}
print(json.dumps({'tv': [r.tv for r in rows], 'metrics': metrics}, sort_keys=True))
"""
        samples = []
        for _ in range(4):
            result = subprocess.run(
                [sys.executable, '-c', program], cwd=Path(__file__).parent,
                capture_output=True, text=True, timeout=180, check=True,
            )
            samples.append(json.loads(result.stdout.splitlines()[-1]))
        self.assertTrue(all(sample == samples[0] for sample in samples[1:]), samples)

    def test_added_reader_revives_a_structurally_dead_claim(self):
        handler = PeTTaChainer()
        plant(handler, 2)
        handler.query_many_refs(['(: $p (Degraded plant t2) $tv)'], steps=20000)
        inspect = (
            "_Key=['sk-key',['Producing',plant,t2],[Kb,'MAIN','Nil']], "
            "'index-hash'(_Key,_H), "
            "once(('&sk_row'(_H,_Key,_R,['sk-row',_,_,_Prem,_]), "
            " member([['Fuelled',plant,t2]|_],_Prem))), "
            "'sk-readable-row?'(_H,_Key,_Prem,Readable)"
        )
        self.assertEqual(janus.query_once(inspect, {'Kb': handler.kb})['Readable'], 'false')
        # Forward runs may expose a taken key even when it has no depth-zero
        # reader. Treat their claims as live, then restore ordinary query D2.
        forward = janus.query_once(
            "'search-id-value'(sk_forward_run,_Was), "
            "setup_call_cleanup('change-state!'(sk_forward_run,1,_), (" + inspect +
            "), 'change-state!'(sk_forward_run,_Was,_))", {'Kb': handler.kb},
        )
        self.assertEqual(forward['Readable'], 'true')
        self.assertEqual(janus.query_once(inspect, {'Kb': handler.kb})['Readable'], 'false')
        handler.add_atoms_no_check([
            '(: revenue (Implication (Producing plant $t) (Revenue plant $t)) (CTV (STV 1 1) (STV 0 1)))',
        ])
        handler.set_query_metrics(True)
        handler.query_many_refs(['(: $p (Revenue plant t2) $tv)'], steps=20000)
        self.assertEqual(janus.query_once(inspect, {'Kb': handler.kb})['Readable'], 'true')
        self.assertGreater(handler.last_query_metrics()['conditioned_evaluations'], 0)
        handler.query_many_refs(['(: $p (Producing plant t2) $tv)'], steps=20000)
        self.assertEqual(janus.query_once(inspect, {'Kb': handler.kb})['Readable'], 'true')

    def test_five_period_reports(self):
        self.check_plant(5, 20000)

    def test_issue_81_five_period_conditioning_settles(self):
        # Producing at t5 certifies zero degradation. Summarizing deep history
        # removes the cross-period conditioning cycle as well as its debt.
        handler = PeTTaChainer()
        plant(handler, 5)
        handler.set_query_metrics(True)
        handler.query_many_refs(['(: $p (Degraded plant t5) $tv)'], steps=20000)
        self.assertEqual(handler.last_query_metrics()['conditions_unpaid'], 0,
                         '#81: five-period filtering should have no conditioning debt')

    def test_four_period_root_matches_branched_product_filter(self):
        handler = PeTTaChainer()
        handler.set_bayes_prior_count(0)
        self.addCleanup(handler.set_bayes_prior_count, .2)
        plant(handler, 4)
        handler.set_query_metrics(True)
        query = ['(: $p (Degraded plant t4) $tv)']
        for repeat in range(3):
            answer = handler.query_many_refs(query, steps=3000)[0][0]
            self.assertAlmostEqual(answer.tv[1], float(bk_t8(4)), delta=1e-8)
            self.assertLess(abs(answer.tv[1]-float(exact_t8(4))), .0011)
            metrics = handler.last_query_metrics()
            self.assertEqual(metrics['conditions_unpaid'], 0)
            self.assertEqual(metrics['conditioned_evaluations'], 510 if repeat == 0 else 0)

    def test_cached_summary_can_be_promoted_to_a_root_claim(self):
        handler = PeTTaChainer()
        handler.set_bayes_prior_count(0)
        self.addCleanup(handler.set_bayes_prior_count, .2)
        plant(handler, 2)
        handler.add_atom('(: wrapper (Implication (Degraded plant $t) (Wrapped plant $t)) (CTV (STV 1 1) (STV 0 1)))')
        handler.set_query_metrics(True)
        wrapped = handler.query_many_refs(['(: $p (Wrapped plant t2) $tv)'], steps=3000)[0][0]
        self.assertAlmostEqual(wrapped.tv[1], float(bk_t8(2, branched=False)), delta=1e-8)
        self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 0)
        for repeat in range(2):
            root = handler.query_many_refs(['(: $p (Degraded plant t2) $tv)'], steps=3000)[0][0]
            self.assertAlmostEqual(root.tv[1], float(exact_t8(2)), delta=1e-8)
            self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 26 if repeat == 0 else 0)

    def test_unpaid_clash_keeps_a_facts_disjoint_waiting_answer(self):
        handler = PeTTaChainer()
        plant(handler, 3)
        handler.query_many_refs(['(: $p (Degraded plant t3) $tv)'], steps=20000)
        handler.add_atom('(: wait-rule (Implication (And (Fuelled plant t3) '
                         '(Not (Degraded plant t3))) (Waiting plant)) '
                         '(CTV (STV 1 1) (STV 0 1)))')
        handler.set_query_metrics(True)
        # One step cannot settle the shared-report clash. The lazy read can
        # reuse the already computed completion Producing3 => Fuelled3=1.
        # Its other premise must omit rep-t3, so D3 is the predictive kernel
        # .05+.7*(.05+.7*.05)=.1095. Thus this waiting proof gives .8905.
        # The old eager channel held an earlier Fuelled3 prediction instead.
        predictive = 1 - .1095
        # A waiting proof is output only, including through the materializing
        # API. It must never become another stored observation or fallback.
        materialized = handler.query_many_materialization(['(: $p (Waiting plant) $tv)'], steps=1)
        self.assertTrue(materialized[0])
        stored = janus.query_once(
            "findall(_F,'&materialized_facts'('materialized-row',_,['Waiting',plant],[Kb,'MAIN','Nil'],_F,_),Rows)",
            {'Kb': handler.kb})['Rows']
        self.assertEqual(stored, [])
        for changed in (False, True):
            if changed:
                handler._call('stored-refs-gc!', [])
                handler._call('deps-gc!', ['(sk-deps-roots)'])
                handler.add_atom('(: extra-report (Producing plant t3) (STV 1 0.8))')
            answer = handler.query_many_refs(['(: $p (Waiting plant) $tv)'], steps=1)[0][0]
            self.assertAlmostEqual(answer.tv[1], predictive, places=12)
            self.assertGreater(answer.tv[2], 0)
            self.assertLessEqual(answer.tv[2], .5)
            self.assertGreater(handler.last_query_metrics()['conditions_unpaid'], 0)
            proof = handler.expand_proof(answer.proof)
            self.assertIn('sound-t0', proof)
            self.assertEqual(proof.count('rep-t3'), 1)
            self.assertNotIn('rep-t1', proof)
            self.assertNotIn('rep-t2', proof)
            self.assertNotIn('extra-report', proof)

    def test_waiting_rate_read_leaves_out_its_own_observation(self):
        handler = PeTTaChainer()
        handler.add_atoms_no_check([
            '(: one (P one) (STV 1 0.9))',
            '(: two (P two) (STV 0 0.9))',
            '(: three (P three) (STV 1 0.9))',
        ])
        # Demand the population fold so its ordinary observation index exists.
        goal = (f'(CPU FoldAllCompiled ({handler.kb} (P $t) extract-tv '
                '(BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv) $tv)')
        handler._call('chainer', [f'1000 {goal}'])
        result = janus.query_once("""
            'base-rate-premises'(Kb,['P',_T],_Result,_Goals),
            _Goals=[['CPU','FoldAllCompiled',_Args,_]],
            'sk-value'(['sk-fold',_Args],'sk-any-filter',[],
                ['sk-goal-val',['CPU',_,_,Raw],_,_,_]),
            'evidence-set'([['fact-ev',[Kb,'MAIN','Nil'],three,['P',three]]],_Ev),
            copy_term([_Goals,_Result],[_ReadGoals,_Rate]),
            'sk-premise-step'([],[],[],false,false,'sk-representative-read',
                ['sk-acc',[],_Ev,[],[]],
                ['CPU','ReadRate',[Kb,['P',_T],Raw,
                    ['rate-plan',_ReadGoals,_Rate],false],
                    ['rate-read',Admissible,Read]],_State)
        """, {'Kb': handler.kb})
        # Equal-weight observations 1,0,1 give 2/3; excluding the row's own
        # final 1 leaves the Bernoulli mean (1+0)/2, with less evidence.
        self.assertAlmostEqual(result['Raw'][1], 2/3)
        self.assertAlmostEqual(result['Admissible'][1], .5)
        self.assertLess(result['Admissible'][2], result['Raw'][2])
        self.assertEqual(result['Read'], result['Admissible'])

    def test_lazy_representatives_are_cut_and_context_local_and_retire_with_row(self):
        handler = PeTTaChainer()
        result = janus.query_once(
            "K=['sk-key',['A',a],[Kb,'MAIN','Nil']], 'index-hash'(K,H), "
            "Main=['sk-val',[['A',a],[Kb,'MAIN','Nil'],main,['STV',0.2,0.7]],['ev-set',0],0], "
            "Local=['sk-val',[['A',a],[Kb,'MAIN','Nil'],local,['STV',0.8,0.7]],['ev-set',0],0], "
            "'context-add!'('&sk_representative',[H,K,7,[],[],Main],_), "
            "setup_call_cleanup(nb_setval(context_overlay,fr81_test), "
            " ('context-add!'('&sk_representative',[H,K,7,[],[],Local],_), "
            "  once('&ctx_sk_representative'(H,K,7,[],[],InContext))), "
            " nb_setval(context_overlay,main)), "
            "once('&ctx_sk_representative'(H,K,7,[],[],InMain)), "
            "findall(_V,'&ctx_sk_representative'(H,K,7,[],[123],_V),OtherCuts), 'context-clear!'(_), 'sk-drop-row-views!'(H,K,7,_), "
            "findall(_V,'&sk_representative'(H,K,7,_,_,_V),After)", {'Kb': handler.kb})
        self.assertEqual(result['InContext'][1][3], ['STV', .8, .7])
        self.assertEqual(result['InMain'][1][3], ['STV', .2, .7])
        self.assertEqual(result['OtherCuts'], [])
        self.assertEqual(result['After'], [])

    def test_unsettled_filtered_summaries_report_uncertainty(self):
        # Exact finite-state enumeration is independent of the chainer. These
        # allowances cannot yet rebuild the t-1 report without t self-support.
        for periods, budget in ((6, 300), (8, 300), (8, 3000)):
            handler = PeTTaChainer()
            plant(handler, periods)
            for repeat in range(3):
                answer = handler.query_many_refs(
                    [f'(: $p (Degraded plant t{periods}) $tv)'], steps=budget)[0][0]
                with self.subTest(periods=periods, budget=budget, repeat=repeat):
                    self.assertLessEqual(
                        abs(answer.tv[1] - float(exact_t8(periods))) * answer.tv[2], .005)

    def test_unsettled_discount_preserves_admitted_sources(self):
        import math
        PeTTaChainer()
        for strength, unfiltered in ((.1227, 0), (.5, .5), (1, .1)):
            got = janus.query_once(
                "'sk-unsettled-value'(81,['sk-val',[['A'],[kb,'MAIN','Nil'],"
                " admitted,['STV',S,0.647]],['ev-set',0],0],"
                " ['sk-val',[['A'],[kb,'MAIN','Nil'],excluded,['STV',R,0.986]],"
                " ['ev-set',0],0], Value)", {'S': strength, 'R': unfiltered})['Value']
            clip = lambda v: max(.001, min(.999, v))
            logit = lambda v: math.log(clip(v) / (1 - clip(v)))
            expected = .647 / (1 + (logit(strength) - logit(unfiltered)) ** 2)
            self.assertEqual(got[1][2], 'admitted' if strength == unfiltered else ['unsettled-summary', 81, 'admitted'])
            self.assertEqual(got[1][3][1], strength)
            self.assertAlmostEqual(got[1][3][2], expected, places=14)
            self.assertEqual(got[2:], [['ev-set', 0], 0])
            # A rebuilt proof already carrying this premise's uncertainty
            # cannot receive the same discount a second time.
            again = janus.query_once(
                "'sk-unsettled-value'(81,V,['sk-val',[['A'],[kb,'MAIN','Nil'],"
                " excluded,['STV',R,0.986]],['ev-set',0],0],Value)",
                {'V': got, 'R': unfiltered})['Value']
            self.assertEqual(again, got)

    def test_root_refinement_work_is_bounded_with_growing_history(self):
        for periods, budget in ((6, 3000), (8, 20000)):
            handler = PeTTaChainer()
            plant(handler, periods)
            handler.set_query_metrics(True)
            query = [f'(: $p (Degraded plant t{periods}) $tv)']
            for repeat in range(2):
                answer = handler.query_many_refs(query, steps=budget)[0][0]
                metrics = handler.last_query_metrics()
                with self.subTest(periods=periods, repeat=repeat):
                    self.assertEqual(metrics['conditioned_evaluations'], 512 if repeat == 0 else 0)
                    self.assertGreater(metrics['conditions_unpaid'], 0)
                    self.assertLess(abs(answer.tv[1] - float(exact_t8(periods))), .0011)
                    self.assertIn(f'rep-t{periods}', handler.expand_proof(answer.proof))
            # Another independent report changes the likelihood input while
            # leaving the root uncertain. The capped attempt becomes eligible.
            handler.add_atom(f'(: extra-report (Producing plant t{periods}) (STV 0 0.7))')
            handler.query_many_refs(query, steps=budget)
            self.assertGreater(handler.last_query_metrics()['conditioned_evaluations'], 0)
            self.assertLessEqual(handler.last_query_metrics()['conditioned_evaluations'], 512)
            handler.query_many_refs(query, steps=budget)
            self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 0)

    def test_dormant_root_is_a_computational_cutoff(self):
        for periods, budget in ((4, 300), (6, 20000)):
            handler = PeTTaChainer()
            plant(handler, periods)
            for repeat in range(2):
                result = handler.query_with_diagnostics(
                    f'(: $p (Degraded plant t{periods}) $tv)', steps=budget)
                self.assertEqual(result['diagnostics']['termination']['reason'], 'budget_exhausted')
                self.assertGreater(result['diagnostics']['termination']['agenda_entries'], 0)
                self.assertGreater(handler.last_query_metrics()['conditions_unpaid'], 0)
                if repeat:
                    self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 0)

    def test_larger_root_slice_can_retry_an_exhausted_smaller_slice(self):
        handler = PeTTaChainer()
        plant(handler, 4)
        handler.set_query_metrics(True)
        query = ['(: $p (Degraded plant t4) $tv)']
        handler.query_many_refs(query, steps=300)
        self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 150)
        handler.query_many_refs(query, steps=300)
        self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 0)
        answer = handler.query_many_refs(query, steps=3000)[0][0]
        self.assertGreater(handler.last_query_metrics()['conditioned_evaluations'], 0)
        self.assertAlmostEqual(answer.tv[1], float(bk_t8(4)), delta=1e-7)
        handler.query_many_refs(query, steps=3000)
        self.assertEqual(handler.last_query_metrics()['conditioned_evaluations'], 0)

    def test_nested_negative_inline_facts_keep_statement_and_kb_identity(self):
        handler = PeTTaChainer()
        handler.add_atoms_no_check([
            '(: report (A a) (STV 0.4 0.7))',
            '(: report (B a) (STV 0.8 0.9))',
        ])
        result = janus.query_once(
            "Scope=[Kb,'MAIN','Nil'], A=['A',a], B=['B',a], "
            "'index-hash'(['sk-key',A,Scope],HA), 'index-hash'(['sk-key',B,Scope],HB), "
            "'sk-leaf-view'(HA,[A,Scope,report,['STV',0.4,0.7]],['sk-val',[_,_,PA,_],EA,_]), "
            "'sk-leaf-view'(HB,[B,Scope,report,['STV',0.8,0.9]],['sk-val',[_,_,PB,_],EB,_]), "
            "'evidence-union'(EA,EB,Original), "
            "P=[by,r,[conjunction,[negated,[negated,PA]],[negated,PB]]], "
            "'rule-result-evidence'([['Goal'],Scope,P,['STV',0.5,0.5]],Original,Ev), "
            "'evidence-entries'(Ev,Entries), 'premise-evidence-overlap?'(EA,Ev,Overlaps), "
            "'evidence-set'([['fact-ev',[other,'MAIN','Nil'],report,A]],OtherSource), "
            "'proof-term-evidence'('proof-walk-in-kb',['fact-source',OtherSource,report],Other), "
            "'premise-evidence-overlap?'(EA,Other,CrossKbOverlap)",
            {'Kb': handler.kb},
        )
        scope = [handler.kb, 'MAIN', 'Nil']
        self.assertCountEqual(result['Entries'], [
            ['fact-ev', scope, 'report', ['A', 'a']],
            ['not-fact-ev', scope, 'report', ['B', 'a']],
        ])
        self.assertEqual(result['Overlaps'], 'true')
        self.assertEqual(result['CrossKbOverlap'], 'false')

    def test_impossible_likelihood_preserves_zero_but_noisy_likelihood_does_not(self):
        for leak in (0, 0.1):
            with self.subTest(leak=leak):
                handler = PeTTaChainer()
                handler.add_atoms_no_check([
                    '(: z (Z a) (STV 0.6 1))',
                    '(: za (Implication (Z a) (A a)) (CTV (STV 0.7 1) (STV 0.2 1)))',
                    f'(: runs (Implication (And (Z a) (Not (A a))) (E a)) (CTV (STV 1 1) (STV {leak} 1)))',
                    '(: report (E a) (STV 1 0.9))',
                ])
                answer = handler.query_many_refs(['(: $p (A a) $tv)'], steps=1000)[0][0]
                if leak == 0:
                    self.assertEqual(answer.tv[1], 0)
                    self.assertLess(answer.tv[2], 1)
                else:
                    self.assertGreater(answer.tv[1], 0)
                    self.assertLess(answer.tv[1], 1)
