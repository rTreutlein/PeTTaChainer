# Merge 1b: unified implication reads with master scheduling

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/merge1b`.
Branch: `merge1b`. Baseline: `d1ee51a7d6d643ea0c36105e415d835ad3de6c51`.

Status: the unified implication judgment reads and both blocker fixes are
retained. Follow-up commit `184d95c254d4a38e8215e4c9ba9998be99102780`
restores master's 0.99 open-proof discount and scheduler-score expectations.
The restoration changes only `runtime/scheduling.metta` and the two score
arrays in `test_hypothesis_rules.metta`; both files are byte-identical to
master `9102bd1cd00e019947d6af69c3a23f0a5cb737c8`.

Original implementation: `f935041d9ae4e5fb671b1a506e6cc2cb2fb903f8`;
original report: `5289defbec4bf781574cf4f511508c48fefc1dc9`. The follow-up
commits use the same `Co-Authored-By` and `Claude-Session` trailers.
No rebase or merge was performed.

## Diagnosis and design as built

Positive judgments and executable CTVs now use the ordinary implication key.
The private positive namespace, namespace unwrapping/read redirection,
stored-source collector and copied positive producers are deleted. Original
facts and original producer values supply both value policies. Hypothetical
judgment worlds retain their private assumptions, consequent metadata,
necessary-assumption checks, borrowing restrictions and temporary/permanent
ownership. No replacement namespace or private statement tag was introduced.

Two small typed boundaries implement the shared read: `sk-read-fact` projects a
positive branch when appropriate, and `sk-read-value` preserves the value's
evidence and dependencies while doing so. Ordinary, conditioned, compatible,
representative and waiting reads use the same policy. Positive reads select
admissible values before merging instead of accepting an open merge containing
executable assumptions or the other value policy.

An executable conversion of an explicitly stated STV is that same source,
not an additional positive judgment. An indexed source lookup compares the
complete statement, scope and step proof by alpha identity without binding the
caller. The raw positive source already supplies that value. This prevents
both duplicate revision and substituting a base-rate-reconciled executable
branch for the original stated positive.

Sources store one immutable TV per statement/proof identity. CTVs are no longer
also published as STVs; quantified sources retain their canonical statement
shape with the same source value. Root discovery finds raw stored keys before
filtering proof/TV, preserving open, ground, negated and quantified zero-budget
source reads. Public `add-to-kb` sources use the same leaf path.

The shared-path fixes preserve both original semantic blocker tests:

- STV/CTV policies read one two-branch sample tally and one population; the
  separate positive-only finish is deleted. Positive-only instance results
  require positive evidence after projection. The inheritance-premise answer
  remains STV (0.8, 0.0012484394506833685), with one instance-fold proof;
  the cyclic-sample test remains empty. A single unit sample gives confidence
  1/(800+1) = 0.0012484394506833685, rather than two independently revised
  copies giving 2/(800+2) = 0.0024937655860349127.
- An Assuming implication remains an executable seed for bookkeeping and its
  ContextRule guard. A positive judgment rejects that seed. The self-judgment
  conjunction remains empty, while the assumed rule's application retains
  STV (0.15799999999999997, 0.11518282916803525).

Further regressions found while removing the old route are fixed at their
sources. Copying stored STVs back into the same key multiplied facts during
repeated scaffold installation; copying a CTV's positive TV into its ordinary
source identity made an identical repeated source fail validation. Both copies
are gone. A focused forward-copy probe then caught lost provenance when a
positive projection was treated as a fresh observation. Forward copies and
frozen summaries now retain their original evidence/dependencies under the
read policy, and live CTV producer views supply positive reads directly.

Positive implication and quantified judgments, including their hypothetical
premise proofs, are not materialized as MAIN observations. Ordinary
materialization remains unchanged. The design is documented in
`docs/metta/implication_lowering.md`.

The 0.99 open-proof priority multiplier is restored exactly as on master.
`is-var` tests the proof without binding it, so a bound premise's expansion
wins the priority tie. CPU policies, including zero search priority for settled
steps, are unchanged. The coordinator retained this policy because its removal
alone delayed paid conditioning for fuzzer seed 22000162, `(D b)`, budget 2000:
0.41847500000000004 instead of master's 0.3991304347827556 (oracle
0.3991304347810001). This restoration preserves anytime quality without
changing the implication design. No API signature, calibration oracle or
expected-failure entry was changed.

## Tests and moved pins

The follow-up strict MeTTa suite, run by `scripts/verify.sh`, passes
**161 tests, zero failed**. The original focused prior-definition suite passed
all **35 tests** (`scratch/merge1b/single-source-prior.log`); the new full gates
below validate the restored scheduler.

All existing TV expectations remain unchanged. The original implication-premise
proof pin is also unchanged. The follow-up restores the two scheduler arrays;
the implication proof presentation change from merge 1b is retained:

| Pin | Before | After / reason |
| --- | --- | --- |
| `test_hypothesis_rules.metta`, initial scheduler array, for A and C | 0.009999000099989962, 0.01, 0.009000000000000001 | 0.0099, 0.0099, 0.009000000000000001. Restored master scores under the 0.99 open-proof discount. |
| Same file, reviewed A scores | 0.3972575715401417, 0.3972972972972973, 0.3575675675675676 | 0.3933243243243243, 0.3933243243243243, 0.3575675675675676. Restored master scores; C returns to the master initial scores. Learned CTVs are unchanged. |
| `test_forward_backward_compose.metta`, open identity proof | Revision of the exact conditional identity and an empirical fold | Exact conditional identity alone; STV remains (1.0, 1.0). Positive reads select their value policy before merging. |

Internal scaffold/materialization assertions inspect the ordinary KB scope.
The two original semantic blocker tests are unedited. Added coverage:

- Negative-only samples invent no positive answer (`test_empty_class_link`).
- Repeating the same CTV source is legal; both polarities answer at budget zero
  (`test_implication_judgment_contexts`).
- A positive read of a real forward-stored CTV retains exactly its evidence and
  dependencies, and answers at zero budget (`test_derived_implications`).

The shared forward read regression was demonstrated failing before the
provenance fix: `forward-source-probe.log`, exit 1, evidence/dependencies
(ev-set 7, 2) instead of (ev-set 4, 9). `forward-source-fixed.log` passes;
the retained suite uses the runtime's actual IDs rather than pinning these
probe-local numbers. Original conjunction/conditioning proof and TV assertions
pass after deleting producer copies.

## Footprint and deleted-symbol audit

Supplied `scratch/core_count.py`, o200k_base and its exact core file set:
**326,924 -> 326,119 core tokens: -805 (-0.2462%)**. Third-party stays 17,685;
combined **344,609 -> 343,804**. Tests, docs, reports and scratch are excluded.
Restoring the discount adds 68 core tokens relative to the previous candidate.
Scheduling is now unchanged from baseline (1,118 tokens). Per-file data:
`scratch/merge1b/token-diff.json`; exact count output:
`scratch/merge1b/discount-restored-tokens.txt`; changed-file table below.

Deleted symbols: `statement-query-kb`, namespace constructor `implication-query`,
finish `implication-instance`, `query-source-premise`,
`positive-implication-producer`, `implication-statement-query-adds`,
`class-link-query-adds`, `query-positive-tv`. Whole-symbol audit over
`pettachainer/`, `third_party/`, `tests/`, `docs/`: **zero matches**.

```sh
rg -n '(^|[^a-zA-Z-])(statement-query-kb|implication-query|implication-instance|query-source-premise|positive-implication-producer|implication-statement-query-adds|class-link-query-adds|query-positive-tv)([^a-zA-Z-]|$)' pettachainer/ third_party/ tests/ docs/
```

The retained query-side and instance-fold names are different symbols, not
compatibility aliases. Follow-up audit:
`scratch/merge1b/discount-restored-deleted-symbol-audit.txt` (zero lines).
`docs/metta/API.md`, `tests/test_tv_calibration.py` and the calibration oracle
are byte-identical to baseline.

## Follow-up gates and benchmark diff

All requested gates were rerun after restoration commit `184d95c2`.
`scripts/verify.sh`: **all six gates PASS**, exit 0, **382 seconds**;
log `scratch/merge1b/discount-restored-verify.log`. The frozen source/test
checkout recorded PASS under verification key `4717712f8ab5` before the
post-gate documentation update.

| Gate | Result |
| --- | --- |
| MeTTa lint | PASS |
| MeTTa suite | 161 passed, zero failed |
| Python unittest | 967 tests, 59 files, 587 units; 125 existing expected failures, one skip |
| Strict Python query audit | 4,430 query metric rows, zero search aborts |
| Import scaling | PASS |
| Judgment scaling | PASS; three query metric rows, zero search aborts |
| ConceptNet | PASS; exactly two answers |

No source, test or validation script changed after this run. Only this report
and the scheduling paragraph in `docs/metta/implication_lowering.md` were updated.
Calibration tests, the oracle and expected-failure entries remain unchanged.

Every PeTTa, test and benchmark process used the worktree's pinned runtime
through `/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, unset
`DISPLAY`, and stdin `/dev/null`. The copied `.venv` points to this worktree.
The standard harness owns seeds, build snapshots, admission and result reuse.
The documented `BENCH_TIMING_HOST=` local override is retained from the original
merge 1b run because this runtime is not installed on the remote timing host.

