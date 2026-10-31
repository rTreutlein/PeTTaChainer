# Structure step 6: one execution owner for scopes and allowances

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct6`.
Branch: `struct6`; base: **84496c3e**. Implementation/report checkpoint:
**5393b9f4**; cleanup/probe correction **dc4d82d3**. The original labels were
f64172b7 and 0fcba2f1. Message-only rewording joined the two required trailers
into one Git footer; both trees, authors and original dates are unchanged.
The benchmark labels retain the original immutable 0fcba2f1 identity.
The correction fixes interrupted-frame cleanup and qualifies
physical test-probe lookups; it is committed before final verification.
Acceptance runs are still in progress; a report-only follow-up will record
completed results.

## Diagnosis and design as built

`prolog/context_overlay.pl` combined storage borrowing with evaluator control:
seed registration, rule activation, forward starts, locality decisions,
propagation policy, per-world budgets and evaluation. Backward and forward
controllers separately initialized allowances and repaired abandoned frames.
The public query controller owned temporary additions and answer retention.

`runtime/execution.metta` now owns those execution responsibilities. Compilation
returns an inert `query-scope` declaration; it allocates an identity but creates
no overlay or mutable scope registry entry. The executor installs declared
scopes before canonicalizing/injecting their temporary additions, prepares MAIN
search, activates assumption rules/seeds structurally, evaluates MAIN and each
input world, and retains the public answer proofs before removing the scopes.
Implication judgments retain their existing private-context policy.

The native overlay supplies indexed physical rows, seed identities, rule rows,
local-key membership and propagation snapshots. MeTTa decides cold-merge
locality from the same indexed producer/member inputs and applies the existing
threshold to the merged value and every row view, including dominated views.
Native storage calls no fixed runtime evaluator, activator, value reader or
forward-join operation. Physical overlay switching restores the previous scope
on success, failure and exceptions.

The execution owner initializes backward, forward and per-world allowances;
opens/returns nested evaluation slices; maintains branch frames; grows and
charges the near-root reserve; and owns generic counter charging. Root/branch
tiers are typed constructors, avoiding unevaluated Atom arguments at the
compiler boundary. Existing amounts, charge formulas, ordering and initial
per-world reserve are preserved. Forward runs retain their prior behavior of
leaving root-claim settings unused, rather than gaining a new allowance.

`prolog/execution.pl` supplies a generic callback/finally bracket, nonbinding
result compatibility and callable-contract registration. It selects no runtime
operation. The registration records arities as well as the existing native
signature metadata: a callable name alone leaves a cross-module MeTTa call
partially applied until its later definition is loaded. Contracts are registered
before mutually recursive users; implementations load after the evaluator and
forward computation modules. No compatibility implementation or old controller
remains. Typed pair callbacks stay named where an inline lambda loses the
strict checker's destructuring proof.

Backward execution finally closes unfinished claim/branch frames, releases
held MAIN work if an exception interrupted it, and retires temporary search
rows. The public-query finally bracket owns physical overlay removal,
temporary additions/catalog retirement, search retirement and collection,
through presentation and proof retention. Forward execution finally closes
frames and clears forward mode. Public API signatures and numerical policies
are unchanged.

## Reserved-file constraint

The brief reserves **all of `eval_versions.metta`** for the parallel step 5.
It also contains a direct evaluation-budget charge at line 942. I requested
permission for a surgical non-ledger replacement with the executor's existing
charge operation and have not received an answer. That file remains untouched,
as do `eval_folds.metta`, `forward/aggregates.metta` and `runtime_helpers.pl`.
Only allowance code changes in `eval_work.metta`; no ledger section is edited.

Consequently, evaluation-budget writers currently fall **6 -> 2**, rather than
the requested one. The remaining writer is explicitly visible in the audit;
it is not hidden behind a compatibility wrapper. The exact proposed one-line
change is retained in `scratch/remaining_budget.patch`, checked with
`git apply --check` but not applied. Its existing `>= 1` guard makes the
executor's one-unit charge equivalent to the direct decrement. The other four requested
settings each have one writer. This is an outstanding scope constraint, not
an achieved target or an accepted exception.

## Structural measurements

Retained supplied counters: `scratch/reference_graph.py`,
`reference_terms.pl`, `core_count.py`. The new `execution_audit.py` records
literal MeTTa/Prolog setting writes, with identical rules on base and candidate.
Generic dynamic counter charging is outside literal counts; its implementation
also moved into the execution owner. These are static references and ownership
counts, not runtime frequencies.

Reproduce with this worktree's `.venv/bin/python`, through `capped`, DISPLAY
unset, `ulimit -v 16000000`, stdin from `/dev/null`:

```sh
.venv/bin/python scratch/reference_graph.py --revision 84496c3e
.venv/bin/python scratch/reference_graph.py
.venv/bin/python scratch/execution_audit.py --revision 84496c3e
.venv/bin/python scratch/execution_audit.py
.venv/bin/python scratch/core_count.py .
```

| Metric | Actual base | Candidate |
|---|---:|---:|
| MeTTa/Prolog files | 55 | 57 |
| Defined names | 1,747 | 1,779 |
| Directed file edges | 380 | 392 |
| External callee references | 1,428 | 1,449 |
| Reciprocal file pairs | 18 | 16 |
| Largest file SCC | 39 | 44 |
| Overlay -> runtime file edges | **9** | **0** |
| Overlay -> runtime callee references | **23** | **0** |
| Evaluation-budget writer files | 6 | **2** |
| Branch-budget writer files | 5 | **1** |
| Branch-frame writer files | 4 | **1** |
| Root-allowance writer files | 4 | **1** |
| Near-reserve writer files | 4 | **1** |
| Brief's five settings: file/setting pairs | 23 | **6** |
| Root-cap writer files (additional audit) | 3 | **1** |

The brief's 22-callee/seven-file baseline predates this base's value-store and
rate-plan ownership extractions. The same supplied graph method measures 23
callees/nine files on actual base 84496c3e. All are removed. Global edges and SCC
size grow; no global cycle-size reduction is claimed.

`o200k_base`, supplied counter's core scope (MeTTa/Prolog and top-level Python):

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core | 327,377 | 329,640 | **+2,263** |
| Third party | 17,685 | 17,685 | 0 |
| Total | 345,062 | 347,325 | **+2,263** |

The owner, explicit contracts, typed scope/snapshot/slice boundaries and finally
support add code. This exceeds the rough sizing estimate; separation is the
measured result. It enables later lifecycle deletion without making native
storage an evaluator controller.

## Tests and moved values

- Strict MeTTa suite passed **162 files, zero failures** after the extraction
  (`scratch/metta-owner-first.log`) and after forward/finally consolidation
  (`scratch/metta-finally.log`). Includes the requested implication-judgment
  contexts and forward-unit tests. Existing expected values are unchanged.
- `test_context_overlay.py`: **27 passed**, including zero/positive threshold,
  per-world budget and storage/provenance boundaries; `scratch/overlay-owner-first.log`.
- `test_context_overlay_cache.py`: **one passed**, including cold/cached load
  equivalence and snapshot reuse; `scratch/cache-finally.log`.
- `test_assuming_exists.py`: **five passed**, all existing source-gated witness
  values and confidence unchanged; `scratch/assuming-owner-second.log`.
- New `test_execution_scope.py`: **three passed**, checking inert compilation,
  failed/throwing hypothetical evaluation cleanup before the next query, and
  repeated reversed mixed MAIN/positive/negative-world batches at budgets
  0, 1 and 20; `scratch/execution-accepted.log`. The explicit CTV fixture
  predicts .9/.8 under a certain action; confidence is checked to normal
  floating-point precision. No old oracle is modified.
- The old native finish hook was removed with its implementation. Test-only
  captures now observe physical `context-clear!` before teardown, retaining
  the same view/provenance assertions. Wrapping the new recursive MeTTa
  context-result function itself caused the existential observer run to lose
  its result; the uninstrumented query retained the exact original value.
  Observing physical teardown restores all five tests without changing source
  semantics or expected values.
- No old truth value, proof expectation, confidence, score, threshold or
  EXPECTED_FAILURES entry changes. Strict checking caught type/effect and
  callable-arity boundaries during development; failed exploratory loads are
  not acceptance evidence.

## Acceptance gates

All project execution uses the pinned worktree runtime through the prescribed
`capped`, virtual-memory limit, DISPLAY and stdin restrictions. Comparisons use
`PETTACHAINER_REPO` set to this worktree. The remote timing host has an independent
`.venv` under its corresponding **struct6** directory only; the shared environment
was read to copy it, never modified. No push, merge or GitHub write is made.

- Quick comparison: **PASS, accuracy changed in zero cases**, 10 cases,
  nine runs executed, ten of 19 results reused, **83 seconds wall**. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_84496c3e-d4590636f_quick/report.md`;
  log `scratch/compare-quick.log`.
