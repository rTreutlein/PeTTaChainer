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

    def test_late_prior_equals_fresh(self):
        self.diagnostic(0.001)
        fresh = self.answer('(Cause now)').tv
        self.diagnostic()
        self.answer('(Cause now)')
        self.h.add_atom('(: prior (Cause now) (STV 0.001 0.5))')
        for _ in range(2):
            self.assertEqual(self.answer('(Cause now)').tv, fresh)

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

    def test_left_out_contributions_do_not_depend_on_the_kb_name(self):
        # Fractional contributions subtracted in hash order changed the last
        # bits of the centre with the KB's name (supplynet soft reports).
        strengths = [0.13, 0.37, 0.71, 0.29, 0.83, 0.07, 0.61, 0.47, 0.93, 0.19, 0.53, 0.41]

        def centre(name):
            self.h = PeTTaChainer()
            self.h.kb = name
            self.h.add_atoms_no_check(
                ['(: diagnostic (Implication (A $x) (B $x)) (CTV (STV 0.9 0.9) (STV 0.2 0.9)))']
                + [f'(: b{i} (B x{i}) (STV {s} 0.9))' for i, s in enumerate(strengths)]
                + [f'(: c{i} (B y{i}) (STV {s} 0.7))' for i, s in enumerate(strengths)])
            self.h._call('set-base-rate', [f'{name} (A $x) (STV 0.5 0.5)'])
            self.answer('(A now)')  # subscribe and maintain the incremental B fold
            facts = ' '.join(f'(fact-ev ({name} MAIN Nil) b{i} (B x{i}))' for i in range(len(strengths)))
            sources = self.h._call('observation-sources', [f'(evidence-set ({facts}))'])[0]
            tv = self.formula('sk-computed-centre', f'{name} (B $x) {sources} ()')
            return [float(value).hex() for value in tv[1:]]

        # These names gave three different centres before the order was fixed.
        self.assertEqual(centre('kbleftouta'), centre('kbleftoutb'))
        self.assertEqual(centre('kbleftouta'), centre('kbleftoutf'))

    def test_excluding_one_membership_removes_the_whole_centre_member(self):
        # A two-membership sample has two sources but only one contribution.
        # With no remaining member, a synthetic concept prior cannot certify
        # an empirical centre even though distinct sources minus hits is one.
        self.h.add_atom('(: node (Inheritance seed concept) (STV 1 1))')
        result = janus.query_once("""
            _Ctx=[Kb,'MAIN','Nil'],
            _Left=[['Member',only,left],_Ctx,left,['STV',1,1]],
            _Right=[['Member',only,right],_Ctx,right,['STV',1,1]],
            _Value=['forward-member-inheritance-observation-value',
                ['forward-derived',_Left,['ev-set',0]],
                ['forward-derived',_Right,['ev-set',0]]],
            'fa-observation-sources'(_Left,_Value,_Sources),
            'base-rate-premises'(Kb,['Inheritance',_X,concept],_,[_Goal]),
            'fa-premise-subscriptions'(_Goal,
                [['fa-subscription',_Identity,_Descriptor,_Triggers]]),
            'fa-register!'(_Identity,_Descriptor,_Triggers,_),
            'fa-id'(_Identity,_Id),
            'fa-swap!'(_Id,[],
                ['forward-aggregate-observation',[_Id,only],_Value,1,1],true,_Sources,_),
            'likelihood-support-counts'(['aggregate-support',_Id],Counts),
            findall(_TV,'sk-computed-centre'(Kb,['Inheritance',_X,concept],
                ['source-list',[]],[],_TV),Before),
            _Sources=['source-list',_List],
            findall(_After,(member(_Source,_List),
                findall(_TV2,'sk-computed-centre'(Kb,['Inheritance',_X,concept],
                    ['source-list',[_Source]],[],_TV2),_After)),After)
        """, {'Kb': self.h.kb})
        self.assertEqual(result['Counts'], ['support-counts', 2, 2, 0, 0, 0])
        self.assertEqual(len(result['Before']), 1)
        self.assertEqual(result['After'], [[], []])

    def test_closed_likelihood_priority_uses_the_runtime_read(self):
        self.h.set_evidence_confidence_k(1)
        self.h._call('set-base-rate', [f'{self.h.kb} (B $x) (STV 0.1 0.9)'])
        raw = '(CTV (STV 0.9 0.9) (STV 0.2 0.9))'
        candidate = f'(likelihood-read {raw} {raw} (stated {raw}))'
        context = '(likelihood-context () (ev-set 0))'
        args = f'{self.h.kb} authored (A $x) (B $x) {candidate} {context}'
        runtime = self.formula('rule-likelihood-read', args)
        expected = self.formula('cpu-expected-tv', f'rule-likelihood-read ({args})')
        self.assertEqual(expected, runtime)
        weight = 1 / (1/10 + 1/1.2) - 1
        self.assertAlmostEqual(float(expected[2][1][1]), (9*.9 + weight*.1)/(9+weight))

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

    def test_physical_sources_share_identity_and_survive_collection(self):
        result = janus.query_once(
            "flag(ev_next_entry,EvidenceBefore,EvidenceBefore),"
            "'observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],one,[report,a]],A),"
            "'observation-sources'(['not-fact-ev',[Kb,'MAIN','Nil'],renamed,[report,a]],B),"
            "'update-likelihood-support!'([source_identity,Kb],1,A,1,0,_),"
            "'update-likelihood-support!'([source_identity,Kb],2,B,1,0,_),"
            "'stored-refs-gc!'(_),garbage_collect_atoms,"
            "'observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],third,[report,a]],C),"
            "(A==B,B==C -> Shared=true;Shared=false),"
            "'likelihood-support-counts'([source_identity,Kb],Counts),"
            "aggregate_all(count,support_identity(_,_,['sk-key',[report,a],[Kb,'MAIN','Nil']]),Entries),"
            "flag(ev_next_entry,EvidenceAfter,EvidenceAfter)",
            {'Kb': self.h.kb})
        self.assertEqual(result['Shared'], 'true')
        self.assertEqual(result['Counts'], ['support-counts', 1, 1, 0, 1, 0])
        self.assertEqual(result['Entries'], 1)
        self.assertEqual(result['EvidenceBefore'], result['EvidenceAfter'])

    def test_physical_source_interning_checks_hash_collisions(self):
        result = janus.query_once(
            "_Key=['sk-key',[report,a],[Kb,'MAIN','Nil']], 'index-hash'(_Key,_Hash),"
            "flag(support_next_identity,_Before,_Before+1),Fake is _Before+1,"
            "setup_call_cleanup(assertz(support_identity(Fake,_Hash,['sk-key',[report,b],[Kb,'MAIN','Nil']]),_Ref),"
            "('observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],one,[report,a]],A),"
            " 'observation-sources'(['not-fact-ev',[Kb,'MAIN','Nil'],two,[report,a]],B),"
            " A=['source-list',[Actual]],(A==B -> Stable=true;Stable=false),"
            " 'observation-keys'(A,Keys),Hash=_Hash),erase(_Ref))", {'Kb': self.h.kb})
        self.assertNotEqual(result['Actual'], result['Fake'])
        self.assertEqual(result['Stable'], 'true')
        self.assertEqual(result['Keys'], [result['Hash']])

    def test_support_identities_follow_context_lifetime_and_main_promotion(self):
        result = janus.query_once(
            "support_identity_id(['sk-key',[main,Kb],[Kb,'MAIN','Nil']],Main),"
            "setup_call_cleanup(nb_setval(context_overlay,identity_fixture),"
            "(support_identity_id(['sk-key',[main,Kb],[Kb,'MAIN','Nil']],Borrowed),"
            " support_identity_id(['sk-key',[local,Kb],[Kb,identity_fixture,'Nil']],Local),"
            " support_identity_id(['aggregate-reader',-9002,[reader,Kb]],Promoted)),"
            "nb_setval(context_overlay,main)),"
            "support_identity_id(['aggregate-reader',-9002,[reader,Kb]],MainReader),"
            "'context-clear!'(_),"
            "(support_identity(Main,_,_),support_identity(Promoted,_,_) -> Kept=true;Kept=false),"
            "(support_identity(Local,_,_)->Leaked=true;Leaked=false),"
            "aggregate_all(count,support_identity_owner(_),Owners),"
            "support_identity_id(['sk-key',[local,Kb],[Kb,identity_fixture,'Nil']],Replacement)",
            {'Kb': self.h.kb})
        self.assertEqual(result['Borrowed'], result['Main'])
        self.assertEqual(result['MainReader'], result['Promoted'])
        self.assertEqual(result['Kept'], 'true')
        self.assertEqual(result['Leaked'], 'false')
        self.assertEqual(result['Owners'], 0)
        self.assertNotEqual(result['Replacement'], result['Local'])

    def test_main_support_write_promotes_a_context_created_source(self):
        result = janus.query_once(
            "setup_call_cleanup(nb_setval(context_overlay,source_fixture),"
            "'observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],one,[retained,a]],Sources),"
            "nb_setval(context_overlay,main)),"
            "'observation-keys'(Sources,Before),"
            "'update-likelihood-support!'([retained_source,Kb],1,Sources,1,0,_),"
            "'context-clear!'(_),'observation-keys'(Sources,After),"
            "'observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],two,[retained,a]],Again),"
            "(Sources==Again -> Stable=true;Stable=false),"
            "'likelihood-support-counts'([retained_source,Kb],Counts)",
            {'Kb': self.h.kb})
        self.assertEqual(result['After'], result['Before'])
        self.assertEqual(result['Stable'], 'true')
        self.assertEqual(result['Counts'], ['support-counts', 1, 1, 0, 0, 0])

    def test_forward_reverse_edges_keep_unchanged_clause_identity(self):
        result = janus.query_once(
            "_Key=[reader,Kb],"
            "'observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],a,[report,a]],A),"
            "'observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],b,[report,b]],B),"
            "'source-list-union'(A,B,AB),"
            "'observation-keys'(A,[_HA]),'observation-keys'(B,[_HB]),"
            "'update-aggregate-sources!'(-9001,_Key,['source-list',[]],0,A,1,_),"
            "clause('&forward_aggregate_read'(_HA,-9001,_Reader),true,_RefA),"
            "'update-aggregate-sources!'(-9001,_Key,A,1,A,0,_),"
            "'update-aggregate-sources!'(-9001,_Key,A,0,AB,1,_),"
            "clause('&forward_aggregate_read'(_HA,-9001,_Reader),true,_StillA),"
            "(_RefA==_StillA -> KeptA=true;KeptA=false),"
            "clause('&forward_aggregate_read'(_HB,-9001,_Reader),true,_RefB),"
            "'update-aggregate-sources!'(-9001,_Key,AB,1,B,1,_),"
            "clause('&forward_aggregate_read'(_HB,-9001,_Reader),true,_StillB),"
            "(_RefB==_StillB -> KeptB=true;KeptB=false),"
            "'aggregate-readers'(-9001,_HA,Removed),"
            "'aggregate-readers'(-9001,_HB,Remaining),"
            "'update-aggregate-sources!'(-9001,_Key,B,1,['source-list',[]],0,_),"
            "'aggregate-readers'(-9001,_HB,Drained)", {'Kb': self.h.kb})
        self.assertEqual((result['KeptA'], result['KeptB']), ('true', 'true'))
        self.assertEqual(result['Removed'], [])
        self.assertEqual(result['Remaining'], [['reader', self.h.kb]])
        self.assertEqual(result['Drained'], [])

    def test_support_updates_never_intern_population_evidence(self):
        # The old summary interned every growing prefix, retaining O(N²)
        # evidence payload. Source deltas and exclusion reads must intern none.
        result = janus.query_once(
            "_Fold=[support_cost,Kb],"
            "aggregate_all(count,ev_set(_,_,_,_,_),_Before),"
            "forall(between(1,100,_I),"
            "('observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],sample,[report,_I]],_Sources),"
            "'update-likelihood-support!'(_Fold,_I,_Sources,1,0,_))),"
            "'likelihood-support-counts'(_Fold,Counts),"
            "findall(_Source,(between(1,99,_I),"
            "'observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],sample,[report,_I]],['source-list',[_Source]])),_Excluded),"
            "'likelihood-support-admissible?'(_Fold,['source-list',_Excluded],OneRemains),"
            "'observation-sources'(['fact-ev',[Kb,'MAIN','Nil'],sample,[report,100]],['source-list',[_Last]]),"
            "'likelihood-support-admissible?'(_Fold,['source-list',[_Last|_Excluded]],Drained),"
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
            "aggregate_all(count,'&forward_aggregate_read'(_,-89,_),Edges),"
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
        # The unknown branch's mass 0.3 costs 0.3^2/12 of variance.
        for observation, expected in ((None, 0.71), (('Split2', 1), 0.747843362516),
                                      (('Split2', 0), 0.672156693757)):
            with self.subTest(observation=observation):
                result = self.bridge(observation)
                self.assertAlmostEqual(float(result.tv[1]), expected, places=8)
                self.assertLess(float(result.tv[2]), 0.04)

    def test_private_judgment_keeps_83_consequent_exclusion(self):
        for observation in (None, ('Split1', 0), ('Split1', 1),
                            ('Split2', 0), ('Split2', 1)):
            with self.subTest(observation=observation):
                result = self.bridge(observation, judgment=True)
                # The judgment's instance fold carries ~1e-3 observations of
                # the instance's own consequent (~6e-7 while a zero-evidence
                # value had the Bernoulli variance); it moves the value by at
                # most 2e-5.
                self.assertAlmostEqual(float(result.tv[1]), 0.71, places=4)


if __name__ == '__main__':
    unittest.main()