Commands, from the worktree root:

```sh
ulimit -v 16000000
unset DISPLAY
/nexus/Dev/OpenCog/bench/capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh </dev/null
/nexus/Dev/OpenCog/bench/capped env PETTACHAINER_REPO="$PWD" BENCH_TIMING_HOST= /nexus/Dev/OpenCog/bench/compare.sh master /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/merge1b --full </dev/null
/nexus/Dev/OpenCog/bench/capped env PETTACHAINER_REPO="$PWD" BENCH_TIMING_HOST= /nexus/Dev/OpenCog/bench/compare.sh anchor /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/merge1b --canary </dev/null
```

The original `/nexus/Dev/OpenCog/bench/fresh-design/e3-brief.md` is no longer
present. The follow-up's explicit Rules and `docs/agent_workflow.md` were followed;
commit trailers were recovered from `5289defb` and `f935041d`.

Master remains `9102bd1cd00e019947d6af69c3a23f0a5cb737c8`; the harness froze
candidate `184d95c254d4a38e8215e4c9ba9998be99102780`, runtime tree
`f6bafed7cdfee1cf63c962c5e9103be7a66f577b`. PeTTa runtime:
`eec735bf4d1d3e31`.

| Profile | Result | Artifact under `/nexus/Dev/OpenCog/bench/results/compare/` |
| --- | --- | --- |
| Full | **PASS**, zero regression flags; **accuracy identical in all 22 compared cases**; 23 cases including reference, 43 runs executed, 2 reused, 355s wall | `9102bd1c_vs_184d95c2_full/report.md` and `compare.json` |
| Anchor canary | **PASS**, zero regression flags; accuracy changed in 4 of 6 cases versus anchor; six candidate runs, six anchor results reused, 153s wall | `anchor-b4065459_vs_184d95c2_canary/report.md` and `compare.json` |

