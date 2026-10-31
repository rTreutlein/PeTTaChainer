"""Run existing posterior/calibration units while capturing their moment calls."""
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pettachainer import PeTTaChainer

PeTTaChainer()  # Load cache before installing any Prolog instrumentation.
from capture_bootstrap import install
install()

original_run = unittest.TestCase.run


def run(self, result=None):
    os.environ['CONFVAR_CASE'] = self.id()
    return original_run(self, result)


unittest.TestCase.run = run
suite = unittest.TestSuite(unittest.defaultTestLoader.discover('tests', pattern=pattern)
                           for pattern in ('test_event_node.py', 'test_tv_calibration.py',
                                           'test_atomic_posterior.py', 'test_posterior_fixture_audit.py',
                                           'test_compound_completion.py', 'test_event_dependence.py'))
raise SystemExit(not unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful())
