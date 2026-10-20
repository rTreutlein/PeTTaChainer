"""The verify.sh result store: every run's status under the key of what it
tested, so scripts/land.sh can skip the gates for code that already passed.

    verify_cache.py key <repo>                          the key of <repo> now
    verify_cache.py record <repo> <key> <status> <s>    append a run's result
    verify_cache.py lookup <repo>                       print the newest result of
                                                        <repo>'s key if a PASS;
                                                        exit 1 otherwise

The key is the checkout's tree (tracked, modified and untracked files, as
.gitignore leaves them; .claude/ excluded), the PeTTa runtime in its .venv
(the same digest bench/compare.py uses), the installed distributions, the
interpreter and SWI-Prolog. Records go to .claude/verify-cache/records.jsonl
in the main checkout, append-only, shared by all its worktrees. See
docs/agent_workflow.md ("Landing a branch").
"""

import fcntl
import hashlib
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def git(repo: Path, *args: str, env: dict | None = None) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True, env=env).stdout.strip()


def output(*argv: str) -> str:
    try:
        return subprocess.run(argv, capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout.strip()
    except OSError:
        return "missing"


def components(repo: Path) -> dict:
    with tempfile.TemporaryDirectory() as scratch:
        env = dict(os.environ, GIT_INDEX_FILE=f"{scratch}/index")
        git(repo, "add", "-A", "--", ".", ":(exclude).claude", env=env)
        tree = git(repo, "write-tree", env=env)
    packages = next((repo / ".venv/lib").glob("python3*/site-packages"), None)
    digest = hashlib.sha256()
    petta = packages / "petta" if packages else None
    if petta and petta.is_dir():
        for path in sorted(p for p in petta.rglob("*") if p.is_file() and "__pycache__" not in p.parts):
            digest.update(str(path.relative_to(petta)).encode() + b"\0" + path.read_bytes())
    return {"tree": tree, "petta": digest.hexdigest()[:16],
            "distributions": sorted(p.name for p in packages.glob("*.dist-info")) if packages else [],
            "python": output(str(repo / ".venv/bin/python"), "-VV"), "swipl": output("swipl", "--version")}


def key(identity: dict) -> str:
    return hashlib.sha256(json.dumps(["verify-cache 1", identity], sort_keys=True).encode()).hexdigest()


def store(repo: Path) -> Path:
    return Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")).parent / ".claude/verify-cache/records.jsonl"


def main(command: str, repo: str, *args: str) -> int:
    repo = Path(repo).resolve()
    identity = components(repo)
    if command == "key":
        print(key(identity))
        return 0
    if command == "record":
        started, status, seconds = args
        # A tree edited while the gates ran tested neither version.
        if key(identity) != started:
            print("verify cache: the checkout changed during the run; result not recorded")
            return 0
        path = store(repo)
        path.parent.mkdir(parents=True, exist_ok=True)
        entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "key": started, "status": status, "seconds": int(seconds),
                 "host": socket.gethostname(), "repo": str(repo), "head": git(repo, "rev-parse", "HEAD"), **identity}
        with open(path, "a") as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            stream.write(json.dumps(entry) + "\n")
        print(f"verify cache: recorded {status} under key {started[:12]}")
        return 0
    # The newest result of the key decides: a later failure of the same code
    # (a flaky gate, a starved run) withdraws an earlier pass.
    path, wanted = store(repo), key(identity)
    r = next((r for r in map(json.loads, reversed(path.read_text().splitlines() if path.exists() else [])) if r["key"] == wanted), None)
    if not r or r["status"] != "PASS":
        return 1
    print(f"PASS of {r['time']} ({r['seconds']} s) in {r['repo']} at {r['head'][:8]} on {r['host']}, key {wanted[:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
