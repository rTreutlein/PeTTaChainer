# Structure step 4a: one owner for value publication and eviction

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct4a`.
Branch: `struct4a`; base: `3d72b4c65b3c004b17883425f10bdd4a2d59c4b8`.
Implementation: **35bac73a**, `Centralize value publication and eviction in one owner`.
Pre-verification report checkpoint: **75a0d509**. The implementation and checkpoint have the requested trailers; this report-only follow-up records the completed acceptance results.

Commits preceding this final report-only follow-up (`git log --oneline master..HEAD`):

```text
75a0d509 Record struct4a ownership measurements before final verification
35bac73a Centralize value publication and eviction in one owner
```

The implementation commit contains the owner and regression. The checkpoint records the structural measurements before final verification; this follow-up records the finished gates and timing checks.


## Diagnosis and design as built

The same cached row value had separate publication, invalidation and eviction implementations in `eval_versions.metta`, `skeleton.metta` and `eval_work.metta`. Branch requests and query-local representative/summary-reference caches also had direct writers in `eval_core.metta` and query startup. The actual base has **20 writer-file/store pairs for the eight stores in the brief**. This is the baseline measured here, rather than the earlier analysis's source-line numbers.

`runtime/backward/value_store.metta` now owns all literal mutations of latest views, retained history, row support, exclusion branches, branch owners, wanted requests, representatives and summary references. It also owns branch-reader registration and branch dirtiness. The publication and eviction implementations have been removed from their former files. There are no aliases, compatibility implementations or schema changes. Index keys, alpha checks, branch retention order, eight-context cap, exclusion cuts, support unions and history dominance retain their existing implementations.

`sk-commit-result!` admits a computed row value and returns `SkeletonCommit`:

- `sk-uncommitted`: no reader notification is needed, including repeated identical results and empty support with no closed-key notification.
- `sk-committed change`: an outside change or empty complete-key notification is ready for scheduling.
- `sk-merge-refresh deps causes before`: publication happened; the prior merged-cache snapshot and original causes let the scheduler compare the recursive post-publication merge before deciding between `sk-view-change` and `sk-value-same`.

`sk-compute` still evaluates the row and owns scheduling. The store neither evaluates a row nor invokes the recursive value reader. This retains the former evaluation/publication/merge-comparison order, including provenance-only refreshes, and avoids an owner-to-evaluator callback. Lazy folds share the same owned `sk-store-view!` publication primitive; their existing change checks remain in the scheduler.

Requests are deduplicated by the owner and removed only after a rebuild returns. Unfinished requests are requeued in the former order. Representative replay remains in the evaluator; its in-progress/result transitions pass through the owner as `RepresentativeUpdate`, preserving cycle markers and the rule against memoizing an exhausted empty replay. Summary-reference publication retains the existing row-local volatility check. Query startup clears both local value caches through the same owner. The only edit to `evaluation.metta` replaces those two cache clears; its `&kb` writes are untouched.

The owner loads before skeleton construction. Its pure view identity, liveness/dependency operations and complete-statement classification moved with it; evaluator types load first. This removes the new load-order cycle instead of retaining registration shims or moving representative/summary evaluation kernels across the compiler boundary. All ordinary and overlay mutations still use the existing context facade. Wildcard query-cache clear patterns are explicitly quoted as data for strict determinism.

## Structural measurement and tokens

Scripts: supplied `scratch/reference_graph.py`, `scratch/reference_terms.pl`, `scratch/core_count.py`, plus `scratch/value_store_audit.py`. Measurements use the actual base revision and final implementation. The reference graph counts tracked MeTTa/Prolog functions and expression/callback references, not dynamic calls, imports or store accesses. The writer audit counts literal MeTTa mutation sites for the named stores, including removal and replacement; generic context/reset infrastructure is outside this ownership metric.

Reproduce the graph with `scratch/reference_graph.py --revision 3d72b4c6` and `scratch/reference_graph.py`; writer counts use `scratch/value_store_audit.py` with the same revision option. Run counters with this worktree's `.venv/bin/python`, through the prescribed capped environment. Captures: `scratch/graph-before.json`, `scratch/graph-after.json`, `scratch/store-writers-before.json`, `scratch/store-writers-after.json`, `scratch/core-before.txt`, `scratch/core-after.txt`.

| Store | Writer files before | After |
|---|---:|---:|
| latest (`&sk_latest`) | 2 | 1 |
| history (`&sk_view`) | 2 | 1 |
| support (`&sk_support`) | 3 | 1 |
| branch (`&sk_branch`) | 2 | 1 |
| branch owner (`&sk_branch_owner`) | 2 | 1 |
| wanted (`&sk_branch_wanted`) | 3 | 1 |
| representative (`&sk_representative`) | 3 | 1 |
| summary reference (`&sk_summary_reference`) | 3 | 1 |
| **Brief's total file/store pairs** | **20** | **8** |
| branch reader | 1 | 1 |
| branch dirty | 2 | 1 |

Every after-column owner is `value_store.metta`. Literal mutation-site counts for these stores are unchanged: this is ownership separation, not deletion of their semantics.

| Graph metric | Base | Result |
|---|---:|---:|
| MeTTa/Prolog files | 53 | 54 |
| Defined names | 1,738 | 1,744 |
| Directed file edges | 352 | 370 |
| External callee references | 1,412 | 1,432 |
| Reciprocal file pairs | 17 | 19 |
| Largest SCC | 37 | 38 |
| Runtime/native to compiler file edges | 11 | 11 |
| Runtime/native to compiler callee references | 16 | 16 |

The requested ownership edges shrink by **12**; global call edges and SCC size grow. The owner has nine outgoing file dependencies, none on the backward evaluator or skeleton implementation. It remains in the large SCC through the existing shared native/runtime dependencies. No global SCC reduction is claimed.

`o200k_base`, supplied counter's core scope (MeTTa/Prolog plus top-level Python):

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core | 326,245 | 326,975 | **+730** |
| Third party | 17,685 | 17,685 | 0 |
| Total | 343,930 | 344,660 | **+730** |

The six new functions are lifecycle operations: result commitment, request admission/completion, query-cache clearing, summary-cache publication and representative-cache transition. Existing moved functions retain their names; no function name was deleted, and no public API signature changed. The new regression test exercises the publication boundary without preserving dead test helpers.

## Tests and moved values

- Strict `scripts/test_metta.sh`: **162 passed, 0 failed**. Log: `scratch/metta-owner-second.log`.
- `test_exclusion_state.py`: **PASS**, 17 isolated probe tests, including the new commit/provenance regression. Log: `scratch/exclusion-final.log`.
- `test_history_closed_replay.py`: **PASS**, one isolated temporal-history/cache audit. Log: `scratch/history-closed-replay.log`.
- `test_pending_work.py`: **PASS**, one randomized differential pending-index test. Log: `scratch/pending-work.log`.
- `test_repeated_queries.py`: **PASS**, five tests, the existing three expected failures unchanged. Log: `scratch/repeated-queries.log`.

The new test distinguishes a forced proof-only refresh from a forced truth-value change: the former preserves dependency support, original causes and settled branch reuse; the latter invalidates the branch and emits an outside change. A repeated identical result emits no change. Existing branch invalidation, teardown, interruption, closed replay and repeated-query checks are retained.

**No existing expected truth value, confidence, proof shape, scheduler count or threshold changed.** No EXPECTED_FAILURES annotation changed. No numerical route was removed. No moved values require derivations.

## Acceptance gates

All tests, PeTTa and benchmark execution use `/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, DISPLAY unset and stdin from `/dev/null`. MeTTa runs through the repository-pinned executable and suite runner. Comparisons set `PETTACHAINER_REPO` to this worktree. Only the remote struct4a environment was prepared for timing; the remote shared environment was read as its copy source, not modified.

