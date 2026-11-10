# Midpoint round evidence

`review-after.jsonl` is byte-identical to `../review/after.jsonl`: all 58
previous review answers, their truth values and proofs, are unchanged.

`reviewer-before4.log` and `reviewer-before5.log` copy the reviewer's branch
measurements before this change. `fixtures.json` captures the same probe4/probe5
inputs; `graded-after.jsonl` replays them. `graded-changes.jsonl` lists all eight
changed supplementary readings: five requested rows, nine_strong and the two
sh_graph compound reads. Their confidence and proof shapes are unchanged.

`cases-after.jsonl` repeats the original 21 cases. Only the derived graded
rule-part-ctv strength moves; cases 4–9 and the full-parts conflict are unchanged.
`verify.log` records the final full verification, with trailing whitespace removed. `benchmarks/` contains
exports and capture analysis from the standard comparator.

Reproduce from the worktree root (all runtime jobs use the pinned venv):

```bash
unset DISPLAY
ulimit -v 16000000
timeout 900 /nexus/Dev/OpenCog/bench/capped .venv/bin/python \
  docs/history/i183_lookup/review/probes.py \
  docs/history/i183_lookup/midpoint/fixtures.json </dev/null
```

Omit the fixture argument for the 58-row review ledger; use
`docs/history/i183_lookup/cases.py` for the original 21 cases. Gates used
`timeout 1200 capped --slots 8 env PETTA_JOBS=8 scripts/verify.sh` and
`timeout 3600 capped env PETTACHAINER_REPO=<worktree> compare.sh ...`, with
absolute `capped`/`compare.sh` paths under `/nexus/Dev/OpenCog/bench`, the same
resource limit, DISPLAY unset and stdin `/dev/null`.
