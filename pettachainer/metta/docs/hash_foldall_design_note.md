# Merged Proofs and `FoldAll`

## Context

PeTTaChainer historically had two related mechanisms:

- `#` acted as an anonymous wildcard in query/premise patterns, for example `(Smokes #)`.
- `FoldAll` aggregates over all matches of a pattern, for example counting all `(Smokes $x)` matches.

The `#` construct has since been removed entirely (see "Removal Of `#`" below). The remaining design question was how aggregation should behave when multiple proof paths derive the same grounded atom.

## Intended Semantics

For a grounded atom, multiple proof paths should be merged before any parent rule or aggregate consumes that atom.

Example:

```metta
(: smokesAnna (Smokes Anna) (STV 1.0 0.9))
(: qAnna (Q Anna) (STV 1.0 0.9))

(: qToSmokes
   (Implication
      (Q $x)
      (Smokes $x))
   (CTV (STV 0.4 0.9) (STV 0.0 1.0)))
```

`(Smokes Anna)` has two proof paths:

```text
smokesAnna
qToSmokes(qAnna)
```

Before another operation consumes `(Smokes Anna)`, these should be represented as one merged proof/output:

```text
merge/revision(smokesAnna, qToSmokes(qAnna))
```

So a fold such as:

```metta
(FoldAll (Smokes $x)
   1
   0
   (|-> ($acc $elem) (+ $acc $elem))
   -> $count)
```

should count `(Smokes Anna)` once, not once per proof path.

## Why Merging Matters For Base Rates

The common intended use of a base-rate question such as "how often does `Smokes` hold" is a fold over the population of grounded instances.

Example population:

```text
Person Anna
Person Bob
Person Cara

Smokes Anna       ; direct
Q Anna            ; derives Smokes Anna
Smokes Bob        ; direct
```

The desired smoking base-rate numerator is:

```text
Smokes Anna
Smokes Bob
```

so the count is `2`, not `3`.

The duplicate proof path for `Smokes Anna` should not create an extra population instance.

Therefore, a base-rate question is an ordinary fold/query over merged grounded outputs. It does not require a special wildcard construct or a special grouped fold operator if the normal fold consumes the merged proof view.

## Implemented Design

The backward chainer merges alpha-equivalent subgoal outputs before any consumer sees them:

```text
raw proof ids
  -> goal-merged-proof-ids
  -> ordinary rule application / ordinary FoldAll
```

This fixed the smokes-style issue:

```text
Bad shape, now avoided:
merge/revision(
  smokingCancerRule(friendSmokingRule(...)),
  smokingCancerRule(smokesEdward)
)

Produced shape:
smokingCancerRule(
  merge/revision(smokesEdward, friendSmokingRule(...))
)
```

In this model:

1. `goal-merged-proof-ids` returns first-class representative proof ids. A group with a single proof path is represented by its raw proof id; a multi-path group gets a synthetic representative node whose output is the merged atom and whose children are the raw proof ids.
2. Those representatives work anywhere normal proof ids work, including as aggregate children. Synthetic representatives are stored with the dedicated proof kind `(merged $output)`; materialization resolves the `merge/revision` proof term carried by the merged output, and liveness, evidence, and cycle checks recurse through the raw children.
3. `FoldAllCompiled` and `GroupedFoldAllCompiled` iterate `goal-merged-proof-ids`, not raw `goal-live-proof-ids`.
4. There is no aggregate-local grouping or per-key dedup; merged ids are unique per grounded output key by construction.

This keeps the semantics simple:

```text
FoldAll does not know about proof-path deduplication.
It just folds over the normal merged result stream.
```

Historical note: an earlier patch instead grouped raw child proof ids by output key inside aggregate execution. That workaround existed because synthetic representatives were stored with the `(aggregate ...)` proof kind, whose materialization expects a `CPU FoldAllCompiled` form to build the proof label, so materializing a representative produced a stuck `aggregate-proof-label` term. Introducing the `(merged $output)` kind with its own materialization rule made representatives fully first-class and let the workaround be removed.

