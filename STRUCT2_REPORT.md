# Structure step 2: source catalog

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct2`.
Branch: `struct2`; base: `48bdacf5b53c2baf837485515d112583034eb4cd`.
The implementation and this report are committed before final verification. Final gate results and commit IDs will be recorded in a report-only follow-up.

## Diagnosis and design as built

The interrupted work contained a usable first catalog and four focused tests. I retained its compiler annotations, indexing owner, graph conversion and lifetime integration, then completed the compiler ingress, explicit fact roles, authored instance-prior admission and open-query indexes. No executable/numerical route is deleted in this step.

`compiler/rules.metta` annotates emitted applications with source roles and ordered population cohorts at the same point that it constructs their numerical plans. An authored rule descriptor is `(source-rule name scope antecedent consequent truth parameters instance-prior reverse-binding-plans)`. It retains the Boolean sides, original truth and WithPrior declaration, explicit ForAll parameters, and the reversible computation/binding plan. Forward application metadata records the branch source, Boolean antecedent, resolved truth expression, output polarity and admission eligibility. Reverse applications record their source/prior role; structural applications remain distinct. Source descriptors are interned modulo alpha-renaming, with reference-counted installation ownership.

`compiler/source_ingress.pl` owns the pure encoding/normalization boundary. Internal runtime additions are `(source-plan descriptor role cohorts semantic-inputs addition)`. `mm2stmt` constructs them, preserving variable sharing between the annotation and executable addition. `prepare-source-addition` consumes annotated products directly and normalizes the public raw `add-to-kb` form at this one boundary. Only raw inputs need proof/CTV-dataflow/cohort decoding, because their original source annotation is unavailable. Completion recipe extraction and raw recipe recovery also moved here; the old runtime recovery walker and datatype are deleted. Runtime installation receives explicit source information and a prepared application. `compileadd` still returns the same externalized products, and public API signatures remain unchanged.

`prolog/source_catalog.pl` alone owns catalog mutation, indexing, generation and removal. It holds source descriptors, application semantic views, statement-output/input indexes, instance-prior admission metadata and fact descriptors. Output prefix/open indexes support both ground and open queries, including a rule with a fixed output argument queried through an open pattern. Prefix keys include the KB. Application IDs connect metadata to existing withdrawal and temporary lifetimes; they are not executable rows. Source lookup and prior selection use an explicit installation sequence, rather than hash-probe order or numeric application ID (temporary and permanent IDs use different ranges). Exact fact deduplication is indexed by a variant hash and clause reference, separately from the broader statement-matching index; removal owns both entries. Separate owner/hash indexes retain full terms to check collisions and variable sharing.

Fact publishers explicitly identify `observation`, `prediction`, `materialized` and `summary` roles. This requires passing a role through the internal `kb-index-fact!` boundary in knowledge ingestion, forward storage, materialization and forgetting; their numerical operations do not change. The graph admits only observation descriptors and context assumptions, rejects summaries as before, and never treats a derived posterior as another observation. Raw forgotten-fact normalization stays at the compiler ingress. Graph discovery no longer inspects summary proofs or derived-copy stores.

`event_graph.pl` reads catalog neighbours, source facts, admission templates and generation. It no longer reads `ccls_index`, `rules`, skeleton rows or CPU instructions, or destructures producer/inversion proofs to recover meaning. It still constructs explanations from admitted source IDs, as before. WithPrior rejection comes from the authored descriptor even when inverse applications are never installed. The raw API gets equivalent explicit metadata at ingress. Cavity prior cohort selection in `eval_folds.metta` uses `source-catalog-priors`; the independent legacy root/population-prior path is outside this extraction and remains unchanged.

Catalog changes advance a KB generation. The existing input-change journal also notifies it for external input/rate changes. Row allocation alone does not. The graph owns its reset operation; force-reset calls it instead of mutating four graph caches directly. Catalog ownership leaves with withdrawn applications and temporary query data; reset of graph caches does not discard authored sources.

The rejected alternative was moving the old graph decoders into another runtime helper. That would still make source meaning depend on executable installation. Here only the compiler/raw ingress sees executable layout; catalog queries do not. Explicit fact roles likewise avoid moving proof-based role classification into the new owner.

## Structural measurement

The step-1 `scratch/reference_graph.py` and Prolog term reader are retained. I extended historical measurement to read native files from `git show` into a temporary directory under this worktree's scratch directory; it no longer assumes native code is unchanged. Terms are parsed, never consulted. The graph algorithm, name resolution and scope are unchanged. The rebuilt base result is byte-identical to the pre-interruption `scratch/graph-before.json`.

Reproduce through the prescribed capped environment:

```sh
.venv/bin/python scratch/reference_graph.py --revision 48bdacf5 > scratch/graph-base-resume.json
.venv/bin/python scratch/reference_graph.py > scratch/graph-after.json
.venv/bin/python scratch/core_count.py . > scratch/tokens-after.txt
```

| Metric | Base 48bdacf5 | struct2 |
|---|---:|---:|
| MeTTa/Prolog files | 50 | 52 |
| Defined names | 1,698 | 1,726 |
| Directed file edges | 326 | 339 |
| External callee references | 1,367 | 1,385 |
| Reciprocal file pairs | 13 | 15 |
| Largest file SCC | 33 | 36 |
| Runtime/native to compiler edges | 9 | 11 |
| Runtime/native to compiler callee references | 14 | 16 |
| Event graph outgoing file edges | 11 | 11 |
| Graph premise/proof/CTV instruction decoders | 3 | 0 |
| Graph executable-relation reads for model meaning | 2 relations | 0 |
| Graph dependency on skeleton input epoch | 1 | 0 |
| Graph dependency on global row allocation | 0 | 0 |

The brief's row-allocation baseline comes from an earlier revision: the actual base already used `&ctx_sk_input_epoch`. This change replaces that last graph-side generation dependency with the catalog generation. It does not claim to remove a direct row-allocation read that was absent at this base.

Total edges and SCC size grow: new ownership interfaces add dependencies, and compiler encoding/catalog modules join the existing cycle. The measured gain is the removal of semantic decoding, not a global cycle reduction. The catalog has no row/proof/CPU decoder. It enables future inversion/completion deletion without using their executable layout for graph discovery; it does not establish coverage sufficient to delete those routes now.

## Tokens and deletion audit

`o200k_base`, supplied `scratch/core_count.py`:

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core (MeTTa/Prolog and top-level Python) | 321,567 | 325,167 | +3,600 |
| Third party | 17,685 | 17,685 | 0 |
| Total | 339,252 | 342,852 | +3,600 |

Step 2 permits structural additions; this exceeds its rough +0.8–2.5K sizing estimate. Source/compiler metadata, raw normalization, explicit fact roles, indexes and lifecycle handling account for the added code. No numerical fallback or duplicate compatibility implementation is retained.

Deleted names have zero hits across `pettachainer/`, `third_party/`, `tests/` and `docs/`: `graph_template`, `graph_premise`, `graph_boolean`, `graph_sources`, `RawCompletion`, `raw-completion`, `raw-completion-step`. `contextual-cpu?` remains because skeleton and runtime instruction evaluation still use it.

## Tests and values

- Latest complete MeTTa run before explicit fact-role publication: **162 passed, 0 failed**, strict determinism, including instance priors and compute inversion. `scratch/metta-ingress-final.log`. Final verification below must cover the complete final tree.
- Seven source-catalog tests check model equality after CPU reordering and removal of rules/conclusion indexes/skeleton rows; unchanged catalog generation after those operations; prior-cohort preservation; equivalent raw/annotated normalization; WithPrior rejection without rows and without ever installing inverse applications; and withdrawal/temporary-owner cleanup.
- Prior-cohort checks compare ordered results and variable sharing against the existing independent prior decoder for STV, uncertain CTV, compound antecedents, ForAll, WithPrior, open queries and fixed output arguments. The fixed-argument/open-query check exposed an incomplete longest-prefix-only index; the final prefix/open indexes fix it.
- Focused run: **42 tests passed** in `scratch/focused-final-roles.log` (six catalog, four completion recipe, 23 event node, nine atomic posterior). After the ordering/scaling fixes, **all seven catalog tests passed** again in `scratch/catalog-order-fixed.log`; final verification covers every focused test on the final tree.
- **No expected numerical answer, confidence, proof value or scheduler score was changed.** Two compiler-inspection tests now unwrap the internal source plan before inspecting its executable product. No EXPECTED_FAILURES changes.
- The intermediate full comparison before the last ingress/index/role changes passed with **accuracy changed in 0 cases**: `/nexus/Dev/OpenCog/bench/results/compare/48bdacf5_vs_48bdacf5-d8712caf9_full/report.md`. The final comparison below supersedes this as acceptance evidence.

## Final gates

Every project/test/benchmark process uses `/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, DISPLAY unset and stdin from `/dev/null`. MeTTa uses this worktree's pinned executable through `scripts/test_metta.sh`. Comparisons use prescribed `compare.sh` with `PETTACHAINER_REPO` set to this worktree. A separate copy of the timing host's environment was prepared only under the remote struct2 path so paired dev-server jobs can use the same interpreter path.

