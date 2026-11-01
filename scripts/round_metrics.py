#!/usr/bin/env python3
"""Append best-effort landing metrics; arguments: REPO BRANCH BASE LANDED."""

import csv
from datetime import datetime, timezone
import fcntl
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile

RESULTS = Path("/nexus/Dev/OpenCog/bench/results")
HEADER = ("date", "branch", "base_commit", "landed_commit", "branch_commits",
          "hours", "files_changed", "lines_added", "lines_removed",
          "core_tokens_before", "core_tokens_after", "compare_reports",
          "two_way_pairs", "cross_functions", "widest_interface",
          "largest_function_scc", "functions_in_cycles")


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], stdin=subprocess.DEVNULL)


def tokens(repo, commit):
    try:
        import tiktoken
    except ImportError:
        return ""
    encoding = tiktoken.get_encoding("o200k_base")
    with tarfile.open(fileobj=io.BytesIO(git(repo, "archive", commit))) as tree:
        return sum(len(encoding.encode(tree.extractfile(member).read().decode("utf-8"),
                                       disallowed_special=()))
                   for member in tree if member.isfile() and (
                       (member.name.startswith("pettachainer/metta/") and
                        Path(member.name).suffix in (".metta", ".pl")) or
                       (Path(member.name).parent == Path("pettachainer") and
                        member.name.endswith(".py"))))


def append(repo, branch, base, landed, results=RESULTS):
    base = git(repo, "rev-parse", base).decode().strip()
    landed = git(repo, "rev-parse", landed).decode().strip()
    commits = git(repo, "log", "--reverse", "--abbrev=8", "--format=%h %ct", f"{base}..{branch}").decode().splitlines()
    hashes = tuple(line.split()[0] for line in commits)
    now = datetime.now(timezone.utc)
    hours = (now.timestamp() - int(commits[0].split()[1])) / 3600
    stats = git(repo, "diff", "--numstat", f"{base}..{landed}",
                "--", "pettachainer")
    changes = [entry.split(b"\t", 2) for entry in stats.splitlines()]
    iterations = 0
    for report in results.glob("compare/*/compare.json"):
        candidate = json.loads(report.read_text())["candidate"]
        label = candidate if isinstance(candidate, str) else candidate[1 if len(candidate) == 4 else 0]
        iterations += label.startswith(hashes)
    coupling = json.loads(subprocess.check_output(
        [sys.executable, str(Path(__file__).with_name("coupling.py")), landed, "--json"],
        cwd=repo, stdin=subprocess.DEVNULL))
    row = (now.isoformat(), branch, base, landed, len(commits), round(hours, 6),
           len(changes), *(sum(int(entry[i]) for entry in changes if entry[i] != b"-")
                           for i in (0, 1)), tokens(repo, base), tokens(repo, landed), iterations,
           *(coupling[name] for name in HEADER[12:]))
    results.mkdir(parents=True, exist_ok=True)
    with (results / "round-metrics.csv").open("a+", newline="") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        stream.seek(0)
        header = next(csv.reader(stream), None)
        writer = csv.writer(stream)
        if header != list(HEADER):
            # Extend the header only; historical rows keep their original fields.
            previous_rows = stream.read()
            stream.seek(0)
            stream.truncate()
            writer.writerow(HEADER)
            stream.write(previous_rows)
        stream.seek(0, 2)
        writer.writerow(row)


if __name__ == "__main__":
    try:
        append(*sys.argv[1:])
    except Exception as error:
        print(f"round metrics: warning: {error}", file=sys.stderr)
