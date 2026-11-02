# Abstraction review at d1ee51a7

The core contains repeated collection mechanics, but repeated indexed reads are not interchangeable with an ordinary runtime map API. This round extracts reusable list operations and inert Python syntax handling, removes eight specialized list walkers and two duplicate Python algorithms, and replaces eleven expanded existence probes. A generic alpha-lookup experiment changed answers and was removed. This is a measured small reduction, not evidence that the remaining design is minimal.

The audit covers all production MeTTa and native Prolog under `pettachainer/metta/`, the top-level Python package, and formula dependencies. The six files reserved for E3 and merge 1b were read, not changed. The public API and all expected answer values remain unchanged.

## Inventory and counting method

Counts use o200k_base, including comments and the new libraries. Baseline is this branch's original HEAD, d1ee51a7. MeTTa expressions were parsed with source spans; the table counts syntactically identified occurrences and the tokens of their complete expressions. Categories overlap and their token columns must not be summed or interpreted as removable duplication. A large expression includes its semantic body. Scalar-index matches are a lower bound: their first row cell must name a hash, prefix, digest or slot; short variable names such as `$h` are not recognized by that count. Recursive walkers require separate empty-list and cons clauses and a recursive call, so case-based and mutual recursion are not included.

| Pattern | Occurrences | Tokens in matching expressions |
| --- | ---: | ---: |
| Space matches | 371 | 18,424 |
| Matches with a visibly scalar first row cell | 239 | 13,191 |
| `index-hash` key construction | 138 | 1,118 |
| Alpha-filtered alternatives, `if (=alpha ...) ... (empty)` | 155 | 5,506 |
| Expanded exact or alpha existence probes | 44 | 1,391 |
| Existing `chainer-first-or` calls | 35 | 1,067 |
| `case` over one collapsed result | 55 | 9,024 |
| Two-arm cases returning their first item or a fallback | 28 | 3,031 |
| Recursive list walkers | 43 | 3,918 |
| `fold-flat` / `map-flat` | 95 / 64 | 2,449 / 1,446 |
| `fold-semidet` / `map-semidet` | 236 / 28 | 6,865 / 500 |
| Cases dispatching on STV/CTV/PTV/FTV constructor patterns | 42 | 2,893 |
| Common proof constructors and patterns | 71 | 546 |

The proof inventory includes `by`, `negated`, `merge/revision`, `fact-source`, `proof-ref`, `conjunction` and `ctx`, both construction and destructuring. It does not claim that all these terms have one construction policy. PTV/FTV are chiefly normalized at ingestion; wrapping every runtime STV operation in another four-way dispatcher would duplicate that boundary.

Native Prolog was inventoried by non-comment source lines containing each idiom. These are line-token footprints, not complete clause sizes:

| Native idiom | Lines | Tokens on those lines |
| --- | ---: | ---: |
| `forall` loops | 70 | 1,647 |
| `findall` collection | 75 | 1,737 |
| Copy before matching | 18 | 294 |
| Lazy-predicate existence-error handling | 16 | 450 |
| Variant comparisons | 28 | 710 |
| Dynamic predicate construction | 14 | 219 |
| STV/CTV/PTV/FTV tags | 35 | 861 |

`ingestion.pl` already supplies `source_atom` to `sorts.pl`. `context_overlay.pl` already centralizes scoped stores, their read facades and mutation policy. The similarly shaped native hash, evidence and dependency operations in `runtime_helpers.pl` have different contracts: ground set membership, ordered evidence identities and graph-backed dependency reachability. A generic set wrapper would not remove those differences. Source copying also differs from returning independent answer copies or preserving a selected clause reference. No new native library is justified by identical writable implementations in this round.

## Candidates ranked by expected net saving and confidence

The estimates below are engineering estimates, not measured reductions. Confidence means confidence in a behavior-preserving extraction on this pinned runtime. The score is estimated net tokens times confidence; it orders proposals after accounting for the observed compiler failures and the reserved-file boundary.

