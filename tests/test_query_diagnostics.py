import json
import re
import unittest

from pettachainer import PeTTaChainer
from pettachainer.query_diagnostics import _parse, _render


class QueryDiagnosticsTests(unittest.TestCase):
    def handler(self, rule=True, flood=False):
        h = PeTTaChainer()
        h.add_atom("(: location (LocatedIn FactoryA Coastvale) (STV 1 0.9))")
        if rule:
            h.add_atom(
                "(: rule (Implication (And (LocatedIn $f $r) (Flooded $r)) (Disrupted $f)) (STV 1 0.9))"
            )
        # Keep the predicate live while its required ground instance is absent.
        h.add_atom("(: inland (Flooded Inland) (STV 1 0.9))")
        if flood:
            h.add_atom("(: flood (Flooded Coastvale) (STV 1 0.9))")
        return h

    def test_shared_company_evidence_is_conditioned_and_complete(self):
        h = PeTTaChainer()
        for atom in (
            "(: attention_volume (Implication (And (Member $company Company) (ElevatedInvestorAttention $company S1)) (TradingVolumeGreaterThan $company S1 200 Shares)) (STV 1.0 0.9))",
            "(: unexpected (Member NorthstarAnnouncementS1 UnexpectedProductAnnouncement) (STV 1.0 0.9))",
            "(: announced (HasAnnouncementForSession Northstar NorthstarAnnouncementS1 S1) (STV 1.0 0.9))",
            "(: company (Member Northstar Company) (STV 1.0 0.9))",
            "(: announcement_attention (Implication (And (Member $company Company) (Member $event UnexpectedProductAnnouncement) (HasAnnouncementForSession $company $event S1)) (ElevatedInvestorAttention $company S1)) (STV 1.0 0.9))",
        ):
            h.add_atom(atom)
        queries = (
            "(: $prf (TradingVolumeGreaterThan Northstar S1 200 Shares) $tv)",
            "(: $prf (ElevatedInvestorAttention Northstar S1) $tv)",
            "(: $prf (Member Northstar Company) $tv)",
        )
        results = [h.query_with_diagnostics(q, steps=300) for q in queries]
        self.assertEqual([len(r["proofs"]) for r in results], [1, 1, 1])
        self.assertIn("(conditioned ", results[0]["proofs"][0])
        self.assertEqual(h.query(queries[0], steps=300, timeout_sec=0), results[0]["proofs"])
        self.assertFalse(results[0]["diagnostics"]["truncated"])

    def test_missing_fact_carries_binding_rule_and_source(self):
        h = self.handler()
        r = h.query_with_diagnostics("(: $p (Disrupted FactoryA) $tv)")
        d = r["diagnostics"]
        self.assertFalse(r["proofs"])
        self.assertEqual(d["termination"]["reason"], "agenda_exhausted")
        self.assertEqual(d["termination"]["agenda_entries"], 0)
        self.assertGreater(d["termination"]["remaining_steps"], 0)
        self.assertFalse(d["truncated"])
        self.assertFalse(any(g["work_requested"] for g in d["goals"]))
        # The started rule continues through its joins; it is no candidate.
        self.assertTrue(all(r["origin"] == "continuation" for r in d["routes"] if r["parent_id"] == d["roots"][0]))
        route = next(
            r for r in d["routes"] if r["remaining_premises"] == ["(Flooded Coastvale)"]
        )
        self.assertIn("rule", route["rule_proof"])
        self.assertIn(
            {
                "kind": "fact",
                "name": "location",
                "expression": "(LocatedIn FactoryA Coastvale)",
            },
            route["supported_evidence"],
        )
        # Projecting a list must not rename its shared variable independently.
        unbound = next(r for r in d["routes"] if len(r["remaining_premises"]) == 2)
        terms = unbound["remaining_premises"]
        self.assertEqual(
            re.findall(r"\$[^ )]+", terms[0])[-1], re.findall(r"\$[^ )]+", terms[1])[0]
        )

    def test_dormant_rule_is_a_candidate_not_a_continuation(self):
        h = PeTTaChainer()
        h.add_atom("(: rule (Implication (MissingA $x) (MissingB $x)) (STV 1 0.9))")
        d = h.query_with_diagnostics("(: $p (MissingB a) $tv)")["diagnostics"]
        self.assertFalse(d["truncated"])
        self.assertTrue(d["routes"])
        self.assertTrue(all(r["origin"] == "candidate" for r in d["routes"]))
        self.assertTrue(any("MissingA" in g["expression"] for g in d["goals"]))

    def test_no_rule_does_not_invent_route(self):
        r = self.handler(rule=False, flood=True).query_with_diagnostics(
            "(: $p (Disrupted FactoryA) $tv)"
        )
        self.assertFalse(r["proofs"])
        self.assertEqual(r["diagnostics"]["routes"], [])

    def test_zero_and_small_budget_then_warm_recovery(self):
        h = self.handler(flood=True)
        for steps in (0, 1):
            d = h.query_with_diagnostics(
                "(: $p (Disrupted FactoryA) $tv)", steps=steps
            )["diagnostics"]
            self.assertEqual(d["termination"]["reason"], "budget_exhausted")
            self.assertEqual(d["termination"]["remaining_steps"], 0)
            self.assertGreater(d["termination"]["agenda_entries"], 0)
            self.assertTrue(d["goals"][0]["work_requested"])
        self.assertTrue(
            h.query_with_diagnostics("(: $p (Disrupted FactoryA) $tv)")["proofs"]
        )

    def test_proofs_unchanged_and_metrics_restored(self):
        expected = self.handler(flood=True).query(
            "(: $p (Disrupted FactoryA) $tv)", timeout_sec=0
        )
        h = self.handler(flood=True)
        h.set_query_metrics(False)
        r = h.query_with_diagnostics("(: $p (Disrupted FactoryA) $tv)")
        self.assertEqual(r["proofs"], expected)
        self.assertEqual(r["diagnostics"]["routes"], [])
        self.assertFalse(h._query_metrics_enabled)
        h.set_query_metrics(True)
        h.query_with_diagnostics("(: $p (Missing) $tv)")
        self.assertTrue(h._query_metrics_enabled)

    def test_limits_and_no_dangling_route_endpoints(self):
        h = self.handler()
        d = h.query_with_diagnostics(
            "(: $p (Disrupted FactoryA) $tv)", max_goals=1, max_routes=1, max_bytes=2048
        )["diagnostics"]
        self.assertTrue(d["truncated"])
        self.assertLessEqual(len(json.dumps(d, separators=(",", ":")).encode()), 2048)
        self.assertEqual(len(d["goals"]), 1)
        ids = {g["id"] for g in d["goals"]}
        for r in d["routes"]:
            self.assertLessEqual({r["parent_id"], r["child_id"]}, ids)
        self.assertGreater(d["omitted"]["goals"], 0)

    def test_byte_limit_omits_oversized_root(self):
        h = self.handler()
        d = h.query_with_diagnostics(
            "(: $p (Unknown " + "x" * 5000 + ") $tv)", max_bytes=2048
        )["diagnostics"]
        self.assertTrue(d["truncated"])
        self.assertEqual(d["goals"], [])
        self.assertEqual(d["omitted"]["goals"], 1)
        self.assertLessEqual(len(json.dumps(d, separators=(",", ":")).encode()), 2048)

    def test_validation_does_not_leave_metrics_enabled(self):
        h = self.handler()
        h.set_query_metrics(False)
        for options in (
            {"steps": True},
            {"max_goals": 0},
            {"max_routes": -1},
            {"max_bytes": 1},
        ):
            with self.assertRaises(ValueError):
                h.query_with_diagnostics("(: $p (Missing) $tv)", **options)
        with self.assertRaises(ValueError):
            h.query_with_diagnostics("not-a-query")
        self.assertFalse(h._query_metrics_enabled)

    def test_previous_query_frontiers_do_not_leak(self):
        h = self.handler()
        h.query_with_diagnostics("(: $p (Disrupted FactoryA) $tv)")
        d = h.query_with_diagnostics("(: $p (Unrelated) $tv)")["diagnostics"]
        self.assertEqual(d["routes"], [])
        self.assertEqual([g["expression"] for g in d["goals"]], ["(Unrelated)"])

    def test_term_parser_preserves_strings_and_nested_terms(self):
        for text in ['(A "two words" (B $x))', '(A "escaped \\" quote")']:
            self.assertEqual(_render(_parse(text)), text)
        for text in ["(", ")", "A B"]:
            with self.assertRaises(RuntimeError):
                _parse(text)


if __name__ == "__main__":
    unittest.main()