- Quick comparison: **PASS; accuracy changed in 0 cases**, all nine compared accuracy cases identical plus the reference check. Nine runs executed, ten results reused, 66 seconds wall. Report: `/nexus/Dev/OpenCog/bench/results/compare/3d72b4c6_vs_3d72b4c6-d650f6181_quick/report.md`; log: `scratch/compare-quick.log`. This captured an earlier whitespace-only form of the same implementation equations. Its Stage 3 timing sample had differing loads; the fresh dev-server retime below supersedes that timing evidence.
- `compare.sh master <worktree> --full`: **PASS; accuracy changed in 0 cases**, all 22 accuracy comparisons identical plus the fuzzer gate. **45 runs executed, two reused, 335 seconds wall**. All 45 present accuracy records have exit 0 and no unsupported marker. Base runtime tree `8e42844b9db9`; candidate `9d0ed86716a0`; PeTTa runtime `eec735bf4d1d3e31`. Report: `/nexus/Dev/OpenCog/bench/results/compare/3d72b4c6_vs_35bac73a_full/report.md`; data: adjacent `compare.json`; log: `scratch/compare-full.log`. One local timing flag did not repeat: conflict pln-reliable l spq4 s1 metric seconds **61.66 -> 81.96**, paired rerun **50.65 -> 50.33**. It is preserved as a false flag, not discarded. A fresh paired dev-server check of that case is recorded below.
- `compare.sh anchor <worktree> --canary --retime`: **PASS**, six cases, **18 runs executed**, including **all 12 fresh paired dev-server jobs exiting 0 at load 1**, **797 seconds wall including the shared timing-slot queue**. All 12 accuracy records exit 0 and have no unsupported marker. The older anchor differs in four cases; all nine anchor deficits are also present on master and are nonblocking under the prescribed runner. The embedded comparison with actual base 3d72b4c6 reused all 12 records. Report: `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_35bac73a_canary-retime-20261030T232919/report.md`; data: adjacent `compare.json`; log: `scratch/compare-canary.log`. No extraction-specific canary regression remains.
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **PASS, all six gates**, **319 seconds wall**, recorded verification key **5651f58b5fda**. MeTTa: **162 files**, zero failures. Python: **1,027 tests / 69 files / 629 units**, the same **24 expected failures and one skip**; **4,528 query metric rows and zero aborts**. Import scaling: **0.946** late/early ratio, chunks **2.624, 2.571, 2.411, 2.501 seconds**. Judgment scaling: PASS, three query rows, zero aborts. ConceptNet: PASS, exactly two results. Log: `scratch/verify-final.log`.

