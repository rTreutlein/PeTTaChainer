# Structure step 5: one owner for statistical contributions

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct5`.
Branch: `struct5`; base: **84496c3e**. Implementation: **948916f9**,
`Centralize statistical contribution lifecycle in one ledger`.
Pre-verification report checkpoint: **821f6814**. This report-only follow-up
records the completed gates. The implementation/checkpoint originally had labels
`e3da7833`/`501597c5`; only commit-message trailer formatting was normalized,
leaving their trees byte-identical. Benchmark reports retain those original
labels. All final commits have both requested trailers in one Git trailer block.

## Diagnosis and design as built

Instance replacement wrote members, signatures, digests and reverse reads from
`eval_versions.metta`; the scheduler erased them individually on hazard changes.
Forward aggregation marked dirty members, folds consumed those marks, and three
files wrote instance-change notifications. User-rate insertion bypassed the cache
writer. Native support counters and regime aliases lived in the general helper
file. Changing the lifetime of one contribution therefore required coordinated
storage edits across evaluator, scheduler, forward and native implementations.

The owner is `runtime/statistical_ledger.metta`, with its native support and
regime implementation in `prolog/statistical_ledger.pl`. Old implementations
leave their former files in this same commit. There are no compatibility aliases.
All existing public API signatures remain unchanged.

- `ledger-replace-member!` replaces a population member's sums, weight, member
  count, physical-source support and indexed observation together.
  `ledger-remove-member!` performs the corresponding subtraction/removal.
  Registration, aggregate identity and trigger-directory storage move with the
  tally implementation; subscription/population selection stays in forward code.
- `ledger-replace-instance!` replaces an instance's contribution in its original
  positive/negative regime segments, updates digest and support, and registers
  reverse reads only on first admission. An unknown sample contributes zero but
  retains its identity and segment history, preserving existing semantics.
  The fold caller still extracts the sample, reads its value and selects its
  initial evidence; the owner does not evaluate inference rows.
- `ledger-read-excluding` projects population state without the selected indexed
  observations. `ledger-instance-read-excluding` projects an instance tally
  without the selected samples. Indexed exclusion discovery and stable subtraction
  order stay with the ledger. Callers retain user-rate authority, exclusion policy
  and result construction. An already selected exclusion list is passed directly;
  there is no second reverse-index traversal.
- `ledger-reset-regime!` preserves admitted members' read-index arrival order,
  appends pending members, clears the old tally/member/index/signature state and
  marks the resulting members pending. Its native alias reset shares the file
  that creates regime aliases. Hazard calculation, the decision to reset, the
  per-evaluation allowance and scheduling remain in `eval_work.metta`.
- Dirty-member consumption and instance-change admission/consumption use the
  owner. Scheduler-local `sk_instance_checked` is still scheduler state, and is
  not moved into the contribution ledger.
- Computed and user base-rate cache replacement/removal now share the owner.
  `base_rates.metta` retains cache lookup, smoothing and reader-notification
  operations. Validation, complement canonicalization, input notification and
  prior-gating policy stay in the API controller. The **only change to reserved
  `runtime/backward/evaluation.metta`** replaces four physical cache-write bindings
  with one ledger call. No other step-6-reserved file is changed.
- Physical support identities, per-source deltas, branch counts, aggregate reverse
  edges and the numerical regime kernels move together out of `runtime_helpers.pl`.
  Their scoped-store representation, indexing, numerical formulas and regime
  merge/drop policy are unchanged. Common context/schema teardown remains the
  existing backend; the reserved `context_overlay.pl` is untouched, including its
  generic release of query-owned physical-source handles.

Bootstrap loads evaluator datatypes before the owner, after base-rate readers and
forward schemas, so the owner is available to both forward and backward code.
No runtime-to-later-module registration shim or duplicated implementation is kept.
The internal user-cache transaction accepts the already validated value as a type
parameter: strict specialization otherwise leaves a residual union type check
at the caller's canonicalization case. The public `set-base-rate` remains typed.

## Structural measurement

The supplied `scratch/reference_graph.py`, `reference_terms.pl` and
`core_count.py` are unchanged. The retained `scratch/ledger_audit.py` counts
literal MeTTa and native mutation sites for the nine stores named by the brief.
Generic context/schema reset machinery and variable-target mutations are outside
this ownership metric. This is a static source count, not execution frequency.

Reproduce with this worktree's `.venv/bin/python`, each command through `capped`,
DISPLAY unset, `ulimit -v 16000000`, stdin from `/dev/null`:

```sh
.venv/bin/python scratch/reference_graph.py --revision 84496c3e > scratch/graph-before.json
.venv/bin/python scratch/reference_graph.py > scratch/graph-after.json
.venv/bin/python scratch/ledger_audit.py --revision 84496c3e > scratch/ledger-before.json
.venv/bin/python scratch/ledger_audit.py > scratch/ledger-after.json
.venv/bin/python scratch/core_count.py . > scratch/core-after.txt
```

The token baseline was captured before editing in `scratch/core-before.txt`.
New files are staged/tracked for the after graph and writer audit.

| Store | Before writer files | After writer file |
|---|---|---|
| `&sk_instance_tally` | eval_versions, eval_work | runtime/statistical_ledger.metta |
| `&sk_instance_member` | eval_versions, eval_work | runtime/statistical_ledger.metta |
| `&sk_instance_regime` | runtime_helpers.pl, eval_work | prolog/statistical_ledger.pl |
| `&sk_instance_digest` | eval_versions, eval_work | runtime/statistical_ledger.metta |
| `&sk_instance_sig` | eval_versions, eval_work | runtime/statistical_ledger.metta |
| `&sk_instance_read` | eval_versions, eval_work | runtime/statistical_ledger.metta |
| `&sk_rate_dirty` | eval_folds, eval_versions, eval_work, forward/aggregates | runtime/statistical_ledger.metta |
| `&sk_instance_changed` | eval_folds, eval_work, forward/aggregates | runtime/statistical_ledger.metta |
| `&base_rate_cache` | base_rates, evaluation | runtime/statistical_ledger.metta |
| **Writer-file/store pairs** | **21** | **9** |

Literal mutation sites for these stores decrease **27 -> 25** through shared
member-consumption and instance-change operations. Every targeted store now has
one mutating file. The native half alone writes regime aliases, including reset.

| Reference graph metric | Base | Result |
|---|---:|---:|
| MeTTa/Prolog files | 55 | 57 |
| Defined names | 1,747 | 1,756 |
| Directed file edges | 380 | 399 |
| External callee references | 1,428 | 1,456 |
| Reciprocal file pairs | 18 | 18 |
| Largest SCC | 39 | 41 |
| Runtime/native to compiler file edges | 11 | 11 |
| Runtime/native to compiler callee references | 16 | 16 |

Ownership edges shrink by **12**; the global call graph grows. Both owner files
join the existing SCC. The MeTTa owner has no dependency on a backward evaluator,
skeleton builder or scheduler module. It reaches existing native primitives,
scoped storage, collection/vocabulary helpers, base-rate readers/notifications,
KB indexed reads and proof/evidence operations. This change does not claim a
smaller global cycle. It removes the scheduler's knowledge of contribution-store
erasure and the evaluators' direct contribution mutations, enabling later
replacement of tally/index storage without coordinating those controllers.

Token counts use `o200k_base` and the supplied counter's core scope:

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core MeTTa/Prolog plus top-level Python | 327,377 | 327,704 | **+327** |
| Third party | 17,685 | 17,685 | 0 |
| Total | 345,062 | 345,389 | **+327** |

## Tests and values

- Strict `scripts/test_metta.sh`: **162 passed, 0 failed**,
  `scratch/metta-third.log`. This precedes the final population projection
  signature cleanup; final verification below repeats the suite on that tree.
- Final focused run: **14 tests passed** across `test_statistical_ledger.py`
  (2), `test_fold_refresh.py` (7), `test_empirical_conditional_history.py` (1),
  `test_joint_base_rate.py` (4). Log: `scratch/focused-final.log`.
- The new population differential performs 70 deterministic replacements/removals,
  with zero/fractional/certain masses. It compares the delta tally both to an
  independent Python member map and to full summation of all retained observation
  rows. It checks leave-one-out sums/mass/count and unchanged authoritative state,
  then sets a rate on the same pattern in another KB and checks isolation.
- The instance differential replaces positive/negative fractional contributions,
  zeros a former sample, checks full stationary recomputation and exclusion
  projection, and verifies reset removes all six instance stores while replaying
  the three admitted members in first-admission order. Existing regime tests cover
  temporal hazard changes and segment merge/drop behavior in the strict suite.
- **No existing expected answer, strength, confidence, proof or scheduler count
  changes. No EXPECTED_FAILURES changes.** There are no moved numerical values
  requiring derivation. Only the new differential test file is added to tests.

During iteration the strict suite caught a residual union-type check at the new
user-cache boundary; preserving the caller's already validated value as a type
parameter resolved it. Initial differential probes also attempted to export local
unbound Prolog aggregation variables; those probes were corrected. No oracle,
threshold or existing expected value was weakened.

## Acceptance gates and limits

Every PeTTa/test/benchmark command ran through the prescribed `capped` wrapper,
with DISPLAY unset, `ulimit -v 16000000`, stdin from `/dev/null`. Tests used this
worktree's pinned environment; MeTTa used `scripts/test_metta.sh`. Comparisons set
`PETTACHAINER_REPO` to this worktree and used the supplied runner, cases and seeds.
Only the remote struct5 environment was prepared for paired dev-server timings;
its interpreter and editable-import paths point to struct5. No other worktree or
shared environment was modified.

All runtime acceptance results concern master **84496c3e**, runtime tree
**2d5bbdf13cd0**, and the implementation tree **e78e184f7266**; PeTTa runtime
**eec735bf4d1d3e31**. The original benchmark labels `e3da7833` and `501597c5`
refer to the same runtime as final implementation **948916f9** and checkpoint
**821f6814**. No source/test changes occurred during final acceptance runs.

- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **PASS, all six
  gates**, **309 seconds wall**, verification key **f1e7f14b3d1a**. Strict MeTTa:
  **162 files passed, zero failed**. Python: **1,032 tests / 71 files / 598 units**,
  the same **24 expected failures and one skip**; **4,534 query metric rows and
  zero aborts**. Import scaling ratio **1.010**, chunks **2.720, 2.734, 2.717,
  2.794 seconds**. Judgment scaling passed, three query rows and zero aborts.
  ConceptNet passed, exactly two results. Log: `scratch/verify-final.log`.
- `compare.sh master <worktree> --full`: **PASS; accuracy changed in zero cases**,
  all 22 accuracy comparisons identical plus the fuzzer gate. **43
  runs executed, 8 results reused, 377.1 seconds wall**.
  All **45 accuracy records** exit 0 and have no unsupported marker. The fuzzer
  retains the same five flagged KBs, with no unsupported KB or crash.
  Report: `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_e3da7833_full/report.md`; data: adjacent `compare.json`;
  log: `scratch/compare-full.log`.
- `compare.sh anchor <worktree> --canary --retime`: **PASS**, six cases, **all 12
  fresh paired dev-server jobs exit 0 at load 1**, **17 runs executed,
  328.6 seconds wall**. Its 12 accuracy records also exit 0, with
  no unsupported marker. The historical anchor differs in four cases; the same
  nine anchor deficits occur on master and are nonblocking under the prescribed
  runner. The embedded master comparison reuses all 12 accuracy records with
  **no answer movement**. Report: `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_e3da7833_canary-retime-20261031T011146/report.md`;
  data: adjacent `compare.json`; log: `scratch/compare-canary.log`.

The quick comparison is preserved as adverse timing evidence: **accuracy changed
in zero cases**, but it reported a local scale regression, metric seconds
**54.82 -> 61.91**, repeated locally **46.24 -> 80.65**. It executed
16 runs, reused 5 results and took 328.2
seconds wall. Report: `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_84496c3e-d7486beb4_quick/report.md`;
log: `scratch/compare-quick.log`. The fresh dev-server pair below supersedes that
timing evidence; it is not silently relabeled a passing quick run.

The full comparison had three local timing flags that its own paired reruns did
not repeat:

| Case | Initial metric seconds, master -> candidate | Local paired rerun |
|---|---|---|
| supplynet stage 3 untimed b25 s4 | 12.92 -> 14.28 | 9.602 -> 9.936 |
| learned stage 3 timed learned b50 r200 s1 | 15.66 -> 18.26 | 16.76 -> 16.83 |
| learned stage 3 untimed learned mined b50 r50 h10 s3 | 75.1 -> 102.4 | 67.61 -> 67.14 |

**Every locally flagged case was additionally retimed as a fresh master/candidate
pair on the dev server**, using `BENCH_TIMING_FULL=1 compare.sh master <worktree>
--full --only '<case>' --retime`. All eight fresh jobs exit 0 at load 1; each
comparison passes with unchanged accuracy. These are process wall seconds:

| Case | Master | struct5 |
|---|---:|---:|
| scale l spq4 s1 | 69.85 | 69.96 |
| supplynet stage 3 untimed b25 s4 | 11.54 | 11.52 |
| learned stage 3 timed learned b50 r200 s1 | 20.55 | 20.39 |
| learned stage 3 untimed learned mined b50 r50 h10 s3 | 90.57 | 90.79 |

Retiming reports and logs:

- scale l spq4 s1: `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_501597c5_full-scale_l_spq4_s1-retime-20261031T011753/report.md`; `scratch/scale-paired-retime.log`.
- supplynet stage 3 untimed b25 s4: `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_501597c5_full-supplynet_stage_3_untimed_b25_s4-retime-20261031T012024/report.md`; `scratch/supplynet-paired-retime.log`.
- learned stage 3 timed learned b50 r200 s1: `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_501597c5_full-learned_stage_3_timed_learned_b50_r200_s1-retime-20261031T012024/report.md`; `scratch/learned-paired-retime.log`.
- learned stage 3 untimed learned mined b50 r50 h10 s3: `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_501597c5_full-learned_stage_3_untimed_learned_mined_b50_r50_h10_s3-retime-20261031T012024/report.md`; `scratch/mined-paired-retime.log`.

Fresh canary process wall seconds against the historical anchor (these gaps also
exist on the task's master; they are not the cost of this extraction):

| Case | Anchor | struct5 |
|---|---:|---:|
| ona conditioning s1 | 5.59 | 10.82 |
| ona identitymatching s8 | 6.80 | 14.68 |
| live b50 5 shifts s1 | 6.96 | 10.47 |
| conflict pln-stated l spq4 s1 | 10.06 | 27.15 |
| conflict pln-reliable l spq4 s1 | 9.86 | 68.65 |
| scale m spq4 r10 s1 | 22.64 | 36.88 |

No scheduling, allowance or anytime policy changed, so curves are outside this
brief. Population/report/temporal policies and numerical approximations remain.
Native support and numerical regime blocks were additionally checked byte for
byte against their original base sections; both are identical. This extraction
does not justify deleting inference routes or regime semantics.

The result is **12 fewer writer-file/store pairs**, **+327 core tokens**, and a
**two-file larger SCC**. No global cycle or performance improvement is claimed.
No existing answer moved against the actual master base, no known
extraction-specific regression remains, and all required gates are complete.
Every process started for this task has finished. The branch is ready for
coordinator review; no push, merge, GitHub write, master code change or other
worktree code change was made. Standard runner outputs and the authorized shared
verification-cache write are the only shared artifacts.
