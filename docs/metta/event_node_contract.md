# Event node contract

This is the shared reference for `prolog/event_node.pl`, the native compound
readers in `prolog/runtime_helpers.pl`, and `prolog/event_graph.pl`.

## Source roles and identity

A stored count `(s,c)` enters as Beta(n s + 1, n (1-s) + 1), with
n = 800 c/(1-c). Confidence zero is the uniform prior; confidence one is a
point at s. A propagated view keeps its output moments instead: mean s and
variance s(1-s)/(n+1), represented as Beta(n s, n (1-s)). Shapes have a 1e-12
lower bound; at zero confidence the propagated distribution is Bernoulli(s).

In a conditional node, a root's stored counts are parameters. Each instantiated
rule has separate parameters for its two branches.

Event bits and parameters have separate identities. A parameter is named by its
estimate owner, never by its law: members whose empty root counts read one
population prior share that population's rate, `population(pattern)` with the
pattern alpha-renamed, and uses of one refined rule share its two branch rates,
`rule(truth, branch)`. A statement's own counts, a stated application's
branches and a uniform root stay local. Equal laws never merge owners; a
repeated event is still one bit. The shared rate is the population centre the
cavity reader returns (the count law of its tally; the ordinary reader's
`bayes-prior-count` shrink is not applied here), so every member's rate is that
centre. All reads of one graph use one cavity, so an owner has one law; a graph
whose owner reads two laws is not built. A stored report on a rule's
conclusion is an observation, rather than another parameter for that conclusion.
An observation on event K multiplies each world by m when K holds and 1-m
otherwise, with m = (n s + 1)/(n+2), or m = s at confidence one. Reports at
confidence zero are omitted before building any factors.

Raw sources are read through the ordinary indexed leaf interface and its scope
rules. Forward copies, frozen summaries and materialized outputs are excluded. Positive and
negative uses of the same canonical source are one factor, with polarity
already represented by its stored strength. Node outputs never become reports.

