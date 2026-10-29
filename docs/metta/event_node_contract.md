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
rule has separate parameters for its two branches. A stored report on a rule's
conclusion is an observation, rather than another parameter for that conclusion.
An observation on event K multiplies each world by m when K holds and 1-m
otherwise, with m = (n s + 1)/(n+2), or m = s at confidence one. Reports at
confidence zero are omitted before building any factors.

Raw sources are read through the ordinary indexed leaf interface and its scope
rules. Forward copies, frozen summaries and materialized outputs are excluded. Positive and
negative uses of the same canonical source are one factor, with polarity
already represented by its stored strength. Node outputs never become reports.

The E3 graph reader follows admitted skeleton structure to find compound
observations, then reads fixed conditional templates through the conclusion
index. It supports an acyclic graph with one explicit, single-parent CTV per
conclusion, at most twelve atoms and twelve parameters, and at most twenty-four
visited statements during observation discovery. Other templates retain the
ordinary evaluator. Shared parents are one event bit in the enumeration; given
branches are not imported as independent marginal parameters. Empty root counts
remain uniform, including when a zero-confidence fact was omitted.

The output subscribes to the model's keys, including children without a report,
so a late observation can wake its readers. Its dependency set holds raw roots
and observations; internal inferred marginals do not become primitive inputs.
Rule-owner references retain withdrawal identity. A numerical memo is local to
an evaluation, keyed by the full model and sources, and cleared with forcing
state. It holds no proofs.

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

For independent parameters theta, terms are signed monomials
`t(coefficient, literals, goal_ids)`. A literal selects theta_i or 1-theta_i.
Z sums all terms; N_g sums terms in which goal g holds. Coefficients are scaled
by their largest absolute value. Zero normalization is inconsistent evidence
and produces no answer.

The parameter posterior is proportional to prior(theta) Z(theta). Its moments
are:

- s = E_prior[N_g]/E_prior[Z], exact by evaluation at the parameter means;
- V = E_prior[N_g^2/Z]/E_prior[Z] - s^2.

The full tensor rule compares 9 and 17 nodes when its fine grid fits 5,000
points. With more than three free dimensions, concentrated Betas (both shapes
above ten and their sum above 1,000) use max(2, floor((N+7)/8)) nodes on an
N-node pass. If the first grid is too large, 5 and 9 nodes are compared, then
15 if necessary. Refinement is bounded by 257 nodes per axis and 70,000 points.
Agreement is within one percent of the variance contribution, plus 1e-12 of
the value at the means. A failed or unresolved rule claims the variance bound.
Bernoulli endpoints with Z=0 contribute zero to N_g^2/Z because N_g <= Z.

When full integration cannot fit, cut-HDMR integrates up to three wide variables
jointly, with first-order contributions from narrow variables. Wide means main
effect relative variance above .05. Uncaptured interaction mass above ten percent,
a nonconverging axis, or more than three wide variables produces the bound.
Exact polynomial second moments supply the constant-Z result. Otherwise a
second-order ratio expansion must agree with HDMR within a factor of two, and
the larger estimate must exceed its estimated next-order error.

Separable messages use tensor integration of their prior and product variables,
with at most four dimensions. Successive rules refine to the same 257-node and
70,000-point limits. One broad Beta (shapes at least one, sum at most ten) uses
sixteen-point Gauss-Legendre integration on intervals graded to 1e-12 of both
endpoints, resolving thin likelihood boundary layers.

## Output and unknown dependence

An exact zero variance is reported at confidence .9999. A claimed bound, or
variance at least s(1-s), is reported at confidence zero. Otherwise
n = s(1-s)/V - 1 and c = n/(n+800). The separable path calculates s(1-s) before
rounding at endpoints, so numerical saturation cannot invent certainty.

For unknown coupling, the existing Charnes-Cooper LP ranges over same-evidence
joint cells consistent with supplied marginals. Local arity is at most four;
beyond that the interval is [0,1]. The independent mean is clipped to the
interval, and variance adds (max(s-lo,hi-s)/2)^2, placing every interval value
within two claimed standard deviations. General graph merging and cap behavior
remain E5 work; E3 retains the previous evaluator outside its supported graph.
