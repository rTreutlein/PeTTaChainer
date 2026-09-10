# Original-reference diagnosis quality check

The reference for the original optimization objective is `1bfbf539`, before
removing the base-rate success prior. `c0cd54e3`, used as a control in subsequent
experiments, already includes that removal. Comparing only against that later
control can establish a local speedup while preserving the original quality
regression.

`benchmarks/stationops/quality_gate.py` compares completed benchmark JSON files.
It checks diagnosis and post-inspection beliefs, individual answered goal IDs,
MAE and maximum error against the oracle posterior, Brier and log loss against
sampled hidden faults, regret, score, and search aborts. A changed budget or
incomplete episode is rejected. A smaller runtime never overrides a quality
failure. Error tolerance is only `1e-12` for numerical noise; no acceptable
quality tradeoff has been selected.

Different answered goal sets make the game's aggregate errors incomparable.
Lost answers fail the check; additional answers require review rather than
being labelled a regression. An unresolved comparison also exits nonzero, so
it cannot silently pass automation. Future scoring on a shared goal set with
captured oracle targets would allow fair numerical comparison when coverage
improves. Differing visible inputs or preceding actions/outcomes likewise
require review. This is a conservative screening tool, not a proof-validity
validator or a statistical performance gate.

For bookkeeping-only optimizations, continue using `compare.py` to require
exact semantic results and full returned proofs after KB UUID normalization.
Reasoning changes may legitimately change proofs; their logical validity still
requires the runtime regression suite. Neither check replaces the other.

## Reproduce

The benchmark driver now accepts `--seed` and `--budget`; defaults remain
seed 7 and budget 600. Its existing seed-7 coverage/score/regret assertions
remain. Run it with the repository's `.venv/bin/python`, selected source trees,
and the same frozen game and supported PeTTa runtime on both sides:

```sh
.venv/bin/python benchmarks/stationops/benchmark.py \
  --repository /path/to/frozen-chainer \
  --chainergame /path/to/frozen-game \
  --petta /path/to/frozen-supported-runtime \
  --seed 7 --budget 600 --json-out /tmp/run.json

.venv/bin/python benchmarks/stationops/quality_gate.py \
  /tmp/original-7.json /tmp/current-7.json --json-out /tmp/gate-7.json
```

The other screening workloads use seeds 11 and 23, each with budget 300.
All have two shifts, four modules, and action budget 1. Freeze and record the
source revisions yourself when using the single-run driver; the gate does not
infer revision identity from filesystem paths.

## Fresh screening results

Both sides used ChainerGame `99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`
and supported PeTTa `e1aac8b791cf70b7843173b613f04b869b666979` from frozen
archives. Reference source is `1bfbf539c06c8e77ab45327ae9a9e9888393a435`;
current source is `94a52ce9d4267ba54d421dcd68e7f416cf499d54`, including compact
demand. No fetch or rebuild occurred. Runtime code was unchanged during runs;
benchmark tooling and documentation were edited in the isolated worktree.
The main checkout and the other agent's work were left untouched.

| Seed / budget | Total diagnosis seconds, original → current | Shift 2 coverage | Shift 2 Brier | Quality assessment |
|---|---:|---:|---:|---|
| 7 / 600 | 113.55 → 87.64 | 100% → 100% | 0.031036 → 0.163857 | Clear regression |
| 11 / 300 | 10.37 → 6.70 | 25% → 50% | Incomparable covered sets | Improved coverage; review quality |
| 23 / 300 | 10.77 → 4.81 | 25% → 50% | Incomparable covered sets | Improved coverage; review quality |

Shift-one coverage has the same percentages as shift two for each side/seed.
Scores, regrets, inspections, and repair outcomes match within each pair.
All six episodes completed with zero aborts across 12 diagnosis batches.
Seed 7 also has worse first-shift errors. The strict numerical gate additionally
flags a tiny seed-23 first-shift post-inspection Brier increase,
0.0078124921875 → 0.0078124925522 (about 3.65e-10); this is not evidence of a
material quality loss. Its raw diagnosis averages remain incomparable because
more goals were answered. No tradeoff threshold was tuned to make these runs pass.

These are single observations per setting, run sequentially in original order
7/11/23 followed by current order 23/11/7. They are quality screening evidence,
not repeated interleaved performance acceptance. In particular, the seed-7
22.8% observed speedup does not satisfy the original equal-quality objective.

Validation: eight quality-gate regressions and two existing benchmark-support
tests passed (`python -m unittest tests.test_stationops_quality_gate
tests.test_benchmark_support -v`). No runtime code changed in this follow-up,
so the MeTTa suite was not rerun. Full inputs, returned proofs, metrics,
environments, and gate output are retained in
the result artifact, `original-quality-results-2026-09-09.json` (removed from the tree to keep it small; retrieve it with `git show 3ada65a7:benchmarks/stationops/original-quality-results-2026-09-09.json`).
Raw logs and the frozen-source driver remain in local
`scratch/original-quality-2026-09-09/`.

## Remaining mechanism

The checked current source includes consumer-specific proof selection and the
compact demand projection. It does not include the separate shorter-path
experiment. In `ensure-goal-at-depth`, an already-expanded goal retains its
stored depth even when a shallower route arrives later. Consequently the
consumer fix alone does not ensure that the independent alarm evidence is
reached within the finite budget.

The earlier [consumer-view investigation](stationops_consumer_views_2026-09-09.md#combined-shorter-path-diagnostic)
captured the distinction: without the shorter-path experiment, the independent
dependency was absent and M01 remained at strength 0.2205079337. Combining the
two changes reached the independent M03 alarm dependency, used it without
cyclic self-support, and returned M01 at 0.7195391377. That combined experiment
was not adopted or fully validated, and its other seeds did not establish a
general quality improvement. The new runs do not collect internal store traces;
the derivation attribution comes from that recorded investigation.

Do not claim that consumer-specific selection by itself restored the original
answer quality. Establish that missing search-path behavior and its broader
quality effects before adopting further scheduler changes. Keep the validated
compact-demand optimization isolated: its exact-result comparison establishes
a bookkeeping speedup, not completion of the original objective.
