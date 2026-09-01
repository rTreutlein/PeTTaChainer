# PLK pattern-mining discussion summary

Status: design summary with a separate unary prototype experiment
Updated: 2026-09-01

## Objective

The goal is to discover reusable implication patterns from observations in a
PLK knowledge base. Given concrete observations such as:

```metta
(Inheritance (A value) state)
(Inheritance (B value) state)
```

the intended generalized candidate is:

```metta
(Implication (A $v) (B $v))
```

It is not:

```metta
(Inheritance (A $v) (B $v))
```

Variables belong in executable implication rules, not in the concrete
inheritance relationship being sampled.

The existing base-rate and induction machinery already provides much of what
is needed to evaluate a known candidate. Aligned observations of `A(value)`
and `B(value)` can be folded to estimate `P(B | A)` and construct an
implication truth value. The hard problem is therefore candidate discovery:
deciding which predicates, argument correspondences, connectives, and formula
structures should be evaluated.

This leads to a firm separation:

- Candidate discovery is heuristic, approximate, explicitly budgeted, and may
  miss patterns.
- Candidate evaluation uses the PLK evidence and existing PLN formulas and is
  authoritative.
- Candidate support or a neural model score is not a PLN truth value.
- A speculative candidate must never silently become an executable rule.

## Extension boundary

Pattern mining should remain an opt-in extension rather than an implicit part
of `compileadd`, `query`, or the forward chainer. The clean dependency is:

```text
pattern-mining extension -> public PeTTaChainer API
```

The chainer does not import the miner. The extension may consume explicitly
selected observations or the canonical delta returned by a forward-chain run,
maintain its own indexes, propose candidates, and ask PeTTaChainer to evaluate
them. Mining and inference have separate budgets.

This avoids imposing mining cost on normal reasoning and keeps heuristic state
out of the logical KB.

## Exact incremental unary discovery

For unary predicates, an occurrence can be indexed by:

```text
(KB, state, shared value) -> predicates observed in that transaction
```

When a new predicate arrives, it is paired with predicates already in the same
bucket. A bucket containing `w` distinct predicates creates:

```text
w * (w - 1)
```

directed implication updates. Across non-uniform sparse data, the exact cost is:

```text
sum over buckets b of w_b * (w_b - 1)
```

Here, width means the number of distinct predicates in one local
`(KB, state, value)` transaction. It does not mean the size of the global
predicate vocabulary.

Sparsity therefore helps substantially when most states contain only a small
subset of all predicates. It does not eliminate the worst case for unusually
wide buckets, and varying sparse subsets can still create many one-off
candidate pairs that consume memory.

## Approximate discovery for wide buckets

Exact all-pairs discovery cannot be subquadratic if every pair must be emitted.
To scale further, candidate recall must be allowed to become approximate.

A practical hybrid is:

1. Enumerate all pairs below a small exact-width threshold.
2. Above that threshold, select only `k` partners for each new occurrence.
3. Select partners deterministically from a hash, learned retrieval model, or a
   mixture of frequent and exploratory samples.
4. Maintain a bounded heavy-hitter or admission sketch rather than storing
   every one-off candidate.
5. Run the exact PLK fold before promotion.

This changes large-bucket discovery from approximately `O(w^2)` to `O(w*k)`.
If a pair has sampling probability `q` per supporting observation and occurs
`s` times, its approximate discovery probability is:

```text
1 - (1 - q)^s
```

Strong recurring patterns are therefore more likely to be found than rare
patterns. This is an explicit recall tradeoff, not a change to the final truth
value semantics.

## Multi-parameter predicates

Multi-parameter predicates should be treated as relational joins with argument
correspondences, not as unrestricted syntactic anti-unification.

The central index becomes:

```text
(state, argument value) -> (fact identity, predicate, argument position)
```

For example, observations might support:

```metta
(Implication
  (Bought $person $item $shop)
  (Liked $person $item))
```

The candidate identity includes:

- Both predicate heads and their arities.
- The equivalence classes connecting argument positions.
- Any constants or typed restrictions retained by the pattern.
- The direction of the implication.

Direction is no longer automatically symmetric. All variables in the
consequent must be bound by the antecedent unless an explicit existential
semantics is introduced. Candidate generation should first mine elementary
slot correspondences, then combine only frequent compatible mappings. Initial
budgets should limit shared variables and formula depth.

## Connective formula mining

The desired language is not limited to conjunction. The general target is:

```metta
(Implication FormulaA FormulaB)
```

Either side may conceptually be a compound formula. Examples include:

```metta
(Implication (And A B) C)
(Implication (Or A B) C)
(Implication (And A (Not B)) C)
(Implication A (Or B C))
```

Candidates should be represented as canonical formula syntax trees plus
variable-slot equivalence classes. Each registered connective needs metadata
describing at least:

