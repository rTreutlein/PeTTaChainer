"""A cold load and a cached replay must provide the same Assuming runtime."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class TestContextOverlayCache(unittest.TestCase):
    def test_cached_library_replays_overlay_bootstrap(self):
        script = '''
from pettachainer import PeTTaChainer
h = PeTTaChainer()
h.add_atoms_no_check([
    '(: (no_inverse r) (Implication (Action x) (Effect x)) (STV 1 1))',
])
rows = h.query_many_refs(['(: $p (Assuming (Action x) (Effect x)) $tv)'], steps=200)[0]
assert len(rows) == 1 and rows[0].tv[1] == 1, rows
assert h.query_many_refs(['(: $p (Effect x) $tv)'], steps=200)[0] == []
'''
        with tempfile.TemporaryDirectory(prefix='overlay-load-cache-') as directory:
            env = {**os.environ, 'PETTA_LOAD_CACHE': directory}
            snapshots = None
            for _ in range(2):
                result = subprocess.run(
                    [sys.executable, '-c', script], env=env, text=True,
                    capture_output=True, timeout=120,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('ERROR:', result.stderr)
                current = {p.name: p.stat().st_mtime_ns
                           for p in Path(directory).glob('*.snapshot')}
                self.assertTrue(current, 'library load was not cacheable')
                if snapshots is not None:
                    self.assertEqual(current, snapshots, 'second load did not reuse its snapshot')
                snapshots = current
