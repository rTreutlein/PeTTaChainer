# Targeted merge 1: implication lowering

**Partial result; the complete one-lowering goal is not achieved.** The largest
retained state removes the separate raw-STV source namespace and its runtime
lookup, plus one two-side packaging wrapper. The positive-judgment namespace
and its live adapters remain because deleting them changed tested behavior.
No existing expected answer was edited.

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/merge1-implication`.
Branch: `merge1-implication`. Baseline: `2ad70bdf`.

## Diagnosis and retained design

A source STV was stored separately from its ordinary executable implication
key. Its permanent CTV producer reread that immutable source through a second
namespace before running the normal base-rate formulas. The source value is
already a compiler input: store it at its ordinary statement key and compile
the CTV producer directly from that value. The producer still reads the normal
rate goals and retains the original ForAll rate parameters. Nested-source
projections use the ordinary source. Rule-evidence confidence now needs only
ordinary KB lookup. This deletes the old storage route, rather than renaming
it to another private key.

The internal full-CTV plan now calls the shared judgment-side builder once
per polarity, directly. Its single-use packaging wrapper is deleted. The
positive, hypothetical and empirical producers otherwise retain their tested
value, evidence, discovery and lifetime behavior.

Design and complete baseline caller/store inventory:
`docs/metta/implication_lowering.md`. Existing Exists witness/claim folds,
Boolean-event quotient planning, compound producers and private judgment-world
borrowing were retained; no shared replacement for their distinct semantics
was demonstrated. B3, Assuming leaf merge, commutative-key canonicalization and
compound-output lowering were not changed.

## Rejected deletions and exact stopping evidence

The ordinary-key positive-judgment experiment removed private publication,
unwrapping, redirection and namespace-specific materialization checks. The
strict suite returned **158 passed, 3 failed**. It was reverted completely,
including its internal test-key rewrites.

| Test | Required existing result | Rejected result |
| --- | --- | --- |
| `test_forward_start_contextualized.metta` | No answer for the Assuming conjunction containing its own assumed implication and consequent | An answer at STV `(0.018959999999999998, 0.42039754412058533)` |
| `test_member_inheritance_premise.metta` | `(STV 0.8 0.0012484394506833685)`, one instance-fold proof | `(STV 0.8 0.0024937655860280327)`, revision of two instance-fold proofs |
| `test_implication_premise.metta` | Proof `(by ab_c (merge/revision a_b (total-implication (by a_b (ctx proof 0)) (by a_b (ctx proof 1)))))` | Proof `(by ab_c a_b)`; TV unchanged at `(STV 1.0 0.9998000399670116)` |

Evidence: `scratch/merge1/delete-query-namespace-metta.log` and
`scratch/merge1/rejected-query-namespace.patch`. A future common read needs to
separate executable assumption seeds from judgment support, count each sample
fold once across STV/CTV policies, and preserve full-premise producer discovery.
These are replacement obligations, not justification for moving the tests or
claiming the private route is inherently necessary.

A second attempted deletion removed the stored-statement collector because
source ingestion already publishes positive statements. The old suite, full
verify and quick comparison passed, but `add-to-kb` is also public and bypasses
source compilation. A direct stored STV then gave no zero-budget judgment
instead of `(STV 0.6 0.7)`. The collector was restored. Two regression assertions
were added to `test_implication_judgment_contexts.metta`: direct STV at budget
zero and direct CTV at budget one. The latter needs an expansion for branch
projection; an initial probe incorrectly demanded it at budget zero and is
not used as evidence of a regression.

The corrected focused STV probe passed with the collector and failed after
only its deletion: `scratch/merge1/direct-stv-retained.log` (exit 0) and
`scratch/merge1/direct-stv-deleted-collector.log` (exit 1, actual `()`). The
negative control restored the retained compiler in an EXIT trap before final
verification. No expected value was changed to accommodate either experiment.

## Footprint and deleted-symbol audit

`o200k_base`, using the supplied counter's exact file set. Core:
**327,208 -> 326,924 tokens; 284 saved (0.087%)**. Third-party:
**17,685 -> 17,685**. Combined: **344,893 -> 344,609**.
Counts exclude tests, reports and scratch files. The complete per-file table
is appended below; JSON snapshots are under `scratch/merge1/tokens-{before,after}.json`.

Deleted symbols: `query-pos-neg-scaffold` and namespace constructor
`implication-stated`. Audit:

```sh
rg -n -F -e query-pos-neg-scaffold -e implication-stated pettachainer/ third_party/ tests/ docs/
```

Zero matches (exit 1). The names are recorded here for the deletion audit;
this root report is outside the specified audit directories. The stored-fact
collector was restored, so it is not listed as deleted. The public API file and
`tests/test_tv_calibration.py` are byte-for-byte unchanged from baseline.

## Validation and benchmarks

All PeTTa, test and benchmark invocations used the pinned worktree runtime,
`/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, unset DISPLAY and
`</dev/null`. Suites used the prescribed repository scripts. Admission waits
were never bypassed; a queued 16-worker exploratory job was stopped and
resubmitted as a matching 8-worker job. No unbounded test or improvised
benchmark runner was used.