- Final `compare.sh master <worktree> --full`: running; log `scratch/compare-full-accepted.log`.
- Final `compare.sh anchor <worktree> --canary --retime`: running; log `scratch/compare-canary-accepted.log`. Fresh paired dev-server timing covers all canary cases, including any flags. The historical anchor differs numerically from this task's base; the embedded master comparison must have no answer movement.
- First complete verification (`scratch/verify-final.log`): all semantic suites passed (162 MeTTa files, 1,021 Python tests, 24 existing expected failures, one skip; zero query aborts), but import scaling failed at **2.220** late/early chunk time. Broad statement-prefix fact deduplication scanned growing buckets of open implication facts. The final owner uses a separate variant-hash identity index with exact clause-reference removal; focused rerun `scratch/import-scaling-fixed.log` passes at **0.990**, chunks **2.330, 2.300, 2.276, 2.308 seconds**. No thresholds or workloads changed.
- A separate overlap probe found that a later fixed-argument output could precede an earlier general output when both sources had the same name. An explicit installation sequence now preserves the former choice across prefix buckets and across temporary/permanent ID ranges; the new test pins the original source's Boolean parent.
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: to run after this corrected report checkpoint is committed; log `scratch/verify-accepted.log`.

No scheduler/budget/anytime policy changed, so curves are outside the brief. No master/main-checkout/other-worktree code edits, pushes, merges or GitHub writes were made. The standard runner's shared benchmark artifacts and authorized verify-cache writes are the only shared outputs.

## Limits

The graph's existing admission/size/cycle restrictions and numerical approximations remain. The raw API cannot recover information absent from a raw application; it preserves the prior admission policy at the single compiler-owned boundary. Independent runtime uses of explanation/instruction shapes outside graph discovery/admission/cavity prior lookup remain for later structural steps. This report is a pre-verification checkpoint until the final gate section is completed.
