# The prior for an estimate

This is the common definition for specificity, Bayes and inversion, population
and instance priors, and an STV rule's inferred negative branch (#89). It uses
the confidence-dependent weight from #69. A prior is an independently justified
centre and its weight; it changes a read strength without adding observations
or increasing the estimate's confidence. Original estimates remain stored.

For an estimate `(s,c)`, centre `(g,c_g)`, evidence scale `k`, and configured
heterogeneity `κ` (default 0.2):

```text
n = c k/(1-c); n_g = c_g k/(1-c_g)
a = max(0, 1/(1/(n_g+1) + 1/(κ+1)) - 1)
read(s,c | g,c_g) = ((n s + a g)/(n+a), c)
```

Certainty is infinite evidence: `c=1` leaves the estimate unchanged, and
`c_g=1` gives `a=κ`. A zero-confidence estimate is unknown `(0.5,0)`;
`n+a=0` also returns unknown. Positive weight requires `n_g κ>1`.
`κ=0` disables this read regularization. Do not replace the weight by a floor.
The separate, opt-in `set-base-rate-smoothing` preprocessing uses k-weighted
pseudo-observations in raw computed rates; it is not this κ prior read.

## Choosing a centre

| Use | Centre |
|---|---|
| Specificity | Only live classes strictly containing the specific class, excluding that estimate's own support. Same-class independent estimates revise. Choose the nearest classes before removing shared support and recomputing; mix incomparable containing classes as distributions, never revise them. Siblings of the specific class cannot supply its centre. |
| Bayes/inversion | Independent `P(B)` at its confidence before reconciliation; otherwise only other likelihood branches with demonstrably disjoint observation support. Exclude the likelihood being shrunk from both the mean and evidence count. A derived negative branch cannot centre its producer. |
| Population and finite instance priors | Structural neutral `(0.5,1)`, so `a=κ`. This includes a stored target belief (#42) and a `WithPrior` belief when used as a prior. An unupdated stored belief retains its stored TV. |
| Inferred STV negative likelihood | Derive raw `P(B|not A)` and its confidence from admissible marginals and the positive rule. Read that estimate once, using an independent negative-class centre if available, otherwise structural neutral `(0.5,1)`. Inputs already used in the derivation cannot also supply its centre. Missing/drained rates or impossible `not A` remain `(0.5,0)` (#83). |

Without an admissible empirical Bayes centre, use structural neutral `(0.5,1)`.
Its confidence expresses a fixed symmetry assumption, not certainty about the
target, and contributes no evidence. A weak admissible empirical centre retains
its actual confidence, including when its weight is zero.

An incomparable-class mixture gives equal weight to each distinct nearest
containing class. For its centre and variance:

```text
g = mean(g_i)
V_g = mean(V_i + (g_i-g)^2), V_i = g_i(1-g_i)/(n_i+1)
```

Convert this variance back to confidence. Identical centres do not become more
confident; disagreement adds variance. Keep zero confidence for an unknown
mixture. This does not alter #49's sibling-conclusion odds denominator.

## Support and repeated reads

Centre support is separate from refresh dependencies. Count eligible observations
once. Remove shared support and recompute; if that cannot be done, omit that
candidate. Different branch or proof names do not establish independence.
Branch support includes physical outcome sources, including certain reports;
certainty of a training report does not license counting it twice. Scoped
statement identity, independent of proof name and polarity, identifies a physical
source. Incremental reference counts mark repeated or unscoped sources as
unverified, causing conservative neutral fallback rather than inflated counts.

Population priors exclude the target observation and observations already used
by the update, including MAIN observations borrowed by a private context. A
fold also excludes values derived through itself. Exclusions subtract indexed
contributions from the shared incremental tally for that read; they do not
rewrite its cache or scan the population for each sensor. If those exclusions
drain the population, a supported inversion uses an unknown `(0.5,0)` bridge
so an independent instance prior can replace it. That bridge adds no evidence
and is never published as a standalone population answer.

`likelihood-read` records original/read CTVs and origin/centre information as
private row data. `CTVBayesFormula` and `CTVInversionFormula` consume resolved
reads without smoothing them again. Completion transforms originals and reads
together. Public proofs remain logical: no exclusion hashes, evidence handles,
raw marginals or support diagnostics are embedded in them. The `(prior TV)`
marker carries the read instance prior through subsequent factored updates;
a stored prior is read once when first used and is never replaced by a newly
shrunk posterior.

A pair of certain likelihoods needs no empirical centre or centre-fold
dependency: the read is exactly its original CTV at every κ. This avoids a
feedback cycle through an unused consequent population. Inversion and completion
read admissible raw marginals once through a private `rate-read` row record
before preparing likelihoods or priors. Its fold plan is compiled once; the
read uses the ordinary exclusion-aware fold evaluator. Ordinary
forward reads retain their antecedent population; an inversion removes its
consumed observation. Positive-only declarations remain in force.

Support bookkeeping uses per-source reference counts and fixed-size per-fold
counters: distinct sources, positive/negative presence, duplicate or unverified
sources, and cross-branch overlap. Each source delta changes those counters in
constant time. No population-sized evidence set is interned. For an empirical
centre, indexed hits for the excluded sources are subtracted from its distinct
count; a positive remainder and no duplicate/unverified sources are necessary.
Subtract their numeric contributions through the reverse index and require a
positive remaining member count: removing one source can remove an entire
multi-source member. A drained tally cannot supply an empirical centre, even
if a synthetic concept prior remains. Cost is proportional to the sources
explicitly excluded, not the marginal population size.
Numeric tallies keep an exact live contribution count, so a drained population
becomes exactly zero rather than a floating-point subtraction residual. Branch pooling requires positive support in
both branches and zero duplicate/unverified and overlap counts.

Specificity chooses the nearest containing classes before excluding samples.
A learned general is re-evaluated without the specific's physical training
sources using the existing `sk-tally-without` path. Omit that selected general
only when no admissible re-evaluation is possible; never promote an ancestor
because the nearest overlaps. An authored contribution with unknown training
provenance cannot certify independent branch pooling.

## Endpoints and uncertainty

Finite-confidence endpoints are estimates. A neutral read at `κ>0` moves them
inside `(0,1)`; use the same variance and odds calculation at and near 0/1.
Exact absorption requires a certain fact or the existing certified certain-zero
likelihood, preserving contradiction handling. When smoothing is disabled or
an empirical centre has zero weight, `ideal-clip` is the continuous numerical
map used throughout odds/variance arithmetic, including at endpoints. It is
not statistical regularization. Continuity is in strength at fixed finite
confidence; certainty remains a separate logical case.

The inferred-branch quarter-minimum confidence and log-odds delta method remain
heuristics. This definition removes self-evidence and endpoint discontinuities;
it does not claim calibrated uncertainty or solve general overlap (#77).

Physical source lists contain collision-checked scalar `sk-key` identities.
Member, per-source counter and forward-observation records share these identities;
no growing population evidence set or serialized term is allocated. The stored
hash provides the reverse-read key, with full term variant equality checking
collisions during interning.

Support handles use a separate identity namespace from proof/evidence entries,
so interning an optimization key cannot perturb evidence IDs or deterministic
traversal. MAIN identities persist without reuse; identities first created in an
assumption world are owned by that query and removed at context cleanup. A MAIN
lookup promotes a borrowed identity before a MAIN holder can retain it. Cleanup
visits only query-owned IDs, never the global identity history.
