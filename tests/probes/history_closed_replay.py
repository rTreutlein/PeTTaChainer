"""Publication soundness on the aggregate loop; T1 owns the full u4 replays."""
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer
from context_nodes import WORK, base_rate_loop


class PublicationTests(unittest.TestCase):
    def test_changed_aggregate_publications_are_sound_and_quiet(self):
        PeTTaChainer()
        janus.consult(str(Path(__file__).resolve().parents[1] / 'context_node_probe.pl'))
        janus.query_once('context_probe_install')
        _, rows = base_rate_loop()
        self.assertEqual(janus.query_once('context_probe_invalid(Rows)')['Rows'], [])
        self.assertGreater(janus.query_once('context_probe_count(N)')['N'], 0)
        for row in rows[-3:]:
            self.assertFalse(any(row['work'][key] for key in WORK))


if __name__ == '__main__':
    unittest.main()
