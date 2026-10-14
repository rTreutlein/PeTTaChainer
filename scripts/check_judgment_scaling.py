#!/usr/bin/env python3
"""Check private implication routing and warm queries against unrelated KB growth.

Run with the worktree's Python through bench/capped, like check_import_scaling.
Ingestion and first-query journal activation are outside the measured work.
"""
from __future__ import annotations

import json
import statistics
import time

import janus_swi

from pettachainer import PeTTaChainer


def main() -> int:
    chainer = PeTTaChainer()
    chainer.add_atoms_no_check([
        "(: r (Implication (Not (A Item)) (B Item)) (STV 0.8 0.9))",
        "(: (no_inverse bridge) (Implication (B Item) (C Item)) "
        "(CTV (STV 1 1) (STV 0 1)))",
    ])
    query = "(: $p (Implication (Not (A Item)) (C Item)) $tv)"
    # Retain one private assumption solely to measure the exact routing hot path.
    chainer._call("compileadd", [
        f"({chainer.kb} ScalingContext Nil) (: (ctx proof scaling) (A Item) (STV 0 1))"
    ])
    control = [f"(A Item) ({chainer.kb} ScalingContext Nil)"]
    routing = [f"(MissingAssumption Item) ({chainer.kb} ScalingContext Nil)"]
    metrics_enabled = chainer._query_metrics_enabled
    rows = []
    previous = 0
    for count in (0, 10000, 40000):
        for start in range(previous, count, 100):
            chainer.add_atoms_no_check([
                f"(: noise{i} (Unrelated {i}) (STV 0.5 0.9))"
                for i in range(start, min(start + 100, count))
            ])
        previous = count
        # Diagnostic snapshots count the accumulated skeleton and would measure
        # history size rather than query work. Keep their abort check on the
        # warm-up, then measure live queries without the snapshot overhead.
        chainer.set_query_metrics(metrics_enabled)
        chainer.query(query, steps=100, timeout_sec=None)
        chainer.set_query_metrics(False)
        times = []
        inferences = []
        for _ in range(5):
            before = janus_swi.query_once("statistics(inferences, N)")["N"]
            started = time.process_time()
            for _ in range(20):
                answers = chainer.query(query, steps=100, timeout_sec=None)
                assert len(answers) == 1 and "STV 0.8 " in answers[0], answers
            times.append((time.process_time() - started) / 20)
            after = janus_swi.query_once("statistics(inferences, N)")["N"]
            inferences.append((after - before) / 20)
        routing_times = []
        control_times = []
        for _ in range(5):
            started = time.process_time()
            for _ in range(200):
                assert chainer._call("judgment-assumed-key?", routing) == ["false"]
            routing_times.append((time.process_time() - started) / 200)
            started = time.process_time()
            for _ in range(200):
                assert chainer._call("judgment-assumed-key?", control) == ["true"]
            control_times.append((time.process_time() - started) / 200)
        rows.append({"unrelated_facts": count,
                     "query_cpu_seconds": statistics.median(times),
                     "query_inferences": statistics.median(inferences),
                     "routing_cpu_seconds": statistics.median(routing_times),
                     "control_cpu_seconds": statistics.median(control_times),
                     "routing_to_control": statistics.median(routing_times) / statistics.median(control_times)})
    ratios = {metric: rows[-1][metric] / rows[0][metric]
              for metric in ("query_inferences", "routing_to_control")}
    passed = ratios["query_inferences"] < 1.2 and ratios["routing_to_control"] < 2
    print(json.dumps({"rows": rows, "large_to_empty_ratios": ratios,
                      "max_query_inference_growth": 1.2, "max_routing_growth": 2, "status": "PASS" if passed else "FAIL"}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
