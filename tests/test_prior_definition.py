"""The approved #89 prior contract, including interaction regressions."""
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer
from pettachainer.query_diagnostics import _parse


class PriorDefinitionTests(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()
        self.h.set_evidence_confidence_k(800)
        self.h.set_bayes_prior_count(0.2)

    def tearDown(self):
        self.h.set_evidence_confidence_k(800)
        self.h.set_bayes_prior_count(0.2)

    def formula(self, name, args):
        return _parse(self.h._call(name, [args])[0])

    def answer(self, goal):
        rows = self.h.query_many_refs([f'(: $p {goal} $tv)'], steps=600)[0]
        self.assertEqual(len(rows), 1)
        return rows[0]

    def diagnostic(self, strength=None):
        self.h = PeTTaChainer()
        self.h.add_atoms_no_check([
            '(: diagnostic (Implication (Cause $t) (Effect $t)) (CTV (STV 0.9 0.9) (STV 0.2 0.9)))',
            '(: effect (Effect now) (STV 1 1))',
            '(: c1 (Cause d1) (STV 1 1))', '(: c2 (Cause d2) (STV 0 1))',
            '(: c3 (Cause d3) (STV 0 1))', '(: c4 (Cause d4) (STV 1 1))',
        ])
        if strength is not None:
            self.h.add_atom(f'(: prior (Cause now) (STV {strength} 0.5))')

    def test_uncertain_endpoints_and_nearby_values_are_continuous(self):
        expected = {
            0: (0.000562083205, 0.181296872224),
            0.000001: (0.000566577889, 0.181297848079),
            0.001: (0.005041118277, 0.182273009733),
            0.5: (0.818173783490, 0.601391801423),
            0.999999: (0.999972002743, 0.818280589557),
            1: (0.999972224965, 0.818280888867),
        }
        for strength, (mean, confidence) in expected.items():
            with self.subTest(strength=strength):
                self.diagnostic(strength)
                for _ in range(2):
                    a = self.answer('(Cause now)')
                    self.assertAlmostEqual(float(a.tv[1]), mean, places=8)
                    self.assertAlmostEqual(float(a.tv[2]), confidence, places=7)

    def test_certain_endpoint_facts_remain_exact_under_likelihoods(self):
        for strength in (0, 1):
            self.diagnostic()
            self.h.add_atom(f'(: certain (Cause now) (STV {strength} 1))')
            for _ in range(2):
                self.assertEqual(self.answer('(Cause now)').tv, ['STV', strength, 1])

    def test_forward_withdrawal_matches_a_fresh_excluded_population(self):
        def build():
            h = PeTTaChainer()
            h.add_atoms_no_check([
                '(: first (P a) (STV 0.2 0.5))',
                '(: other (S a) (STV 0.7 0.6))',
                '(: p (Implication (P $x) (Q $x)) (CTV (STV 1 0.9) (STV 0 1)))',
                '(: s (Implication (S $x) (Q $x)) (CTV (STV 1 0.9) (STV 0 1)))',
            ])
            h.forward_chain(h.all_facts(), steps=20)
            return h

        self.h = build()
        self.h.add_atom('(: removed (P a) (STV 0.8 0.5))')
        self.h.forward_chain(self.h.all_facts(), steps=20)
        self.answer('(Q a)')
        self.h.remove_statement('removed')
        after = self.answer('(P a)')
        self.assertNotIn('removed', self.h.expand_proof(after.proof))
        self.assertEqual(self.answer('(P a)').tv, after.tv)
        self.h = build()
        fresh = self.answer('(P a)')
        for actual, expected in zip(after.tv[1:], fresh.tv[1:]):
            self.assertAlmostEqual(float(actual), float(expected), places=12)

    def test_late_prior_and_withdrawal_equal_fresh(self):
        self.diagnostic(0.001)
        fresh = self.answer('(Cause now)').tv
        self.diagnostic()
        before = self.answer('(Cause now)').tv
        self.h.add_atom('(: prior (Cause now) (STV 0.001 0.5))')
        for _ in range(2):
            self.assertEqual(self.answer('(Cause now)').tv, fresh)
        self.h.remove_statement('prior')
        self.assertEqual(self.answer('(Cause now)').tv, before)

    def test_incomparable_containing_generals_are_a_mixture(self):
        # k=1 makes a confidence inflation observable in the strength.
        self.h.set_evidence_confidence_k(1)
        self.h.add_atoms_no_check([
            '(: specific (Implication (And (A $x) (B $x)) (T $x)) (CTV (STV 0.99 0.4) (STV 0.5 0)))',
            '(: ga (Implication (A $x) (T $x)) (CTV (STV 0.3 0.99) (STV 0.5 0)))',
            '(: a (A now) (STV 1 1))', '(: b (B now) (STV 1 1))',
        ])
        one = self.answer('(T now)').tv
        self.h.add_atom('(: gb (Implication (B $x) (T $x)) (CTV (STV 0.3 0.99) (STV 0.5 0)))')
        both = self.answer('(T now)')
        self.assertAlmostEqual(float(one[1]), float(both.tv[1]), places=9)
        self.assertIn('class-mixture', self.h.expand_proof(both.proof))

    def test_nearest_containing_general_excludes_its_ancestor(self):
        self.h.set_evidence_confidence_k(1)
        self.h.add_atoms_no_check([
            '(: specific (Implication (And (A $x) (B $x) (C $x)) (T $x)) (CTV (STV 0.9 0.4) (STV 0.5 0)))',
            '(: near (Implication (And (A $x) (B $x)) (T $x)) (CTV (STV 0.2 0.99) (STV 0.5 0)))',
            '(: a (A now) (STV 1 1))', '(: b (B now) (STV 1 1))',
            '(: c (C now) (STV 1 1))',
        ])
        nearest = self.answer('(T now)').tv
        self.h.add_atom('(: ancestor (Implication (A $x) (T $x)) (CTV (STV 0.99 0.99) (STV 0.5 0)))')
        self.assertEqual(self.answer('(T now)').tv, nearest)

    def test_nearest_overlap_does_not_promote_independent_ancestor(self):
        self.h.set_evidence_confidence_k(1)
        self.h.add_atoms_no_check([
            '(: specific (Implication (And (A $x) (B $x) (C $x)) (T $x)) (CTV (STV 0.9 0.4) (STV 0.5 0)))',
            '(: near (Implication (And (A $x) (B $x)) (T $x)) (CTV (STV 0.2 0.99) (STV 0.5 0)))',
            '(: a (A now) (STV 1 1))', '(: b (B now) (STV 1 0.8))',
            '(: c (C now) (STV 1 1))',
        ])
        without_ancestor = self.answer('(T now)').tv
        self.h.add_atom('(: ancestor (Implication (A $x) (T $x)) (CTV (STV 0.01 0.99) (STV 0.5 0)))')
        result = self.answer('(T now)')
        self.assertEqual(result.tv, without_ancestor)
        self.assertNotIn('ancestor', self.h.expand_proof(result.proof))

    def test_learned_general_recomputes_without_specific_samples(self):
        self.h.set_evidence_confidence_k(5)
        self.h.set_rule_refinement(True)
        self.h._call('set-positive-only-predicate', [f'{self.h.kb} S'])
        self.h._call('set-positive-only-predicate', [f'{self.h.kb} L'])
        self.h.add_atoms_no_check([
            '(: gen (Implication (S a $t) (Win $t)) (STV 0.5 0.01))',
            '(: spec (Implication (And (S a $t) (L b $t)) (Win $t)) (STV 0.5 0.01))',
        ] + [atom for i in range(12) for atom in (
            f'(: s{i} (S a t{i}) (STV 1 1))',
            f'(: l{i} (L {"b" if i < 3 else "c"} t{i}) (STV 1 1))',
            f'(: w{i} (Win t{i}) (STV {int(i < 3)} 1))',
        )] + ['(: sx (S a new) (STV 1 1))', '(: lx (L b new) (STV 1 1))'])
        result = self.answer('(Win new)')
        self.assertIn('specializes', self.h.expand_proof(result.proof))
        self.assertLess(float(result.tv[1]), .99)
        self.assertGreater(float(result.tv[1]), .9)
        self.assertEqual(self.answer('(Win new)').tv, result.tv)

    def test_disagreeing_generals_do_not_gain_revision_confidence(self):
        self.h.set_evidence_confidence_k(1)
        self.h.add_atoms_no_check([
            '(: specific (Implication (And (A $x) (B $x)) (T $x)) (CTV (STV 0.99 0.4) (STV 0.5 0)))',
            '(: ga (Implication (A $x) (T $x)) (CTV (STV 0.1 0.9) (STV 0.5 0)))',
            '(: gb (Implication (B $x) (T $x)) (CTV (STV 0.9 0.9) (STV 0.5 0)))',
            '(: a (A now) (STV 1 1))', '(: b (B now) (STV 1 1))',
        ])
        # V=.169, n_g=.25/.169-1 < 1/kappa, so #69 gives zero weight.
        result = self.answer('(T now)')
        self.assertAlmostEqual(float(result.tv[1]), .99)
        self.assertIn('class-mixture', self.h.expand_proof(result.proof))

    def test_independent_marginal_centre_refreshes_after_set_and_clear(self):
        self.h.set_evidence_confidence_k(1)
        self.h.add_atoms_no_check([
            '(: diagnostic (Implication (A $x) (B $x)) (CTV (STV 0.9 0.9) (STV 0.2 0.9)))',
            '(: observation (B now) (STV 1 1))',
        ])
        self.h._call('set-base-rate', [f'{self.h.kb} (A $x) (STV 0.5 0.5)'])
        neutral = self.answer('(A now)').tv
        self.h._call('set-base-rate', [f'{self.h.kb} (B $x) (STV 0.1 0.9)'])
        weight = 1 / (1/10 + 1/1.2) - 1
        u = (9*.9 + weight*.1) / (9 + weight)
        v = (9*.2 + weight*.1) / (9 + weight)
        centred = self.answer('(A now)')
        self.assertAlmostEqual(float(centred.tv[1]), u/(u+v))
        self.assertNotEqual(centred.tv, neutral)
        self.assertEqual(self.answer('(A now)').tv, centred.tv)
        self.h._call('clear-base-rate', [f'{self.h.kb} (B $x)'])
        self.assertEqual(self.answer('(A now)').tv, neutral)

    def test_computed_centre_excludes_samples_and_current_observation(self):
        self.h.add_atoms_no_check([
            '(: diagnostic (Implication (A $x) (B $x)) (CTV (STV 0.9 0.9) (STV 0.2 0.9)))',
            '(: sample (B training) (STV 1 1))',
            '(: observation (B now) (STV 1 1))',
        ] + [f'(: b{i} (B independent{i}) (STV 0 1))' for i in range(6)])
        self.h._call('set-base-rate', [f'{self.h.kb} (A $x) (STV 0.5 0.5)'])
        self.answer('(A now)')  # subscribe and maintain the incremental B fold
        scope = f'({self.h.kb} MAIN Nil)'
        samples = f'(evidence-set ((fact-ev {scope} sample (B training))))'
        current = f'(evidence-set ((fact-ev {scope} observation (B now))))'
        sources = self.h._call('observation-sources', [f'(evidence-union {samples} {current})'])[0]
        centre = self.formula('sk-computed-centre',
                              f'{self.h.kb} (B $x) {sources} ()')
        self.assertEqual(centre[0], 'STV')
        self.assertEqual(float(centre[1]), 0)
        self.assertAlmostEqual(float(centre[2]), 6/806)

    def test_timed_worker_replays_the_same_prior_settings(self):
        self.h.set_evidence_confidence_k(1)
        self.h.set_bayes_prior_count(.7)
        self.h.add_atoms_no_check([
            '(: diagnostic (WithPrior (Belief $x) (Implication (A $x) (B $x))) (CTV (STV 0.9 0.9) (STV 0.2 0.9)))',
            '(: prior (Belief now) (STV 0 0.5))',
            '(: observation (B now) (STV 1 1))',
        ])
        live = self.h.query('(: $p (A now) $tv)', steps=600, timeout_sec=0)
        timed = self.h.query('(: $p (A now) $tv)', steps=600, timeout_sec=60)
        self.assertEqual([_parse(row)[3] for row in live], [_parse(row)[3] for row in timed])

    def test_bayes_without_branch_provenance_uses_neutral(self):
        for k, expected in ((800, 0.818173783490), (1, 0.811881188119)):
            with self.subTest(k=k):
                self.h.set_evidence_confidence_k(k)
                read = self.h._call('read-likelihoods', ['(CTV (STV 0.9 0.9) (STV 0.2 0.9)) (CTV (STV 0.5 1) (STV 0.5 1)) unknown-support'])[0]
                result = self.formula('CTVBayesFormula', f'(STV 0.5 0.5) {read}')
                self.assertAlmostEqual(float(result[1][1]), expected, places=10)

    def test_leave_one_out_requires_disjoint_branch_sources(self):
        # Source identity/overlap counters are exercised by the native fixtures.
        for k, expected in ((800, .818164159576), (1, .813171080888)):
            with self.subTest(k=k):
                self.h.set_evidence_confidence_k(k)
                centres = self.h._call('likelihood-centres', [
                    f'(CTV (STV 0.9 0.9) (STV 0.2 0.9)) (support-counts 18 9 9 0 0)'])[0]
                self.assertEqual(_parse(centres),
                    ['CTV', ['STV', '0.2', '0.9'], ['STV', '0.9', '0.9']])
                read = self.h._call('read-likelihoods', [
                    f'(CTV (STV 0.9 0.9) (STV 0.2 0.9)) {centres} disjoint'])[0]
                actual = self.formula('CTVBayesFormula', f'(STV 0.5 0.5) {read}')
                self.assertAlmostEqual(float(actual[1][1]), expected, places=10)
                shared = self.formula('likelihood-centres',
                    f'(CTV (STV 0.9 0.9) (STV 0.2 0.9)) (support-counts 9 9 9 0 9)')
                self.assertEqual(shared, ['CTV', ['STV', '0.5', '1'], ['STV', '0.5', '1']])

    def test_original_prior_is_read_once_across_sensors(self):
        self.h.set_evidence_confidence_k(1)
        self.h.add_atoms_no_check([
            '(: one (Implication (Cause $x) (Effect1 $x)) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: two (Implication (Cause $x) (Effect2 $x)) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: prior (Cause now) (STV 0 0.5))',
            '(: first (Effect1 now) (STV 1 1))',
        ])
        self.h._call('set-base-rate', [f'{self.h.kb} (Cause $x) (STV 0.5 0.9)'])
        self.assertAlmostEqual(float(self.answer('(Cause now)').tv[1]), 9/31)
        self.h.add_atom('(: second (Effect2 now) (STV 1 1))')
        self.assertAlmostEqual(float(self.answer('(Cause now)').tv[1]), .648)
        self.assertAlmostEqual(float(self.answer('(Cause now)').tv[1]), .648)

    def test_instance_prior_updates_when_its_excluded_population_is_empty(self):
        self.h.set_evidence_confidence_k(1)
        self.h.add_atoms_no_check([
            '(: diagnostic (Implication (A $x) (B $x)) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: prior (A now) (STV 0 0.5))',
            '(: observation (B now) (STV 1 1))',
        ])
        for _ in range(2):
            self.assertAlmostEqual(float(self.answer('(A now)').tv[1]), 9/31)

    def test_population_prior_leaves_the_target_out(self):
        self.diagnostic(0)
        a = self.answer('(Cause now)')
        self.assertIn('(prior (STV 0.5 0.004975124378109453))', self.h.expand_proof(a.proof))

    def test_stv_withprior_excludes_the_observation_from_its_negative_branch(self):
        self.h.add_atoms_no_check([
            '(: diagnostic (WithPrior (Belief $x) (Implication (A $x) (B $x))) (STV 0.8 0.9))',
            '(: prior (Belief now) (STV 0.3 0.8))',
            '(: observation (B now) (STV 1 1))',
        ])
        self.h._call('set-base-rate', [f'{self.h.kb} (A $x) (STV 0.25 0.9)'])
        p = (.3 * 3200 + .1) / 3200.2
        u = (.8 * 7200 + .1) / 7200.2
        for _ in range(2):
            a = self.answer('(A now)')
            self.assertAlmostEqual(float(a.tv[1]), u*p/(u*p + .5*(1-p)), places=10)
            proof = self.h.expand_proof(a.proof)
            self.assertNotIn('resolved-negative', proof)
            self.assertNotIn('ev-set', proof)

    def test_stv_inversion_does_not_use_its_observation_as_a_marginal(self):
        self.h.add_atoms_no_check([
            '(: diagnostic (Implication (A $x) (B $x)) (STV 0.8 0.9))',
            '(: observation (B now) (STV 1 1))',
        ])
        self.h._call('set-base-rate', [f'{self.h.kb} (A $x) (STV 0.25 0.9)'])
        a = self.answer('(A now)')
        self.assertAlmostEqual(float(a.tv[1]), (.25 * 7200 + .1) / 7200.2)
        self.assertIn('population-prior', self.h.expand_proof(a.proof))

    def test_withprior_uses_the_same_finite_instance_read(self):
        self.h.set_evidence_confidence_k(1)
        self.h.add_atoms_no_check([
            '(: diagnostic (WithPrior (Belief $t) (Implication (Cause $t) (Effect $t))) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: belief (Belief now) (STV 0 0.5))',
            '(: effect (Effect now) (STV 1 1))',
        ])
        self.assertAlmostEqual(float(self.answer('(Cause now)').tv[1]), 9/31)

    def test_learned_branches_pool_only_other_branch_observations(self):
        self.h.set_evidence_confidence_k(1)
        self.h.set_rule_refinement(True)
        self.h._call('set-rule-change-hazard', [f'{self.h.kb} 0'])
        self.h.add_atom('(: diagnostic (Implication (A $t) (B $t)) (CTV (STV 0.5 0) (STV 0.5 0)))')
        atoms = []
        for branch, successes in ((1, 9), (0, 2)):
            for i in range(10):
                atoms += [f'(: a{branch}_{i} (A d{branch}_{i}) (STV {branch} 1))',
                          f'(: b{branch}_{i} (B d{branch}_{i}) (STV {int(i < successes)} 1))']
        self.h.add_atoms_no_check(atoms + ['(: observation (B now) (STV 1 1))'])
        self.h._call('set-base-rate', [f'{self.h.kb} (A $t) (STV 0.5 0.5)'])
        a = self.answer('(A now)')
        # The centre for .9 has only the ten negative-class observations,
        # and conversely for .2. It never includes its own ten observations.
        weight = 1 / (1/11 + 1/1.2) - 1
        u = (9 + weight*.2) / (10 + weight)
        v = (2 + weight*.9) / (10 + weight)
        self.assertAlmostEqual(float(a.tv[1]), u/(u+v), places=7)
        proof = self.h.expand_proof(a.proof)
        self.assertIn('inverted diagnostic', proof)
        for private in ('rule-support', 'likelihood-read', 'ev-set', 'resolved-negative'):
            self.assertNotIn(private, proof)

    def test_branch_support_reference_counts_and_collection(self):
        fold = f'(support-fixture {self.h.kb})'
        one = f'(evidence-set ((fact-ev ({self.h.kb} MAIN Nil) one (Report one))))'
        two = f'(evidence-set ((fact-ev ({self.h.kb} MAIN Nil) two (Report two))))'

        def update(member, evidence, positive, negative):
            sources = self.h._call('observation-sources', [evidence])[0]
            self.h._call('update-likelihood-support!', [f'{fold} {member} {sources} {positive} {negative}'])

        def centres():
            rows = self.h.handler.process_metta_string(
                f'!(likelihood-centres (CTV (STV 0.9 0.9) (STV 0.2 0.9)) (likelihood-support-counts {fold}))')
            self.assertEqual(len(rows), 1)
            return _parse(rows[0])

        neutral = ['CTV', ['STV', '0.5', '1'], ['STV', '0.5', '1']]
        update(1, one, 1, 0)
        update(2, one, 1, 0)
        update(3, one, 0, 1)
        self.assertEqual(centres(), neutral)
        update(1, '(ev-set 0)', 0, 0)
        self.assertEqual(centres(), neutral)  # second sample still shares it
        update(2, '(ev-set 0)', 0, 0)
        update(1, two, 1, 0)
        self.h._call('stored-refs-gc!', [''])
        self.assertEqual(centres(), ['CTV', ['STV', '0.2', '0.9'], ['STV', '0.9', '0.9']])
        update(1, two, 0, 1)  # same sources, changed branch membership
        self.assertEqual(centres(), neutral)
        update(1, two, 1, 0)
        self.assertEqual(centres(), ['CTV', ['STV', '0.2', '0.9'], ['STV', '0.9', '0.9']])
        update(4, '(ev-set 0)', 1, 0)  # active sample without verified support
        self.assertEqual(centres(), neutral)
        update(4, '(ev-set 0)', 0, 0)
        self.assertEqual(centres(), ['CTV', ['STV', '0.2', '0.9'], ['STV', '0.9', '0.9']])

    def test_support_updates_never_intern_population_evidence(self):
        # The old summary interned every growing prefix, retaining O(N²)
        # evidence payload. Source deltas and exclusion reads must intern none.
        result = janus.query_once(
            "_Fold=[support_cost,Kb],"
            "aggregate_all(count,ev_set(_,_,_,_,_),_Before),"
            "forall(between(1,100,_I),"
            "'update-likelihood-support!'(_Fold,_I,"
            "['source-list',[['observation-source',[Kb,'MAIN','Nil'],[report,_I]]]],1,0,_)),"
            "'likelihood-support-counts'(_Fold,Counts),"
            "findall(['observation-source',[Kb,'MAIN','Nil'],[report,_I]],between(1,99,_I),_Excluded),"
            "'likelihood-support-admissible?'(_Fold,['source-list',_Excluded],OneRemains),"
            "'likelihood-support-admissible?'(_Fold,['source-list',"
            "[['observation-source',[Kb,'MAIN','Nil'],[report,100]]|_Excluded]],Drained),"
            "aggregate_all(count,ev_set(_,_,_,_,_),_After),Delta is _After-_Before",
            {'Kb': self.h.kb})
        self.assertEqual(result['Delta'], 0)
        self.assertEqual(result['Counts'], ['support-counts', 100, 100, 0, 0, 0])
        self.assertEqual(result['OneRemains'], 'true')
        self.assertEqual(result['Drained'], 'false')

        # Unverified diagnostics reject pooling, but are not physical keys.
        result = janus.query_once(
            "'observation-keys'(['source-list',['unverified-observation']],Keys),"
            "'update-aggregate-sources!'(-89,[fixture,Kb],['source-list',[]],0,"
            "['source-list',['unverified-observation']],1,_),"
            "aggregate_all(count,'&forward_aggregate_read'(_,-89,[fixture,Kb]),Edges),"
            "'likelihood-support-counts'(['aggregate-support',-89],Counts)", {'Kb': self.h.kb})
        self.assertEqual(result['Keys'], [])
        self.assertEqual(result['Edges'], 0)
        self.assertEqual(result['Counts'], ['support-counts', 1, 1, 0, 1, 0])

    def test_branch_pool_rejects_renamed_repeated_and_unscoped_sources(self):
        fold = f'(physical-fixture {self.h.kb})'

        def update(member, entry, pos, neg):
            sources = self.h._call('observation-sources', [f'(evidence-set ({entry}))'])[0]
            self.h._call('update-likelihood-support!', [
                f'{fold} {member} {sources} {pos} {neg}'])

        def pooled():
            rows = self.h.handler.process_metta_string(
                f'!(likelihood-centres (CTV (STV 0.9 0.9) (STV 0.2 0.9)) (likelihood-support-counts {fold}))')
            self.assertEqual(len(rows), 1)
            return _parse(rows[0])

        scope = f'({self.h.kb} MAIN Nil)'
        neutral = ['CTV', ['STV', '0.5', '1'], ['STV', '0.5', '1']]
        disjoint = ['CTV', ['STV', '0.2', '0.9'], ['STV', '0.9', '0.9']]
        update(1, f'(fact-ev {scope} first (Report one))', 1, 0)
        update(2, f'(not-fact-ev {scope} renamed (Report one))', 0, 1)
        self.assertEqual(pooled(), neutral)
        update(2, f'(fact-ev {scope} other (Report two))', 0, 1)
        self.assertEqual(pooled(), disjoint)
        update(3, f'(fact-ev {scope} alias (Report one))', 1, 0)
        self.assertEqual(pooled(), neutral)
        update(3, '', 0, 0)
        self.assertEqual(pooled(), disjoint)
        update(3, '(mystery report)', 1, 0)
        self.assertEqual(pooled(), neutral)
        update(3, '', 0, 0)
        self.assertEqual(pooled(), disjoint)

    def test_certain_complement_likelihood_certifies_zero(self):
        self.h.add_atoms_no_check([
            '(: diagnostic (Implication (A $x) (B $x)) (CTV (STV 1 1) (STV 0.2 1)))',
            '(: prior (A now) (STV 0.3 0.8))',
            '(: observation (B now) (STV 0 1))',
        ])
        self.h._call('set-base-rate', [f'{self.h.kb} (A $x) (STV 0.5 0.9)'])
        for _ in range(2):
            self.assertEqual(float(self.answer('(A now)').tv[1]), 0)

    def test_complete_loop_preserves_its_logical_zero(self):
        for head in ('B', 'D'):
            self.h._call('set-complete-predicate', [f'{self.h.kb} {head}'])
        self.h.add_atoms_no_check([
            '(: rB (Implication (Or (A $x) (D $x)) (B $x)) (CTV (STV 0.47 1) (STV 0 1)))',
            '(: rD (Implication (Or (A $x) (B $x)) (D $x)) (CTV (STV 1 1) (STV 0 1)))',
            '(: observed (D now) (STV 0 1))',
        ])
        for head, strength in (('A', .18), ('B', .0846), ('D', .18)):
            self.h._call('set-base-rate', [f'{self.h.kb} ({head} $x) (STV {strength} 1)'])
        for _ in range(2):
            self.assertEqual(float(self.answer('(A now)').tv[1]), 0)

    def test_zero_weight_unknown_and_certain_inputs(self):
        self.h.set_bayes_prior_count(0)
        self.assertEqual(float(self.formula('bayes-shrink', '0.3 0.5 0.5 1')), 0.3)
        self.assertEqual(float(self.formula('bayes-shrink', '0.9 0 0.1 0')), 0.5)
        for strength in (0, 1):
            self.assertEqual(float(self.formula('population-prior-tv',
                f'(STV {strength} 1)')[1]), strength)
        read = self.h._call('read-likelihoods', ['(CTV (STV 0.9 0.9) (STV 0.2 0.9)) (CTV (STV 0.5 1) (STV 0.5 1)) unknown-support'])[0]
        result = self.formula('CTVBayesFormula', f'(STV 0.5 0.5) {read}')
        self.assertAlmostEqual(float(result[1][1]), 9/11)

    def bridge(self, observation=None, judgment=False):
        self.h = PeTTaChainer()
        atoms = [
            '(: bridge (Implication (And (StockSplit $e) (Implemented $e)) (PreservesOwnership $e)) (STV 0.8 0.9))',
            '(: split (StockSplit Split1) (STV 0.7 0.9))',
        ]
        if not judgment:
            atoms.append('(: impl (Implemented Split1) (STV 1 1))')
        if observation:
            member, value = observation
            atoms.append(f'(: observed (PreservesOwnership {member}) (STV {value} 1))')
        self.h.add_atoms_no_check(atoms)
        goal = '(PreservesOwnership Split1)'
        if judgment:
            goal = '(Implication (Implemented Split1) (PreservesOwnership Split1))'
        cold = self.answer(goal)
        self.assertEqual(self.answer(goal).tv, cold.tv)
        return cold

    def test_one_other_member_is_a_weak_negative_branch_estimate(self):
        for observation, expected in ((None, 0.71), (('Split2', 1), 0.747843362516),
                                      (('Split2', 0), 0.672156693757)):
            with self.subTest(observation=observation):
                result = self.bridge(observation)
                self.assertAlmostEqual(float(result.tv[1]), expected, places=8)
                self.assertLess(float(result.tv[2]), 0.02)

    def test_private_judgment_keeps_83_consequent_exclusion(self):
        for observation in (None, ('Split1', 0), ('Split1', 1),
                            ('Split2', 0), ('Split2', 1)):
            with self.subTest(observation=observation):
                result = self.bridge(observation, judgment=True)
                self.assertAlmostEqual(float(result.tv[1]), 0.71)


if __name__ == '__main__':
    unittest.main()
