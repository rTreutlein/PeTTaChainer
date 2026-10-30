# POSTERIOR1 — working checkpoint, not ready to land

Branch `posterior1`; worktree `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/posterior1`.
Base `2b6c42a8`. This report is a durable checkpoint for continuation, not an acceptance claim.

The inherited uncommitted draft let atomic observations reach the event graph, but its first
quick comparison regressed SupplyNet stage 1 error from .01379 to .03783 and roughly doubled
runtime. The draft also computed the ordinary merged answer before calling the graph.

Current implementation moves graph admission ahead of ordinary merging and row evaluation,
discovers live ground neighbours through conclusion/premise indexes, validates supported
explicit CTV templates throughout discovery, and excludes `no_inverse`, instance-prior and
frozen-summary shapes that its model cannot represent. Observation discovery retains authored
sources, not every unobserved descendant. Confidence-zero compound adapters cannot connect
otherwise disconnected evidence components. Plans depend on the input epoch and overlay frame;
skeleton row generation is no longer an input because discovery now reads compiler indexes.

Stored root counts with no likelihoods remain source counts. This is necessary to prevent
converting a source into a propagated moment before the ordinary fallback consumes it.
Evidence-free predictions still use the ordinary evaluator in this checkpoint. Atomic trees
with fixed CTV branches use exact upward likelihood/joint-goal messages before quadrature;
other admitted models still enumerate worlds. Point parameters are eliminated from those
world terms and identical monomials combined. All numerical inputs still use the existing
stored-count/propagated-moment conversions and the existing event-node numerical safeguards.

## Validation so far

All executed PeTTa/test/benchmark commands used `bench/capped`, `ulimit -v 16000000`, unset
`DISPLAY`, and `/dev/null` stdin. Only this worktree's code was edited; no push, merge, or
GitHub write occurred. Comparisons create their normal external result artifacts.

* P16: all 18 checks pass numerically/parity/omission; the runner reports 17 unexpected
  successes because the original failure ledger has deliberately not yet been edited.
  Evidence: `scratch/posterior1-root-p16.log`, `scratch/posterior1-tree-p16.log`.
* K0: 86 checks, no ordinary failure, six unexpected successes against the original ledger.
  Evidence: `scratch/posterior1-indexed-k0.log`, `scratch/posterior1-independent-k0.log`.
* Source-gated Assuming/Exists and specificity focused checks passed after component-level
  template validation; variable-head ingestion also passed. See
  `scratch/posterior1-admission-tests.log` and `scratch/posterior1-template-ingestion.log`.
* The initial broad Python sweep failed; it is diagnostic only, included intermediate edits,
  and is not final validation (`scratch/posterior1-python-first.log`).
* The source-boundary MeTTa sweep: **142 passed, 20 failed**, including old posterior/proof
  pins and unresolved regressions. `test_nested_consequent_projection` passes. See
  `scratch/posterior1-source-boundary-metta.log`.
* Soft-report/dependence sweep still fails on old semantics/proof pins; do not claim it passes.
  See `scratch/posterior1-boundary-focused.log`.

## Required early performance checkpoint

The complete paired quick run before the source-boundary correction reports:

`REGRESSIONS (2): supplynet stage 1 b25 s2 seconds 1.875 -> 2.905 (rerun 1.72 -> 2.951); scale l spq4 s1 seconds 40.63 -> 58.43 (rerun 40.09 -> 58.71)`

`accuracy changed in 4 cases`

Report: `/nexus/Dev/OpenCog/bench/results/compare/c873c6c3_vs_2b6c42a8-d8769d047_quick/report.md`.
The named master advanced to `c873c6c3` while work proceeded; fixed-base exploratory runs
also used `2b6c42a8` and record that exact base. Scale's repeated slowdown violates the brief's
10% checkpoint. **Do not finish deletions until this has been resolved.**

The indexed hard-source exploratory stage-1 comparison reports PASS, but its inference time
is still approximately 58% higher (1.412 -> 2.233 s in the preceding hard-source run), below
the harness's additional one-second flag threshold. Harness PASS does not establish the brief's
stricter 10% requirement. RSS also needs the final +5% audit.

A full paired quick run of the source-boundary correction was started in
`scratch/posterior1-source-boundary-quick.log`; read its completed result before further work.

## Outstanding acceptance work

The implementation is unfinished. Net production tokens and executable lines are currently
up, not down; no deletion credit is claimed. Inversion/completion and compound fallback
functions have not been deleted. General conjunction/STV template admission and the required
completion replacement remain unfinished. Fix numerical/context regressions before moving
fixture values, and independently derive every changed pin from the D0 oracle or ProbLog.
Shrink `EXPECTED_FAILURES` only after revalidation; it is currently unchanged. Recheck source
identity, exclusion/filtered reads, withdrawal and context teardown after the final design.

Then finish deletions with a symbol audit, report exact token/line deltas and deleted functions,
commit the completed report before final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`,
and run the full master comparison, anchor canary and paired dev-server retimes of flagged
cases. None of those final gates has passed or been claimed at this checkpoint.