Canary accuracy changes versus anchor are live b50 5 shifts s1, conflict
pln-stated l spq4 s1, conflict pln-reliable l spq4 s1, and scale m spq4 r10 s1.
Its embedded comparison against current master passes using 12 stored results;
all nine anchor disadvantages are also present on master, with no
candidate-specific blocker. No runtime improvement is claimed from these timings.
Logs: `scratch/merge1b/discount-restored-full.log` and
`scratch/merge1b/discount-restored-canary.log`.

## Fuzzer parity and the restored anytime result

Full profile `fuzz all n100 s22`, budgets 100 and 2000: **identical to master**.
A raw per-seed audit compared all non-proof row fields, proofs, generated KBs,
exact references, flags and classifications: **zero differences**.

| Metric | Master | Restored candidate |
| --- | ---: | ---: |
| Mean absolute error | 0.005060085160683605 | 0.005060085160683605 |
| Answered queries | 363 | 363 |
| Flagged KBs | 6 | 6 |
| Unsupported / crashed KBs | 0 / 0 | 0 / 0 |

Existing flagged categories remain five error KBs and one no-answer KB;
there are zero budget-regression flags. In seed **22000162**, **`(D b)`**:

| Value | Master | Restored candidate |
| --- | ---: | ---: |
| Exact oracle | 0.3991304347810001 | 0.3991304347810001 |
| Budget 100 | 0.41847500000000004 | 0.41847500000000004 |
| Budget 2000 | 0.3991304347827556 | 0.3991304347827556 |
| Budget-2000 absolute error | 1.7555401576885288e-12 | 1.7555401576885288e-12 |

The restored candidate carries the same conditioned proof as master.
The prior no-discount candidate stayed at 0.41847500000000004 at budget 2000.
Restoring the original search order resolves that regression while preserving
the implication implementation and the blocker fixes. The full profile now
also eliminates all three SupplyNet numerical differences disclosed in the
previous report: **no full-profile accuracy number moves**.

Audit script: `scratch/merge1b/audit-restored-fuzz.py`; evidence:
`scratch/merge1b/discount-restored-fuzz-audit.json` and `.log`. The script
only reads standard benchmark artifacts; it does not run an additional fuzzer.
The earlier single-source scheduler ablation remains historical evidence at
`/nexus/Dev/OpenCog/bench/results/compare/d1ee51a7_vs_d1ee51a7-d141573f8_full-fuzz/report.md`.
The previous no-discount full/canary/curves results in commit `5289defb` are
superseded by the requested restored-candidate gates above. No new curves
were requested; the scheduler is exactly master's.

## Limits and hand-back

The unified positive reads, shared two-branch instance tally, Assuming seed
exclusion, source identity and projected provenance fixes all remain as in
`5289defb`. A diff of the restoration commit against that commit contains
only the scheduling file and two scheduler-score expectations.

Exists witness/claim folds, Boolean-event conditional planning, compound
outputs and connective canonicalization remain outside this change. Private
hypothetical worlds are retained; the deleted namespace held positive result
publication. Benchmark parity covers the prescribed finite suite and budgets.

No master/main-checkout/other-worktree edit, push, merge, GitHub write or
admission-service change was performed. Standard gate and benchmark tools own
their shared cache and result artifacts. All started jobs completed and were
reaped before hand-back. Implementation and documentation commits retain the
original brief's trailers.

## Changed core file counts

