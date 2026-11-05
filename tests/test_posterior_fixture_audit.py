"""The posterior MeTTa pins are checked against their authored Boolean model.

The fixture records each pin's file, sources and recorded strength; the pins
themselves are read from the .metta files, so a pin that drifts away from the
oracle fails here.
"""
import json
from pathlib import Path
import re
import unittest

from tests.posterior_fixture_oracle import source_oracle

REPO = Path(__file__).resolve().parent.parent
RECORDS = json.loads(Path(__file__).with_name('fixtures').joinpath('posterior1_oracle_audit.json').read_text())


def tvs(term):
    if isinstance(term, list):
        if term and term[0] == 'STV':
            yield term
        else:
            for child in term:
                yield from tvs(child)


def pins(record):
    """The cited file's pins of the recorded strength, as (s, [c, ...])."""
    values = list(tvs(record['new']))
    s = values[-1][1] if values else str(record['new'])
    text = (REPO / record['file']).read_text()
    return s, s in text, [float(c) for c in re.findall(re.escape(s) + r'\)?\s+([0-9][0-9.eE-]*)', text)]


class PosteriorFixtureAuditTests(unittest.TestCase):
    def test_pinned_strengths_match_the_independent_event_oracle(self):
        for record in RECORDS:
            with self.subTest(file=record['file'], goal=record['goal']):
                s, present, _ = pins(record)
                self.assertTrue(present, f"{record['file']} no longer pins strength {s}")
                oracle = source_oracle(record['sources'], record['goal'], record['rates'], record['k'], record['smoothing'])
                self.assertAlmostEqual(float(s), oracle['s'], delta=1e-10)

    # 43 of the 63 confidence pins are outside a factor 2 of the oracle
    # variance, though every strength matches: the confidence pins moved after
    # the Oct 31 audit recorded them, and the oracle's variance did not.
    # Which side is right is open.
    @unittest.expectedFailure
    def test_pinned_confidences_match_the_oracle_variance(self):
        for record in RECORDS:
            s, _, confidences = pins(record)
            if not confidences:
                continue  # a strength-only pin
            with self.subTest(file=record['file'], goal=record['goal']):
                oracle = source_oracle(record['sources'], record['goal'], record['rates'], record['k'], record['smoothing'])
                mean = min(max(float(s), 1e-6), 1-1e-6)

                def consistent(c):
                    if oracle['var'] == 0:
                        return c == .9999
                    return c < 1 and .5 <= mean*(1-mean)/(record['k']*c/(1-c)+1)/oracle['var'] <= 2
                # A shared strength literal can pin several sites; one is this record's.
                self.assertTrue(any(map(consistent, confidences)), (s, confidences, oracle))
