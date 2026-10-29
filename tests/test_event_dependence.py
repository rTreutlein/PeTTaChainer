"""E3's source roles, shared parents and same-KB source lifecycle."""
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer
from tests.test_tv_calibration import kb_atoms
from tests.tv_calibration_oracles import SETTINGS, event_oracle, probes, variance_ratio


class EventDependenceTests(unittest.TestCase):
    def load(self, model):
        h = PeTTaChainer()
        facts, compounds = kb_atoms(model)
        h.add_atoms_no_check(facts + compounds)
        return h

    def calibrated(self, h, model):
        expected = event_oracle(model)
        values = []
        for goal in model['goals']:
            rows = h.query_many_refs([f'(: $p {goal} $tv)'], steps=1000)[0]
            self.assertEqual(len(rows), 1)
            tv = rows[0].tv
            self.assertAlmostEqual(tv[1], expected[goal]['s'], delta=1e-12)
            self.assertTrue(.5 <= variance_ratio(*tv[1:], expected[goal]) <= 2, (tv, expected[goal]))
            values.append(tv)
        return values

    def test_two_children_share_the_parent_inside_the_likelihood(self):
        m = probes(*SETTINGS['H'])['P4']
        # These are two observations, not new marginal parameters for A/B.
        m['comps'] += [('(A a)', lambda w: w['A'], .7, .9),
                       ('(B a)', lambda w: w['B'], .3, .9)]
        self.calibrated(self.load(m), m)

    def test_a_late_raw_child_report_wakes_the_parent(self):
        m = probes(*SETTINGS['H'])['P3']
        h = self.load(m)
        before = self.calibrated(h, m)
        h.add_atoms_no_check(['(: late (B a) (STV 0.75 0.9))'])
        m['comps'] += [('(B a)', lambda w: w['B'], .75, .9)]
        after = self.calibrated(h, m)
        self.assertNotEqual(after, before)
        self.assertEqual(self.calibrated(h, m), after)

    def test_forward_copies_are_never_observations(self):
        m = probes(*SETTINGS['H'])['P3']
        h = self.load(m)
        before = self.calibrated(h, m)
        h.forward_chain(h.select_facts(['(A a)', '(Or (A a) (B a))']), steps=1000)
        self.assertEqual(self.calibrated(h, m), before)
        self.assertEqual(self.calibrated(h, m), before)

    def test_a_zero_confidence_source_is_absent_from_a_warm_node(self):
        m = probes(*SETTINGS['H'])['P3']
        h = self.load(m)
        before = self.calibrated(h, m)
        h.add_atoms_no_check(['(: unknown (B a) (STV 0.01 0))'])
        self.assertEqual(self.calibrated(h, m), before)