| File | Before | After | Delta |
| --- | ---: | ---: | ---: |
| `pettachainer/metta/compiler/query_lowering.metta` | 7,539 | 6,279 | -1,260 |
| `pettachainer/metta/compiler/rules.metta` | 19,487 | 19,441 | -46 |
| `pettachainer/metta/core/types.metta` | 4,220 | 4,212 | -8 |
| `pettachainer/metta/runtime/backward/evaluation.metta` | 100,831 | 101,125 | +294 |
| `pettachainer/metta/runtime/backward/skeleton.metta` | 32,542 | 32,777 | +235 |
| `pettachainer/metta/runtime/backward/upward.metta` | 5,701 | 5,684 | -17 |
| `pettachainer/metta/runtime/evidence.metta` | 7,074 | 7,045 | -29 |
| `pettachainer/metta/runtime/forward/aggregates.metta` | 6,012 | 5,974 | -38 |
| `pettachainer/metta/runtime/knowledge_store.metta` | 5,238 | 5,302 | +64 |
Totals: 326,924 -> 326,119

## Complete generated full comparison

# 9102bd1c vs 184d95c2 (full)

**PASS**

accuracy identical in all 22 cases.

- base: `9102bd1c` = 9102bd1cd00e019947d6af69c3a23f0a5cb737c8, runtime tree 9b7e2eec4896
- candidate: `184d95c2` = 184d95c254d4a38e8215e4c9ba9998be99102780, runtime tree f6bafed7cdfe
- ChainerGame: supply `3daf989e93 supply-network`, replay `d274b45767 bench-hooks`; PeTTa runtime eec735bf4d1d3e31
- 23 cases; 43 runs executed, 2 of 45 results reused from the store; 355 s wall, 1934 CPU-s
- load: 17-33 pool slots held during this comparison's runs (cpu target 24)

Thresholds: error/Brier worse by >5% relative and >0.002 absolute (per row, also per kind); coverage drop >0.001; regret worse by >5% and >0.05 (agreement reported, never flagged); fuzz flagged KBs up by any; seconds >10% and >1 s worse; peak RSS >35% and >300 MB higher; a run that fails only for the candidate. A timing flag counts only if a paired rerun repeats it. Timing not taken side by side, at loads whose calibrated slowdowns differ by more than 5%, is marked `load differs` and not flagged. `reused` marks results from the store (the same code ran this case before).

## Cases

Each case's points along its budget curve, low to high budget.

| suite | case | budgets | base error | candidate error | base s | candidate s |
|---|---|---|---|---|---|---|
| supplynet | stage 1 s3 | 100 | 0.004954 | 0.004954 | 3.52 | 3.479 |
| supplynet | stage 3 timed s3 | 25 / 50 / 100 | 0.004467 / 0.001985 / 0.001986 | 0.004467 / 0.001985 / 0.001986 | 9.922 / 17.28 / 19.52 | 10.43 / 17.77 / 20.08 |
| supplynet | stage 3 untimed s4 | 25 / 100 | 0.0003949 / 0.0003949 | 0.0003949 / 0.0003949 | 14.63 / 21.73 | 13.84 / 20.28 |
| supplynet | stage 3 timed soft0.9 s3 | 100 | 0.0201 | 0.0201 | 45.12 | 42.45 |
| supplynet | stage 3 untimed soft0.9 s4 | 100 | 0.01906 | 0.01906 | 59.47 | 58.22 |
| scale | l s1 | 4 / 16 | 0.003808 / 0.0009293 | 0.003808 / 0.0009293 | 78.85 / 163.7 | 74.81 / 144.1 |
| scale | s s1 | 1 | 0.01837 | 0.01837 | 2.25 | 2.438 |
| conflict | pln-sources m s2 | 4 | 0.07546 | 0.07546 | 21.53 | 22.39 |
| conflict | pln-sources m s3 | 4 | 0.184 | 0.184 | 20.76 | 12.88 |
| conflict | pln-reliable l s1 | 4 | 0.05407 | 0.05407 | 71.95 | 91.91 |
| learned | stage 3 timed learned s1 | 200 | 0.08156 | 0.08156 | 26.77 | 25.03 |
| supplynet | stage 4 extend s2 | 50 | 1.75e-07 | 1.75e-07 | 23.83 | 23.72 |
| learned | stage 3 timed learned s2 | 200 | 0.06048 | 0.06048 | 28.42 | 27.58 |
| learned | stage 3 untimed learned mined s3 | 50 | 0.2392 | 0.2392 | 125.3 | 125.4 |
| replay | s1 | 25 | 0.1076 | 0.1076 | 3.998 | 3.826 |
| replay | s4 | 25 | 0.1269 | 0.1269 | 4.148 | 4.155 |
| combinet | n2 s1 |  | 0.09231 | 0.09231 | 0.691 | 0.724 |
| fuzz | all s22 |  | 0.00506 | 0.00506 | 54 | 53 |

## Suite totals

