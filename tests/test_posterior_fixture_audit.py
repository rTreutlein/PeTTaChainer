"""Every moved MeTTa fixture is checked from its authored Boolean model."""
import json
from pathlib import Path
import unittest

from tests.posterior_fixture_oracle import source_oracle


def tvs(term):
    if isinstance(term, list):
        if term and term[0] == 'STV':
            yield term
        else:
            for child in term:
                yield from tvs(child)


class PosteriorFixtureAuditTests(unittest.TestCase):
    def test_moved_references_match_the_independent_event_oracle(self):
        records = json.loads(Path(__file__).with_name('fixtures').joinpath('posterior1_oracle_audit.json').read_text())
        for record in records:
            with self.subTest(file=record['file'], goal=record['goal'], old=record['old']):
                oracle = source_oracle(record['sources'], record['goal'], record['rates'], record['k'], record['smoothing'])
                values = list(tvs(record['new']))
                if not values:
                    self.assertAlmostEqual(float(record['new']), oracle['s'], delta=1e-10)
                    continue
                _, s, c = values[-1]
                s, c = float(s), float(c)
                self.assertAlmostEqual(s, oracle['s'], delta=1e-10)
                if oracle['var'] == 0:
                    self.assertEqual(c, .9999)
                else:
                    mean = min(max(s, 1e-6), 1-1e-6)
                    variance = mean*(1-mean)/(record['k']*c/(1-c)+1)
                    self.assertTrue(.5 <= variance/oracle['var'] <= 2)
