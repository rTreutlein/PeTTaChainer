# Evaluator call-cycle reduction

Base: `2bd2f6ca625a853b5102e707c91f051cef9cb62e`, branch `scc-shrink`.
Implementation: `dfeb453a527dcc3058325f50395e631ece879158`
(`Separate lazy evaluator reads from merge and fold computation`).
Benchmarked frozen build: `2bd2f6ca-d020d024b`, runtime tree `4ec8cd120b35`;
committing changed no runtime source.

## Design as built

The recursive value/row/conditioning kernel stays in `eval_core.metta`.
Three earlier compiler units receive typed reader capabilities:

- `eval_merge.metta`: evidence comparison, merge modes, reference-class selection,
  sample pooling and overlap components.
- `eval_folds.metta`: member folds, incremental rate/instance maintenance, coverage,
  compound priors and evidence, and population/message calculations.
- `eval_sampling.metta`: stored-premise predictions and outcome scoring.

A capability is data containing a reader, unpacked and explicitly typed at an
actual read. Passing a bare higher-order reader across these units caused PeTTa
specialization to lose argument typing. Keeping the capability intact between
stages preserves the compiler boundary. No eager member-value collection was
introduced: member reads, pending-member handling, reference-row rereads and mode
learning still happen in their original order and only on the branches that used
them before. Rate takes retain their own exclusion-aware reader registration.

The native event graph still calls `sk-part-prior` with its original signature;
that entry supplies the ordinary value reader to `sk-cavity-prior`. The reserved
worker's `sk-rate-take!` entry similarly supplies the reader to `sk-take-rate`.
The early shared `sk-merge-facts` interface delegates to the pure pair comparison.
These are current caller boundaries, not compatibility implementations.

Six internal functions were deleted and their callers rewired:
`sk-chain-weight`, `sk-admitted`, `sk-given-value`, `sk-admitted-merge`,
`sk-left-out-view`, and `sk-node-state`. Five boundary/selection functions were
added: `sk-pair-facts`, `sk-take-rate`, `sk-sibling-value`, `sk-outcome-step`, and
`sk-cavity-prior`. The backward runtime therefore has one fewer function overall.

The named outcome-selection step is necessary: lifting its local `view` binding
into a lambda shared it across fold iterations and changed learned combination
answers. Restoring a typed step restored the original answers. Existing row and
fold kernels that protect writable variables remain boundaries.

## Measurements

Commands were run from this worktree using the supplied `scratch/scc.py` and
`scratch/core_count.py`.

| Measure | Before | After | Change |
| --- | ---: | ---: | ---: |
| Largest backward-runtime SCC | 83 | 29 | -54 (65.1%) |
| Backward-runtime functions | 673 | 672 | -1 |
| `eval_core.metta` o200k tokens | 31,760 | 15,499 | -16,261 |
| Core o200k tokens | 323,955 | 323,864 | -91 |
| Third-party o200k tokens | 17,685 | 17,685 | 0 |
| Core plus third party | 341,640 | 341,549 | -91 |

The 29-function SCC is entirely in `eval_core.metta`; the next-largest SCC
remains 27. The 50 functions in the three extracted units form only singleton
SCCs when analyzed together. Token savings include condensing duplicated design commentary;
the counts above use the brief's complete-source metric. Reader capabilities
preserve runtime recursion and lazy effects while removing implicit source-level
back edges from the extracted families.

Evidence: `scratch/scc-before.txt`, `scratch/scc-after.txt`,
`scratch/scc-extracted.txt`, `scratch/tokens-before.txt`, `scratch/tokens-after.txt`.

## Validation

- Extraction checkpoint: MeTTa suite, **162 passed, 0 failed**.
- Cleanup checkpoint: MeTTa suite, **162 passed, 0 failed**.
- Final `scripts/verify.sh`: **PASS**, all six gates in 695 s:
  MeTTa lint; 162 MeTTa files; 988 Python tests in 62 files / 589 units
  (64 expected failures, one nightly skip); import scaling; judgment scaling;
  ConceptNet. Query metrics: 4,485 Python query rows and three judgment-scaling
  query rows, zero aborts. Log: `scratch/verify-final.log`.
  The script exited zero, but did not record the shared cache entry because this
  report was edited during the run. Runtime sources stayed unchanged.
- Quick comparison against master: **PASS**, accuracy changed in **0 cases**.
  This checkpoint preceded restoration of the native event-graph entry point.
  Report: `/nexus/Dev/OpenCog/bench/results/compare/2bd2f6ca_vs_2bd2f6ca-d2381b37b_quick/report.md`.
- Final full comparison against master: **PASS**, identical accuracy in all
  22 accuracy cases; 23 cases total, 43 runs executed, two results reused,
  682 s wall. All 45 selected records exited zero. `scratch/full.log`;
  `/nexus/Dev/OpenCog/bench/results/compare/2bd2f6ca_vs_2bd2f6ca-d020d024b_full/report.md`.
  The 100-KB fuzzer has the same five existing error flags and one existing
  no-answer flag on both builds, zero crashes, unsupported KBs or budget
  regressions, and identical mean absolute error `0.005060085160683605`.
- Initial anchor canary: accuracy completed, but all dev-server invocations used
  a local-only worktree interpreter path and exited 127. Its nominal PASS is
  insufficient for the timing gate.
- Canonical anchor canary with `--retime` and the runner's standard interpreter
  path: **PASS**, all 12 remote runs exited zero at load 1, 315 s wall;
  `scratch/canary-retime.log`. The frozen candidate and PeTTa fingerprint
  `eec735bf4d1d3e31` are unchanged. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_2bd2f6ca-d020d024b_canary-retime-20261029T222543/report.md`.
  Four accuracy differences and nine behind-anchor flags are already present on
  master; the canonical master comparison reports no blocking regression.
- Focused nightly root-refinement bound test: **PASS**, one test in 162.669 s;
  `scratch/nightly-root.log`.

No expected truth value, proof shape, scheduler score, or `EXPECTED_FAILURES`
entry was changed. Tests calling deleted or parameterized internals now call
the owning operation or supply its reader capability; their assertions remain.
The exclusion-cut probe exercises admission rather than the deleted local read.

Exact-symbol audit of every deleted function over `pettachainer/`, `third_party/`,
`tests/`, and `docs/`: **zero hits**. Reserved files, master, the main checkout,
and other worktrees were not edited. No push, merge or GitHub write was performed.
All PeTTa, suite and benchmark commands used `bench/capped`, `ulimit -v 16000000`,
unset `DISPLAY`, and `/dev/null` stdin. Verification's runner-owned shared cache
write is the allowed exception from the brief.