- Additional paired dev-server retime of **supplynet stage 3 timed b100 s3**: **PASS; accuracy changed in 0 cases**, both fresh jobs exit 0 at load 1. Process wall seconds **14.96 -> 15.06**; reported benchmark seconds **12.97 -> 13.05**, with peak RSS **226.6 -> 226.8 MB**. Report: `/nexus/Dev/OpenCog/bench/results/compare/3d72b4c6_vs_75a0d509_full-stage_3_timed_b100_s3-retime-20261030T233139/report.md`; log: `scratch/stage3-paired-retime.log`. Candidate report checkpoint 75a0d509 and implementation 35bac73a have the identical runtime tree **9d0ed86716a0**.
- Additional paired dev-server retime of **conflict pln-reliable l spq4 s1**: **PASS; accuracy changed in 0 cases**, both fresh jobs exit 0 at load 1. Process wall seconds **68.64 -> 68.40**; reported benchmark seconds **67.23 -> 66.98**, peak RSS **325.3 -> 325.7 MB**. Report: `/nexus/Dev/OpenCog/bench/results/compare/3d72b4c6_vs_75a0d509_full-conflict_pln-reliable_l_spq4_s1-retime-20261030T233659/report.md`; log: `scratch/conflict-paired-retime.log`. This independently clears the full comparison's local false flag.

Fresh paired **process wall seconds** against the historical anchor (these gaps also exist on the task's base; they are not the extraction's cost):

| Case | Anchor | struct4a |
|---|---:|---:|
| live b50, five shifts, seed 1 | 6.94 | 10.43 |
| conflict pln-reliable l spq4 s1 | 9.86 | 68.75 |
| scale m spq4 r10 s1 | 22.65 | 36.62 |
| conflict pln-stated l spq4 s1 | 10.03 | 27.17 |
| ONA conditioning s1 | 5.61 | 10.79 |
| ONA identitymatching s8 | 6.76 | 14.62 |

The standalone **master-versus-candidate canary comparison also passes with accuracy changed in 0 cases**, all six compared cases identical. It reused the 12 accuracy records and ran six fresh candidate timing jobs successfully at load 1 (166 seconds wall). Report: `/nexus/Dev/OpenCog/bench/results/compare/3d72b4c6_vs_75a0d509-db618712b_canary/report.md`; log: `scratch/compare-master-canary.log`. The label includes the uncommitted report-only capture; its recorded runtime tree is the same **9d0ed86716a0**. This separately exposes the anchor run's embedded master comparison as a reviewable report.

## Limits and hand-back

The measured structural result is one publication/eviction owner, not a smaller global call graph. Retained history and exclusion semantics, conditioning, numerical approximations, scheduling order and budgets remain. No scheduling/allowance/anytime policy changes require curves. Other modules retain read-only iteration through scoped value relations where selection needs it. The generic context facade, collectors and global reset infrastructure remain shared. This separation enables subsequent replacement/removal of duplicated value-cache bookkeeping; it does not justify removing historical or excluded proofs without separate semantic evidence.

All required acceptance gates and paired retimes are complete and passing. No answer moved against the actual base, no known extraction-specific regression remains, and every process started for this task has finished. The worktree is ready for coordinator review. No master/main-checkout/other-worktree code changes, pushes, merges or GitHub writes were made. The prescribed benchmark outputs and authorized verify-cache writes are shared runner artifacts.