| suite | base s | candidate s | delta | base peak MB | candidate peak MB |
|---|---|---|---|---|---|
| supplynet | 215.0 | 210.3 | -4.8 (-2%) | 253 | 250 |
| scale | 244.8 | 221.3 | -23.5 (-10%) | 1368 | 1358 |
| conflict | 114.2 | 127.2 | +12.9 (+11%) | 314 | 278 |
| learned | 180.5 | 178.1 | -2.5 (-1%) | 609 | 526 |
| replay | 8.1 | 8.0 | -0.2 (-2%) | 243 | 244 |
| combinet | 0.7 | 0.7 | +0.0 (+5%) | 178 | 178 |
| fuzz | 54.0 | 53.0 | -1.0 (-2%) | 176 | 176 |

## StationOps replay belief streams

| case | beliefs | changed | max belief shift |
|---|---|---|---|
| b25 s1 | 200 | identical | 0 |
| b25 s4 | 200 | identical | 0 |

## Fuzzer

Fuzz all n100 s22: 6 -> 6 flagged KBs; newly flagged: none; no longer flagged: none.
- base: 0 unsupported KBs (none); 0 crashes.
- candidate: 0 unsupported KBs (none); 0 crashes.

## Metrics

| suite | case | metric | base | candidate | delta | flag | reference | note |
|---|---|---|---|---|---|---|---|---|
| supplynet | stage 1 b100 s3 | error | 0.004954 | 0.004954 | 0 |  |  |  |
| supplynet | stage 1 b100 s3 | brier | 0.01046 | 0.01046 | 0 |  |  |  |
| supplynet | stage 1 b100 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 1 b100 s3 | seconds | 3.52 | 3.479 | -0.041 |  |  |  |
| supplynet | stage 1 b100 s3 | peak_mb | 193.3 | 193.4 | 0.1 |  |  |  |
| supplynet | stage 3 timed b25 s3 | error | 0.004467 | 0.004467 | 0 |  |  | load differs |
| supplynet | stage 3 timed b25 s3 | brier | 0.1726 | 0.1726 | 0 |  |  | load differs |
| supplynet | stage 3 timed b25 s3 | coverage | 1 | 1 | 0 |  |  | load differs |
| supplynet | stage 3 timed b25 s3 | seconds | 9.922 | 10.43 | 0.51 |  |  | load differs |
| supplynet | stage 3 timed b25 s3 | peak_mb | 211.6 | 209.9 | -1.7 |  |  | load differs |
| supplynet | stage 3 timed b50 s3 | error | 0.001985 | 0.001985 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | brier | 0.1712 | 0.1712 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | seconds | 17.28 | 17.77 | 0.488 |  |  |  |
| supplynet | stage 3 timed b50 s3 | peak_mb | 231.2 | 231.6 | 0.4 |  |  |  |
| supplynet | stage 3 timed b100 s3 | error | 0.001986 | 0.001986 | 0 |  |  |  |
| supplynet | stage 3 timed b100 s3 | brier | 0.1712 | 0.1712 | 0 |  |  |  |
| supplynet | stage 3 timed b100 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 timed b100 s3 | seconds | 19.52 | 20.08 | 0.559 |  |  |  |
| supplynet | stage 3 timed b100 s3 | peak_mb | 237.7 | 237.3 | -0.4 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | error | 0.0003949 | 0.0003949 | 0 |  |  | load differs |
| supplynet | stage 3 untimed b25 s4 | brier | 0.1319 | 0.1319 | 0 |  |  | load differs |
| supplynet | stage 3 untimed b25 s4 | coverage | 1 | 1 | 0 |  |  | load differs |
| supplynet | stage 3 untimed b25 s4 | seconds | 14.63 | 13.84 | -0.789 |  |  | load differs |
| supplynet | stage 3 untimed b25 s4 | peak_mb | 207.4 | 205.5 | -1.9 |  |  | load differs |
| supplynet | stage 3 untimed b100 s4 | error | 0.0003949 | 0.0003949 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | brier | 0.1319 | 0.1319 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | seconds | 21.73 | 20.28 | -1.455 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | peak_mb | 229.4 | 228.1 | -1.3 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | error | 0.0201 | 0.0201 | 0 |  |  | load differs |
| supplynet | stage 3 timed soft0.9 b100 s3 | brier | 0.1805 | 0.1805 | 0 |  |  | load differs |
| supplynet | stage 3 timed soft0.9 b100 s3 | coverage | 0.9752 | 0.9752 | 0 |  |  | load differs |
| supplynet | stage 3 timed soft0.9 b100 s3 | seconds | 45.12 | 42.45 | -2.67 |  |  | load differs |
| supplynet | stage 3 timed soft0.9 b100 s3 | peak_mb | 253.1 | 250.4 | -2.7 |  |  | load differs |
| supplynet | stage 3 untimed soft0.9 b100 s4 | error | 0.01906 | 0.01906 | 0 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | brier | 0.1403 | 0.1403 | 0 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | coverage | 0.9707 | 0.9707 | 0 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | seconds | 59.47 | 58.22 | -1.251 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | peak_mb | 243.6 | 244 | 0.4 |  |  |  |
| scale | l spq4 s1 | error | 0.003808 | 0.003808 | 0 |  |  |  |
| scale | l spq4 s1 | brier | 0.0432 | 0.0432 | 0 |  |  |  |
| scale | l spq4 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | l spq4 s1 | seconds | 78.85 | 74.81 | -4.035 |  |  |  |
| scale | l spq4 s1 | peak_mb | 919.1 | 913.2 | -5.9 |  |  |  |
| scale | l spq16 s1 | error | 0.0009293 | 0.0009293 | 0 |  |  |  |
| scale | l spq16 s1 | brier | 0.04303 | 0.04303 | 0 |  |  |  |
| scale | l spq16 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | l spq16 s1 | seconds | 163.7 | 144.1 | -19.65 |  |  |  |
| scale | l spq16 s1 | peak_mb | 1368 | 1358 | -10.3 |  |  |  |
| scale | s spq1 s1 | error | 0.01837 | 0.01837 | 0 |  |  |  |
| scale | s spq1 s1 | brier | 0.1587 | 0.1587 | 0 |  |  |  |
| scale | s spq1 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | s spq1 s1 | seconds | 2.25 | 2.438 | 0.188 |  |  |  |
| scale | s spq1 s1 | peak_mb | 185.5 | 184.6 | -0.9 |  |  |  |
| conflict | pln-sources m spq4 s2 | error | 0.07546 | 0.07546 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | brier | 0.1073 | 0.1073 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | coverage | 0.9875 | 0.9875 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | seconds | 21.53 | 22.39 | 0.857 |  |  |  |
| conflict | pln-sources m spq4 s2 | peak_mb | 277.3 | 275.9 | -1.4 |  |  |  |
| conflict | pln-sources m spq4 s3 | error | 0.184 | 0.184 | 0 |  |  | load differs |
| conflict | pln-sources m spq4 s3 | brier | 0.1299 | 0.1299 | 0 |  |  | load differs |
| conflict | pln-sources m spq4 s3 | coverage | 1 | 1 | 0 |  |  | load differs |
| conflict | pln-sources m spq4 s3 | seconds | 20.76 | 12.88 | -7.879 |  |  | load differs |
| conflict | pln-sources m spq4 s3 | peak_mb | 278.5 | 278 | -0.5 |  |  | load differs |
| conflict | pln-reliable l spq4 s1 | error | 0.05407 | 0.05407 | 0 |  |  | load differs |
| conflict | pln-reliable l spq4 s1 | brier | 0.07161 | 0.07161 | 0 |  |  | load differs |
| conflict | pln-reliable l spq4 s1 | coverage | 1 | 1 | 0 |  |  | load differs |
| conflict | pln-reliable l spq4 s1 | seconds | 71.95 | 91.91 | 19.97 | load differs |  | load differs |
| conflict | pln-reliable l spq4 s1 | peak_mb | 313.6 | 277.9 | -35.7 |  |  | load differs |
| learned | stage 3 timed learned b50 r200 s1 | error | 0.08156 | 0.08156 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | brier | 0.1163 | 0.1163 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | coverage | 1 | 1 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | seconds | 26.77 | 25.03 | -1.743 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | peak_mb | 302.7 | 302.5 | -0.2 |  |  |  |
| supplynet | stage 4 extend b50 s2 | error | 1.75e-07 | 1.75e-07 | 0 |  |  | load differs |
| supplynet | stage 4 extend b50 s2 | brier | 0.1894 | 0.1894 | 0 |  |  | load differs |
| supplynet | stage 4 extend b50 s2 | coverage | 1 | 1 | 0 |  |  | load differs |
| supplynet | stage 4 extend b50 s2 | seconds | 23.83 | 23.72 | -0.109 |  |  | load differs |
| supplynet | stage 4 extend b50 s2 | regret | 0 | 0 | 0 |  |  | load differs |
| supplynet | stage 4 extend b50 s2 | agreement | 1 | 1 | 0 |  |  | load differs |
| supplynet | stage 4 extend b50 s2 | peak_mb | 232.7 | 234.9 | 2.2 |  |  | load differs |
| learned | stage 3 timed learned b50 r200 s2 | error | 0.06048 | 0.06048 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | brier | 0.1833 | 0.1833 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | coverage | 1 | 1 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | seconds | 28.42 | 27.58 | -0.839 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | peak_mb | 304.9 | 306 | 1.1 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | error | 0.2392 | 0.2392 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | brier | 0.2906 | 0.2906 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | coverage | 0.9643 | 0.9643 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | seconds | 125.3 | 125.4 | 0.097 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | peak_mb | 608.8 | 525.6 | -83.2 |  |  |  |
| replay | b25 s1 | error | 0.1076 | 0.1076 | 0 |  |  |  |
| replay | b25 s1 | brier | 0.04388 | 0.04388 | 0 |  |  |  |
| replay | b25 s1 | coverage | 1 | 1 | 0 |  |  |  |
| replay | b25 s1 | regret | 627.5 | 627.5 | 0 |  |  |  |
| replay | b25 s1 | seconds | 3.998 | 3.826 | -0.1715 |  |  |  |
| replay | b25 s1 | peak_mb | 242.2 | 241.8 | -0.4 |  |  |  |
| replay | b25 s4 | error | 0.1269 | 0.1269 | 0 |  |  |  |
| replay | b25 s4 | brier | 0.07751 | 0.07751 | 0 |  |  |  |
| replay | b25 s4 | coverage | 1 | 1 | 0 |  |  |  |
| replay | b25 s4 | regret | 229.4 | 229.4 | 0 |  |  |  |
| replay | b25 s4 | seconds | 4.148 | 4.155 | 0.007582 |  |  |  |
| replay | b25 s4 | peak_mb | 243.4 | 243.6 | 0.2 |  |  |  |
| combinet | n2 s1 | error | 0.09231 | 0.09231 | 0 |  | 0.06702 |  |
| combinet | n2 s1 | brier | 0.1727 | 0.1727 | 0 |  | 0.175 |  |
| combinet | n2 s1 | coverage | 0.91 | 0.91 | 0 |  | 1 |  |
| combinet | n2 s1 | seconds | 0.691 | 0.724 | 0.033 |  |  |  |
| combinet | n2 s1 | peak_mb | 177.9 | 177.7 | -0.2 |  |  |  |
| fuzz | all n100 s22 | flagged | 6 | 6 | 0 |  |  |  |
| fuzz | all n100 s22 | unsupported | 0 | 0 | 0 |  |  |  |
| fuzz | all n100 s22 | crashed | 0 | 0 | 0 |  |  |  |
| fuzz | all n100 s22 | error | 0.00506 | 0.00506 | 0 |  |  |  |
| fuzz | all n100 s22 | answered | 363 | 363 | 0 |  |  |  |
| fuzz | all n100 s22 | seconds | 54 | 53 | -1 |  |  |  |
| fuzz | all n100 s22 | peak_mb | 175.6 | 175.8 | 0.2 |  |  |  |