- Baseline strict MeTTa: 161 passed, zero failed.
- Retained strict MeTTa, with new public-entry assertions: 161 passed, zero failed.
- Final verify: **PASS, all six gates**, 547 s. Strict MeTTa 161/0;
  Python 967 tests, 125 existing expected failures, one skip; 4,430 Python
  query-metric rows and three judgment-scaling rows, all with zero aborts.
  Verification cache recorded PASS under key `106e11180467`.
- Full master comparison: **PASS; accuracy changed in 0 cases** (identical in
  all 22 compared cases, 23 profile cases). All 45 selected base/candidate/
  reference records have exit zero and no unsupported marker. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/2ad70bdf_vs_805541cf-d7729233b_full/report.md`.
  Three initial timing flags did not repeat: stage-3 timed b25 paired rerun
  8.59 -> 8.65 s; untimed b25 11.11 -> 11.11 s; conflict sources m spq4
  16.29 -> 16.32 s. No confirmed timing regression. Large scale spq16 wall
  159.61 -> 158.24 s; accuracy unchanged. These are benchmark-preservation
  results, not a general speedup claim.
- Final local anchor canary: **PASS; accuracy changed in 4 of 6 cases versus
  anchor**, the same differences present on master. Its embedded master
  comparison passes. Nine behind-anchor metrics are shared with master, with
  no blocking regression; the harness labels five timing metrics as progress
  toward the anchor. All 12 selected base/candidate records have exit zero,
  no unsupported marker, and no selected remote timing. This rerun reused the
  stored local workloads (zero runs executed). Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_805541cf-d0f4811b9_canary/report.md`.

The default canary's six remote timing jobs exited 127 because the worktree's
`.venv/bin/python` does not exist on `roman@dev-server`. Its nominal PASS is
not counted as complete timing evidence. Remote report/JSON are preserved in
`scratch/merge1/canary-remote-{report.md,compare.json}`. The same standard canary
was rerun using the documented `BENCH_TIMING_HOST=` local-timing override;
no remote installation or service was changed. The candidate name may differ
because docs/tests changed: its source runtime tree remains
`25ed4b085512cd9913bcd42b7b6a9abf8c784173`, with identical production files
verified against the full-comparison frozen build.

Two intermediate source-only jobs were stopped after identifying the missing
public-entry coverage; they are not counted as completed validation. Final
logs: `scratch/merge1/final-{metta,verify,full,canary-local}.log`.

## Moved values, limits and hand-back

No existing expected strength, confidence, proof or API signature moved.
The calibration expected-failure dictionary remains unchanged (122 entries);
the complete Python suite has 125 pre-existing expected failures and one skip.
The new direct-source assertions add coverage without replacing old assertions.

The main merge objective remains incomplete. The positive-query namespace,
source/derived collector, positive projection, CTV-premise scaffold and private
judgment contexts remain. The failed ordinary-key candidate is not shipped.
Speed preservation is established only to the standard benchmark thresholds;
remote-host timing remains unavailable for this worktree runtime. No curves
were run: scheduling, budgets and anytime policies were not changed.

Implementation commits (`git log --oneline 2ad70bdf..HEAD` before the
report-only commit), all on `merge1-implication` with the requested trailers:

```text
7eeeb368 Store immutable implication sources at ordinary keys
805541cf Delete redundant stored implication copies from query lowering
7a560aaa Document implication lowering producers and deletion boundaries
```

`7a560aaa` is the design-first inventory. `805541cf` initially deleted the
collector as well as the wrapper; **its collector deletion is restored by
`7eeeb368`**, after the focused public-entry probe. `7eeeb368` contains the
retained raw-source deletion, restored collector, regression assertions and
updated design. Review the final branch state rather than taking `805541cf`
alone. A final documentation-only commit adds this report.

