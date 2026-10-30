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
import janus_swi as janus
h = PeTTaChainer()
# Replay must retain typed facades, constructor-headed physical arities and
# the native read-only waiter relation, as well as logical query behavior.
assert janus.query_once("""
    context_store('&sk_new',6,local),
    predicate_property('&sk_wait'(_,_,_),static),
    predicate_property(context_store(_,_,_),static)
""")["truth"]
assert janus.query_once("""
    forall(context_store(_S,_A,_),
           (declared_space_type(_S,_T), atom_concat('&',_N,_S),
            atom_concat('&ctx_',_N,_R), declared_space_type(_R,_T),
            functor(_H,_R,_A), predicate_property(_H,static)))
""")["truth"]
# Generated native declarations must retain their effects and polymorphic
# sharing through both a cold load and a cached replay.
assert janus.query_once("""
    fun('deps-union'),
    declared_fn_type('deps-union', ['Number','Number'], 'Number', det),
    fun('event-node-value'),
    declared_fn_type('event-node-value', _, _, semidet),
    fun('sk-active-reader'),
    declared_fn_type('sk-active-reader', [], _, nondet),
    declared_fn_type('member-canon', [_A], _B, det), var(_A), _A == _B,
    declared_fn_type(alpha_unique_keys, [['List',_T]], ['List',_U], det),
    var(_T), _T == _U
""")["truth"]
# Plain-store schemas keep their scalar first column and row arity.
assert janus.query_once("""
    declared_space_type('&kb_prefix', _PrefixRow),
    _PrefixRow = ['Number'|_], length(_PrefixRow, 5),
    declared_space_type('&hm_recent', _RecentRow),
    _RecentRow = ['Number'|_], length(_RecentRow, 8)
""")["truth"]
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