## Error per kind

| suite | case | kind | base | candidate | delta | flag |
|---|---|---|---|---|---|---|
| supplynet | stage 1 b100 s3 | blocked | 0.0007752 | 0.0007752 | 0 |  |
| supplynet | stage 1 b100 s3 | storm | 0.01658 | 0.01658 | 0 |  |
| supplynet | stage 3 timed b25 s3 | blocked | 0.0004569 | 0.0004569 | 0 |  |
| supplynet | stage 3 timed b25 s3 | degraded | 0.008599 | 0.008599 | 0 |  |
| supplynet | stage 3 timed b25 s3 | previous_storm | 0.000979 | 0.000979 | 0 |  |
| supplynet | stage 3 timed b25 s3 | producing | 0.002065 | 0.002065 | 0 |  |
| supplynet | stage 3 timed b25 s3 | producing_unstocked | 0.0199 | 0.0199 | 0 |  |
| supplynet | stage 3 timed b25 s3 | storm | 0.000372 | 0.000372 | 0 |  |
| supplynet | stage 3 timed b50 s3 | blocked | 0.0004569 | 0.0004569 | 0 |  |
| supplynet | stage 3 timed b50 s3 | degraded | 0.008651 | 0.008651 | 0 |  |
| supplynet | stage 3 timed b50 s3 | previous_storm | 0.000979 | 0.000979 | 0 |  |
| supplynet | stage 3 timed b50 s3 | producing | 0.001932 | 0.001932 | 0 |  |
| supplynet | stage 3 timed b50 s3 | producing_unstocked | 0.002042 | 0.002042 | 0 |  |
| supplynet | stage 3 timed b50 s3 | storm | 0.000372 | 0.000372 | 0 |  |
| supplynet | stage 3 timed b100 s3 | blocked | 0.0004569 | 0.0004569 | 0 |  |
| supplynet | stage 3 timed b100 s3 | degraded | 0.008599 | 0.008599 | 0 |  |
| supplynet | stage 3 timed b100 s3 | previous_storm | 0.000979 | 0.000979 | 0 |  |
| supplynet | stage 3 timed b100 s3 | producing | 0.002065 | 0.002065 | 0 |  |
| supplynet | stage 3 timed b100 s3 | producing_unstocked | 0.002042 | 0.002042 | 0 |  |
| supplynet | stage 3 timed b100 s3 | storm | 0.000372 | 0.000372 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | blocked | 1.937e-07 | 1.937e-07 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | degraded | 0.001459 | 0.001459 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | previous_storm | 4.152e-07 | 4.152e-07 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | producing | 0.002016 | 0.002016 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | producing_unstocked | 0 | 0 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | storm | 3.515e-07 | 3.515e-07 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | blocked | 1.937e-07 | 1.937e-07 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | degraded | 0.001459 | 0.001459 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | previous_storm | 4.152e-07 | 4.152e-07 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | producing | 0.002016 | 0.002016 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | producing_unstocked | 0 | 0 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | storm | 3.515e-07 | 3.515e-07 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | blocked | 0.001236 | 0.001236 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | degraded | 0.008751 | 0.008751 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | previous_storm | 0.004232 | 0.004232 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | producing | 0.07318 | 0.07318 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | producing_unstocked | 0.09519 | 0.09519 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | storm | 0.001468 | 0.001468 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | blocked | 6.529e-06 | 6.529e-06 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | degraded | 0.002109 | 0.002109 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | previous_storm | 3.65e-05 | 3.65e-05 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | producing | 0.01998 | 0.01998 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | producing_unstocked | 0.1244 | 0.1244 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | storm | 1.196e-05 | 1.196e-05 | 0 |  |
| scale | l spq4 s1 | blocked | 0.003087 | 0.003087 | 0 |  |
| scale | l spq4 s1 | front | 0.0113 | 0.0113 | 0 |  |
| scale | l spq4 s1 | past_front | 0.01026 | 0.01026 | 0 |  |
| scale | l spq4 s1 | past_storm | 0.002409 | 0.002409 | 0 |  |
| scale | l spq4 s1 | storm | 0.005014 | 0.005014 | 0 |  |
| scale | l spq16 s1 | blocked | 0.0009428 | 0.0009428 | 0 |  |
| scale | l spq16 s1 | front | 0.003011 | 0.003011 | 0 |  |
| scale | l spq16 s1 | past_front | 4.801e-05 | 4.801e-05 | 0 |  |
| scale | l spq16 s1 | past_storm | 1.175e-05 | 1.175e-05 | 0 |  |
| scale | l spq16 s1 | storm | 0.0015 | 0.0015 | 0 |  |
| scale | s spq1 s1 | blocked | 0.01205 | 0.01205 | 0 |  |
| scale | s spq1 s1 | front | 0.04346 | 0.04346 | 0 |  |
| scale | s spq1 s1 | past_front | 0.03911 | 0.03911 | 0 |  |
| scale | s spq1 s1 | past_storm | 0.01197 | 0.01197 | 0 |  |
| scale | s spq1 s1 | storm | 0.02221 | 0.02221 | 0 |  |
| conflict | pln-sources m spq4 s2 | component | 0.12 | 0.12 | 0 |  |
| conflict | pln-sources m spq4 s2 | system | 0.03091 | 0.03091 | 0 |  |
| conflict | pln-sources m spq4 s3 | component | 0.1847 | 0.1847 | 0 |  |
| conflict | pln-sources m spq4 s3 | system | 0.1833 | 0.1833 | 0 |  |
| conflict | pln-reliable l spq4 s1 | component | 0.05288 | 0.05288 | 0 |  |
| conflict | pln-reliable l spq4 s1 | system | 0.05527 | 0.05527 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | blocked | 0.09388 | 0.09388 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | degraded | 0.06246 | 0.06246 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | previous_storm | 0.1073 | 0.1073 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | producing | 0.04975 | 0.04975 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | producing_unstocked | 0 | 0 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | storm | 0.1125 | 0.1125 | 0 |  |
| supplynet | stage 4 extend b50 s2 | blocked | 1.412e-07 | 1.412e-07 | 0 |  |
| supplynet | stage 4 extend b50 s2 | degraded | 4.5e-08 | 4.5e-08 | 0 |  |
| supplynet | stage 4 extend b50 s2 | previous_storm | 3.363e-07 | 3.363e-07 | 0 |  |
| supplynet | stage 4 extend b50 s2 | storm | 2.758e-07 | 2.758e-07 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | blocked | 0.05229 | 0.05229 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | degraded | 0.1079 | 0.1079 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | previous_storm | 0.0759 | 0.0759 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | producing | 0.06454 | 0.06454 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | producing_unstocked | 0 | 0 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | storm | 0.08071 | 0.08071 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | blocked | 0.2228 | 0.2228 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | degraded | 0.1102 | 0.1102 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | previous_storm | 0.2493 | 0.2493 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | producing | 0.3481 | 0.3481 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | storm | 0.2405 | 0.2405 | 0 |  |
| combinet | n2 s1 | causes | 0.07404 | 0.07404 | 0 |  |
| combinet | n2 s1 | interacting | 0.1196 | 0.1196 | 0 |  |
| combinet | n2 s1 | redundant | 0.06379 | 0.06379 | 0 |  |
| combinet | n2 s1 | signs | 0.1119 | 0.1119 | 0 |  |

The CombiNet reference column is the revision backend (independent of the build).
