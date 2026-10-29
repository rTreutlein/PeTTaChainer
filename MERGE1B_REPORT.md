# Merge 1b: implication lowering under the relaxed gate

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/merge1b`.
Branch: `merge1b`. Baseline: `d1ee51a7d6d643ea0c36105e415d835ad3de6c51`.

Status: implementation complete and committed as
`f935041d9ae4e5fb671b1a506e6cc2cb2fb903f8`. All six verification gates,
full comparison and anchor canary pass; scheduling curves completed. No existing
test strength or confidence expectation was changed. This report is committed
separately after the implementation.

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

The 0.99 open-proof priority multiplier is deleted. Ordinary premise confidence
is its TV confidence; CPU policies, including zero search priority for settled
steps, are unchanged. No API signature, calibration oracle or expected-failure
entry was changed.

## Tests and moved pins

Standalone strict MeTTa: **161 passed, zero failed**, exit 0,
`scratch/merge1b/final-metta.log`. The focused prior-definition suite also
passes all **35 tests** (`single-source-prior.log`).

All existing TV expectations remain unchanged. The original implication-premise
proof pin is also unchanged. Only these public expected presentations moved:

| Pin | Before | After / reason |
| --- | --- | --- |
| `test_hypothesis_rules.metta`, initial scheduler array, for A and C | 0.0099, 0.0099, 0.009000000000000001 | 0.009999000099989962, 0.01, 0.009000000000000001. The actual MP confidence and floor now bound the first two scores instead of the multiplier. |
| Same file, reviewed A scores | 0.3933243243243243, 0.3933243243243243, 0.3575675675675676 | 0.3972575715401417, 0.3972972972972973, 0.3575675675675676. Learned CTVs are unchanged. C retains the new initial scores. |
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
**326,924 -> 326,051 core tokens: -873 (-0.2670%)**. Third-party stays 17,685;
combined **344,609 -> 343,736**. Tests, docs, reports and scratch are excluded.
Per-file data: `scratch/merge1b/token-diff.json`; changed-file table below.

Deleted symbols: `statement-query-kb`, namespace constructor `implication-query`,
finish `implication-instance`, `query-source-premise`,
`positive-implication-producer`, `implication-statement-query-adds`,
`class-link-query-adds`, `query-positive-tv`. Whole-symbol audit over
`pettachainer/`, `third_party/`, `tests/`, `docs/`: **zero matches**.

```sh
rg -n '(^|[^a-zA-Z-])(statement-query-kb|implication-query|implication-instance|query-source-premise|positive-implication-producer|implication-statement-query-adds|class-link-query-adds|query-positive-tv)([^a-zA-Z-]|$)' pettachainer/ third_party/ tests/ docs/
```

The retained query-side and instance-fold names are different symbols, not
compatibility aliases. Audit: `scratch/merge1b/deleted-symbol-audit.txt`.
`docs/metta/API.md`, `tests/test_tv_calibration.py` and the calibration oracle
are byte-identical to baseline.

## Final gates and benchmark diff

`scripts/verify.sh`: **all six gates PASS**, exit 0, 333 seconds in the
first complete run (`scratch/merge1b/final-verify.log`):

| Gate | Result |
| --- | --- |
| MeTTa lint | PASS |
| MeTTa suite | 161 passed, zero failed |
| Python unittest | 967 tests, 59 files, 587 units; 125 existing expected failures, one skip |
| Strict Python query audit | 4,430 query metric rows, zero search aborts |
| Import scaling | PASS |
| Judgment scaling | PASS; three query metric rows, zero search aborts |
| ConceptNet | PASS; exactly two answers |

`EXPECTED_FAILURES` diff: empty. Calibration test and oracle files are unchanged.
The first complete verification ran while report/docs edits were still being
written, so the script correctly declined to cache it. The frozen-checkout
recording run uses the same command and logs to
`scratch/merge1b/cache-verify.log`; its final gate table and cache line record the
result. No source/test edits were made after the first complete pass.

Every PeTTa, test and benchmark
process used the pinned worktree runtime through `/nexus/Dev/OpenCog/bench/capped`,
`ulimit -v 16000000`, unset DISPLAY and stdin `/dev/null`. Suites use the
prescribed scripts. Admission and full-size comparison waits were never
bypassed. Standard compare profiles supply all seeds and builds; no improvised
benchmark runner was used. Timing uses the documented `BENCH_TIMING_HOST=` local
override because this worktree runtime is not installed on the remote host.
Scheduling curves are included because priorities changed.

Commands (from this worktree, with stdin redirected as shown):

```sh
ulimit -v 16000000
unset DISPLAY
/nexus/Dev/OpenCog/bench/capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh </dev/null
/nexus/Dev/OpenCog/bench/capped env PETTACHAINER_REPO="$PWD" BENCH_TIMING_HOST= /nexus/Dev/OpenCog/bench/compare.sh master "$PWD" --full --no-fail-fast </dev/null
/nexus/Dev/OpenCog/bench/capped env PETTACHAINER_REPO="$PWD" BENCH_TIMING_HOST= /nexus/Dev/OpenCog/bench/compare.sh anchor "$PWD" --canary --no-fail-fast </dev/null
/nexus/Dev/OpenCog/bench/capped env PETTACHAINER_REPO="$PWD" BENCH_TIMING_HOST= /nexus/Dev/OpenCog/bench/compare.sh master "$PWD" --curves --no-fail-fast </dev/null
```

Master advanced concurrently to `9102bd1c` before these final comparisons;
implementation remains based on `d1ee51a7`, with no rebase/merge. The harness
froze the final candidate as `d1ee51a7-d37485e53`, runtime tree
`157cccd14dc0d5b20968d5c927162a38181d4d20`. The implementation commit above has
that same runtime code. PeTTa runtime: `eec735bf4d1d3e31`.

| Profile | Final result | Artifact under `/nexus/Dev/OpenCog/bench/results/compare/` |
| --- | --- | --- |
| Full | PASS, no regression flags; 43 runs executed, 2 reused, 179s wall | `9102bd1c_vs_d1ee51a7-d37485e53_full/report.md` and `compare.json` |
| Anchor canary | PASS; six candidate runs, six anchor results reused, 109s wall; embedded current-master comparison green | `anchor-b4065459_vs_d1ee51a7-d37485e53_canary/report.md` and `compare.json` |
| Scheduling curves | Completed, all runs exit zero; 633s wall | `9102bd1c_vs_d1ee51a7-d37485e53_curves/curves.md` and `curves.json` |

All selected full/canary records exit zero for both builds. Canary reports nine
anchor disadvantages already present on master; no candidate-specific blocker.
Curves contain 40 paired budget points across eight ladders and no unsupported
case. Actual errors are identical except timed stage 3 s2 at budget 100:
0.0004905316461539028 -> 0.0004905316461541097 (delta 2.069e-16).
This is no claim of a runtime improvement.

Full accuracy changed in four cases. The exact unrounded accuracy delta table
and the complete generated full report are reproduced below. The accepted timed
stage 3 b100 s3 noise is Brier +1.6968266514094665e-9; the two soft-evidence
changes are rounding-level. Fuzzer mean error moves by +5.329081327064538e-5.
Across all 100 fuzzer seeds the answered atom sets, flags and categories remain
identical: 363 answered queries; six flagged KBs (five error, one no-answer), zero
unsupported/crashed KBs, zero budget-regression flags. Exactly one numerical
answer changes, seed 22000162, `(D b)` at budget 2000:

- Exact oracle: 0.3991304347810001.
- Master: 0.3991304347827556, conditioned proof; absolute error 1.756e-12.
- Candidate: 0.41847500000000004, unconditioned proof; absolute error
  0.019344565218999965. Its earlier budget-100 estimate was already this value.
- All budget-100 values are unchanged; this KB was already error-flagged.

The KB has B learned from A (positive .59, negative .88), C from B-or-E
(.47/0), E from C (1/0), and D from C-or-B (.56/.19), with observed A(b).
The positive C/E cycle supplies no independent support, so D's exact mean is
.19 + (.56-.19) * P(B(b)); P(B(b)) = .5652173913, yielding .399130434781.
The new priority order retains the earlier approximation within the high budget.
This finite-budget numerical regression is disclosed, rather than hidden by
changing budgets, seeds, assertions or the requested scheduling policy.
Raw per-seed audit: `scratch/merge1b/final-fuzz-diff.json`.

Superseded intermediate comparisons are not final gates. The CTV-copy candidate
passed full/canary but failed repeated-source validation; its logs use
`ctv-copy-rejected-`. A leaf-only projection candidate passed strict tests but
failed the focused forward provenance probe; its stopped gates use
`leaf-projection-rejected-`. Early loader failures are recorded with
`negative-guard-rejected-`. All such jobs were stopped and reaped.

A standard scheduler ablation at the single-source checkpoint restored only
master's scheduling file, with an EXIT trap restoring the final file afterward.
`compare.sh master <worktree> --full --only fuzz --no-fail-fast` returned
**PASS, accuracy changed in 0 cases**, versus the earlier final-priority
candidate's one changed fuzzer answer. Report:
`/nexus/Dev/OpenCog/bench/results/compare/d1ee51a7_vs_d1ee51a7-d141573f8_full-fuzz/report.md`.
This separates the multiplier's finite-budget effect from the implication
storage/read changes. Final full results and exact moved values follow below.

## Limits and hand-back

Implementation commit: `f935041d9ae4e5fb671b1a506e6cc2cb2fb903f8`.
Both implementation and report commits carry the brief's required trailers.
Exists witness/claim folds,
Boolean-event conditional planning, compound outputs and connective
canonicalization remain outside this change. Private hypothetical worlds are
retained; the deleted namespace held positive result publication, not those
worlds. Finite-budget scheduling effects must be read with the benchmark diff,
not as a claim of universally identical search trajectories or a speedup.

No master/main-checkout/other-worktree edit, push, merge, GitHub write or
admission-service change was performed. Standard gate and benchmark tools own
their shared cache and result artifacts.

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
| `pettachainer/metta/runtime/scheduling.metta` | 1,118 | 1,050 | -68 |
Totals: 326,924 -> 326,051

## Exact full accuracy diff

| Suite / case | Field | Master | Candidate | Delta |
| --- | --- | ---: | ---: | ---: |
| supplynet stage 3 timed b100 s3 | metrics.brier | 0.17123147388436308 | 0.17123147558118973 | 1.6968266514094665e-09 |
| supplynet stage 3 timed b100 s3 | metrics.error | 0.001985701064877706 | 0.0019856998213202003 | -1.243557505668097e-09 |
| supplynet stage 3 timed b100 s3 | kinds.degraded | 0.008598546648212992 | 0.008598538265364782 | -8.382848210725102e-09 |
| supplynet stage 3 timed b100 s3 | kinds.previous_storm | 0.0009789835391916164 | 0.0009789835391916162 | -2.168404344971009e-19 |
| supplynet stage 3 timed b100 s3 | kinds.producing | 0.0020647004812875346 | 0.0020646995091489102 | -9.72138624374258e-10 |
| supplynet stage 3 timed b100 s3 | kinds.producing_unstocked | 0.0020423497710092705 | 0.0020423497710092735 | 3.0357660829594124e-18 |
| supplynet stage 3 timed soft0.9 b100 s3 | kinds.degraded | 0.008751122455716987 | 0.00875112245571699 | 3.469446951953614e-18 |
| supplynet stage 3 untimed soft0.9 b100 s4 | metrics.brier | 0.1403006281991811 | 0.14030062819918102 | -8.326672684688674e-17 |
| supplynet stage 3 untimed soft0.9 b100 s4 | metrics.error | 0.019060397469273554 | 0.019060397469273294 | -2.6020852139652106e-16 |
| supplynet stage 3 untimed soft0.9 b100 s4 | kinds.degraded | 0.0021091256442015613 | 0.0021091256442007807 | -7.806255641895632e-16 |
| supplynet stage 3 untimed soft0.9 b100 s4 | kinds.producing | 0.019977738596691035 | 0.019977738596689276 | -1.7590096046404824e-15 |
| fuzz all n100 s22 | metrics.error | 0.005060085160683605 | 0.0051133759739542504 | 5.329081327064538e-05 |

## Complete generated full comparison

# 9102bd1c vs d1ee51a7-d37485e53 (full)

**PASS**

accuracy changed in 4 of 22 cases: supplynet stage 3 timed b100 s3, supplynet stage 3 timed soft0.9 b100 s3, supplynet stage 3 untimed soft0.9 b100 s4, fuzz all n100 s22.

- base: `9102bd1c` = 9102bd1cd00e019947d6af69c3a23f0a5cb737c8, runtime tree 9b7e2eec4896
- candidate: `d1ee51a7-d37485e53` = d1ee51a7d6d643ea0c36105e415d835ad3de6c51+37485e53, runtime tree 157cccd14dc0
- ChainerGame: supply `3daf989e93 supply-network`, replay `d274b45767 bench-hooks`; PeTTa runtime eec735bf4d1d3e31
- 23 cases; 43 runs executed, 2 of 45 results reused from the store; 179 s wall, 1751 CPU-s
- load: 12-24 pool slots held during this comparison's runs (cpu target 24)

Thresholds: error/Brier worse by >5% relative and >0.002 absolute (per row, also per kind); coverage drop >0.001; regret worse by >5% and >0.05 (agreement reported, never flagged); fuzz flagged KBs up by any; seconds >10% and >1 s worse; peak RSS >35% and >300 MB higher; a run that fails only for the candidate. A timing flag counts only if a paired rerun repeats it. Timing not taken side by side, at loads whose calibrated slowdowns differ by more than 5%, is marked `load differs` and not flagged. `reused` marks results from the store (the same code ran this case before).

## Cases

Each case's points along its budget curve, low to high budget.

| suite | case | budgets | base error | candidate error | base s | candidate s |
|---|---|---|---|---|---|---|
| supplynet | stage 1 s3 | 100 | 0.004954 | 0.004954 | 4.791 | 4.634 |
| supplynet | stage 3 timed s3 | 25 / 50 / 100 | 0.004467 / 0.001985 / 0.001986 | 0.004467 / 0.001985 / 0.001986 | 8.719 / 13.5 / 15.47 | 9.108 / 13.89 / 15.48 |
| supplynet | stage 3 untimed s4 | 25 / 100 | 0.0003949 / 0.0003949 | 0.0003949 / 0.0003949 | 11.33 / 17.61 | 11.71 / 18.32 |
| supplynet | stage 3 timed soft0.9 s3 | 100 | 0.0201 | 0.0201 | 35.68 | 35.11 |
| supplynet | stage 3 untimed soft0.9 s4 | 100 | 0.01906 | 0.01906 | 49.74 | 50.44 |
| scale | l s1 | 4 / 16 | 0.003808 / 0.0009293 | 0.003808 / 0.0009293 | 58.5 / 139.5 | 59.42 / 141 |
| scale | s s1 | 1 | 0.01837 | 0.01837 | 3.178 | 2.997 |
| conflict | pln-sources m s2 | 4 | 0.07546 | 0.07546 | 18.53 | 18.52 |
| conflict | pln-sources m s3 | 4 | 0.184 | 0.184 | 18.02 | 17.31 |
| conflict | pln-reliable l s1 | 4 | 0.05407 | 0.05407 | 64.15 | 65.52 |
| learned | stage 3 timed learned s1 | 200 | 0.08156 | 0.08156 | 22.99 | 21.41 |
| supplynet | stage 4 extend s2 | 50 | 1.75e-07 | 1.75e-07 | 20.83 | 19.7 |
| learned | stage 3 timed learned s2 | 200 | 0.06048 | 0.06048 | 23.97 | 23.34 |
| learned | stage 3 untimed learned mined s3 | 50 | 0.2392 | 0.2392 | 89.72 | 90.2 |
| replay | s1 | 25 | 0.1076 | 0.1076 | 5.191 | 5.012 |
| replay | s4 | 25 | 0.1269 | 0.1269 | 5.713 | 5.615 |
| combinet | n2 s1 |  | 0.09231 | 0.09231 | 0.947 | 0.949 |
| fuzz | all s22 |  | 0.00506 | 0.005113 | 57 | 56 |

## Suite totals

| suite | base s | candidate s | delta | base peak MB | candidate peak MB |
|---|---|---|---|---|---|
| supplynet | 177.7 | 178.4 | +0.7 (+0%) | 254 | 254 |
| scale | 201.1 | 203.4 | +2.3 (+1%) | 1370 | 1360 |
| conflict | 100.7 | 101.4 | +0.7 (+1%) | 316 | 290 |
| learned | 136.7 | 135.0 | -1.7 (-1%) | 610 | 609 |
| replay | 10.9 | 10.6 | -0.3 (-3%) | 244 | 244 |
| combinet | 0.9 | 0.9 | +0.0 (+0%) | 178 | 178 |
| fuzz | 57.0 | 56.0 | -1.0 (-2%) | 176 | 176 |

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
| supplynet | stage 1 b100 s3 | seconds | 4.791 | 4.634 | -0.157 |  |  |  |
| supplynet | stage 1 b100 s3 | peak_mb | 193.2 | 193.3 | 0.1 |  |  |  |
| supplynet | stage 3 timed b25 s3 | error | 0.004467 | 0.004467 | 0 |  |  |  |
| supplynet | stage 3 timed b25 s3 | brier | 0.1726 | 0.1726 | 0 |  |  |  |
| supplynet | stage 3 timed b25 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 timed b25 s3 | seconds | 8.719 | 9.108 | 0.389 |  |  |  |
| supplynet | stage 3 timed b25 s3 | peak_mb | 211.5 | 211.2 | -0.3 |  |  |  |
| supplynet | stage 3 timed b50 s3 | error | 0.001985 | 0.001985 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | brier | 0.1712 | 0.1712 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | seconds | 13.5 | 13.89 | 0.383 |  |  |  |
| supplynet | stage 3 timed b50 s3 | peak_mb | 231.5 | 230.1 | -1.4 |  |  |  |
| supplynet | stage 3 timed b100 s3 | error | 0.001986 | 0.001986 | -1.244e-09 |  |  |  |
| supplynet | stage 3 timed b100 s3 | brier | 0.1712 | 0.1712 | 1.697e-09 |  |  |  |
| supplynet | stage 3 timed b100 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 timed b100 s3 | seconds | 15.47 | 15.48 | 0.008 |  |  |  |
| supplynet | stage 3 timed b100 s3 | peak_mb | 237.9 | 236.4 | -1.5 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | error | 0.0003949 | 0.0003949 | 0 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | brier | 0.1319 | 0.1319 | 0 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | seconds | 11.33 | 11.71 | 0.386 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | peak_mb | 207.2 | 207.5 | 0.3 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | error | 0.0003949 | 0.0003949 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | brier | 0.1319 | 0.1319 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | seconds | 17.61 | 18.32 | 0.714 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | peak_mb | 229.8 | 229.4 | -0.4 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | error | 0.0201 | 0.0201 | 0 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | brier | 0.1805 | 0.1805 | 0 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | coverage | 0.9752 | 0.9752 | 0 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | seconds | 35.68 | 35.11 | -0.566 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | peak_mb | 254.3 | 253.5 | -0.8 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | error | 0.01906 | 0.01906 | -2.602e-16 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | brier | 0.1403 | 0.1403 | -8.327e-17 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | coverage | 0.9707 | 0.9707 | 0 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | seconds | 49.74 | 50.44 | 0.697 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | peak_mb | 244.9 | 244.7 | -0.2 |  |  |  |
| scale | l spq4 s1 | error | 0.003808 | 0.003808 | 0 |  |  |  |
| scale | l spq4 s1 | brier | 0.0432 | 0.0432 | 0 |  |  |  |
| scale | l spq4 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | l spq4 s1 | seconds | 58.5 | 59.42 | 0.924 |  |  |  |
| scale | l spq4 s1 | peak_mb | 918.4 | 909.4 | -9 |  |  |  |
| scale | l spq16 s1 | error | 0.0009293 | 0.0009293 | 0 |  |  |  |
| scale | l spq16 s1 | brier | 0.04303 | 0.04303 | 0 |  |  |  |
| scale | l spq16 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | l spq16 s1 | seconds | 139.5 | 141 | 1.516 |  |  |  |
| scale | l spq16 s1 | peak_mb | 1370 | 1360 | -10.3 |  |  |  |
| scale | s spq1 s1 | error | 0.01837 | 0.01837 | 0 |  |  |  |
| scale | s spq1 s1 | brier | 0.1587 | 0.1587 | 0 |  |  |  |
| scale | s spq1 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | s spq1 s1 | seconds | 3.178 | 2.997 | -0.181 |  |  |  |
| scale | s spq1 s1 | peak_mb | 185.5 | 184.7 | -0.8 |  |  |  |
| conflict | pln-sources m spq4 s2 | error | 0.07546 | 0.07546 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | brier | 0.1073 | 0.1073 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | coverage | 0.9875 | 0.9875 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | seconds | 18.53 | 18.52 | -0.007 |  |  |  |
| conflict | pln-sources m spq4 s2 | peak_mb | 277.9 | 276.8 | -1.1 |  |  |  |
| conflict | pln-sources m spq4 s3 | error | 0.184 | 0.184 | 0 |  |  |  |
| conflict | pln-sources m spq4 s3 | brier | 0.1299 | 0.1299 | 0 |  |  |  |
| conflict | pln-sources m spq4 s3 | coverage | 1 | 1 | 0 |  |  |  |
| conflict | pln-sources m spq4 s3 | seconds | 18.02 | 17.31 | -0.707 |  |  |  |
| conflict | pln-sources m spq4 s3 | peak_mb | 278.6 | 278.5 | -0.1 |  |  |  |
| conflict | pln-reliable l spq4 s1 | error | 0.05407 | 0.05407 | 0 |  |  |  |
| conflict | pln-reliable l spq4 s1 | brier | 0.07161 | 0.07161 | 0 |  |  |  |
| conflict | pln-reliable l spq4 s1 | coverage | 1 | 1 | 0 |  |  |  |
| conflict | pln-reliable l spq4 s1 | seconds | 64.15 | 65.52 | 1.369 |  |  |  |
| conflict | pln-reliable l spq4 s1 | peak_mb | 315.6 | 290.5 | -25.1 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | error | 0.08156 | 0.08156 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | brier | 0.1163 | 0.1163 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | coverage | 1 | 1 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | seconds | 22.99 | 21.41 | -1.577 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | peak_mb | 302.7 | 303.5 | 0.8 |  |  |  |
| supplynet | stage 4 extend b50 s2 | error | 1.75e-07 | 1.75e-07 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | brier | 0.1894 | 0.1894 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | seconds | 20.83 | 19.7 | -1.131 |  |  |  |
| supplynet | stage 4 extend b50 s2 | regret | 0 | 0 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | agreement | 1 | 1 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | peak_mb | 233.7 | 233.9 | 0.2 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | error | 0.06048 | 0.06048 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | brier | 0.1833 | 0.1833 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | coverage | 1 | 1 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | seconds | 23.97 | 23.34 | -0.624 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | peak_mb | 307.1 | 306.2 | -0.9 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | error | 0.2392 | 0.2392 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | brier | 0.2906 | 0.2906 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | coverage | 0.9643 | 0.9643 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | seconds | 89.72 | 90.2 | 0.489 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | peak_mb | 609.7 | 609.2 | -0.5 |  |  |  |
| replay | b25 s1 | error | 0.1076 | 0.1076 | 0 |  |  |  |
| replay | b25 s1 | brier | 0.04388 | 0.04388 | 0 |  |  |  |
| replay | b25 s1 | coverage | 1 | 1 | 0 |  |  |  |
| replay | b25 s1 | regret | 627.5 | 627.5 | 0 |  |  |  |
| replay | b25 s1 | seconds | 5.191 | 5.012 | -0.1784 |  |  |  |
| replay | b25 s1 | peak_mb | 242.1 | 242.1 | 0 |  |  |  |
| replay | b25 s4 | error | 0.1269 | 0.1269 | 0 |  |  |  |
| replay | b25 s4 | brier | 0.07751 | 0.07751 | 0 |  |  |  |
| replay | b25 s4 | coverage | 1 | 1 | 0 |  |  |  |
| replay | b25 s4 | regret | 229.4 | 229.4 | 0 |  |  |  |
| replay | b25 s4 | seconds | 5.713 | 5.615 | -0.09772 |  |  |  |
| replay | b25 s4 | peak_mb | 244.2 | 244 | -0.2 |  |  |  |
| combinet | n2 s1 | error | 0.09231 | 0.09231 | 0 |  | 0.06702 |  |
| combinet | n2 s1 | brier | 0.1727 | 0.1727 | 0 |  | 0.175 |  |
| combinet | n2 s1 | coverage | 0.91 | 0.91 | 0 |  | 1 |  |
| combinet | n2 s1 | seconds | 0.947 | 0.949 | 0.002 |  |  |  |
| combinet | n2 s1 | peak_mb | 177.9 | 178.3 | 0.4 |  |  |  |
| fuzz | all n100 s22 | flagged | 6 | 6 | 0 |  |  |  |
| fuzz | all n100 s22 | unsupported | 0 | 0 | 0 |  |  |  |
| fuzz | all n100 s22 | crashed | 0 | 0 | 0 |  |  |  |
| fuzz | all n100 s22 | error | 0.00506 | 0.005113 | 5.329e-05 |  |  |  |
| fuzz | all n100 s22 | answered | 363 | 363 | 0 |  |  |  |
| fuzz | all n100 s22 | seconds | 57 | 56 | -1 |  |  |  |
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
| supplynet | stage 3 timed b100 s3 | degraded | 0.008599 | 0.008599 | -8.383e-09 |  |
| supplynet | stage 3 timed b100 s3 | previous_storm | 0.000979 | 0.000979 | -2.168e-19 |  |
| supplynet | stage 3 timed b100 s3 | producing | 0.002065 | 0.002065 | -9.721e-10 |  |
| supplynet | stage 3 timed b100 s3 | producing_unstocked | 0.002042 | 0.002042 | 3.036e-18 |  |
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
| supplynet | stage 3 timed soft0.9 b100 s3 | degraded | 0.008751 | 0.008751 | 3.469e-18 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | previous_storm | 0.004232 | 0.004232 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | producing | 0.07318 | 0.07318 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | producing_unstocked | 0.09519 | 0.09519 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | storm | 0.001468 | 0.001468 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | blocked | 6.529e-06 | 6.529e-06 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | degraded | 0.002109 | 0.002109 | -7.806e-16 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | previous_storm | 3.65e-05 | 3.65e-05 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | producing | 0.01998 | 0.01998 | -1.759e-15 |  |
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
