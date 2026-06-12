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
      (Premises (Q $x))
      (Conclusions (Smokes $x)))
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
2. **Assumed query-context premises.** Implication queries stored their assumed premises as KB facts; premises containing `#` needed a dedicated `wildcard_premise_index` so the (ground) hash fact could answer grounded subgoals. Stored facts containing real variables answer grounded subgoals through ordinary unification, so variable premises subsume this without any index. One semantic difference remains: a variable premise binds to the instance it matches (enumeration), whereas `#` stayed anonymous (one total over anything). The anonymous-total reading is expressed with an explicit `FoldAll` aggregation instead, as in the generic `ii_total` total-implication rule (see `tests/test_total_implication_aggregate.metta` and `benchmarks/demo_total_implication_pattern_mining.metta`).
3. **Inverse-implication estimation premises.** `toQuery` replaced rule variables with `#` to form base-rate estimation premises such as `(Smokes #)`: find all proofs of the pattern and merge them into a node-probability estimate. The wildcard mechanism never delivered those semantics (instances answered the premise one at a time, and revision-merge would sum evidence counts instead of counting each instance once). Inversion now uses explicit `FoldAll` base-rate premises instead — see "Base Rates Via FoldAll" below.

## Base Rates Via FoldAll

`inverse-implication` (compile.metta) now generates, for an implication A→B, the rule

```text
witness proof of B
base rate of A   = (CPU FoldAllCompiled ($kb A-pattern extract-tv (BaseRateEvidence 0 0) BaseRateAcc base-rate result-tv) $atv)
base rate of B   = same shape over the B pattern
(CPU CTVInversionFormula ($atv $btv $itv) $iitv)
(CPU CTVFormula ($btv_wit $iitv) $mp-tv)
```

Key semantics:

- **One piece of evidence per instance.** `BaseRateAcc` folds the merged per-instance TVs: strength is the confidence-weighted mean of instance strengths, and the evidence count is the sum of instance confidences, finished by `BaseRateTv` into `(STV s n/(n+1))`. Multiple proof paths of one instance are merged first (the merged-proof machinery above), so a derived duplicate never inflates the base rate — unlike revision-merge, which would sum the underlying evidence counts.
- **Base rates are evidence-transparent.** A `base-rate` aggregate commits with empty evidence (`run-aggregate-heap`). A base rate is a population statistic, so sharing an instance with another premise (e.g. the B witness also appearing in B's base rate) must not trip the evidence-overlap guard. This replaces the old rule that hash-typed results carried no evidence.
- **No self-reference.** `aggregate-fold-source-ids` excludes instances whose proof depends on the aggregate itself, otherwise each inverted conclusion would feed back into its own base rate and amplify forever.
- **`CTVInversionFormula` takes both base rates.** The CTV-semantics change (commit 5f7466c) had dropped the B base-rate premise and computed P(B) analytically from P(A) and the rule CTV; it now consumes an actual proof-derived base rate of B again. The rule's conclusion TV is the modus-ponens output, no longer unified with the A estimate (a variable collision that had made the rule unfirable).

`tests/test_implication_inversion.metta` covers the end-to-end behavior.

Removed along with the construct: `contains-hash?`, the hash-to-variable rewriting in `direct-goal-results-view`, the `wildcard_premise_index`/`wildcard_premise_context` stores and their lookup path, and the hash special cases in `open-rule-goal?`, `materializable-proof-output?`, and `leaf-evidence-for-result`.
