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
- **The cap counts what is enumerated** (cp4). The 12-bit cap itself is unchanged.
  - One predicate, `graph_choices`, gives each bit's values, and both the bill and the enumerator use it.
  - A bit is fixed when a certain observation on it decides it, or when its law is a certain endpoint. For a
    root, that law comes from its revised sources (`graph_revised` plus `graph_fixed_law`), the same law its
    parameter gets.
  - The cap bills the bits that can still vary, with a block counting as one bit. That bounds both the worlds
    and the monomials at 4,096.
  - As a result, refined 6- and 10-use KBs are now admitted.
  - cp3 had a bug here: the bill fixed any root with a certain endpoint source, while the parameter revised all
    sources. Two sources STV 1 1 and STV .2 1 revise to the point .6, so the bit was billed as fixed but
    enumerated as varying, giving 2^24 worlds. Now `stress_certain_counts` is exact at (27/29)^n for every n up
    to 12, in at most 0.3 s (new public test).

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
- **compare --quick and --full against master (cp4):** both PASS.
  - Accuracy changed in two cases: supplynet stage 1 b100 s3 (error .004954 → .005123, under the flag
    threshold; Brier .01046 → .01031) and fuzz (−3e-18).
  - The supplynet move comes from billing by bits, which admits more graphs.
- **Canary** (`compare.sh anchor --canary`): PASS at cp3 and at cp4.

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

- **Net core tokens about +1,408 (cl100k).** This is over #168's +800 ceiling and inside the shared #106/#168 +4,000
  ceiling (R1.5). No admission system was added.
- **Inherited follow-ups, left alone:**
  - The cavity reader takes the first prior fold in installation order. A ground pattern such as `(P a0)` then
    yields no prior.
  - The cavity drops the counts of training members that are in the graph (.923 against the once-counted .941).
  - Plans and inputs are still built at b0.
  - The ordinary reader still publishes the independent answer for over-cap shared models.
