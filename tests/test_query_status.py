"""query_many_with_status says whether the call ran out of budget or refused
work, and nothing else: answers stay query_many's, and did-not-run-out does not
mean an answer is correct (#155)."""
import json
import subprocess
import sys
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer
from tests.test_deep_conditioning import plant

RAN_OUT, DID_NOT = "ran-out", "did-not-run-out"


def debut_atoms(events=2, parts=9):
    """Each event is known only through a report over its roles, as a KE source
    states it: the event graph answers it and reading it costs that many bits."""
    atoms = []
    for e in range(events):
        roles = " ".join(f"(Role{i} e{e} p{i})" for i in range(parts))
        atoms += [
            f"(: rep{e} (Implication (And (Debut e{e}) {roles}) (Affirms c{e})) (CTV (STV 0.5 0.01) (STV 0.5 0.01)))",
            f"(: seen{e} (Affirms c{e}) (STV 1 1))",
        ]
    return atoms


COUNTS = """
import json, sys
from pettachainer import PeTTaChainer
from tests.test_deep_conditioning import plant
call = sys.argv[1]
h = PeTTaChainer()
plant(h, 4)
h.set_query_metrics(True)
out = []
for query in ("(: $p (Degraded plant t4) $tv)", "(: $p (Degraded plant t4) $tv)", "(: $p (Storm t2) $tv)"):
    result = getattr(h, call)([query], 400, timeout_sec=0)
    m = h.last_query_metrics()
    out.append([result["answers"] if call == "query_many_with_status" else result,
                m["expansions"], m["row_computes"], m["graph_evaluations"]])
print(json.dumps(out))
"""

WORK = """
import json, sys
import janus_swi as janus
from pettachainer import PeTTaChainer
call, n = sys.argv[1], int(sys.argv[2])
h = PeTTaChainer()
h.add_atoms_no_check([f"(: f{i} (P a{i}) (STV 1 1))" for i in range(n)])
query = ["(: $p (P $x) $tv)"]
for _ in range(2):
    getattr(h, call)(query, 20000, timeout_sec=0)
before = janus.query_once("statistics(inferences, I)")["I"]
getattr(h, call)(query, 1, timeout_sec=0)
print(json.dumps(janus.query_once("statistics(inferences, I)")["I"] - before))
"""


PLANT = """
import json, sys
from pettachainer import PeTTaChainer
from tests.test_deep_conditioning import plant
h = PeTTaChainer()
plant(h, 4)
statuses = [h.query_many_with_status(["(: $p (Degraded plant t4) $tv)"], int(steps), timeout_sec=0)["status"]
            for steps in sys.argv[1:]]
print(json.dumps(statuses + [h.query_many_with_status([], 0, timeout_sec=0)["status"]]))
"""

TIMED = """
import json, sys
from pettachainer import PeTTaChainer
atoms, query = ["(: a (A x) (STV 0.8 0.9))"], ["(: $p (A x) $tv)"]
out = []
for steps in (0, 100):
    for timeout in (120, 0):
        h = PeTTaChainer()
        h.add_atoms_no_check(atoms)
        out.append(h.query_many_with_status(query, steps, timeout_sec=timeout))
print(json.dumps(out))
"""


def last_json(script, *args):
    run = subprocess.run([sys.executable, "-c", script, *map(str, args)], capture_output=True, text=True, check=True)
    return json.loads(run.stdout.splitlines()[-1])