All exec sessions started for tests, verification, probes and comparisons
were reaped. At hand-back preparation the admission pool reported zero rows
and zero slots in use. No push, merge, GitHub write, main-checkout source edit,
other-worktree edit or admission-service change was performed. The working
branch remains `merge1-implication`; no background waiter was used.

## All core and third-party file counts

| File | Before | After | Delta |
| --- | ---: | ---: | ---: |
| `pettachainer/metta/bootstrap.metta` | 1,522 | 1,522 | +0 |
| `pettachainer/metta/compiler/compiler.metta` | 295 | 295 | +0 |
| `pettachainer/metta/compiler/query_lowering.metta` | 7,746 | 7,539 | -207 |
| `pettachainer/metta/compiler/rules.metta` | 19,542 | 19,487 | -55 |
| `pettachainer/metta/compiler/runtime_encoding.metta` | 1,058 | 1,058 | +0 |
| `pettachainer/metta/compiler/source_lowering.metta` | 14,538 | 14,538 | +0 |
| `pettachainer/metta/core/logic_config.metta` | 1,203 | 1,203 | +0 |
| `pettachainer/metta/core/logic_configs/pln.metta` | 102 | 102 | +0 |
| `pettachainer/metta/core/logic_configs/predicate_logic.metta` | 75 | 75 | +0 |
| `pettachainer/metta/core/types.metta` | 4,220 | 4,220 | +0 |
| `pettachainer/metta/petta_chainer.metta` | 243 | 243 | +0 |
| `pettachainer/metta/prolog/context_overlay.pl` | 4,488 | 4,488 | +0 |
| `pettachainer/metta/prolog/event_node.pl` | 6,991 | 6,991 | +0 |
| `pettachainer/metta/prolog/ingestion.pl` | 4,559 | 4,559 | +0 |
| `pettachainer/metta/prolog/runtime_helpers.pl` | 55,976 | 55,954 | -22 |
| `pettachainer/metta/prolog/sorts.pl` | 2,518 | 2,518 | +0 |
| `pettachainer/metta/runtime/backward/diagnostics.metta` | 1,494 | 1,494 | +0 |
| `pettachainer/metta/runtime/backward/evaluation.metta` | 100,831 | 100,831 | +0 |
| `pettachainer/metta/runtime/backward/forgetting.metta` | 3,732 | 3,732 | +0 |
| `pettachainer/metta/runtime/backward/skeleton.metta` | 32,542 | 32,542 | +0 |
| `pettachainer/metta/runtime/backward/upward.metta` | 5,701 | 5,701 | +0 |
| `pettachainer/metta/runtime/base_rates.metta` | 1,804 | 1,804 | +0 |
| `pettachainer/metta/runtime/evidence.metta` | 7,074 | 7,074 | +0 |
| `pettachainer/metta/runtime/forward/aggregates.metta` | 6,012 | 6,012 | +0 |
| `pettachainer/metta/runtime/forward/schema.metta` | 1,926 | 1,926 | +0 |
| `pettachainer/metta/runtime/hypothesis_mining.metta` | 4,792 | 4,792 | +0 |
| `pettachainer/metta/runtime/hypothesis_review.metta` | 2,875 | 2,875 | +0 |
| `pettachainer/metta/runtime/ingest.metta` | 530 | 530 | +0 |
| `pettachainer/metta/runtime/kb_index.metta` | 608 | 608 | +0 |
| `pettachainer/metta/runtime/knowledge_store.metta` | 5,238 | 5,238 | +0 |
| `pettachainer/metta/runtime/observed_predicates.metta` | 486 | 486 | +0 |
| `pettachainer/metta/runtime/query.metta` | 3,477 | 3,477 | +0 |
| `pettachainer/metta/runtime/scheduling.metta` | 1,118 | 1,118 | +0 |
| `pettachainer/metta/runtime/skeleton_journal.metta` | 8,514 | 8,514 | +0 |
| `pettachainer/metta/runtime/values.metta` | 2,857 | 2,857 | +0 |
| `pettachainer/__init__.py` | 131 | 131 | +0 |
| `pettachainer/pettachainer.py` | 8,149 | 8,149 | +0 |
| `pettachainer/pln_validator.py` | 758 | 758 | +0 |
| `pettachainer/query_diagnostics.py` | 1,483 | 1,483 | +0 |
| `third_party/pln_formulas/metta/compute_inverse.metta` | 515 | 515 | +0 |
| `third_party/pln_formulas/metta/distributions.metta` | 5,693 | 5,693 | +0 |
| `third_party/pln_formulas/metta/truth_values.metta` | 11,477 | 11,477 | +0 |