class EventReviewRegressionTests(unittest.TestCase):
    load = EventDependenceTests.load
    calibrated = EventDependenceTests.calibrated
    # Native reads deliberately keep the current evaluation and its caches alive.
    def graph_read(self, h, goal='A'):
        result = janus.query_once(
            "'event-network-read'(['sk-key',[Goal,a],[Kb,'MAIN','Nil']],"
            " 'sk-any-filter',[],['ev-set',0],fallback,_Out),copy_term(_Out,Out),"
            "term_variables(Out,_Vars),maplist(=(test_variable),_Vars)", {'Kb': h.kb, 'Goal': goal})
        self.assertTrue(result['truth'])
        return result['Out']

    def test_observed_external_child_is_in_the_joint_model(self):
        h = self.load(probes(*SETTINGS['H'])['P3'])
        h.add_atoms_no_check([
            '(: rD (Implication (A $x) (D $x)) (CTV (STV 1 1) (STV 0 1)))',
            '(: d (D a) (STV 1 1))',
        ])
        row, = h.query_many_refs(['(: $p (A a) $tv)'], steps=1000)[0]
        self.assertEqual(row.tv[1:], [1.0, .9999])
        out = self.graph_read(h)
        self.assertNotEqual(out, 'fallback')
        self.assertEqual(out[1][3], ['STV', 1.0, .9999])

    def test_configured_zero_root_prior_is_not_uniform(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: rB (Implication (A $x) (B $x)) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: k0 (Or (A a) (B a)) (STV 1 1))',
        ])
        h._call('set-base-rate', [f'{h.kb} (A $x) (STV 0 1)'])
        row, = h.query_many_refs(['(: $p (A a) $tv)'], steps=1000)[0]
        self.assertEqual(row.tv[1:], [0.0, .9999])
        self.assertEqual(self.graph_read(h)[1][3], ['STV', 0.0, .9999])
        self.assertIn('population-prior', h.expand_proof(row.proof))

    def test_empirical_root_prior_matches_the_cavity_reader(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: f1 (A b) (STV 0.2 0.9))',
            '(: f2 (A c) (STV 0.4 0.9))',
            '(: rB (Implication (A $x) (B $x)) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: k0 (Or (A a) (B a)) (STV 1 1))',
        ])
        h.query_many_refs(['(: $p (A a) $tv)'], steps=1000)
        out = self.graph_read(h)
        self.assertNotEqual(out, 'fallback')
        prior = janus.query_once(
            "'sk-part-prior'(['sk-key',['A',a],[Kb,'MAIN','Nil']],['ev-set',0],[],"
            " ['sk-val',[_,_,_,['STV',_S,_C]],_,_]),"
            " event_node:event_node_dist(stored,_S,_C,800,_D),event_node:dist_mean(_D,M)", {'Kb': h.kb})
        self.assertTrue(prior['truth'])
        mu = prior['M']
        self.assertAlmostEqual(out[1][3][1], mu / (mu + .2 * (1 - mu)), delta=1e-12)

    def test_population_prior_excludes_the_consumers_evidence(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: f1 (A b) (STV 0.2 0.9))',
            '(: f2 (A c) (STV 0.4 0.9))',
            '(: rB (Implication (A $x) (B $x)) (CTV (STV 0.9 1) (STV 0.2 1)))',
            '(: k0 (Or (A a) (B a)) (STV 1 1))',
        ])
        h.query_many_refs(['(: $p (A a) $tv)'], steps=1000)
        result = janus.query_once(
            "_Scope=[Kb,'MAIN','Nil'],_Key=['sk-key',['A',a],_Scope],"
            " 'leaf-evidence-for-result'([['A',b],_Scope,f1,['STV',0.2,0.9]],_Ev),"
            " 'event-network-read'(_Key,'sk-any-filter',[],_Ev,fallback,"
            " ['sk-val',[_,_,_,['STV',S,_]],_,_]),"
            " 'sk-part-prior'(_Key,_Ev,[],['sk-val',[_,_,_,['STV',_PS,_PC]],_,_]),"
            " event_node:event_node_dist(stored,_PS,_PC,800,_D),event_node:dist_mean(_D,M)",
            {'Kb': h.kb})
        self.assertTrue(result['truth'])
        self.assertAlmostEqual(result['S'], result['M'] / (result['M'] + .2 * (1 - result['M'])), delta=1e-12)

    def test_raw_report_invalidates_plan_without_a_new_row_or_evaluation(self):
        m = probes(*SETTINGS['H'])['P3']
        h = self.load(m)
        self.calibrated(h, m)
        before = self.graph_read(h)
        generation = janus.query_once("'search-id-value'(sk_row_seq,N)")['N']
        h.add_atoms_no_check(['(: late (B a) (STV 0.75 0.9))'])
        self.assertEqual(janus.query_once("'search-id-value'(sk_row_seq,N)")['N'], generation)
        after = self.graph_read(h)
        self.assertNotEqual(after, 'fallback')
        self.assertNotEqual(before[1][3], after[1][3])
        m['comps'] += [('(B a)', lambda w: w['B'], .75, .9)]
        self.assertAlmostEqual(after[1][3][1], event_oracle(m)['(A a)']['s'], delta=1e-12)

    def test_first_compound_invalidates_unavailable_scope_within_evaluation(self):
        h = PeTTaChainer()
        facts, compounds = kb_atoms(probes(*SETTINGS['H'])['P3'])
        h.add_atoms_no_check(facts)
        # The compound key itself needs no rows for template discovery.
        read = ("Key=['sk-key',['Or',['A',a],['B',a]],[Kb,'MAIN','Nil']],"
                " 'event-network-read'(Key,'sk-any-filter',[],['ev-set',0],fallback,Out)")
        before = janus.query_once(read, {'Kb': h.kb})
        self.assertEqual(before['Out'], 'fallback')
        h.add_atoms_no_check(compounds)
        after = janus.query_once(read, {'Kb': h.kb})
        self.assertNotEqual(after['Out'], 'fallback')
        # Adding actual admitted rows must also invalidate a cached plan.
        old = janus.query_once("'search-id-value'(sk_row_seq,N)")['N']
        h._call('change-state!', ['sk_budget 1000', 'sk_row_budget 1000', 'sk_walk_budget 1000'])
        h._call('sk-walk!', [f'(((A a) ({h.kb} MAIN Nil) $p $tv))'])
        new = janus.query_once("'search-id-value'(sk_row_seq,N)")['N']
        self.assertGreater(new, old)
        self.assertNotEqual(janus.query_once(read, {'Kb': h.kb})['Out'], 'fallback')
        generations = janus.query_once(
            "findall([_E,_R],event_graph_plan(_,main,_E-_R,['sk-key',['Or',['A',a],['B',a]],[Kb,'MAIN','Nil']],_),Gs)",
            {'Kb': h.kb})['Gs']
        self.assertGreaterEqual(len(generations), 2)

    def test_an_stv_producer_forces_the_whole_graph_to_fall_back(self):
        h = self.load(probes(*SETTINGS['H'])['P3'])
        h.add_atoms_no_check([
            '(: d (D a) (STV 1 1))',
            '(: extra (Implication (D $x) (B $x)) (STV 0.8 0.9))',
        ])
        h.query_many_refs(['(: $p (B a) $tv)'], steps=1000)
        self.assertEqual(self.graph_read(h, 'B'), 'fallback')

    def test_compatible_read_keeps_the_raw_report_excluding_k0(self):
        h = self.load(probes(*SETTINGS['H'])['P3'])
        h.add_atoms_no_check(['(: raw (B a) (STV 0.75 0.9))'])
        h.query_many_refs(['(: $p (B a) $tv)'], steps=1000)
        result = janus.query_once(
            "Scope=[Kb,'MAIN','Nil'],Key=['sk-key',['B',a],Scope],"
            " 'leaf-evidence-for-result'([['Or',['A',a],['B',a]],Scope,k0,['STV',1.0,0.9]],Ev),"
            " 'sk-compatible-value'([],Key,'sk-any-filter',[],Ev,true,"
            " ['sk-val',[_,_,_,TV],Actual,_]),"
            " 'premise-evidence-overlap?'(Ev,Actual,Overlap)", {'Kb': h.kb})
        self.assertTrue(result['truth'])
        self.assertEqual(result['Overlap'], 'false')
        self.assertEqual(result['TV'], ['STV', .75, .9])

    def test_compatible_reads_honour_proof_and_tv_filters(self):
        h = self.load(probes(*SETTINGS['H'])['P3'])
        h.add_atoms_no_check(['(: raw (B a) (STV 0.75 0.9))'])
        h.query_many_refs(['(: $p (B a) $tv)'], steps=1000)
        for pattern in ("['sk-filter',raw,_]", "['sk-filter',_,['STV',0.75,0.9]]"):
            with self.subTest(pattern=pattern):
                result = janus.query_once(
                    "Key=['sk-key',['B',a],[Kb,'MAIN','Nil']],"
                    f" 'sk-compatible-value'([],Key,{pattern},[],['ev-set',0],true,"
                    " ['sk-val',[_,_,_,TV],_,_])", {'Kb': h.kb})
                self.assertTrue(result['truth'])
                self.assertEqual(result['TV'], ['STV', .75, .9])
