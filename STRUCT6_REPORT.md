# Structure step 6: one execution owner for scopes and allowances

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct6`.
Branch: `struct6`; base: **84496c3e**. This implementation/report checkpoint is
committed before final verification. Acceptance runs are still in progress;
a report-only follow-up will record completed results.

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
it is not hidden behind a compatibility wrapper. The other four requested
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
| Core | 327,377 | 329,635 | **+2,258** |
| Third party | 17,685 | 17,685 | 0 |
| Total | 345,062 | 347,320 | **+2,258** |

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
- Standalone Python suite: running (`scratch/python-first.log`).
- Full master comparison: running (`scratch/compare-full.log`).
- Master budget curves: queued/running (`scratch/compare-curves.log`). The
  runner makes `--full` and `--curves` mutually exclusive, so these are two
  prescribed comparisons rather than an invalid combined command.
- Anchor canary with fresh paired dev-server timing: running
  (`scratch/compare-canary.log`). Flagged full cases will receive an additional
  paired dev-server retime as required.
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: to run after
  this report checkpoint is committed.

## Limits and hand-back status

This checkpoint is not final acceptance. The reserved evaluation-budget writer
is outstanding, and full/Python/curves/canary/final verification must finish.
The numerical approximations, conditioning policies, search/evaluation order,
per-world allowances, public proof presentation and retained-cache behavior
remain. No native controller implementation or dead helper is retained for
compatibility. The measured support growth and larger SCC are stated above.
