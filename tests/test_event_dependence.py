"""E3's source roles, shared parents and same-KB source lifecycle."""
import unittest

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
