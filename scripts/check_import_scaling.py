#!/usr/bin/env python3
"""Check that inversion-eligible bulk imports do not slow as state grows."""

from __future__ import annotations

import argparse
import json
import logging
import statistics
import time
from pathlib import Path

from pettachainer import PeTTaChainer


def generated_statements(count: int) -> list[str]:
    return [
        (
            f"(: import_scaling_{index} "
            f"(Implication (Premises (ImportScalingSource{index} $x)) "
            f"(Conclusions (ImportScalingTarget{index} $x))) "
            "(CTV (STV 0.7 0.393469) (STV 0 1)))"
        )
        for index in range(count)
    ]


def load_statements(path: Path, start_line: int, count: int) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    statements = lines[start_line - 1 : start_line - 1 + count]
    if len(statements) != count:
        raise SystemExit(
            f"wanted {count} statements from line {start_line}, "
            f"but {path} supplied {len(statements)}"
        )
    return statements


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        type=Path,
        help="read one MeTTa statement per line instead of generating input",
    )
    parser.add_argument("--start-line", type=int, default=45000)
    parser.add_argument("--statements", type=int)
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument("--chunk-size", type=int)
    parser.add_argument(
        "--max-growth",
        type=float,
        default=1.5,
        help="maximum allowed late-chunk/early-chunk median ratio",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    statement_count = args.statements or (20000 if args.input else 8000)
    chunk_size = args.chunk_size or (5000 if args.input else 2000)
    if statement_count < chunk_size * 4:
        raise SystemExit("the scaling check requires at least four chunks")
    if statement_count % chunk_size:
        raise SystemExit("statement count must be divisible by chunk size")
    if chunk_size % args.batch_size:
        raise SystemExit("chunk size must be divisible by batch size")

    statements = (
        load_statements(args.input, args.start_line, statement_count)
        if args.input
        else generated_statements(statement_count)
    )

    logging.getLogger().setLevel(logging.WARNING)
    handler = PeTTaChainer()
    rows: list[dict[str, float | int]] = []
    total_started = time.perf_counter()
    for chunk_start in range(0, statement_count, chunk_size):
        chunk = statements[chunk_start : chunk_start + chunk_size]
        started = time.perf_counter()
        for batch_start in range(0, len(chunk), args.batch_size):
            handler.add_atoms_no_check(
                chunk[batch_start : batch_start + args.batch_size]
            )
        seconds = time.perf_counter() - started
        row: dict[str, float | int] = {
            "start": chunk_start + 1,
            "end": chunk_start + len(chunk),
            "seconds": seconds,
            "statements_per_second": len(chunk) / seconds,
        }
        rows.append(row)
        print(
            f"{row['start']:>6}-{row['end']:<6}  "
            f"{seconds:8.3f}s  {row['statements_per_second']:8.1f} stmt/s",
            flush=True,
        )

    times = [float(row["seconds"]) for row in rows]
    half = len(times) // 2
    early_median = statistics.median(times[:half])
    late_median = statistics.median(times[-half:])
    growth = late_median / early_median
    increases = sum(right > left for left, right in zip(times, times[1:]))
    clear_growth = growth > args.max_growth and increases >= len(times) - 2
    payload = {
        "input": str(args.input.resolve()) if args.input else "generated",
        "start_line": args.start_line if args.input else None,
        "statements": statement_count,
        "batch_size": args.batch_size,
        "chunk_size": chunk_size,
        "total_seconds": time.perf_counter() - total_started,
        "early_chunk_median_seconds": early_median,
        "late_chunk_median_seconds": late_median,
        "late_to_early_ratio": growth,
        "max_growth": args.max_growth,
        "chunks": rows,
        "status": "FAIL" if clear_growth else "PASS",
    }
    if args.json_out:
        args.json_out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print(
        f"late/early median ratio: {growth:.3f} "
        f"(limit {args.max_growth:.3f})"
    )
    if clear_growth:
        print("FAIL: import chunks show clear accumulated-state growth")
        return 1
    print("PASS: no clear accumulated-state growth")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
