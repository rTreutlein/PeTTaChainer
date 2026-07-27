#!/usr/bin/env python3
"""Export a reproducible compiled ConceptNet rule dump for one checkout."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
import time


BATCH_SIZE = 100


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pettachainer-root", required=True, type=Path)
    parser.add_argument("--petta-root", required=True, type=Path)
    parser.add_argument("--dump", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--kb", required=True)
    parser.add_argument("--rule-shape", required=True, choices=("raw", "wrapped"))
    parser.add_argument("--strict-det", action="store_true")
    parser.add_argument("--progress-every", type=int, default=10000)
    return parser.parse_args()


def export_predicate(janus, path: Path, goal: str, output: str) -> int:
    result = janus.query_once(
        "nb_setval(export_count, 0),"
        "open(Path, append, _Stream),"
        "setup_call_cleanup(true,"
        f"forall({goal}, (portray_clause(_Stream, {output}),"
        "nb_getval(export_count, _N0), _N is _N0 + 1,"
        "nb_setval(export_count, _N))),"
        "close(_Stream)),"
        "nb_getval(export_count, Count)",
        {"Path": str(path)},
    )
    if result is None:
        raise RuntimeError(f"Could not export rows for {goal}")
    return int(result["Count"])


def main() -> int:
    args = parse_args()
    chainer_root = args.pettachainer_root.resolve()
    petta_root = args.petta_root.resolve()
    dump_path = args.dump.resolve()
    out_path = args.out.resolve()

    if not (chainer_root / "pettachainer" / "pettachainer.py").is_file():
        raise SystemExit(f"Invalid PeTTaChainer checkout: {chainer_root}")
    if not (petta_root / "src" / "main.pl").is_file():
        raise SystemExit(f"Invalid PeTTa checkout: {petta_root}")
    if not dump_path.is_file():
        raise SystemExit(f"Missing PLN dump: {dump_path}")

    os.environ["PETTA_PATH"] = str(petta_root)
    sys.path.insert(0, str(petta_root / "python"))
    sys.path.insert(0, str(chainer_root))

    import petta

    petta.PeTTa(petta_path=str(petta_root))
    # Older PeTTa revisions do not consistently honor the Python wrapper's
    # quiet default. Set the Prolog-side flag before PeTTaChainer loads and
    # compiles its libraries so large exports remain usable.
    petta.janus.query_once("retractall(silent(_)),assertz(silent(true))")
    if args.strict_det:
        petta.janus.query_once(
            "retractall(strict_mode(_)),assertz(strict_mode(true)),"
            "retractall(strict_det(_)),assertz(strict_det(true))"
        )

    from pettachainer import PeTTaChainer

    handler = PeTTaChainer()
    handler.kb = args.kb
    loaded = 0
    batch: list[str] = []
    started = time.monotonic()
    with dump_path.open("rt", encoding="utf-8") as source:
        for raw_line in source:
            atom = raw_line.strip()
            if not atom:
                continue
            batch.append(atom)
            if len(batch) < BATCH_SIZE:
                continue
            handler.add_atoms_no_check(batch)
            loaded += len(batch)
            batch = []
            if args.progress_every and loaded % args.progress_every == 0:
                elapsed = time.monotonic() - started
                print(
                    f"loaded={loaded} elapsed_sec={elapsed:.1f} "
                    f"rate_per_sec={loaded / elapsed:.1f}",
                    file=sys.stderr,
                    flush=True,
                )
    if batch:
        handler.add_atoms_no_check(batch)
        loaded += len(batch)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "wt", encoding="utf-8", dir=out_path.parent, delete=False
    ) as output:
        temp_path = Path(output.name)
        rule_arity = 4 if args.rule_shape == "wrapped" else 3
        output.write(f":- dynamic rules/{rule_arity}.\n")
        output.write(":- dynamic prem_index/4.\n")
        output.write(":- dynamic ccls_index/2.\n")
        output.write(":- dynamic ccls_head_index/2.\n\n")

    if args.rule_shape == "wrapped":
        rules_goal = "rules('runtime-rule-row', _A, _B, _C)"
        rules_output = "rules('runtime-rule-row', _A, _B, _C)"
    else:
        rules_goal = "rules(_A, _B, _C)"
        rules_output = "rules(_A, _B, _C)"
    rows = {
        "rules": export_predicate(
            petta.janus,
            temp_path,
            rules_goal,
            rules_output,
        ),
        "prem_index": export_predicate(
            petta.janus,
            temp_path,
            "prem_index(_A, _B, _C, _D)",
            "prem_index(_A, _B, _C, _D)",
        ),
        "ccls_index": export_predicate(
            petta.janus,
            temp_path,
            "ccls_index(_A, _B)",
            "ccls_index(_A, _B)",
        ),
        "ccls_head_index": export_predicate(
            petta.janus,
            temp_path,
            "ccls_head_index(_A, _B)",
            "ccls_head_index(_A, _B)",
        ),
    }
    if not rows["rules"]:
        temp_path.unlink()
        raise SystemExit("Export produced no rules")
    if not rows["prem_index"] or not rows["ccls_index"]:
        temp_path.unlink()
        raise SystemExit("Export produced incomplete rule indexes")
    temp_path.replace(out_path)

    elapsed = time.monotonic() - started
    print(
        json.dumps(
            {
                "checkout": str(chainer_root),
                "kb": args.kb,
                "loaded": loaded,
                "elapsed_sec": round(elapsed, 3),
                "rows": rows,
                "output": str(out_path),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