The graph reader discovers atomic and compound observations through live
conclusion and premise indexes, starting with the goal and its formula atoms.
An unobserved nested goal compound cannot hide its atoms' observations.
A producer whose antecedent has a ground, non-negated positive-only conjunct
with no source, no producer and no user base rate never applies (#169): a
positive-only statement is only its stored instances. It is no producer of the
key, so a generic rule for another source does not take a grounded channel's
key out of the graph. Every other visible live producer must match the
supported template; one unsupported producer rejects the graph. It supports an acyclic graph with
one explicit CTV source per conclusion, or a family of certain-positive rules.
A family uses the disjunction of its distinct ground antecedents as its parent,
with positive branch 1 and the conclusion's empty-root prior as fallback.
Refined CTV sources read both branches from their current RuleTruth key through
the ordinary reader with the caller's exclusions. These remain stored counts;
the truth's proof and dependencies accompany the answer, and a later sample
refreshes the parameter. With no samples refinement leaves the model unchanged.
Every producer's rule identity accompanies the proof. Without observations,
a family answers only when some root has source counts. Producer selection
groups rule names in O(P log P), preserving installation order within each name.
Before enumeration, roots with identical occurrence paths as
same-polarity literals of the same And/Or are folded into one block bit.
Paths cover the goal, reports and all conditional parents, so a separately read
root cannot fold, nor can roots used together under different connectives or
polarities. The block holds with the product of its parts' literals (all false
for a complemented block), kept as an expression in their owners, so a rate a
block shares with another block or a retained event keeps its powers. Original
source proofs, exclusions, subscriptions and dependencies remain attached to the
unfolded model. The polynomial kernel therefore returns the same strength and
variance bound as full enumeration. This does not assert equality of the full
posterior variance integral, which the kernel bounds.
The graph admits at most twelve parameters after folding (one per folded atom
and a second branch per conditional), checked when the plan is built. That
bound counts the bits that can vary: a certain observation on a bit, or a
certain-endpoint law (a root's revised sources), fixes it, one predicate
shared by the bill and the enumerator. It governs enumeration and the polynomial alike: each bit contributes one of
two factors (theta or 1-theta; a block's product or 1), so there are at most
4,096 distinct monomials however often an owner recurs, and powers stay below
twice the bit count. Overlapping reports with few occurrence signatures stay
exact however many parts they share. Discovery and the unfolded
model are only memory-guarded, at 256 visited statements and atoms. A key enters
the graph once a query with budget needs or reads it, for one evaluation unit if
it has a model then (a query's need admits its roots before evaluation spends
the allowance); later answers of an admitted key refresh as facts are absorbed,
paid like every computation from the reading query's graph tier. Budget zero
computes no new posterior. Other templates retain the
ordinary evaluator. Observed children outside a compound enter the same joint
model. Shared parents are one event bit in the enumeration; given branches are
not imported as independent marginal parameters. Empty root counts read `sk-part-prior`, including configured rates and cavity population counts.
Only a root with neither source counts nor a population prior remains uniform.
Population prior proofs and dependencies accompany the answer without becoming
observations.

The output subscribes to every visited key, including children without a report,
so a late observation can wake its readers. Its dependency set holds raw roots
and observations; internal inferred marginals do not become primitive inputs.
Rule-owner references retain withdrawal identity. Structural discovery and plans, including unsupported results, are cached by
scope, overlay frame and input epoch. An epoch change retires that frame's older
KB snapshots; skeleton row creation does not change source templates. Numerical
results are keyed by the Boolean structure, observations and resolved parameter
moments. Proof metadata stays outside that key, so a refined rule's variables
cannot leave the numerical hash unbound. Caches clear with evaluation
forcing state.
They hold source data rather than output proof DAGs. Population priors are read
after plan lookup. A replacement must satisfy the caller's proof/TV filter and
have no evidence overlap with its exclusion evidence; otherwise the compatible
ordinary value survives. An admitted model with impossible evidence returns no
answer and cannot fall back to a stored source. Compiler forms, including
frequency-valued implication conjuncts, retain their existing readers.

## Compound readers and merging

A formula has integer atom indices in first-occurrence order, with `Not`, `And`
and `Or` over formulas. Repeated atoms share one index. A sibling cavity excludes
the compound and target feedback; an unread or unknown part has a uniform prior.
A sibling that settles the compound for every possible target value leaves the
target undetermined, so no message is returned.

An observed compound sends a Pearl likelihood. A predicted compound instead
uses Jeffrey kinematics: P'(G) = P* P(G|K) + (1-P*) P(G|not K). P* revises the
prediction with the parts' estimate using their counts. An absorbing parts'
probability stays unchanged. Joint readers calculate their goal in the same
worlds. A connective over all the same children in another order is the original
compound and retains its TV.

Observed messages act together on the cavity value, a set population rate, or a
uniform prior. Separable literal messages share only their target. Their other
literals form an independent product W; each target likelihood is affine in W.
The product uses its first two moments to construct a Beta approximation. A
message whose affine likelihood varies by less than 1e-9 relative over W's
whole range treats W as fixed. Messages sharing another atom are enumerated
in one union node, with that atom represented once. Products and world weights
are scaled in log space.

Predictions apply after observations, in the canonical order of their prediction,
conditionals, position and source evidence. A prediction's count is capped by
its new uncertain raw-source count. Updates with no new evidence, or already
counted by an antecedent completion, are omitted. The Jeffrey variance propagates
the prior, both conditionals and the prediction, including products of variances.
The separate cavity-rate reader excludes the node's evidence, excluded keys,
materialized values and forward copies.

## Posterior moments

For independent parameters theta, terms are
`t(coefficient, literals, goal_ids)`. A literal `Id-1` selects theta_Id and
`Id-0` 1-theta_Id; a block literal `w(Literals)-1` is their product and
`w(Literals)-0` its complement. One parameter may occur in several literals.
Z sums all terms; N_g sums terms in which goal g holds. Coefficients are scaled
by their largest absolute value. Zero normalization is inconsistent evidence
and produces no answer.

The parameter posterior is proportional to prior(theta) Z(theta). Its moments
are:

- s = E_prior[N_g]/E_prior[Z];
- V = E_prior[N_g^2/Z]/E_prior[Z] - s^2.

The production kernel computes only closed-form polynomial moments. A monomial
maps each parameter to its powers `c(T,F)` of theta and 1-theta; a literal adds
one power, so negative literals are never expanded and independent parameters
stay factored. Only a block's complement adds a monomial. Equal monomials are
combined and point parameters are folded into their coefficients. Products add
powers. A monomial's expectation is the product over its parameters of
E[theta^T (1-theta)^F]: (a)_T (b)_F/(a+b)_(T+F) for Beta(a,b), from rising
factorials up to twice the powers used; Bernoulli(p) gives p, 1-p, or 0 when
both powers are positive. The strength is E[N]/E[Z] from the same polynomial,
not N or Z at the parameter means, which repeated powers would bias. Rational
arithmetic over the supplied numeric inputs preserves polynomial cancellations
and tiny endpoint variances; only the final square root and returned variance
are floating point.

The graph splits into components that share no bit and no uncertain
parameter (points tie nothing); the goal splits into its top-level conjuncts.
Each component is enumerated and integrated alone, and E[N], E[Z], E[N^2],
E[NZ] and E[Z^2] multiply across components, so independent structure never
expands. Work is paid before it is done, from the invocation's graph tier, an
allowance as large as its evaluation allowance, at 1/256 unit per scalar
operation: a component's worlds times its models and factors before
enumeration; its expanded monomials times the parameters they can carry, for
Z and every N, before expansion; its monomial pairs times monomial length
before pairing. A refused payment refuses the answer like unpaid work and is
not cached; the ordinary read keeps its answer, and a read with more budget
computes it.

Let e=E[Z], s=E[N]/e, D=N-sZ, Q=E[D^2], T=Var(Z), and b=max(s,1-s), with
expectations under the independent prior. The claimed variance is

    min(s(1-s), (Q + b sqrt(T Q))/e^2).

It is **exact when Z is constant** (T=0), including stationary interactions
and long products. Otherwise it is a conservative upper bound, tagged
`conservative`; that tag carries its numeric variance through the existing
confidence conversion. It is not the `bound` sentinel, which forces confidence
zero. Forced and parameter-independent goals retain exact zero variance.

Proof: since 0<=N<=Z, |D/Z|<=b where Z>0. At zero-Z points D=0 and their
contribution is defined as zero. Therefore

    e^2 Var_post(N/Z) = Q - E[(Z-e) D (D/Z)]
                     <= Q + b sqrt(T Q)

by Cauchy-Schwarz. The Bernoulli variance is also an upper bound, so taking
the smaller preserves conservativeness. This includes signed literal
representations of valid event polynomials; it requires the event invariant
0<=N<=Z, not nonnegative individual coefficients. It makes no independence
assumption about the tilted posterior parameters, nor about uses of one
parameter.

Separable messages retain their existing product-moment Beta parameter model
and compile their affine likelihoods into this same polynomial kernel. Their
atom cap remains unchanged; over-cap models retain their analytic strength
and claim the Bernoulli variance bound. Deterministic siblings fold before
that cap. There is no quadrature, numerical refinement, dimension-dependent
integration fallback, or numerical-rule cache.

The bound trades tightness for a simple guarantee. Round 2's 1,713-goal trial
has no overconfident converted confidence; median variance factors are 1.58
on D0 and 2.56 on authored posterior fixtures. Thin endpoint boundary layers
can widen by tens of millions, reducing useful confidence. The full inputs,
reference error labels and distributions are in `git show c3ee6d01:experiments/confvar/` and
`git show c3ee6d01:CONFVAR_REPORT.md`; numerical references alone are not certified exactness.

## Output and unknown dependence

An exact zero variance is a point: internally confidence 1, so later
computations, caches, materialized and forward copies keep it exact. The
public answer boundary (`public-tv` in `runtime/presentation.metta`) reports
a computed point at confidence .9999; a stored source keeps its stated 1.
A written truth-value pattern matches the reported value. A claimed bound, or
variance at least s(1-s), is reported at confidence zero. Otherwise
n = clip(s, 1e-6, 1-1e-6)(1-clip(s, 1e-6, 1-1e-6))/V - 1 and c = n/(n+800),
the inverse of the public ideal-var decoder. The bound test still uses the
unclipped Bernoulli variance. The separable path calculates s(1-s) before
rounding at endpoints, so numerical saturation cannot invent certainty.

For unknown coupling, the existing Charnes-Cooper LP ranges over same-evidence
joint cells consistent with supplied marginals. Local arity is at most four;
beyond that the interval is [0,1]. The independent mean is clipped to the
interval, and variance adds (max(s-lo,hi-s)/2)^2, placing every interval value
within two claimed standard deviations. General graph merging and cap behavior
remain E5 work; E3 retains the previous evaluator outside its supported graph.