## Removal Of `#`

The `#` wildcard has been removed from the engine. Investigation showed its roles were already covered by existing mechanisms:

1. **Direct matching.** A goal containing `#` was converted hash-to-variable before matching the KB, so `(Pred $v #)` behaved exactly like `(Pred $v $w)`. Plain variables replace it directly.
2. **Assumed query-context premises.** Implication queries stored their assumed premises as KB facts; premises containing `#` needed a dedicated `wildcard_premise_index` so the (ground) hash fact could answer grounded subgoals. Stored facts containing real variables answer grounded subgoals through ordinary unification, so variable premises subsume this without any index. One semantic difference remains: a variable premise binds to the instance it matches (enumeration), whereas `#` stayed anonymous (one total over anything). The anonymous-total reading is expressed with an explicit `FoldAll` aggregation instead, as in the generic `ii_total` total-implication rule (see `tests/test_total_implication_aggregate.metta`).
3. **Inverse-implication estimation premises.** `toQuery` replaced rule variables with `#` to form base-rate estimation premises such as `(Smokes #)`: find all proofs of the pattern and merge them into a node-probability estimate. The wildcard mechanism never delivered those semantics (instances answered the premise one at a time, and revision-merge would sum evidence counts instead of counting each instance once). Inversion now uses explicit `FoldAll` base-rate premises instead — see "Base Rates Via FoldAll" below.

## Base Rates Via FoldAll

`inverse-implication` (compile.metta) now generates, for an implication A→B, the rule

```text
witness proof of B
base rate of A   = (CPU FoldAllCompiled ($kb A-pattern extract-tv (BaseRateEvidence 0 0) BaseRateAcc base-rate result-tv) $atv)
base rate of B   = same shape over the B pattern
(CPU CTVInversionFormula ($atv $btv $itv) $iitv)
(CPU CTVModusPonensFormula ($btv_wit $iitv) $mp-tv)
```

Key semantics:

