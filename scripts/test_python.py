#!/usr/bin/env python3
"""Run the Python suite in parallel, each unit in its own interpreter.

A unit is a test file name under ``tests/`` (default pattern ``test*.py``),
run as ``python -m unittest discover -s tests -p <name>`` from the repository
root, so its tests load as under one serial ``unittest discover -s tests``,
in a fresh process. A file that took more than its share of the previous run
(total time over the worker count) is split into parts of about half a share,
each a group of its tests selected with ``-k`` and balanced by the tests'
recorded durations. A part, not a test, pays the library load, so a file of
many quick tests does not pay it per test. Its tests are listed afresh on
every run, so new tests are never missed; a part fails unless it ran every
test it selected. unittest's exit status decides each unit: failures, errors
and unexpected successes fail it; skips and expected failures do not. A
failing unit's full output, tracebacks included, is printed under its name.
The run fails if any unit fails. With ``-v`` every unit runs verbose and
prints its whole output.

``PETTA_JOBS`` units run at once (default: the CPU count), longest first by
their durations in the previous run, which are kept in the user's cache
directory and only order the work. Each unit writes its query metrics to a
file of its own; they are appended to ``PETTACHAINER_QUERY_METRICS_PATH`` in
unit order at the end.

Run it through ``bench/capped --slots N`` with ``PETTA_JOBS=N``, like
``scripts/test_metta.sh``.
"""
from __future__ import annotations

import json
import math
import os
import re
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DURATIONS = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "pettachainer" / "python-test-seconds.json"
LIST_TESTS = """
import sys, unittest
def ids(suite):
    for test in suite:
        yield from ids(test) if isinstance(test, unittest.TestSuite) else [test.id()]
print("\\n".join(ids(unittest.defaultTestLoader.discover("tests", pattern=sys.argv[1]))))
"""


def run(name: str, tests: tuple[str, ...], metrics: Path | None, verbose: bool) -> tuple[int, float, str]:
    env = dict(os.environ)
    if metrics:
        env["PETTACHAINER_QUERY_METRICS_PATH"] = str(metrics)
    # A -k pattern without "*" matches as a substring; a leading "*" makes it
    # match this one test id.
    select = [arg for test in tests for arg in ("-k", f"*{test}")]
    started = time.monotonic()
    done = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", *(["-v"] if verbose else []),
         "-s", "tests", "-p", name, *select],
        cwd=REPO, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True)
    status = done.returncode
    if tests and status == 0 and not re.search(rf"^Ran {len(tests)} tests? in", done.stdout, re.M):
        status = 1
    return status, time.monotonic() - started, done.stdout


def tests_of(name: str) -> list[str] | None:
    """The test ids of file ``name``, or None when it does not load cleanly
    (it then runs whole and reports its own error)."""
    done = subprocess.run([sys.executable, "-c", LIST_TESTS, name], cwd=REPO,
                          stdin=subprocess.DEVNULL, capture_output=True, text=True)
    ids = done.stdout.split()
    if done.returncode or not ids or any(test.startswith("unittest.") for test in ids):
        return None
    return ids


def main() -> int:
    if sys.argv[1:] not in ([], ["-v"]):
        print(f"Usage: {sys.argv[0]} [-v]", file=sys.stderr)
        return 2
    verbose = sys.argv[1:] == ["-v"]
    jobs = os.environ.get("PETTA_JOBS", str(os.cpu_count()))
    if not jobs.isdigit() or int(jobs) < 1:
        print(f"PETTA_JOBS must be a positive integer, got: {jobs}", file=sys.stderr)
        return 2
    try:
        previous = json.loads(DURATIONS.read_text())
    except (OSError, ValueError):
        previous = {}
    names = sorted({path.name for path in (REPO / "tests").rglob("test*.py")})
    share = sum(previous.get(name, 0) for name in names) / int(jobs)
    units = []
    estimate: dict[tuple[str, tuple[str, ...]], float] = {}
    for name in names:
        tests = tests_of(name) if previous.get(name, 0) > share else None
        if not tests:
            units.append((name, ()))
            estimate[units[-1]] = previous.get(name, float("inf"))
            continue
        # Longest first into the lightest part, by recorded test durations.
        weight = {test: previous.get(test, 1.0) for test in tests}
        parts = [[] for _ in range(min(len(tests), math.ceil(2 * previous[name] / share)))]
        for test in sorted(tests, key=lambda test: -weight[test]):
            min(parts, key=lambda part: sum(weight[t] for t in part)).append(test)
        for part in parts:
            units.append((name, tuple(sorted(part))))
            estimate[units[-1]] = previous[name] * sum(weight[t] for t in part) / sum(weight.values())
    units.sort(key=lambda unit: -estimate[unit])
    metrics_path = os.environ.get("PETTACHAINER_QUERY_METRICS_PATH")
    started = time.monotonic()
    seconds: dict[tuple[str, tuple[str, ...]], float] = {}
    failed = []
    totals: dict[str, int] = {}
    with tempfile.TemporaryDirectory(prefix="pettachainer-python-tests-") as scratch:
        metrics = {unit: Path(scratch) / f"{index}.jsonl" if metrics_path else None
                   for index, unit in enumerate(units)}
        with ThreadPoolExecutor(int(jobs)) as pool:
            futures = {pool.submit(run, *unit, metrics[unit], verbose): unit for unit in units}
            for future in as_completed(futures):
                unit = futures[future]
                status, seconds[unit], output = future.result()
                name, tests = unit
                label = (f"{name} {tests[0].split('.', 1)[1]}" if len(tests) == 1 else
                         f"{name} ({len(tests)} tests from {tests[0].split('.', 1)[1]})" if tests else name)
                ran = re.findall(r"^Ran (\d+) tests? in", output, re.M)
                verdict = output.rstrip().splitlines()[-1] if output.strip() else "no output"
                totals["tests"] = totals.get("tests", 0) + sum(map(int, ran))
                for key, value in re.findall(r"(\w[\w ]*)=(\d+)", verdict):
                    totals[key] = totals.get(key, 0) + int(value)
                if status == 0:
                    print(f"ok    {label:<60} {seconds[unit]:6.1f}s  {verdict}", flush=True)
                    if verbose:
                        print(output.rstrip(), flush=True)
                else:
                    failed.append(label)
                    rule = "=" * 70
                    print(f"\n{rule}\nFAIL  {label} (exit {status}, {seconds[unit]:.1f}s)\n{rule}\n"
                          f"{output.rstrip()}\n{rule}\n", flush=True)
        if metrics_path:
            with open(metrics_path, "a", encoding="utf-8") as stream:
                for unit in units:
                    if metrics[unit].exists():
                        stream.write(metrics[unit].read_text(encoding="utf-8"))
    durations = dict(previous)
    for (name, tests), value in seconds.items():
        if len(tests) == 1:
            durations[tests[0]] = value
    for name in names:
        durations[name] = sum(value for (unit_name, _), value in seconds.items() if unit_name == name)
    DURATIONS.parent.mkdir(parents=True, exist_ok=True)
    temporary = DURATIONS.with_suffix(f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(durations, indent=1, sort_keys=True))
    temporary.replace(DURATIONS)
    counts = "".join(f", {key}={value}" for key, value in sorted(totals.items()) if key != "tests")
    print(f"\nRan {totals.get('tests', 0)} tests in {len(names)} files ({len(units)} units) "
          f"with {jobs} workers in {time.monotonic() - started:.1f}s{counts}")
    if failed:
        print(f"FAILED ({len(failed)} units): {', '.join(sorted(failed))}")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
