# Structure step 4a: one owner for value publication and eviction

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct4a`.
Branch: `struct4a`; base: `3d72b4c65b3c004b17883425f10bdd4a2d59c4b8`.
Implementation: **35bac73a**, `Centralize value publication and eviction in one owner`.
This report checkpoint is committed before the final verification. Acceptance results below are completed in a report-only follow-up.

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

- Quick comparison: running at checkpoint; `scratch/compare-quick.log`. It captured an earlier whitespace-only form of the same implementation equations.
- `compare.sh master <worktree> --full`: running at checkpoint; `scratch/compare-full.log`.
- `compare.sh anchor <worktree> --canary --retime`: running at checkpoint; `scratch/compare-canary.log`. This requests fresh paired dev-server timings.
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: starts after this report is committed. Log: `scratch/verify-final.log`.

## Limits and hand-back

The measured structural result is one publication/eviction owner, not a smaller global call graph. Retained history and exclusion semantics, conditioning, numerical approximations, scheduling order and budgets remain. No scheduling/allowance/anytime policy changes require curves. The generic context facade, collectors and global reset infrastructure remain shared. This separation enables subsequent replacement/removal of duplicated value-cache bookkeeping; it does not justify removing historical or excluded proofs without separate semantic evidence.

At this checkpoint the final gates are outstanding; this report is not yet a completed hand-back. No master/main-checkout/other-worktree code changes, pushes, merges or GitHub writes were made. The prescribed benchmark outputs and authorized verify-cache writes are shared runner artifacts.
