# Structure step 4b: one owner for exposed KB copies

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct4b`.
Branch: `struct4b`; base: **3d72b4c6**.
Implementation: **a3f6cddb**, `Centralize exposed KB copy publication and removal`.
Pre-verification report and reproducible publication audit: **8e9f5e0e**,
committed before final verification. This report-only follow-up records the
completed acceptance gates, including the flagged scale case's dev-server
retime. All commits carry the requested Co-Authored-By and Claude-Session trailers.

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

All final gates use implementation **a3f6cddb**, runtime tree
**7bdde4b095f9**. The base is **3d72b4c6**, runtime tree **8e42844b9db9**;
PeTTa runtime **eec735bf4d1d3e31**. The quick comparison's dirty snapshot has
exactly the same runtime tree as the implementation commit. There are no
source/test changes after the implementation commit.

- Quick comparison: **PASS, accuracy changed in zero cases**, 62 seconds wall;
  14 runs executed, five of 19 results reused. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/3d72b4c6_vs_3d72b4c6-d46865c84_quick/report.md`;
  log: `scratch/compare-quick.log`.
- `compare.sh master <worktree> --full`: **PASS, accuracy changed in zero
  cases**. All 22 accuracy comparisons are identical, plus the reference/fuzzer
  gate: 23 cases, **38 runs executed, nine of 45 results reused**, **401 seconds
  wall**. All **45 accuracy records exit 0**, with no unsupported marker.
  The fuzzer retains the same five flagged KBs, zero unsupported inputs and
  zero crashes. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/3d72b4c6_vs_a3f6cddb_full/report.md`;
  data: adjacent `compare.json`; log: `scratch/compare-full.log`.
- One local scale timing flag did **not** repeat on the runner's automatic
  paired rerun: `scale l spq16 s1`, normalized inference seconds
  **145.2 → 187.5** initially, **109.7 → 109.3** on rerun. The initial process
  wall samples were **182.08 → 227.51 seconds** at pool loads **24 → 33**;
  rerun samples **134.29 → 134.04 seconds** at loads **19 → 20**.
  The required additional **paired dev-server retime passed**, with identical
  accuracy: **158.57 → 157.30 process wall seconds**, both exit 0 at load 1,
  and identical **1,501.6 MB** peak RSS. Inference seconds are **142.2 → 140.9**.
  Command: `BENCH_TIMING_FULL=1 compare.sh master <worktree> --full --only
  "scale l spq16 s1" --retime`; two fresh timing jobs, **435 seconds wall**
  including preparation/queue time. No regression or false flag remains in
  that retime. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/3d72b4c6_vs_8e9f5e0e_full-scale_l_spq16_s1-retime-20261030T233108/report.md`;
  data: adjacent `compare.json`; log: `scratch/scale-paired-retime.log`.
  This report names checkpoint **8e9f5e0e**, with the implementation's identical
  runtime tree **7bdde4b095f9**, and reuses the stored accuracy for those trees.
  Local suite totals include noisy -28% to +13% timing differences; none is
  claimed as a speedup or a confirmed regression. Scale peak RSS is unchanged
  at **1,498 MB**. No memory threshold is flagged.
- Fresh paired `compare.sh anchor <worktree> --canary --retime`: **PASS**,
  six cases, **all 12 fresh dev-server timing jobs exit 0 at load 1**,
  **302 seconds wall**. The runner executed 17 jobs including local accuracy
  work. All 12 accuracy records exit 0 without an unsupported marker. Four
  cases differ from the historical anchor; the embedded comparison with this
  task's master has **no answer movement**, reusing all 12 records. All nine
  anchor deficits are also present on master and are nonblocking under the
  prescribed runner. No regression or false timing flag remains. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_a3f6cddb_canary-retime-20261030T232155/report.md`;
  data: adjacent `compare.json`; log: `scratch/compare-canary.log`.
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **PASS, all
  six gates**, **297 seconds wall**, recorded verification key
  **1784183f9c97**. Strict MeTTa: **162 files**, zero failures. Python:
  **1,030 tests / 70 files / 630 units**, the same **24 expected failures and
  one skip**, **4,534 query metric rows and zero aborts**. Import scaling:
  **1.078** late/early median ratio, chunks **2.580, 2.589, 2.610, 2.964
  seconds**. Judgment scaling passed with three query rows and zero aborts;
  ConceptNet returned exactly two results. Log: `scratch/verify-final.log`.

Fresh paired **process wall seconds** against the historical anchor (these
are historical baseline gaps, not the extraction's cost):

| Case | Anchor | struct4b |
|---|---:|---:|
| live b50, five shifts, seed 1 | 6.94 | 10.56 |
| conflict pln-reliable l spq4 s1 | 9.91 | 68.60 |
| scale m spq4 r10 s1 | 22.64 | 36.53 |
| conflict pln-stated l spq4 s1 | 10.14 | 27.09 |
| ONA conditioning s1 | 5.59 | 10.80 |
| ONA identitymatching s8 | 6.80 | 14.62 |

No scheduling, budget or anytime policy changed, so curves are outside scope.
No push, merge or GitHub write is made. Local code changes are confined to
struct4b; prescribed benchmark outputs and the runner-authorized verification
cache are the only shared writes.

## Limits

This is a storage-ownership separation: **four KB writer files become one**,
with **+402 core tokens**, **ten additional file edges**, **four fewer external
callee references**, and a **one-file larger SCC**. Copy layouts, evidence and
provenance policies, numerical approximations, index behavior and query budgets
are unchanged. It enables later copy-lifecycle simplification; it does not
claim that the physical stores or inference routes can already be deleted.
All required acceptance gates are complete and passing, including the extra
paired dev-server retime. No answer moved against the actual base, no known
extraction-specific regression remains, and every process started for this
task has finished. The branch is ready for coordinator review; no push or
merge was performed.
