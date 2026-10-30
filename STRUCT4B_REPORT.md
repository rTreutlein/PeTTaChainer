# Structure step 4b: one owner for exposed KB copies

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct4b`.
Branch: `struct4b`; base: **3d72b4c6**.
Implementation: **a3f6cddb**, `Centralize exposed KB copy publication and removal`.
This report and the publication audit are committed before final verification.
Final acceptance results will be recorded in a report-only follow-up.

## Diagnosis and design as built

Four runtime files mutated the exposed KB. Each controller also maintained part
of the physical copy's lifetime: prefix/open indexes, catalog role, evidence and
dependencies, and withdrawal registration. Removal and replacement therefore
required storage knowledge in materialization, forward chaining and forgetting.

`runtime/kb_publication.metta` now owns all eight literal `&kb` mutation sites,
its prefix/open index writes, the three derived-copy stores, and their
publication/removal provenance transactions. Bootstrap loads it immediately
before knowledge storage, after the journal and forward schemas it uses.

- `kb-publish-fact!` installs authored/temporary facts with the role supplied by
  compiler ingress. Live ingestion retains its duplicate check, functional
  policy, journal, combination learning and aggregate notification in
  `knowledge_store.metta`. Temporary insertion preserves exact clause references
  and the original index-before-fact insertion order; live insertion preserves
  fact-before-index order.
- `kb-publish-materialized!` replaces the prior materialization for its output
  key, preserves expanded fact proofs and evidence, registers the original
  source proof for withdrawal, and journals the exposed change. Materialization
  selection and traversal remain in `backward/evaluation.metta`.
- `kb-publish-prediction!` replaces the prior forward copy, preserving the check
  that an already stored identical fact needs no copy. Evidence, dependencies,
  catalog role and withdrawal registration leave with the old copy. Forward
  joins, scheduling and the decision to publish remain in `backward/upward.metta`.
- `kb-publish-summary!` records the forgotten proof's source provenance and
  publishes the summary with its evidence and bounded dependency window.
  Forgetting still chooses the value, computes decay and the dependency cut,
  evicts inference state, and decides whether to summarize or replay.
- `kb-retire-copy!` removes the affected materialization, prediction or summary.
  Forgetting then thaws a dead summary, clears its join digests, queues
  reconstruction, invalidates the merge and journals the change. The owner
  does not decide reconstruction policy.
- The generic backend insertion helper and `clear-temp-query-adds` move together
  into the owner. Exact temporary clause references include both facts/indexes
  and rule rows; cleanup keeps its existing catalog and dormancy cleanup order.
  Query bracketing is unchanged. Catalog records themselves still belong to
  the native source-catalog owner, and shared provenance sets to their existing
  native owner.

Catalog roles remain the explicit step-2 roles: **observation, prediction,
materialized, summary**. The existing withdrawal ledger's `forward` kind denotes
prediction copies; its schema and the physical store shapes are unchanged.
No compatibility aliases or duplicate implementations remain. Deleted names
`upsert-materialized!`, `sk-forward-store!` and `sk-forget-forward-copy!` have
zero hits in `pettachainer/`, `third_party/`, `tests/` and `docs/`.
Public API signatures are unchanged. None of step 4a's reserved files
(`eval_versions.metta`, `skeleton.metta`, `eval_work.metta`) is edited.
`eval_values.metta` has only a comment reference updated to the new owner name.

## Structural measurements

The supplied `scratch/reference_graph.py`, `reference_terms.pl` and
`core_count.py` are unchanged. The new retained `scratch/publication_audit.py`
counts literal mutation sites and writer files for the publication stores,
using the same MeTTa form reader. These are static ownership/reference counts,
not execution frequencies. Dynamic target-space insertion and exact temporary
clause erasure are outside literal counts; both implementations now live in
`kb_publication.metta` too.

Reproduction, from this worktree with DISPLAY unset, `ulimit -v 16000000` and
stdin from `/dev/null`, wrapping each invocation in the prescribed `capped`:

```sh
.venv/bin/python scratch/reference_graph.py --revision 3d72b4c6 > scratch/graph-before.json
.venv/bin/python scratch/reference_graph.py > scratch/graph-after.json
.venv/bin/python scratch/publication_audit.py --revision 3d72b4c6 > scratch/publication-before.json
.venv/bin/python scratch/publication_audit.py > scratch/publication-after.json
.venv/bin/python scratch/core_count.py . > scratch/tokens-after.txt
```

The token baseline was captured before editing in `scratch/tokens-before.txt`.

| Metric | Base 3d72b4c6 | struct4b |
|---|---:|---:|
| MeTTa/Prolog files | 53 | 54 |
| Defined names | 1,738 | 1,741 |
| Directed file edges | 352 | 362 |
| External callee references | 1,412 | 1,408 |
| Reciprocal file pairs | 17 | 16 |
| Largest file SCC | 37 | 38 |
| Runtime/native to compiler file edges | 11 | 11 |
| Runtime/native to compiler callee references | 16 | 16 |
| `&kb` writer files | **4** | **1** |
| `&kb` literal mutation sites | 8 | 8 |

The three shared `&kb` ownership edges are removed. Index and derived-copy store
writes move into that same owner. No global SCC reduction is claimed: the new
owner joins the existing cycle, adding one file. Total file edges rise by ten,
while external callee references fall by four and reciprocal pairs fall by one.
The boundary enables later copy-transaction simplification without making
forward/materialization/forgetting controllers coordinate physical storage.

Token counts, `o200k_base`, supplied counter:

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core MeTTa/Prolog and top-level Python | 326,245 | 326,647 | **+402** |
| Third party | 17,685 | 17,685 | 0 |
| Total | 343,930 | 344,332 | **+402** |

The increase is the explicit publication/removal boundaries and ownership
comments. This step permits support structure growth; it does not claim a
numerical-policy deletion or a reduction in the number of physical writes.

## Tests and moved values

- Strict MeTTa suite: **162 files passed, zero failures** after extraction, and
  again after moving temporary cleanup. Logs: `scratch/metta-second.log`,
  `scratch/metta-owner-final.log`. Includes the requested
  `test_forward_backward_compose.metta`, materialization, forgetting and
  withdrawal tests.
- `test_withdrawal_bridge.py`: **3 tests passed**;
  `scratch/withdrawal-bridge.log`.
- `test_forgetting_aggregates.py`: **8 tests passed**;
  `scratch/forgetting-aggregates.log`.
- New `test_kb_publication.py`: **3 tests passed**;
  `scratch/publication-accepted.log`. Covers materialize → forward → withdraw →
  budget-zero/read-again, catalog role preservation, surviving authored facts,
  both directions of fact/index/catalog consistency, mixed summary removal and
  thaw/reconstruction of the live contributor, and Assuming cleanup without
  temporary fact/index/catalog leaks.
- No existing test value, proof expectation, confidence, scheduler score or
  EXPECTED_FAILURES entry is edited. No answer is intended to move. New-test
  development corrected an invalid Assuming syntax and Janus probe variables;
  its cold-read assertion also recognizes the legitimate population prior
  supplied by a surviving rule after the retired instance copies disappear.
  Those were fixture assumptions, not runtime changes or weakened old tests.
- Initial strict checking rejected declaring the new authored publication
  boundary deterministic: its existing acyclic insertion operation is
  semideterministic. The boundary now declares the actual effect and preserves
  both the live empty result and temporary backend's Boolean result.
  No new import-order warning occurs; existing native `/` and forward-use
  `sk-merge-facts` warnings remain.

## Acceptance gates

All project execution uses the pinned worktree runtime, `ulimit -v 16000000`,
DISPLAY unset and stdin from `/dev/null`. Test/measurement jobs use `capped`;
benchmark jobs use prescribed `compare.sh`, which admits its child runs through
the same pool. No runners, seeds or frozen builds are improvised.
Comparisons set `PETTACHAINER_REPO` to this worktree. An independent remote
`.venv` was prepared only under the remote struct4b path for paired dev-server
timing; its editable import and script interpreters point there. The shared
remote environment was read to make that copy and is unmodified.

At this pre-verification checkpoint, the following prescribed comparisons are
running or awaiting their results:

- `compare.sh master <worktree> --quick`: `scratch/compare-quick.log`.
- `compare.sh master <worktree> --full`: `scratch/compare-full.log`.
- `compare.sh anchor <worktree> --canary --retime`:
  `scratch/compare-canary.log` (requests fresh paired dev-server timing).
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh` will run after
  this report is committed. Any flagged full-comparison case receives the
  prescribed paired dev-server retime before hand-back.

No scheduling, budget or anytime policy changes, so curves are outside scope.
The final report-only follow-up will record verdicts, report paths, exit/status
coverage and any remaining limits. No push, merge or GitHub write is made.
The local code changes are confined to struct4b; prescribed benchmark outputs
and the runner-authorized verification cache are the only shared writes.
