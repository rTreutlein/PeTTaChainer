# Structure step 3: proof semantics at construction

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct3`.
Branch: `struct3`; base: `a9cd7e1bcc81c807ee9a60fd1a3a276c47d22a64`.
Implementation: **26d3a380**, `Record proof semantics with immutable proof identities`.
This report checkpoint precedes final verification; completed gate results will be recorded in a report-only follow-up.

## Diagnosis and design as built

Numerical readers repeatedly recognized public `by`, inversion, completion and node explanations. The same representation also selected application identity, population-versus-instance updates, observation admission, completion givens, specificity and the order of Jeffrey updates. Moving those tests without recording their result would leave numerical behavior dependent on explanations.

The proof owner is `runtime/proofs.metta` with its native storage/normalization boundary in `prolog/proof_semantics.pl`. The former `runtime/evidence.metta` is renamed, with its old definition removed. Bootstrap loads the owner at the same point. No public API signature changes.

`record-proof!` publishes an immutable record under the existing proof id. It captures the step-2 source-catalog application role, permanent owner code, normalized application/prior-update/node relation, full signed given-evidence set, existing dependency id, zero-likelihood certificate, uncertainty-source ids, representative status and observed-source status. The existing `&proof` explanation/evidence/packed-owner word and `&proof_fact` result remain, with one publication owner. Owner zero still means no permanent owner; permanent rule id zero is encoded as one. Provenance resolution through the shared rule-set DAG stays lazy, rather than allocating transitive withdrawal sets at every construction.

The normalized relation gives an application its rule and premise proofs; an inversion/completion/report its update kind, prior source, read prior and observation; a message its source and likelihood; a predicted-compound update its prediction and conditionals; and a joint its source and parts. Stored references read this indexed record. Transient inline values normalize at the same owner boundary, without allocating another proof id or a second inline cache. Unknown user proof atoms normalize as opaque values. Newly introduced semantic tags written as user proof terms cannot impersonate internal application/update metadata. Head classification checks actual nonvariable heads and does not instantiate variable-headed proofs. The signed evidence walker now also handles such open heads without passing an unbound argument to a deterministic leaf classifier.

Application templates are recorded once during rule installation, retaining conclusion/premise variable sharing. Their records supply the existing rule-name, inversion, refined-rule/reference-class and combination-learning reads. The latter retain the conclusion index's exact match order and use its type/scope/value/premise columns; they do not read its explanation column. Catalog removal owns template removal, including temporary query lifetimes. This preserves the actual matching policy while removing proof-layout selection of numerical meaning.

The reference collector marks the records' semantic/source proof and evidence handles and signed given sets, and deletes the metadata with its proof. It accounts for the metadata's allocated and retained words in the existing metered collection schedule. Application templates are registered reference holders, including the existing removal barrier. Dependency collection marks metadata dependency ids too. The old given/uncertainty/representative memo predicates and their cleanup are deleted; their results are construction metadata. The old `sk-store-proof!` helper is removed, and its graph caller and direct tests use the owner operation. No compatibility alias or test-only helper remains.

Public explanations, proof-pattern queries, computed evidence identities and materialization provenance keep their shapes and policies. Given-fact certainty is still checked in the live KB. Existing proof identity/selector operations and the construction-boundary inline evidence walk remain: this step does not delete inference routes or replace syntactic proof identity with a different equivalence relation.

## Structural measurements

The supplied `scratch/reference_graph.py`, `reference_terms.pl` and `core_count.py` are unchanged. The new committed `scratch/proof_shape_audit.py` scans semantic MeTTa patterns in cases, lets, matches and equation arguments, excluding output constructors and the new owner; it also carries an explicit ledger of native route/source decoders. It is a static source measurement, not runtime evidence.

Reproduce from this worktree, using the prescribed capped environment:

```sh
.venv/bin/python scratch/reference_graph.py --revision a9cd7e1b > scratch/graph-before.json
.venv/bin/python scratch/reference_graph.py > scratch/graph-final.json
.venv/bin/python scratch/proof_shape_audit.py a9cd7e1b > scratch/proof-shapes-base-final.json
.venv/bin/python scratch/proof_shape_audit.py > scratch/proof-shapes-final.json
.venv/bin/python scratch/core_count.py . > scratch/tokens-final.txt
```

| Metric | Base a9cd7e1b | struct3 |
|---|---:|---:|
| MeTTa/Prolog files | 52 | 53 |
| Defined names | 1,726 | 1,738 |
| Directed file edges | 339 | 352 |
| External callee references | 1,385 | 1,412 |
| Reciprocal file pairs | 15 | 17 |
| Largest file SCC | 36 | 37 |
| Runtime/native to compiler file edges | 11 | 11 |
| Runtime/native to compiler callee references | 16 | 16 |
| Route constructor patterns outside the proof owner | 39 | 0 |
| Native route/source decoders in the explicit ledger | 8 | 0 |
| Runtime `&proof_fact` writer files | 1 | 1 |

The brief's conservative 31-pattern baseline is from an earlier scan. The retained broader pattern scan finds **39** on the actual base: evidence 14, eval_values 16, eval_versions 5, skeleton 2, sampling 1 and knowledge storage 1. This includes the two combination-learning readers outside the four originally highlighted MeTTa files. The native ledger separately covers Jeffrey ordering, completion givens, dormancy completion/application tests and three observation-source classifiers. Scalar head-based classifiers are removed as well, but are not added to the pattern count. The actual base already has one `&proof_fact` writer, so this report claims its ownership move to the native proof owner, not a nonexistent second writer's removal.

The owner has the sole route normalizer and the inline construction/ingestion evidence walker. Consumers use semantic records; renaming an explanation no longer selects the tested prior/update and dominance routes. File edges and SCC size increase. The gain is the removed semantic decoding and unified lifetime, not a global dependency-cycle reduction.

Token counts use `o200k_base` and the supplied counter:

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core MeTTa/Prolog and top-level Python | 325,167 | 326,245 | +1,078 |
| Third party | 17,685 | 17,685 | 0 |
| Total | 342,852 | 343,930 | +1,078 |

## Tests and values

- The complete strict MeTTa suite passed **162 files, zero failures** after the owner rewiring and again after observation-source recording. Logs: `scratch/metta-accepted.log`, `scratch/metta-owner-final.log`. These include `test_proof_state_history.metta` and `test_prior_factored_merge.metta`. Final verification below will cover the committed tree, including the last open-head construction guard.
- Five new Python boundary tests passed on the implementation tree: `scratch/proof-metadata-accepted.log`. They compare inline/reference update relations; replace a stored explanation while checking unchanged prior/update and givens; compare inline/reference joint dominance and conditional-statement dominance; check catalog role, owner/result/dependency capture; verify opaque semantic-tag user proofs and unbound-head preservation; remove an executable rule row while retaining its application template; and check metadata/template cleanup. Several of these checks are combined within one test method.
- Existing direct given-evidence tests now call `record-proof!` and check the owner record rather than a removed memo predicate. Their expected signed evidence and numerical values are unchanged.
- Exploratory quick comparison: **PASS, accuracy changed in zero cases**, 106 seconds wall; report `/nexus/Dev/OpenCog/bench/results/compare/a9cd7e1b_vs_a9cd7e1b-d342d92b9_quick/report.md`, log `scratch/compare-quick.log`. Its runtime snapshot predates the final source-property consolidation, so it is iteration evidence only. The full/canary runs below judge the committed implementation.
- No expected answer, strength, confidence, proof value or scheduler score was edited. `EXPECTED_FAILURES` has no diff. There are no moved numerical values to derive.

During iteration, strict checking caught erased index-id/list boundaries, and the first full MeTTa run exposed unreduced `Atom` arguments at the new native boundary. Restoring typed proof inputs and binding the result tuple before publication restored all 162 files. A later boundary test caught an open-head classifier mutation/error; guarded head dispatch and the evidence-walk guard fix it without changing expected answers. The first exploratory `verify.sh` ran while source edits were still in progress and is **not acceptance evidence**: lint saw the unstaged old filename, and two fresh Python workers read files during replacement. The runner correctly declined to cache that changing checkout. No failing oracle or threshold was weakened.

## Acceptance gates

Every PeTTa/test/benchmark process uses `/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, DISPLAY unset and stdin from `/dev/null`. MeTTa suites use `scripts/test_metta.sh` and the worktree's pinned executable. Comparisons set `PETTACHAINER_REPO` to this worktree. The remote timing host received an independent `.venv` only under the remote struct3 path; its editable import and script interpreters point there. No shared environment or other worktree was edited.

At this checkpoint, `compare.sh master <worktree> --full` and `compare.sh anchor <worktree> --canary --retime` are running against implementation **26d3a380**. Focused rule-retirement, double-negation and given-evidence tests are also running. Their completed results and the final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh` result will be appended in a report-only commit after this checkpoint. Any flagged case will receive the required paired dev-server retime.

No scheduling, allowance or anytime policy changed, so curves are outside the brief. No pushes, merges or GitHub writes were made. Master/main-checkout/other-worktree code is untouched; prescribed runner outputs and verification-cache writes are the authorized shared artifacts.

## Limits

This is structural separation, with **+1,078 core tokens**, **13 additional file edges** and a **one-file larger SCC**. It does not establish replacement coverage for deleting inversion, completion, observed messages, Jeffrey updates or joint routes. Inline temporary proofs still cross the centralized normalizer; stored proofs read recorded metadata. Logical source provenance remains shared and lazily resolved rather than eagerly flattened. Existing numerical approximations and proof identity/selector policies remain. Final acceptance gates are pending at this report checkpoint.