- **One piece of evidence per instance.** `BaseRateAcc` folds the merged per-instance TVs: strength is the confidence-weighted mean of instance strengths, and the evidence count is the sum of instance confidences, finished by `BaseRateTv` into `(STV s n/(n+K))` with the shared `evidence-confidence-k` (800, the same K used for implication evidence counts). Multiple proof paths of one instance are merged first (the merged-proof machinery above), so a derived duplicate never inflates the base rate — unlike revision-merge, which would sum the underlying evidence counts.
- **Base rates are evidence-transparent.** A `base-rate` aggregate commits with empty evidence (`run-aggregate-heap`). A base rate is a population statistic, so sharing an instance with another premise (e.g. the B witness also appearing in B's base rate) must not trip the evidence-overlap guard. This replaces the old rule that hash-typed results carried no evidence.
- **No self-reference.** `aggregate-fold-source-ids` excludes instances whose proof depends on the aggregate itself, otherwise each inverted conclusion would feed back into its own base rate and amplify forever.
- **`CTVInversionFormula` takes both base rates.** The CTV-semantics change (commit 5f7466c) had dropped the B base-rate premise and computed P(B) analytically from P(A) and the rule CTV; it now consumes an actual proof-derived base rate of B again. The rule's conclusion TV is the modus-ponens output, no longer unified with the A estimate (a variable collision that had made the rule unfirable).

`tests/test_implication_inversion.metta` covers the end-to-end behavior.

## Base-Rate Cache

Computing a base rate folds over every derivable instance of the pattern,
which is the dominant cost of inversion. Base rates are therefore cached per
knowledge base in `&base_rate_cache`:

- `(set-base-rate $kbid $pattern $tv)` records a user-provided estimate;
  `(clear-base-rate $kbid $pattern)` removes any entry. User entries take
  precedence and survive knowledge-base changes.
- When a base-rate fold goal expands and a *user* entry exists, the aggregate
  commits the cached TV directly and the fold never runs — user values are
  authoritative (the proof shows a bare `cpu` token instead of a
  `foldall-proof`).
- A *computed* entry instead becomes the aggregate's initial snapshot: the
  cached value answers immediately, and the fold machinery still spawns at
  reduced priority (`base-rate-refine-score`). If leftover budget lets the
  refold find a better estimate, the ordinary anytime snapshot replacement
  swaps it in and re-propagates downstream conclusions.
- Forward chaining maintains additive sufficient statistics for the base-rate
  folds emitted by the compiler. Each canonical output actually processed by
  the requested forward budget updates its contribution in constant work and
  stores a `forward-approx` cache entry. `compileadd` itself still does no
  chaining; callers choose which canonical facts to pass to `forward-chain`
  and how far to run it after an addition.
- Refinement of a complete `computed` snapshot is monotone: a refold may only replace the current base-rate
  snapshot when its confidence (instance count) is at least as high, so a
  shallow refold can never degrade a deeper cached estimate, and `no-evidence`
  never replaces a real value. A `forward-approx` snapshot is deliberately not
  protected by that guard: it represents partial scheduled work, so a complete
  fold is authoritative even when its confidence is lower.
- After each query the chainer harvests the computed base rates into the
  cache, so repeated inversions over an unchanged knowledge base get instant
  estimates plus cheap incremental refinement.
- Adding a fact or rule to a knowledge base invalidates that kb's computed
  entries (user entries persist).

`tests/test_base_rate_cache.metta` covers user overrides, cache reuse, and
invalidation. `tests/test_forward_incremental_base_rates.metta` covers
incremental estimates, full-fold refinement, inheritance scaling, revised
forward outputs, and forward/backward provenance deduplication.

### Incremental member-inheritance fold

The compiler-generated empirical `Inheritance` producer has one additionally
supported incremental shape: `FoldAllCompiled` over `MemberInheritanceSample`,
extracting `WeightedTv` from the two `Member` TVs, starting at
`BaseRateEvidence 0 0`, accumulating with `WeightedBaseRateAcc`, and finishing
with `(member-inheritance kb)`. Other `FoldAllCompiled` expressions are not
registered by this path.

Registration creates indexes for the concrete subject and concept classes.
If either complete class term contains a variable, whether at top level or
nested inside a compound class, the fold is not registered and no identity,
interest, observation, or cache row is created; such an open query cannot
provide the selective class key required by this path.
Forward processing of either affected canonical `Member` output looks up the
other side for the same object, replaces that object's prior joined
contribution, and adjusts additive weight/mass totals. Removal recomputes from
any surviving canonical proof or subtracts the observation when one side has
no support. Multiple proofs therefore contribute through the single canonical
merged output rather than as duplicate samples. Work is proportional to the
interests for the changed class/object, not the number of historical objects.

The resulting cache row is `forward-approx`: it can answer immediately, but a
normal backward fold remains live and authoritative, with its ordinary proof,
evidence deduplication, and cycle checks. Only facts actually processed by a
requested forward-chain budget update the cache; `compileadd` never runs the
fold. Time windows and general incremental `FoldAllCompiled` support remain
outside this mechanism. Focused coverage is in
`tests/test_forward_incremental_member_inheritance.metta`.

Removed along with the construct: `contains-hash?`, the hash-to-variable rewriting in `direct-goal-results-view`, the `wildcard_premise_index`/`wildcard_premise_context` stores and their lookup path, and the hash special cases in `open-rule-goal?`, `materializable-proof-output?`, and `leaf-evidence-for-result`.

## Evidence Semantics

Evidence sets exist to keep revision honest: proofs merge as independent only
when they share no support. Two refinements make that the invariant
"evidence = unmarked knowledge-base statements actually used":

1. **Hypotheses are not evidence.** The assumed context premises that
   implication queries inject (`(ctx proof N)` tokens) define the conditional
   being computed; every branch under the hypothesis shares them by
   construction. They are excluded from stored evidence and from proof-term
   evidence walks, so two derivation branches that share only the hypothesis
   revision-merge. This is what makes the fact-level and implication-level
   representations of the same deduction agree (see
   `examples/deductionrevision_*.metta`).
2. **Unmarked implications are evidence.** Applying a compiled implication
   adds `(rule-ev $kbid $name)` to the conclusion's evidence, so derivations
   sharing an uncertain implication are treated as dependent (dominance, not
   revision). Rules that are part of the logic itself — deduction schemas,
   transitivity axioms — are declared with `(mark-logic-rule $name)` and add
   no evidence; engine-generated rules (total implication, query compounds,
   context assumptions, inverse scaffolding) are implicitly logic. Inverse
   and bidirectional applications resolve to the underlying implication name.
3. **Materialized derivations keep their original evidence.** Forward chaining
   and `query-materialize` retain the source facts and rule applications of a
   cached result. If backward chaining later rediscovers that same path, it is
   dependent evidence and cannot be revised with itself. `&kb` stores one
   canonical merged fact per grounded type. A private forward frontier retains
   only its active non-dominated contributors and their evidence: disjoint
   additions merge directly into the canonical fact, while an overlapping
   candidate scans that one frontier so it can replace a subsumed branch
   without losing the other independent branches. Superseded candidates are
   discarded rather than kept as proof history.

`rule-ev` entries participate in revision independence and dominance but are
filtered out of the frontier conjunction guard: the positive and negative
branches of a total-implication query legitimately invoke the same rule, and
chained applications of one rule remain allowed.

`tests/test_evidence_semantics.metta` pins both behaviors.

## Lifting-merge: pooling proofs that share a premise

When several proofs of one grounded conclusion share a premise but are otherwise
independent, dominance discards all but one and loses the confidence the others
would add. Lifting-merge instead pools them at the *implication* level: factor
the shared premise out, revise the independent residual implications, and
re-apply the premise once. Two implications `A->B` applied to the same `a`, or a
direct `A->B` versus a deduction chain `A->X->B`, or `A,X->B` / `A,Y->B` sharing
only `A`, all pool to the higher revised confidence instead of dominating.

The formula that produced each proof's TV is already in the store as its CPU
formula children, so a proof is **re-evaluated structurally** with the shared
leaves overridden: `factor-reeval` folds the premise proofs (identified by child
position, never by TV value) and re-applies the rule CTV. When several facts are
shared, they are factored out as a *conjunction*: probing all shared leaves at
strength 1 (conjunction = 1) and at 0 (conjunction = 0) recovers each proof's
residual implication CTV, because the conclusion is linear in the shared
conjunction's strength. The residuals are revised and re-applied via
`CTVModusPonensFormula` to the real conjunction of the shared leaves' TVs. Single-leaf is
the one-element case. No new per-node storage is needed.

`merge-proof-id-output` pools a group only when `group-factorable?` holds:

- the proofs share at least one fact leaf,
- every proof is standard implication-shaped (premises -> And-fold ->
  CTVModusPonensFormula); other shapes fall back to revision/dominance,
- the residual evidence sets (each proof's evidence minus the shared facts) are
  pairwise disjoint. This rejects proofs that also share an uncertain rule or
  whose evidence subsumes another's -- they are not independent given the shared
  premise, so pooling would double count, and they dominate instead, and
- each residual round-trips: re-applying it to the real shared conjunction
  reproduces the proof's stored TV. This holds when the shared facts enter
  through one conjunction (the 2-point probe is exact there) and fails when they
  enter through different conjunctions or depths, where it would be inexact;
  those groups fall back to dominance.

Because every conjunction has disjoint fact-leaves (the conjunction guard), each
fact occurs at most once per proof, so the structural re-evaluation is exact for
all engine proofs. `tests/test_lifting_merge.metta` covers the single- and
multi-leaf pooled cases, the shared-rule case that must not pool, and the
different-conjunction case the round-trip check rejects.
