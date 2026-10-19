"""Reports update independent predictions by odds, after corroboration (#103)."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer


class SoftReportTests(unittest.TestCase):
    def test_endpoint_confidence_is_the_revised_reports_confidence(self):
        for strength in (0, 1):
            with self.subTest(strength=strength):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: cause (C a) (STV 1 1))',
                    f'(: cp (Implication (C a) (P a)) (CTV (STV {strength} 0.8) (STV {1-strength} 1)))',
                ])
                query = ['(: $p (P a) $tv)']
                prior = h.query_many_refs(query, steps=3000)[0][0]
                self.assertEqual(prior.tv[1], strength)
                self.assertAlmostEqual(prior.tv[2], .8, delta=1e-3)
                h.add_atoms_no_check([f'(: report (P a) (STV {strength} 0.8))'])
                answer = h.query_many_refs(query, steps=3000)[0][0]
                self.assertEqual(answer.tv[1], strength)
                self.assertGreaterEqual(answer.tv[2], max(prior.tv[2], .8))
                self.assertAlmostEqual(answer.tv[2], .8, delta=1e-12)
                h.add_atoms_no_check([f'(: other-report (P a) (STV {strength} 0.5))'])
                corroborated = h.query_many_refs(query, steps=3000)[0][0]
                self.assertEqual(corroborated.tv[1], strength)
                self.assertAlmostEqual(corroborated.tv[2], 5 / 6, delta=1e-12)

    def test_endpoint_update_keeps_prediction_evidence_and_dependencies(self):
        for strength in (0, 1):
            with self.subTest(strength=strength):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: cause (C a) (STV 1 0.8))',
                    f'(: cp (Implication (C a) (P a)) (CTV (STV {strength} 1) (STV {strength} 1)))',
                ])
                query = ['(: $p (P a) $tv)']
                h.query_many_refs(query, steps=3000)
                before = janus.query_once(
                    "'sk-value'(['sk-key',['P',a],[Kb,'MAIN','Nil']], 'sk-any-filter', [], "
                    "['sk-val',_,Ev,Deps])", {'Kb': h.kb})
                h.add_atoms_no_check([f'(: report (P a) (STV {strength} 0.8))'])
                answer = h.query_many_refs(query, steps=3000)[0][0]
                after = janus.query_once(
                    "'sk-value'(['sk-key',['P',a],[Kb,'MAIN','Nil']], 'sk-any-filter', [], "
                    "['sk-val',_,Ev,Deps]), 'evidence-subset?'(BeforeEv,Ev,EvidenceKept), "
                    "'deps-within?'(BeforeDeps,Deps,DependenciesKept), 'evidence-entries'(Ev,Entries)",
                    {'Kb': h.kb, 'BeforeEv': before['Ev'], 'BeforeDeps': before['Deps']})
                self.assertEqual(after['EvidenceKept'], 'true')
                self.assertEqual(after['DependenciesKept'], 'true')
                for source, statement in (('cause', ['C', 'a']), ('report', ['P', 'a'])):
                    self.assertIn(['fact-ev', [h.kb, 'MAIN', 'Nil'], source, statement], after['Entries'])
                self.assertIn('(by cp cause)', h.expand_proof(answer.proof))

    def test_stored_cut_excludes_a_prediction_sharing_branch_evidence(self):
        h = PeTTaChainer()
        h.set_bayes_prior_count(0)
        self.addCleanup(h.set_bayes_prior_count, .2)
        h.add_atoms_no_check([
            '(: report (P a) (STV 0.6 0.5))',
            '(: forecast (F a) (STV 0.9 0.9))',
            '(: fp (Implication (F a) (P a)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            '(: pa (Implication (P a) (A a)) (CTV (STV 0.8 1) (STV 0.1 1)))',
            '(: root (Implication (And (A a) (F a)) (T a)) (CTV (STV 1 1) (STV 0 1)))',
        ])
        rows = h.query_many_refs(['(: $p (P a) $tv)', '(: $p (T a) $tv)'], steps=20000)
        self.assertNotAlmostEqual(rows[0][0].tv[1], .6)
        result = janus.query_once(
            "Scope=[Kb,'MAIN','Nil'], Pin=['sk-key',['P',a],Scope], "
            "Key=['sk-key',['T',a],Scope], 'index-hash'(Pin,PH), 'index-hash'(Key,H), "
            "Target=['sk-key-target',H,Key,'sk-any-filter',[]], "
            "'change-state!'(sk_eval_budget,20000,_), 'change-state!'(sk_claim_depth,64,_), "
            "setup_call_cleanup('sk-open-claim!'(_), ("
            "'sk-target-value'([['sk-given',PH,Pin,true]],Target,['sk-val',[_,_,_,['STV',Yes,_]],YE,_]), "
            "'sk-target-value'([['sk-given',PH,Pin,false]],Target,['sk-val',[_,_,_,['STV',No,_]],NE,_]), "
            "'evidence-union'(YE,NE,Branch), 'evidence-negated'(Branch,Negative), "
            "'evidence-union'(Branch,Negative,Both), "
            "'sk-compatible-value'([],Pin,'sk-any-filter',[],Both,[],true, "
            " ['sk-val',[_,_,_,['STV',Weight,_]],_,_]), "
            "'sk-mix-on'([],Target,[],[Pin],[['sk-val',[_,_,_,['STV',Mixed,_]],_,_]])), "
            "'sk-close-claim!'(_))", {'Kb': h.kb})
        self.assertTrue(result['truth'])
        self.assertAlmostEqual(result['Weight'], .6, delta=1e-12)
        self.assertNotAlmostEqual(result['Yes'], result['No'])
        self.assertAlmostEqual(result['Mixed'], .6 * result['Yes'] + .4 * result['No'], delta=1e-12)

    def model(self, confidence, strength=1):
        h = PeTTaChainer()
        h.set_evidence_confidence_k(5)
        self.addCleanup(h.set_evidence_confidence_k, 800)
        h.add_atoms_no_check([
            '(: w (W a) (STV 1 1))',
            '(: wz (Implication (W a) (Z a)) (CTV (STV 0.5 1) (STV 0.5 1)))',
            '(: zp (Implication (Z a) (P a)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            f'(: report (P a) (STV {strength} {confidence}))',
            '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.3 1)))',
        ])
        return h

    def test_direct_consequence_and_inversion_agree_with_forward(self):
        queries = [f'(: $p ({name} a) $tv)' for name in ('P', 'Q', 'Z')]
        for c in (.5, .9, .99, 1):
            for strength in (0, .3, 1):
                answers = []
                for forward in (False, True):
                    with self.subTest(confidence=c, strength=strength, forward=forward):
                        h = self.model(c, strength)
                        if forward:
                            h.forward_chain(h.select_facts(['(W a)', '(P a)']), steps=3000)
                        rows = h.query_many_refs(queries, steps=3000)
                        self.assertEqual([len(row) for row in rows], [1, 1, 1])
                        values = [row[0].tv[1] for row in rows]
                        self.assertAlmostEqual(values[0], strength, delta=1e-12)
                        self.assertGreater(rows[0][0].tv[2], 0)
                        self.assertAlmostEqual(values[1], .3 + .5 * strength, delta=1e-12)
                        self.assertAlmostEqual(values[2], .1 + .8 * strength, delta=1e-12)
                        if c < 1:
                            self.assertIn('factored-revision', h.expand_proof(rows[0][0].proof))
                        answers.append(values)
                if len(answers) == 2:
                    for backward, forward in zip(*answers):
                        self.assertAlmostEqual(backward, forward, delta=1e-12)

    def test_late_observation_replaces_a_warm_prediction(self):
        for forward in (False, True):
            with self.subTest(forward=forward):
                h = self.model(0)
                if forward:
                    h.forward_chain(h.select_facts('(W a)'), steps=3000)
                query = ['(: $p (P a) $tv)', '(: $p (Q a) $tv)']
                self.assertAlmostEqual(h.query_many_refs(query, steps=3000)[0][0].tv[1], .5)
                h.add_atoms_no_check(['(: late-report (P a) (STV 1 0.9))'])
                rows = h.query_many_refs(query, steps=3000)
                self.assertEqual(rows[0][0].tv[1], 1)
                self.assertAlmostEqual(rows[1][0].tv[1], .8)

    def test_late_observation_updates_a_frozen_prediction(self):
        h = self.model(0)
        h.set_forgetting(1)
        self.addCleanup(h.set_forgetting, 0)
        query = ['(: $p (P a) $tv)']
        self.assertAlmostEqual(h.query_many_refs(query, steps=3000)[0][0].tv[1], .5)
        h.advance_epoch()
        h.advance_epoch()
        frozen = h.query_many_refs(query, steps=3000)[0][0]
        self.assertIn('forgotten', h.expand_proof(frozen.proof))
        h.add_atoms_no_check(['(: late-report (P a) (STV 1 0.9))'])
        rows = h.query_many_refs(query + ['(: $p (Q a) $tv)'], steps=3000)
        self.assertEqual(rows[0][0].tv[1], 1)
        self.assertAlmostEqual(rows[1][0].tv[1], .8)
        self.assertIn('forgotten', h.expand_proof(rows[0][0].proof))

    def test_filtered_observation_does_not_hide_prediction(self):
        h = self.model(.9)
        # Surface validation accepts only proof names; exercise the runtime's
        # existing constrained-proof query directly.
        rows = h._call('query', [f'3000 {h.kb} (: (by zp $body) (P a) $tv)'])
        self.assertEqual(len(rows), 1)
        self.assertIn('(STV 0.5 ', rows[0])

    def test_negative_report_has_the_same_value(self):
        h = self.model(0)
        h.add_atoms_no_check(['(: negative-report (Not (P a)) (STV 1 0.9))'])
        rows = h.query_many_refs(['(: $p (P a) $tv)', '(: $p (Q a) $tv)'], steps=3000)
        self.assertEqual(rows[0][0].tv[1], 0)
        self.assertAlmostEqual(rows[1][0].tv[1], .3)

    def test_independent_stated_samples_still_revise(self):
        h = self.model(.9)
        h.add_atoms_no_check(['(: other-report (P a) (STV 0 0.5))'])
        rows = h.query_many_refs(['(: $p (P a) $tv)'], steps=3000)[0]
        self.assertEqual(len(rows), 1)
        self.assertAlmostEqual(rows[0].tv[1], .9, delta=1e-12)
        self.assertAlmostEqual(rows[0].tv[2], 10 / 11, delta=1e-5)

    def test_fractional_reports_update_the_prediction_as_prior(self):
        for c in (.5, .9, .99, 1):
            for prediction, report in ((.1, .6), (0, .8), (.99, .6)):
                answers = []
                for forward in (False, True):
                    with self.subTest(c=c, prediction=prediction, report=report, forward=forward):
                        h = PeTTaChainer()
                        h.set_evidence_confidence_k(5)
                        self.addCleanup(h.set_evidence_confidence_k, 800)
                        h.add_atoms_no_check([
                            '(: cause (C a) (STV 1 1))',
                            f'(: cp (Implication (C a) (P a)) (CTV (STV {prediction} 1) (STV {prediction} 1)))',
                            f'(: report (P a) (STV {report} {c}))',
                            '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.3 1)))',
                        ])
                        if forward:
                            h.forward_chain(h.select_facts(['(C a)', '(P a)']), steps=3000)
                        rows = h.query_many_refs(['(: $p (P a) $tv)', '(: $p (Q a) $tv)'], steps=3000)
                        self.assertEqual([len(row) for row in rows], [1, 1])
                        # A lone report has the leave-one-out centre 1/2.
                        # B2 keeps confidence-1 fractional reports Jeffrey;
                        # this is not the limit of the finite-confidence rule.
                        expected = report if c == 1 else (prediction * report / (
                            prediction * report + (1 - prediction) * (1 - report)))
                        self.assertAlmostEqual(rows[0][0].tv[1], expected, delta=1e-12)
                        self.assertAlmostEqual(rows[1][0].tv[1], .3 + .5 * expected, delta=1e-12)
                        if c < 1:
                            self.assertLess(rows[0][0].tv[2], .9999)
                        answers.append(rows[0][0].tv[1])
                self.assertAlmostEqual(*answers, delta=1e-12)

    def test_report_updates_a_prediction_with_independent_diagnostics(self):
        for c in (.5, .9, .99):
            h = PeTTaChainer()
            h.set_bayes_prior_count(0)
            self.addCleanup(h.set_bayes_prior_count, .2)
            h.add_atoms_no_check([
                '(: cause (C a) (STV 1 1))',
                '(: cp (Implication (C a) (P a)) (CTV (STV 0.1 1) (STV 0.1 1)))',
                '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.2 1)))',
                '(: sensor (Q a) (STV 1 1))',
                f'(: report (P a) (STV 0.6 {c}))',
            ])
            row = h.query_many_refs(['(: $p (P a) $tv)'], steps=3000)[0][0]
            # Prior odds 1/9, report likelihood ratio 3/2, sensor ratio 4.
            self.assertAlmostEqual(row.tv[1], .4, delta=1e-12)
            proof = h.expand_proof(row.proof)
            for source in ('cause', 'sensor', 'report'):
                self.assertIn(source, proof)

    def test_corroboration_precedes_the_likelihood_update(self):
        for forward in (False, True):
            h = PeTTaChainer()
            h.set_evidence_confidence_k(5)
            self.addCleanup(h.set_evidence_confidence_k, 800)
            h.add_atoms_no_check([
                '(: cause (C a) (STV 1 1))',
                '(: cp (Implication (C a) (P a)) (CTV (STV 0.5 1) (STV 0.5 1)))',
                '(: r1 (P a) (STV 0.6 0.5))',
                '(: r2 (P a) (STV 0.6 0.5))',
            ])
            if forward:
                h.forward_chain(h.select_facts(['(C a)', '(P a)']), steps=3000)
            row = h.query_many_refs(['(: $p (P a) $tv)'], steps=3000)[0][0]
            self.assertAlmostEqual(row.tv[1], .6, delta=1e-12)
            self.assertAlmostEqual(row.tv[2], 2 / 3, delta=1e-8)
            proof = h.expand_proof(row.proof)
            self.assertIn('merge/revision', proof)
            self.assertIn('(prior (STV 0.5 0.0))', proof)

    def test_late_population_and_explicit_rate_refresh_a_warm_report(self):
        h = PeTTaChainer()
        h.set_evidence_confidence_k(5)
        self.addCleanup(h.set_evidence_confidence_k, 800)
        h.add_atoms_no_check([
            '(: cause (C a) (STV 1 1))',
            '(: cp (Implication (C $x) (P $x)) (CTV (STV 0.1 1) (STV 0.1 1)))',
            '(: report (P a) (STV 0.6 0.9))',
            '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.3 1)))',
        ])
        q = ['(: $p (Q a) $tv)', '(: $p (P a) $tv)']
        initial = h.query_many_refs(q, steps=3000)
        self.assertAlmostEqual(initial[1][0].tv[1], 1 / 7)
        h.add_atoms_no_check(['(: pb (P b) (STV 0.2 1))', '(: pc (P c) (STV 0.2 1))'])
        # Two confidence-1 members have empirical weight two. The common
        # neutral pseudocount 0.2 gives b = (0.4 + 0.1) / 2.2.
        b = .5 / 2.2
        expected = (.1 * .6 * (1 - b)) / (.1 * .6 * (1 - b) + .9 * .4 * b)
        updated = h.query_many_refs(q, steps=3000)
        self.assertAlmostEqual(updated[1][0].tv[1], expected)
        self.assertAlmostEqual(updated[0][0].tv[1], .3 + .5 * expected)
        h._call('set-base-rate', [f'{h.kb} (P $x) (STV 0.8 1)'])
        explicit = h.query_many_refs(q, steps=3000)
        self.assertAlmostEqual(explicit[1][0].tv[1], .04)
        self.assertAlmostEqual(explicit[0][0].tv[1], .32)

    def test_frozen_diagnostic_summary_remains_the_prior(self):
        h = PeTTaChainer()
        h.set_evidence_confidence_k(5)
        self.addCleanup(h.set_evidence_confidence_k, 800)
        h.set_forgetting(1)
        self.addCleanup(h.set_forgetting, 0)
        h.add_atoms_no_check([
            '(: q (Q a) (STV 1 1))',
            '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.2 1)))',
        ])
        query = ['(: $p (P a) $tv)']
        prior = h.query_many_refs(query, steps=3000)[0][0].tv[1]
        # Statistical fold members normally replay on expiry. Freeze the
        # actual diagnostic row through the summary writer to exercise a
        # retained historical diagnostic, without replacing it by a fixture.
        key = f'(sk-key (P a) ({h.kb} MAIN Nil))'
        key_hash = int(h._call('index-hash', [key])[0])
        h._call('sk-freeze!', [f'1 () ({key_hash} {key} false)'])
        frozen = h.query_many_refs(query, steps=3000)[0][0]
        self.assertIn('forgotten', h.expand_proof(frozen.proof))
        h.add_atoms_no_check(['(: report (P a) (STV 0.6 0.9))'])
        posterior = h.query_many_refs(query, steps=3000)[0][0]
        expected = prior * .6 / (prior * .6 + (1 - prior) * .4)
        self.assertAlmostEqual(posterior.tv[1], expected)
        proof = h.expand_proof(posterior.proof)
        self.assertIn('forgotten', proof)
        self.assertIn('report', proof)


if __name__ == '__main__':
    unittest.main()
