# Boilerplate round 2

Branch: `boilerplate2`. Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/boilerplate2`.
Baseline: `c39d127c33ac6d664253498f37fa28dbc986fb6d`.

## Commits

`01cd9e18 Consolidate datatype and native runtime declarations` implements all
three candidates and extends the cold-load/cache-replay test. `HEAD` is the
report-only follow-up recording the final gates. `git log --oneline c39d127c..`
lists both commits. No pushes, merges or GitHub writes.

## Diagnosis and design as built

The remaining manual declarations repeated nominal types in each constructor,
and native entry-point names appeared both in the bootstrap import list and in
scattered type signatures. These are source declarations, rather than repeated
runtime inference operations. Their expansion can preserve the compiled model.

1. Converted 86 manual Type/constructor groups (147 constructors) to the pinned
   PeTTa `datatype` syntax. Existing datatypes also use compact formatting where
   readable. Opaque types, brands, aliases and foreign types retain their existing
   declarations. Overloaded `:` and `base-rate` constructors keep their signatures.
2. Added `core/natives.metta`: one table contains all 210 existing native entry
   points, grouped by determinism. It retains 197 typed signatures and 13
   intentionally untyped entry points. The eight non-comment source lines of
   `declare-natives!` register the direct native functions and submit the generated
   declarations to PeTTa's ordinary loader. Existing native implementations and
   direct calls stay intact; no runtime dispatch wrapper was introduced. The
   bootstrap still resolves the same two supported helper paths, then loads this
   table before compiler/runtime consumers. The former import list and scattered
   native signatures were deleted.
3. Moved 36 paired typed-space declarations/initializers into the existing
   `store_schema.pl` table as `plain` stores. This adds no generator code. Their
   documentation moved with their schemas. Physical predicate names, row field
   order, scalar first columns and overlay policies remain unchanged. Initialization
   now occurs in the existing bootstrap store-declaration phase, before consumers.

The bounded scope deliberately excludes the previously rejected runtime alpha-match
wrapper, cache-or-compute abstractions, generic proof/TV visitors, and scheduler
changes described in `docs/metta/abstraction_review.md`. The four heap imports and
explicit FFI arities are left alone: they include untyped calls and are too small
to justify another declaration mechanism. The untyped logic configuration space
also stays at its existing initialization point.

## Source and size evidence

The static expansion audit preserves the complete original declaration multiset
(including generated space schemas), modulo declaration-local type-variable names.
The only additional signature is the internal `declare-natives!` loader. All
MeTTa equation bodies and their order are unchanged across the 40 current files.
No existing function or public API signature was removed or changed.

Counts use the supplied `scratch/core_count.py`, `o200k_base`, including comments
and the new generator/table. Production scope includes all eligible core MeTTa,
Prolog, top-level package Python, and `third_party/pln_formulas` plus
`third_party/metta_lowering`. Tests, reports, benchmarks and simulations are excluded.
“Code lines” below means nonblank physical source lines that do not begin with a
MeTTa, Prolog or Python comment marker; declaration and generator lines count.
Per-candidate counts were reconstructed from the baseline source using the same
transformations in `scratch/count-stages`, solely for static counting.

| Candidate / cumulative state | Total tokens | Token delta | Code lines | Line delta |
| --- | ---: | ---: | ---: | ---: |
| Baseline | 338,814 | — | 16,777 | — |
| Compact datatypes | 337,951 | -863 | 16,650 | -127 |
| Native metadata, including generator | 336,914 | -1,037 | 16,673 | +23 |
| Additional plain store declarations | 336,604 | -310 | 16,637 | -36 |
| **Net** | **336,604** | **-2,210** | **16,637** | **-140** |

Core: 321,129 → 318,919 tokens; 15,897 → 15,757 code lines.
Third-party formulas/lowering: unchanged at 17,685 tokens and 880 code lines.
Net token reduction: 0.652%. No separate generic-library credit is claimed.
The native table increases physical lines because formerly one long import line
now has explicit entries; the bundle reduces both requested totals.

## Validation

- Datatype checkpoint: strict `scripts/test_metta.sh`, **162 passed, 0 failed**.
- Native-table checkpoint: strict suite, **162 passed, 0 failed**.
- Grouped-native checkpoint: strict suite, **162 passed, 0 failed**.
- Store-schema checkpoint: strict suite, **162 passed, 0 failed**.
- Extended cold-load/cache-replay test: **PASS**, 1 test, 21.893 s. It checks native
  callable registration, det/semidet/nondet effects, polymorphic variable sharing,
  scalar-indexed row shapes, unchanged snapshot timestamps, and Assuming isolation.
- First full `scripts/verify.sh`: **PASS**, all six gates, 416 s. Python ran
  992 tests in 63 files (590 units), with 64 expected failures and 1 skip;
  4,496 query rows, zero aborts. MeTTa passed all 162 files. The runner declined
  to cache this result because the test/report changed while it ran.
- The stable-tree verification rerun's durable gate table is in
  `scratch/verify-final.log`. Production source and tests have not changed since
  `01cd9e18`; the rerun follows the report commit so the runner can record a
  reusable result for the complete, unchanged hand-back tree.
- `git diff --check`: PASS.

Every PeTTa, test and benchmark invocation was launched through
`/nexus/Dev/OpenCog/bench/capped`, with `ulimit -v 16000000`, `DISPLAY` unset and
stdin from `/dev/null`. Suite jobs use `--slots 16` and `PETTA_JOBS=16`. Gate
waiters use captured PIDs, `timeout` and `kill -0`, followed by `wait`.
Logs are under this worktree's `scratch/`.

The new test initially assumed an empty plain space already had a physical dynamic
predicate. PeTTa creates those predicates lazily. The assertion was corrected to
check the declared scalar first field and row arity. This changed no pre-existing
expected value or production behavior.

## Benchmarks

Candidates frozen by the standard runner: `c39d127c-d93d60dd0` (full and first
canary) and `c39d127c-d6aefd2bc` (paired canary retime). Their production runtime
tree is the same, `fdf76f1b34a3`; the labels differ after test/report edits.
PeTTa runtime digest: `eec735bf4d1d3e31`.

- Master full comparison: **PASS**; `accuracy changed in 0 cases` / accuracy
  identical in all 22 paired cases. 23 total cases, 44 runs executed, 1 of 45
  results reused; 392 s wall. No timing flags or regressions.
  Report: `/nexus/Dev/OpenCog/bench/results/compare/c39d127c_vs_c39d127c-d93d60dd0_full/report.md`.
- Anchor canary: **PASS**. The successful paired dev-server retime executed all
  12 runs across 6 cases, with exit 0 for both sides in every case; 301 s wall.
  `accuracy changed in 4 cases` is relative to the older anchor `b4065459`,
  and all four differences are also present on master. The runner's nested
  master comparison passed, with no candidate regression. Nine metrics remain
  behind the anchor on master too, including the live error/Brier/regret and
  the six case timings. None was waived or newly accepted for this branch.
  Report: `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_c39d127c-d6aefd2bc_canary-retime-20261030T062912/report.md`.
- Peak RSS against master: **PASS** for all 22 paired cases, maximum increase
  **+0.511%**, SupplyNet stage 3 timed b100 s3, 215.4 → 216.5 MB. This uses
  each comparison record's paired `timing.peak_mb`, rather than the runner's
  looser default threshold. The largest workload, scale l spq16 s1, moved
  1,358.4 → 1,357.4 MB. Full per-case audit: `scratch/rss_audit.json`.
- Paired dev-server retiming: **PASS**, all six canary cases timed with both
  builds on `roman@dev-server`, through the standard `--canary --retime` runner.
  The full comparison against master had no timing flags needing a retime.

The first canary's remote timing invocations exited 127 because the worktree-specific
Python path did not exist on `roman@dev-server`. Its local accuracy jobs run
normally. Prepared only the remote `boilerplate2/.venv` by copying the host's
existing pinned environment and repointing its editable finder; no main-checkout
source or other worktree was modified. The successful paired rerun supersedes
all six failed timing invocations; the first canary's printed PASS alone was
not treated as sufficient timing evidence.

## Moved values and expected failures

No pre-existing test answer, expected number or proof changed. The
`EXPECTED_FAILURES` mapping in `tests/test_tv_calibration.py` is unchanged.
Only additional cache/metadata assertions were added to an existing test.

## Limits

No answer values or expected failures moved. No claim of an inference-speed
improvement is made. This is declaration cleanup; logical equations, numerical
algorithms, search order and budgets are unchanged. The older anchor's existing
accuracy/performance differences remain, as reported above. Curves and nightly
benchmarks were not required for this change, which changes neither scheduling
nor budgets. The static scripts and all gate logs remain under ignored `scratch/`.