| Rank | Operation | Estimated net saving | Confidence | Score | Files and decision |
| --- | --- | ---: | ---: | ---: | --- |
| 1 | Polymorphic reverse and short-circuit list existence | 300 | .95 | 285 | `compiler/source_lowering`, `runtime/evidence`, `runtime/statistics/base_rates`, `runtime/backward/skeleton`; implemented |
| 2 | Inert MeTTa parsing and rendering | 200 | .99 | 198 | `pln_validator.py`, `query_diagnostics.py`, `pettachainer.py`; implemented |
| 3 | Remaining typed reverse and append walkers | 180 | .80 | 144 | Four remaining walkers in `source_lowering` are used by reserved `rules`/`query_lowering`; defer coordinated deletion and migration |
| 4 | Exact row existence, preserving the row as data | 100 | .95 | 95 | `source_lowering`, `skeleton_journal`, `base_rates`, `skeleton`; generic support extracted, eleven additional probes migrated |
| 5 | Optional first values with a pure fallback | 60 | .90 | 54 | `evidence`, `hypothesis_mining`, `upward`, reserved `evaluation`; existing `chainer-first-or` is adequate; no new abstraction |
| 6 | Generic indexed alpha lookup as a runtime function | 1,000 | 0 after experiment | 0 | 155 alternatives across skeleton/evaluation/forgetting/etc.; rejected in its tested form |
| 7 | General cache-or-compute and TV/proof visitors | Unestablished | Low | Unranked | Most of the 9,024 optional-case tokens are actual computation or state publication; no single replacement contract established |

Rank 3 is deferred because its callers belong to another agent. Its score is not a claim of an available reduction in this branch. The three removed reverse walkers have 215 tokens of declarations and definitions; five removed existential list walkers have 368. The four retained typed list walkers have 310. Six pre-existing generic operations have 394 tokens of declarations and definitions: moving them does not count as a net saving.

## Library contracts and extraction

`pettachainer/metta/lib/collections.metta` is loaded after the standard libraries and before compiler specialization. It contains eight operations:

- `fold-semidet f initial items`: left fold, preserving item order; any failed step fails the entire fold.
- `map-semidet f items`: one result per element in order; a failed element fails the whole map. It is not a filtering map.
- `append-flat left right`: proper-list concatenation preserving element types and identity.
- `reverse-onto items tail`: reverse the proper list onto the supplied tail, preserving element identity and the element type.
- `any-flat? predicate items`: deterministic boolean test in list order; the empty list is false and the first true result stops traversal. This must not become a strict boolean fold that evaluates the remaining predicates.
- `stored-list-member? item items`: nonbinding identity membership (`==`), preserving the distinction between two different variables.
- `foreach-flat f items`: run effects in order and return the empty result list after successful traversal, preserving the callback effect declaration.
- `space-row-present? space row`: whether one unifying row exists, with no output bindings escaping the collapsed match. Callers passing an open row expression quote it explicitly so the compiler does not interpret a variable first cell as a function head.

`tests/metta/test_collections.metta` imports only standard PeTTa libraries and this module, without the chainer. It checks short-circuit effects, single-result determinism, open-variable identity, row existence, reverse, append, map/fold and ordered effects. The generic module uses no KB, skeleton, proof or TV symbols and is useful in an unrelated MeTTa project. `chainer-first-or` remains in `runtime/evidence.metta`, outside the generic library.

The removed walkers are `prepend-reversed-proofs`, `prepend-reversed-tvs`, `prepend-reversed-atoms`, `contains-head-list?`, `proof-term-contains-negated-list?`, `base-rate-cache-user-present?`, `sk-any-member?` and `prefilter-prunes-walk`. Their callers use `reverse-onto` or `any-flat?`. The prefilter test now calls the shared operation and the existing premise predicate; no obsolete helper remains for tests. The context-variable read computes its source variables once before testing membership.

`pettachainer/metta_syntax.py` owns inert `parse_source`, `parse_term` and `render` operations. Source parsing preserves quoted tokens, supports comments, and returns no parse for malformed source. Parsing one term requires exactly one complete form and raises on malformed or multiple forms. Rendering preserves string tokens and writes native float exponents in PeTTa syntax. Validation, diagnostic projection and proof expansion now use these operations. This eliminates the diagnostic parser and renderer and the runtime's separate renderer. Tests importing diagnostic internals were migrated to the actual library; no aliases remain. `tests/test_metta_syntax.py` tests this module directly. It has no chainer dependencies and also qualifies for separate generic-library accounting.

## Boundaries that should remain