class QueryStatusTests(unittest.TestCase):
    def handler(self, atoms):
        h = PeTTaChainer()
        h.add_atoms_no_check(atoms)
        return h

    def status(self, h, query, steps):
        return h.query_many_with_status([query], steps, timeout_sec=0)["status"]

    def test_answers_are_those_of_query_many(self):
        atoms = [f"(: p{i} (P a{i}) (STV 0.{i + 1} 0.5))" for i in range(7)]
        query = ["(: $p (P $x) $tv)", "(: $p (Z x) $tv)"]
        for steps in (0, 1, 100):
            with self.subTest(steps=steps):
                self.assertEqual(self.handler(atoms).query_many_with_status(query, steps, timeout_sec=0)["answers"],
                                 self.handler(atoms).query_many(query, steps, timeout_sec=0))

    def test_the_status_costs_no_reasoning(self):
        # One process per call: an earlier KB's deferred tier moves the counts.
        self.assertEqual(last_json(COUNTS, "query_many"), last_json(COUNTS, "query_many_with_status"))

    def test_added_work_does_not_grow_with_the_answers(self):
        def added(n):
            return last_json(WORK, "query_many_with_status", n) - last_json(WORK, "query_many", n)
        self.assertEqual(added(10), added(1000))

    def test_budget_zero_with_work_left_ran_out(self):
        h = self.handler(["(: a (A x) (STV 0.8 0.9))"])
        query = "(: $p (A x) $tv)"
        self.assertEqual(self.status(h, query, 0), RAN_OUT)
        self.assertEqual(self.status(h, query, 100), DID_NOT)
        # Nothing is left to do, so a call without budget has not run out.
        self.assertEqual(self.status(h, query, 0), DID_NOT)

    def test_search_left_ran_out_and_more_budget_finishes_it(self):
        atoms = ["(: a (A x) (STV 0.8 0.9))"] + [
            f"(: r{i} (Implication (A $y) (B{i} $y)) (STV 0.9 0.9))" for i in range(6)
        ] + [f"(: s{i} (Implication (B{i} $y) (C $y)) (STV 0.9 0.9))" for i in range(6)]
        h = self.handler(atoms)
        query = "(: $p (C x) $tv)"
        self.assertEqual(self.status(h, query, 1), RAN_OUT)
        self.assertEqual(self.status(h, query, 5000), DID_NOT)

    def test_refused_graph_work_ran_out_with_nothing_else_left(self):
        # The case KE asked about, ProductDebut at 1000: diagnostics see an
        # exhausted agenda. Forced here, since its budget window depends on the KB.
        query = "(: $p (Debut $x) $tv)"
        self.assertEqual(self.status(self.handler(debut_atoms()), query, 100), DID_NOT)
        for predicate in ("graph_take(_)", "graph_admit(_)"):
            with self.subTest(predicate):
                h = self.handler(debut_atoms())
                janus.query_once(f"wrap_predicate({predicate}, status_test, _W, fail)")
                try:
                    self.assertEqual(self.status(h, query, 100), RAN_OUT)
                    h.set_query_metrics(True)
                    reason = h.query_with_diagnostics(query, 100)["diagnostics"]["termination"]["reason"]
                finally:
                    janus.query_once(f"unwrap_predicate({predicate.replace('(_)', '/1')}, status_test)")
                self.assertEqual(reason, "agenda_exhausted")
                self.assertEqual(self.status(h, query, 100), DID_NOT)

    def test_unpaid_rows_and_conditions_ran_out_on_every_call(self):
        self.assertEqual(last_json(PLANT, 400, 400, 400), [RAN_OUT] * 3 + [DID_NOT])

    def test_did_not_run_out_is_not_correct(self):
        # #172: the exact value of (P a) is 0; nothing here ran out, and the
        # status must not be read as vouching for 0.3.
        h = self.handler(["(: prior (P a) (STV 0.3 0.9))", "(: link (Edge a b) (STV 1 1))",
                          "(: observed (C b) (STV 0 1))",
                          "(: joined (Implication (And (P $x) (Edge $x $y)) (C $y)) (STV 1 1))"])
        result = h.query_many_with_status(["(: $p (P a) $tv)"], 3000, timeout_sec=0)
        self.assertEqual(result["status"], DID_NOT)
        self.assertEqual(result["answers"], [["(: prior (P a) (STV 0.3 0.9))"]])

    def test_a_status_is_of_its_own_call(self):
        statuses = last_json(PLANT, 400, 20000, 20000)
        self.assertEqual(statuses[0], RAN_OUT)
        self.assertEqual(statuses[-2], DID_NOT)

    def test_an_assuming_context_reports_its_own_search(self):
        rules = ["(: r1 (Implication (A $x) (B $x)) (CTV (STV 0.9 0.9) (STV 0.2 0.9)))",
                 "(: r2 (Implication (B $x) (C $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9)))"]
        query = "(: $p (Assuming (A z) (C z)) $tv)"
        self.assertEqual(self.status(self.handler(rules), query, 0), RAN_OUT)
        self.assertEqual(self.status(self.handler(rules), query, 5000), DID_NOT)

    def test_a_batch_ran_out_when_any_root_did(self):
        atoms = ["(: a (A x) (STV 0.8 0.9))"] + debut_atoms()
        batch = ["(: $p (A x) $tv)", "(: $p (Debut $x) $tv)", "(: $p (Z x) $tv)"]
        short = self.handler(atoms).query_many_with_status(batch, 8, timeout_sec=0)
        self.assertEqual(short["status"], RAN_OUT)
        self.assertEqual(len(short["answers"]), 3)
        self.assertEqual(self.handler(atoms).query_many_with_status(batch, 500, timeout_sec=0)["status"], DID_NOT)
        self.assertEqual(self.handler([]).query_many_with_status([], 0, timeout_sec=0),
                         {"answers": [], "status": DID_NOT})

    def test_a_timed_worker_carries_the_status(self):
        zero_timed, zero_live, paid_timed, paid_live = last_json(TIMED)
        self.assertEqual(zero_timed, zero_live)
        self.assertEqual(zero_live["status"], RAN_OUT)
        self.assertEqual(paid_timed, paid_live)
        self.assertEqual(paid_live["status"], DID_NOT)

    def test_metta_form_is_one_term_with_empty_positions(self):
        h = self.handler(["(: a (A x) (STV 0.8 0.9))"])
        self.assertEqual(h._call("query-many-with-status", [f"100 {h.kb} ((: $p (A x) $tv) (: $p (Z x) $tv))"]),
                         [f"(query-outcome {DID_NOT} (((: a (A x) (STV 0.8 0.9))) ()))"])
        self.assertEqual(h._call("query-many-with-status", [f"100 {h.kb} ()"]), [f"(query-outcome {DID_NOT} ())"])

    def test_an_error_leaves_the_next_status_intact(self):
        h = self.handler(["(: a (A x) (STV 0.8 0.9))"])
        self.assertEqual(self.status(h, "(: $p (A x) $tv)", 0), RAN_OUT)
        with self.assertRaises(Exception):
            h._call("query-many-with-status", [f"100 {h.kb} ((: $p (Assuming (A x)) $tv))"])
        self.assertEqual(self.status(h, "(: $p (A x) $tv)", 100), DID_NOT)


if __name__ == "__main__":
    unittest.main()
