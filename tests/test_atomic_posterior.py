"""Atomic reports use the same event likelihood as compound evidence (posterior1)."""
import unittest
import json
import math
import time
from fractions import Fraction
from pathlib import Path

import janus_swi as janus
from pettachainer import PeTTaChainer
from tests.test_tv_calibration import main_answer, assuming_answer
from tests.tv_calibration_oracles import SETTINGS, event_oracle, probes


class AtomicPosteriorTests(unittest.TestCase):
    def test_joint_chain_evidence_and_assuming_match_the_oracle(self):
        for setting, config in SETTINGS.items():
            with self.subTest(setting=setting):
                model = probes(*config)['P16']
                expected = event_oracle(model, ratio_bound=True)['(A a)']
                main = main_answer(model, '(A a)')
                self.assertEqual(len(main), 1)
                self.assertAlmostEqual(main[0][1], expected['s'], delta=1e-12)
                if config[1] == 0:
                    self.assertEqual(main[0][2], config[0])  # no observation: keep source counts
                else:
                    self.assertAlmostEqual(main[0][2], expected['bound_c'], delta=1e-7)
                self.assertEqual(assuming_answer(model, '(A a)'), main)
                if 0 in config[:2]:
                    omitted = dict(model, comps=[] if config[1] == 0 else model['comps'],
                                   roots={} if config[0] == 0 else model['roots'])
                    self.assertEqual(main_answer(omitted, '(A a)'), main)

    def test_issue150_certain_joint_keeps_one_source_without_enumeration(self):
        request = json.loads(Path(__file__).with_name('fixtures').joinpath('issue150.json').read_text())
        started = time.monotonic()
        h = PeTTaChainer()
        for declaration in request['ir_declarations']:
            name, args = declaration['function'], declaration['args']
            if name == 'set-evidence-confidence-k':
                h.set_evidence_confidence_k(float(args[0]))
            elif name == 'set-argument-sorts':
                h.set_argument_sorts(args[0], args[1].strip('()').split())
            else:
                h.set_constant_sort(*args)
        h.add_atoms_no_check([entry['atom'] for entry in request['entries']])
        row, = h.query_many_refs(request['queries'], steps=request['steps'])[0]
        self.assertEqual(row.tv[1], 1)
        self.assertLess(time.monotonic() - started, 10)
        evidence = janus.query_once("'proof-ref-evidence'(Pid,Ev), 'evidence-entries'(Ev,Entries)",
                                    {'Pid': int(row.proof[1])})
        self.assertEqual(len(evidence['Entries']), 1)

    def test_uncertain_wide_conjunction_folds_to_the_moment_answer(self):
        request = json.loads(Path(__file__).with_name('fixtures').joinpath('issue150.json').read_text())
        h = PeTTaChainer()
        started = time.monotonic()
        h.add_atoms_no_check([request['entries'][0]['atom'].replace('(STV 1 1)', '(STV 1 0.9)')])
        row, = h.query_many_refs(['(: $p (Event Event_95fb56869e14af48_75423f0c) $tv)'], steps=500)[0]
        # The goal t and the folded other 29 parts W (moments 2^-29, 3^-29): Z = a + c t W,
        # N = t (a + c W); the contract's moment variance, converted at k = 800.
        m = Fraction(7201, 7202)
        a, c, t1, t2, w1, w2 = 1 - m, 2 * m - 1, Fraction(1, 2), Fraction(1, 3), Fraction(1, 2**29), Fraction(1, 3**29)
        e = a + c * t1 * w1
        s = (a * t1 + c * t1 * w1) / e
        q = (a*a*t2 + (1-s)**2*c*c*t2*w2 + s*s*a*a + 2*a*(1-s)*c*t2*w1 - 2*s*a*a*t1 - 2*(1-s)*c*s*a*t1*w1)
        var = (float(q) + float(max(s, 1 - s)) * math.sqrt(float(c*c*t2*w2 - (c*t1*w1)**2) * float(q))) / float(e*e)
        n = float(s * (1 - s)) / var - 1
        self.assertAlmostEqual(row.tv[1], float(s), delta=1e-12)
        self.assertAlmostEqual(row.tv[2], n / (n + 800), delta=1e-12)
        self.assertLess(time.monotonic() - started, 10)

    def test_boolean_antecedent_completions_match_the_joint_oracle(self):
        for parent, holds in (
            ('(And (A $x) (B $x))', lambda w: w['A'] & w['B']),
            ('(Or (A $x) (B $x))', lambda w: w['A'] | w['B']),
            ('(And (A $x) (Not (B $x)))', lambda w: w['A'] & ~w['B']),
        ):
            for confidence in (1, .9):
                with self.subTest(parent=parent, confidence=confidence):
                    model = dict(atoms=['A', 'B', 'C'], roots={'A': (.4, .9), 'B': (.3, .9)},
                                 rules={'C': (holds, (.9, confidence), (.1, confidence))},
                                 comps=[('(C a)', lambda w: w['C'], .8, .9)],
                                 goals={'(B a)': lambda w: w['B']})
                    expected = event_oracle(model, ratio_bound=True)['(B a)']
                    h = PeTTaChainer()
                    h.add_atoms_no_check([
                        '(: a (A a) (STV 0.4 0.9))', '(: b (B a) (STV 0.3 0.9))',
                        f'(: rule (Implication {parent} (C $x)) (CTV (STV 0.9 {confidence}) (STV 0.1 {confidence})))',
                        '(: report (C a) (STV 0.8 0.9))',
                    ])
                    row, = h.query_many_refs(['(: $p (B a) $tv)'], steps=1000)[0]
                    self.assertAlmostEqual(row.tv[1], expected['s'], delta=1e-12)
                    self.assertAlmostEqual(row.tv[2], expected['bound_c'], delta=1e-7)

    def test_fractional_certain_and_finite_endpoint_reports_are_pearl(self):
        for prior, strength, confidence in ((.3, .8, 1), (.5, 1, .5), (.5, 0, .5)):
            with self.subTest(prior=prior, strength=strength, confidence=confidence):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: a (A a) (STV 1 1))',
                    f'(: rule (Implication (A $x) (B $x)) (CTV (STV {prior} 1) (STV {prior} 1)))',
                    f'(: report (B a) (STV {strength} {confidence}))',
                ])
                predictive = strength if confidence == 1 else (800 * confidence / (1 - confidence) * strength + 1) / (800 * confidence / (1 - confidence) + 2)
                expected = prior * predictive / (prior * predictive + (1 - prior) * (1 - predictive))
                row, = h.query_many_refs(['(: $p (B a) $tv)'], steps=1000)[0]
                self.assertAlmostEqual(row.tv[1], expected, delta=1e-12)
                self.assertEqual(row.tv[2], .9999)
                if confidence < 1:
                    self.assertGreater(row.tv[1], 0)
                    self.assertLess(row.tv[1], 1)

    def test_a_root_without_likelihoods_keeps_its_source_counts(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a (A a) (STV 0.7 0.9))',
            '(: rule (Implication (A $x) (B $x)) (CTV (STV 0.9 1) (STV 0.1 1)))',
        ])
        row, = h.query_many_refs(['(: $p (A a) $tv)'], steps=1000)[0]
        self.assertEqual(row.tv, ['STV', .7, .9])

    def test_a_goal_fixed_in_every_surviving_world_has_zero_variance(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a (A a) (STV 1 1))',
            '(: b (B a) (STV 1 1))',
            '(: d (D a) (STV 0.3 0.9))',
            '(: report (And (A a) (D a)) (STV 0.9 0.9))',
        ])
        row, = h.query_many_refs(['(: $p (And (A a) (B a)) $tv)'], steps=1000)[0]
        self.assertEqual(row.tv, ['STV', 1.0, .9999])

    def test_impossible_evidence_does_not_fall_back_to_a_certain_source(self):
        for warm in (False, True):
            with self.subTest(warm=warm):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: a (A a) (STV 0 1))',
                    '(: rule (Implication (A $x) (B $x)) (CTV (STV 1 1) (STV 0 1)))',
                ])
                query = ['(: $p (A a) $tv)']
                if warm:
                    self.assertEqual(h.query_many_refs(query, steps=1000)[0][0].tv, ['STV', 0, 1])
                h.add_atoms_no_check(['(: report (B a) (STV 1 1))'])
                self.assertEqual(h.query_many_refs(query, steps=1000), [[]])

    def test_unsupported_components_keep_the_ordinary_fallback(self):
        for shape in ('no_inverse', 'cycle', 'cap'):
            with self.subTest(shape=shape):
                h = PeTTaChainer()
                if shape == 'no_inverse':
                    rules = ['(: (no_inverse rule) (Implication (A a) (B a)) (CTV (STV 0.9 1) (STV 0.1 1)))']
                elif shape == 'cycle':
                    rules = [f'(: {a}{b} (Implication ({a} a) ({b} a)) (CTV (STV 0.9 1) (STV 0.1 1)))' for a, b in (('A', 'B'), ('B', 'A'))]
                else:
                    rules = [f'(: r{i} (Implication (A{i} a) (A{i+1} a)) (CTV (STV 0.9 1) (STV 0.1 1)))' for i in range(13)]
                report = 'A13' if shape == 'cap' else 'B'
                h.add_atoms_no_check(rules + [f'(: report ({report} a) (STV 0.8 0.9))'])
                goal = ['A0' if shape == 'cap' else 'A', 'a']
                result = janus.query_once(
                    "'event-network-read'(['sk-key',Goal,[Kb,'MAIN','Nil']], 'sk-any-filter', [], ['ev-set',0], Out)",
                    {'Goal': goal, 'Kb': h.kb})
                self.assertEqual(result['Out'], 'no-event-model')