- First standalone Python suite: **1,050 tests / 71 files / 598 units**, 24
  existing expected failures and one skip. It exposed two failed units:
  the overlay observer's module lookup (four errors) and the interrupted-frame
  cleanup regression (one failure). The observer now qualifies its physical
  lookup with `user:`; all 27 overlay tests pass (`scratch/overlay-finally.log`).
  The cleanup helper had reused the result variable of `change-state!` in its
  quoted wildcard. Distinct reset-result and stored-frame variables restore
  full clearing. All **17 exclusion-state probes pass** in their isolated
  test process (`scratch/exclusion-fixed.log`). No assertion was weakened.
- Pre-cleanup-fix full master comparison: **PASS, accuracy changed in zero
  cases**, 23 cases, 36 executed / nine reused records, **201 seconds wall**.
  Report `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_84496c3e-dd01c84b9_full/report.md`;
  log `scratch/compare-full.log`. This is exploratory evidence for the earlier
  runtime tree, superseded by the new full comparison after the cleanup fix.
- Corrected-tree curves: **eight workloads / 40 paired budget points**, all
  measured errors exactly equal, no missing or unsupported points, **642 seconds
  wall**. Ladders include scale m/l through 32 steps per query, ordinary and
  soft SupplyNet, the ten-region workload, conflict and replay. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/84496c3e_vs_0fcba2f1_curves/curves.md`;
  adjacent `curves.json`; log `scratch/compare-curves-final.log`. Local timings
  span changing machine loads and are not claimed as speedups.
- Corrected-tree anchor canary: **PASS**, six cases, all **12 accuracy records
  exit 0**, no unsupported marker, **12 fresh paired dev-server timing records
  at load 1**, **316 seconds wall**. Four cases differ from the historical
  anchor; the nine historical anchor deficits are also present on master.
  The embedded comparison against actual base 84496c3e has no answer movement.
  Report `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_0fcba2f1_canary-retime-20261031T013334/report.md`;
  adjacent `compare.json`; log `scratch/compare-canary-final.log`.
- Corrected-tree final verification: **PASS, all six gates**, **291 seconds
  wall**, verification key **5750b590669e**. Strict MeTTa: **162 files**, zero
  failures. Python: **1,033 tests / 71 files / 598 units**, the existing
  **24 expected failures and one skip**, **4,548 query metric rows and zero
  aborts**. Import scaling: **0.998** late/early median ratio, chunks
  **2.694, 2.649, 2.660, 2.672 seconds**. Judgment scaling: three query rows,
  zero aborts. ConceptNet: exactly two query results. Log:
  `scratch/verify-accepted.log`. The earlier queued verification was stopped
  before starting when the first Python suite found the frame-clear defect.
- Corrected-tree full profile: **still queued** behind a landing-priority
  full comparison (`scratch/compare-full-accepted.log`). The first concurrent
  full launch failed in benchmark freeze-directory creation before running a
  case (`scratch/compare-full-final.log`); curves created the same immutable
  candidate successfully, and the queued retry uses that existing build.
  Required full-case timing retimes will follow any flags.

The accepted corrected runtime tree is **c2e1668e2f12** (code commit
**dc4d82d3**, benchmark identity **0fcba2f1**); base runtime tree **2d5bbdf13cd0**; PeTTa runtime
**eec735bf4d1d3e31**. Earlier quick/full exploration used runtime tree
**9d482010d97c** before the quoted-wildcard fix. No source or test changes
follow the corrected implementation checkpoint.

## Limits and hand-back status

This checkpoint is not final acceptance. The reserved evaluation-budget writer
is outstanding, and the corrected-tree full comparison must finish. All
other corrected-tree gates are complete and passing.
The numerical approximations, conditioning policies, search/evaluation order,
per-world allowances, public proof presentation and retained-cache behavior
remain. No native controller implementation or dead helper is retained for
compatibility. The measured support growth and larger SCC are stated above.