- Arity.
- Associativity, commutativity, and idempotence where applicable.
- Its truth-value evaluator.
- Variable-binding safety rules.
- Any valid pruning or monotonicity assumptions.

Associative and commutative formulas should be flattened and sorted, and
idempotent duplicates removed, so syntactic rearrangements do not become
separate candidates.

Connectives also need different discovery statistics:

- `And` can identify interactions whose conditional strength differs from
  either input alone.
- `Or` can improve coverage and must avoid double-counting overlap.
- `Not` requires explicit negative evidence. Absence in a sparse or open-world
  state is not negation.
- Numeric, comparative, and other specialized connectives may require value
  distributions rather than Boolean occurrence sets.

For example, a useful interaction score for a conjunctive extension is:

```text
gain((And A B) -> C)
  = exact-score((And A B) -> C)
    - max(exact-score(A -> C), exact-score(B -> C))
```

This allows `(And A B) -> C` to be retained even when neither `A -> C` nor
`B -> C` is individually strong. Other connectives require their own gain or
coverage criteria rather than being treated as conjunction under another name.

## Neural candidate proposal

A neural network can improve scalability, but it should propose candidates
rather than replace the symbolic evaluator. It cannot make unrestricted
formula enumeration tractable; it can learn which small part of the search
space is worth evaluating.

The proposed pipeline is:

```text
new PLK observations
        |
        v
symbolic occurrence and argument indexes
        |
        v
learned candidate retrieval
        |
        v
neural-guided formula construction
        |
        v
top-K canonical Implication candidates
        |
        v
exact PLK fold and PLN truth-value calculation
        |
        v
accepted rule or rejected candidate
```

The model needs to predict more than predicate names:

- Which predicates or formula fragments to connect.
- Which argument positions share variables.
- Which connective to use.
- How to construct the formula tree on either side.
- Whether an extension is likely to improve upon its subformulas.

A dense transformer attending to every fact in a wide state would reproduce a
quadratic bottleneck. A more scalable starting point is an online low-rank
embedding or factorization model over predicate argument positions, combined
with approximate nearest-neighbor retrieval. A bounded grammar-guided neural
beam can then be added for higher-order formula construction.

A possible training signal is masked observation prediction:

```text
state facts minus one observation -> predict the held-out observation
```

To encourage genuinely connective patterns rather than only atomic
correlations, training and ranking should also use the exact marginal gain over
subformulas. Exact evaluation results can feed back into the proposal model as
online ranking examples.

The neural approach introduces false negatives: a real pattern may not enter
the top-K proposal queue. It need not introduce logically false rules as long
as canonicalization, binding checks, and exact PLK validation remain mandatory.

## Levels of pattern mining and scalability

In the following table:

- `N` is the number of fact observations.
- `w_b` is the number of facts or predicates active in one state-and-binding
  bucket.
- `r_x` is the number of relational occurrences sharing one indexed argument
  value.
- `P` is the number of predicate types.
- `a` is predicate arity.
- `k` is the number of retrieved partners per observation.
- `L` is the number of leaves in a formula.
- `B` is beam width.
- `M` is the number of candidates sent for exact validation.

The costs below describe candidate discovery. Exact validation additionally
costs one evidence fold for each of the `M` selected candidates; incremental
maintenance can then update only candidates affected by new observations.

| Level | Patterns discovered | Exhaustive symbolic cost | Approximate or neural cost | Scalability | Recommended approach |
|---|---|---:|---:|---|---|
| 0. Base rates | `(A $v)` | `O(N)` | Unnecessary | Excellent | Exact incremental fold |
| 1. Unary atomic rules | `(Implication (A $v) (B $v))` | `O(sum_b w_b^2)` | About `O(N*k)` | Good with sampling | Exact for small buckets; sampled or sketched partner discovery for large ones |
| 2. Relational atomic rules | `(P $x $y) -> (Q $x $y)` and other slot mappings | Roughly `O(sum_x r_x^2)` after argument-value indexing; arity adds slot combinations | About `O(N*a*k)` plus retrieval | Good to moderate | Symbolic argument indexes plus learned predicate-position embeddings |
| 3. One connective layer | `(And A B) -> C`, `(Or A B) -> C`, and other registered connectives | Up to `O(P^3)` atomic combinations or `O(sum_b w_b^3)` local combinations | Roughly `O(N*k + B*M)`, depending on the proposer | Moderate | Expand promising atomic rules and score connective-specific marginal gain |
| 4. Small bounded formulas | `(And A (Or B C)) -> D`, compound consequents, and shared relational variables | Exponential in `L`; roughly `Catalan(L-1) * connective_choices^(L-1) * P^L`, before variable mappings | Approximately `O(B*L*k)` proposal work plus exact validation of `M` candidates | Practical only with bounded guided search | Neural grammar-guided beam, canonicalization, and strict depth and candidate budgets |
| 5. Larger relational formula trees | Multiple connectives, several shared variables, and multi-argument predicates | Exponential formula trees multiplied by rapidly growing variable and slot partitions | Still bounded by `B`, but recall falls as the search space grows | Difficult | Hierarchical mining of reusable fragments, typed variables, neural retrieval, and periodic exact refinement |
| 6. Unrestricted pattern mining | Arbitrary formulas on either side using every registered connective | Unbounded search space | A network can guess but cannot cover it systematically | Not scalable | Require an explicit bounded grammar and resource budget |

