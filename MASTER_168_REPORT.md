# Master round #168: shared population parameters

Base: master bdae8d7e. Branch: master-168. Design: dp-sharedparam.md and its review. Kernel: the owner-keyed
kernel shared with #106 (dp-106.md R1.3).

## What changed

- **One owner-keyed polynomial kernel** (`prolog/event_node.pl`, `event_node_moments`).
  - A monomial maps each parameter to `c(T,F)`, its powers of theta and of 1-theta. Repeated uses keep their
    powers, and negative literals are never expanded.
  - `theta + (1-theta) = 1` merges complementary monomials of one owner at equal coefficients. This keeps
    independent groups factored: a full partition of n owners becomes one term, so there is no 2^n or 4^n blowup.
  - The strength is E[N]/E[Z]. The plug-in path `forms/add_term/lit_value` is deleted.
  - The variance bound min(s(1-s), (Q+max(s,1-s)sqrt(TQ))/e²) uses the exact E[N²], E[NZ] and E[Z²]. These
    come from Beta rising factorials computed up to twice the powers used (Bernoulli is handled in closed form).
  - `event_node_product` and `moments(M,M2)` are deleted.
  - Pair work above 2^20 pairs returns `unaffordable`. The graph treats that like unpaid work, so the ordinary
    read keeps the incumbent.
- **Owners** (`prolog/event_graph.pl`, `graph_parameter`). Each use is mapped to an owner and its law:
  - `population(pattern)` when the use reads a population prior;
  - `rule(RuleTruth, branch)` for a refined branch;
  - otherwise the statement, or `branch(Type,P)`.
  The graph checks that each owner has exactly one law. Folded blocks keep `w(literals)` expressed in their
  owners, instead of using product moments.
- **The cap counts what is enumerated.** The 12-bit cap itself is unchanged.
  - A certain root outside any block counts 0, because its bit is fixed from its point law.
  - A conditional whose parent is certain counts 1 instead of 2.
  - As a result, refined 6- and 10-use KBs are now admitted.

## Which latent is shared (review item 2)

- All members share the population centre g. This is the count-law tally that the cavity reader returns.
- `bayes-prior-count` (κ) only shrinks the ordinary single-member reader. The graph does not apply it, as the
  asymmetric pin (Beta(2.6,1.4)) shows. The test with learned rate 3:1 gives E[g²] = 10/21 at κ = 0.2 and at κ = 5.
- Master has no member-own rate across repeated uses: one event is one bit. The temporal per-member case is #165.
- The heterogeneity reading, θ_i | g ~ Beta(κg, κ(1−g)), would change only the variance terms. It is a follow-up.

## Results

- **Design probe (25 KBs, 112 answered requests):** 112/112 have exact strength, and the neutral confidences are
  exact. Master had 35 goals wrong.
- **Reviewer suite (master-168-review, 91 tests):** 86 pass. The 5 failures are the three inherited classes the
  coordinator ruled out of scope:
  - population owner depends on installation order;
  - training-member cavity;
  - b0 plan/input construction.
- **Partition stress:** 12 independent owners answer in 0.30 s with exact s and V (base 4.0 s; cp1 timed out).
- **verify.sh:** 7/7 PASS.
- **compare --quick and --full against master:** both PASS. The only accuracy change is a 1e-17 shift in
  fuzz/supplynet.
- **Canary:** see below.

## Moved test values

Five MeTTa pins moved in their last bits, because E[N]/E[Z] is now computed in exact rationals instead of a
float plug-in:

- antecedent_completion
- compound_key_reads (two pins)
- double_negation_evidence (two pins)
- rule_refinement
- implication_projection: c moved by 3e-12, because the Jeffrey finite-difference amplifies a 1-ulp change.

`test_graph_folding` was rewired to Bindings-Params. New tests are in `tests/test_shared_parameters.py`, plus a
fold test with shared owners.

## Limits

- **Net core tokens +1,227 (cl100k).** This is over #168's +800 ceiling and inside the shared #106/#168 +4,000
  ceiling (R1.5). No admission system was added.
- **Inherited follow-ups, left alone:**
  - The cavity reader takes the first prior fold in installation order. A ground pattern such as `(P a0)` then
    yields no prior.
  - The cavity drops the counts of training members that are in the graph (.923 against the once-counted .941).
  - Plans and inputs are still built at b0.
  - The ordinary reader still publishes the independent answer for over-cap shared models.
