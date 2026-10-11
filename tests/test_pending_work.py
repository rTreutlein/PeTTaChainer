"""Differential test of the pending-work index (runtime_helpers.pl, "Pending
work"): random child links, cycles included (their components merge), and work
added and taken, each node's pending state compared with a search of the links
for work."""

import subprocess
import sys
import textwrap
import unittest
from pathlib import Path

HELPERS = Path(__file__).resolve().parents[1] / "pettachainer" / "metta" / "prolog" / "runtime_helpers.pl"

SCRIPT = textwrap.dedent(
    """
    import random, sys
    import janus_swi as janus
    janus.consult("pw_stub", "attribute_free_variant(A, B) :- A =@= B.")
    janus.consult(sys.argv[1])
    seed, nodes, steps = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    rng = random.Random(seed)
    for n in range(nodes):
        janus.query_once("assertz('&sk_expanded'(N, N))", {"N": n})
    links, work, linked = set(), [0] * nodes, set()
    def reaches_work(n):
        seen, stack = {n}, [n]
        while stack:
            x = stack.pop()
            if work[x] > 0:
                return True
            for (a, b) in links:
                if a == x and b not in seen:
                    seen.add(b); stack.append(b)
        return False
    for step in range(steps):
        r = rng.random()
        if r < 0.45:
            u, v = rng.randrange(nodes), rng.randrange(nodes)
            if u != v and (u, v) not in links:
                links.add((u, v)); linked.update((u, v))
                janus.query_once("'sk-link-pending!'(U, U, V, V, _)", {"U": u, "V": v})
        elif r < 0.75:
            n = rng.randrange(nodes)
            work[n] += 1; linked.add(n)
            janus.query_once("'sk-work!'(N, N, 1, _)", {"N": n})
        else:
            busy = [n for n in range(nodes) if work[n] > 0]
            if busy:
                n = rng.choice(busy)
                work[n] -= 1
                janus.query_once("'sk-work!'(N, N, -1, _)", {"N": n})
        bad = janus.query_once("findall(_R, ( pw_deg(_R, _O, _I), aggregate_all(count, pw_out(_R, _, _), _O1), "
                               "aggregate_all(count, pw_in(_R, _, _), _I1), ( _O \\== _O1 ; _I \\== _I1 ) ), Bad)")["Bad"]
        if bad:
            print(f"seed {seed} step {step}: link counts of {bad} wrong")
            sys.exit(1)
        for n in range(nodes):
            got = janus.query_once("'sk-pending?'(N, N, B)", {"N": n})["B"] == "true"
            want = reaches_work(n) if n in linked else False
            if got != want:
                print(f"seed {seed} step {step} node {n}: index {got}, links {want}")
                sys.exit(1)
    merged = janus.query_once("aggregate_all(count, pw_up(_, _), M)")["M"]
    print("ok" if merged > 0 else f"seed {seed}: no component merged")
    """
)


class PendingWorkIndexTest(unittest.TestCase):
    def test_matches_search_of_links(self):
        for seed, nodes, steps in ((1, 6, 300), (2, 12, 400), (3, 25, 500), (4, 40, 600)):
            run = subprocess.run(
                [sys.executable, "-c", SCRIPT, str(HELPERS), str(seed), str(nodes), str(steps)],
                capture_output=True, text=True, timeout=600,
            )
            self.assertEqual(run.stdout.strip().splitlines()[-1:], ["ok"], run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