The practical division is:

- Levels 0-1 can be exact or nearly exact.
- Level 2 benefits from hybrid symbolic and learned retrieval.
- Level 3 requires bounded connective-specific expansion.
- Levels 4-5 require incomplete, guided beam search.
- Level 6 is not an operational target without restricting the language.

Sparse states strongly improve levels 1-2 because cost depends on local bucket
width rather than the global vocabulary. Sparsity alone does not control the
number of possible formula trees at levels 3-5.

## Recommended ownership

| Component | Responsibility | Authoritative? |
|---|---|---|
| Symbolic occurrence and positional indexes | Find legal shared bindings | Yes |
| Sampling, sketches, embeddings, and approximate retrieval | Select likely partners and fragments | No |
| Neural or heuristic formula generator | Propose connective trees and variable mappings | No |
| Canonicalizer and binding/type checker | Remove duplicate and invalid formulas | Yes |
| PeTTaChainer fold and PLN formulas | Calculate support, strength, confidence, and proofs | Yes |
| Explicit promotion policy | Decide whether a validated candidate becomes an executable rule | Yes |

The extension owns indexes, learned state, sketches, proposal queues, and
budgets. PeTTaChainer remains responsible for connective semantics, exact
evidence evaluation, truth values, proofs, and executing any explicitly
promoted rules.

## Suggested staged implementation

1. Keep the unary extension as an isolated performance baseline.
2. Replace unbounded wide-bucket pairing with an exact-small/sampled-large
   policy and a bounded candidate store.
3. Add relational argument-position indexes and canonical slot mappings.
4. Add a registered, bounded formula grammar covering all intended
   connectives rather than hard-coding conjunction.
5. Begin with online factorization or low-rank embeddings for top-K retrieval.
6. Add a nonlinear grammar-guided proposer only when measurements show that
   higher-order interaction discovery justifies it.
7. Use exact PLK folds for final scoring at every stage, and keep promotion
   explicit.

## Existing unary prototype and benchmark

The separate branch `experiment/pattern-mining-extension` at commit
`4d604f6b` contains an opt-in unary prototype based on master `a7c81319`. It
does not modify the core chainer or incur disabled-mode cost. It records
transaction co-occurrence support, not PLN truth values, and deliberately does
not promote candidates automatically.

The benchmark was measured on 2026-08-25 using the repository-pinned PeTTa
runtime and Python 3.10.16 on an AMD Ryzen 7 5700X3D under WSL2. Each
configuration ran three times in a fresh process. Times exclude library loading
and benchmark-input setup.

| Transactions | Width | Observations | Directed updates | Stored support rows | Candidates | Median seconds | Peak RSS MiB |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 | 1 | 100 | 0 | 0 | 0 | 0.009835 | 139.4 |
| 100 | 2 | 200 | 200 | 100 | 2 | 0.020905 | 138.8 |
| 100 | 4 | 400 | 1,200 | 600 | 12 | 0.070218 | 137.8 |
| 100 | 8 | 800 | 5,600 | 2,800 | 56 | 0.246281 | 155.4 |
| 500 | 1 | 500 | 0 | 0 | 0 | 0.044618 | 155.0 |
| 500 | 2 | 1,000 | 1,000 | 500 | 2 | 0.114733 | 158.3 |
| 500 | 4 | 2,000 | 6,000 | 3,000 | 12 | 0.502114 | 233.6 |
| 500 | 8 | 4,000 | 28,000 | 14,000 | 56 | 1.820213 | 363.1 |

The benchmark confirms the expected output-sensitive quadratic behavior. It is
a baseline for unary exact discovery, not evidence that multi-parameter or
connective mining has been implemented or benchmarked.

## Open design decisions

- Exact-width threshold and sampled partner count for wide buckets.
- Deterministic sampling scheme and heavy-hitter admission policy.
- Evidence reservoir or replay policy used for exact candidate validation.
- Maximum argument mappings, shared variables, formula leaves, and formula
  depth.
- The initial set of registered connectives and their individual discovery
  criteria.
- Whether compound consequents are enabled initially or merely represented by
  the grammar for later activation.
- Candidate diversity policy so a beam is not filled with equivalent variants.
- Neural training cadence, negative sampling, drift handling, and persistence.
- Promotion thresholds and whether promoted rules require held-out validation.

These are resource and search-policy decisions. They should not change the
meaning of implication, connective evaluation, or PLN truth values.