Compiler collection assembly now uses the shared proper-list operations; source-computation and trigger walks retain their specialized semantics. The low-level `make-space-pair`/`row3`/`row4`, nominal proof conversion and accumulator guards may look like aliases, but they establish a representation or compiler boundary. An Atom parameter can suppress evaluation, a raw tuple can be interpreted as a call, and constructor patterns can accidentally classify an unrelated tuple as a TV. These are not equivalent to ordinary object-language helper calls.

Proof construction retains scoped evidence identities, reference DAG ownership and negation polarity. Population priors, stored reports, conditional branches and partial-fold confidence have different mathematics and cannot share a cosmetic TV mapper. Fold accumulation order also affects floating point results; replacing it with a hash iteration is not a cleanup.

A mutable store's vocabulary should express its query (membership, value read, scoped replacement, or exact-clause removal), while leaving its selective scalar first argument visible. A universal tagged key/value space would lose the existing first-argument indexes. Scoped context reads must keep the existing `&ctx_*` facade and mutation ownership. Collector, retirement and clause-reference operations must not be hidden behind a generic remove-by-unification API.

## Rejected indexed-lookup experiment

A MeTTa `space-alpha-present?` function factored the repeated collapsed match plus nonbinding alpha check. The direct variable-sharing probe passed, yet callers changed behavior. Unquoted open row arguments first failed strict determinism loading `sk-note-rule!`. Explicit quotes fixed that loading failure, but the suite then failed `test_answers_by_index`, `test_dormant_rules`, `test_forgetting` and `test_forward_chainer`. One visible failure lost a registered open-member answer; another lost `(Or (A j) (B j))` from forgetting's answer set. The failed full run returned nonzero.

All alpha-wrapper definitions, migrations and their temporary tests were reverted. The next strict MeTTa run passed all 162 files. This establishes that the tested function boundary is unsafe, not the exact compiler cause. The generated helper used a generic `match/4` where the original literal-store expression was specialized; variable/evaluation behavior across that boundary needs a stronger contract before trying again. A future compile-time expansion may be preferable, but it has not been implemented or validated here. It would be inaccurate to count the rejected wrapper's apparent savings.

## Remaining reserved-file targets

| Reserved file | Inventory and follow-up |
| --- | --- |
| `compiler/rules.metta` | 10 expanded existence probes, 4 alpha alternatives, 6 recursive list walkers. Collection assembly uses `append-flat` and `reverse-onto`; keep source-compute and trigger traversal semantics. |
| `compiler/query_lowering.metta` | 2 hash constructions and 2 TV-dispatch cases. Collection assembly uses `append-flat` and `reverse-onto`; check temporary assumption/rule ownership. |
| `runtime/scheduling.metta` | 1 recursive list walker. Review against the short-circuit/fold contract; no scheduler policy or budgets changed in this round. |
| `runtime/evaluator/evaluation.metta` | 75 alpha alternatives, 7 expanded existence probes, 17 optional-first cases, 11 TV cases, 4 recursive walkers, 69 hash constructions. Exact-existence probes can be considered individually; leave cache misses lazy, preserve conditioned-read exclusions, and do not reintroduce the rejected alpha wrapper. |
| `prolog/runtime_helpers.pl` | Largest native concentration of collection, indexed identity and proof/TV plumbing. Any native extraction must preserve ordered evidence, dependency DAGs, exact clause references, cleanup ownership and native hot-path performance. |
| `prolog/event_node.pl` | Numerical TV/node operations are not an alternative implementation of generic list collection; defer changes to E3. |

## Measured size

| Group | Before | After | Delta |
| --- | ---: | ---: | ---: |
| Core excluding the separately eligible generic libraries | 326,924 | 325,401 | -1,523 |
| New generic libraries | 0 | 987 | +987 |
| Existing third-party formulas/lowering | 17,685 | 17,685 | 0 |
| **Total** | **344,609** | **344,073** | **-536** |

The library split follows the brief's counting update: no chainer symbols, own tests, and use outside this project. The total reduction is 536 tokens (0.156%); the 1,523-token core reduction must not be presented as the total saving. Reports and tests are outside this production count. Per-file counts and final gates are in `git show 9102bd1c:ABSTRACTION_REPORT.md`. This result does not establish a lower bound on achievable core size; it records the extractions that survived this round's boundaries and validation.
