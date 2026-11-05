# master-certain: c = 1 as a point mass

Branch `master-certain` from master ab304382. Commits a4c7de38, f87613ef,
fdc025e3 (+ this report). Contract: `bench/results/fresh-design/dp-certain.md` with
`dp-certain-review.md`. Scope: the point reading only; the finite count law
(D1) is not touched.

## Design as built

- **Point law.** `confidence-to-count` is defined below 1 only (the 10^4 k
  surrogate is deleted). `ideal-var` of c = 1 is 0, zero variance converts back
  to confidence 1 (`ideal-conf-from-var`, native `node_stv`). Points stay exact
  through composition, caches, materialization, forward copies and budget-0
  re-reads.
- **Publication.** A computed point is published at .9999
  (`public-tv`, fact_reads/selection.metta); a stored source (raw proof
  `fact-source`, or a bare name such as `unfounded`) keeps its 1. It is applied
  before proof expansion to query answers, `query_many_refs`, Assuming answers
  and forward results. A written TV pattern matches a value or its published
  form (floats compared numerically); the boundary re-matches the whole written
  annotation (proof, statement, TV) on copies, so shared variables keep their
  constraint.
- **The 14 count readers handle c = 1** (each tested in
  `tests/metta/test_certain_points.metta`): bayes-prior-weight, bayes-shrink,
  merge-stv-fields (already), ideal-var, AndMarginalProjection,
  ConsistentTriple (a point is never drained or emptied), forgetting decay
  (point stays), base-rate smoothing, fold child score (0), forward minimum
  evidence (never weak), KL change (a point moved unboundedly unless
  unchanged), hypothesis review (3 sites, rewritten in confidence terms).
- **Consequences of points** (each needed to keep answers right):
  any point prior takes the factored update, and a prior decided at 0 or 1
  decides the posterior (values.metta); a frozen summary is a
  derived view, not a certain-leaf takeover (policy.metta); a prediction certain
  of a reported endpoint stays certain; in revision a point dominates finite
  views (kept alone) and point views merge to their equal-weight mean in any
  order (formulas.metta).

## Pins

Every moved pin was re-derived per site (capture of base vs candidate, no
string replacement): ~150 MeTTa sites to .9999 (incl. the 101 targets; the two
withheld best-first rows moved to the equal-weight mean .41 and stay
unendorsed), ~115 finite confidences that lost the fictitious input variance
(e.g. .79994 -> .8, .86360 -> .86364 = 19/22), temporal I19 sites now equal the
16-path oracle exactly, proof-shape-only moves (dominated finite views dropped,
node-jeffrey -> node-message for certain predictions, twin choice), ~40 Python
asserts, and the corroborating reference model updated to the point law.
Fixture audit xfail: still 43/63 (all finite-variance, i.e. D1), mark kept.

## Gates

verify.sh at fdc025e3: all 7 PASS (fuzzer gate: 0 new). compare --quick:
PASS (9 cases changed accuracy). compare --full vs master: PASS (22 changed,
none flagged; an earlier fuzz s22 flag, seed 22000133, was fixed by
fdc025e3). Canary vs anchor: PASS. Calibration: test_tv_calibration
unchanged (no new or newly passing xfail); fixture-audit xfail stays 43/63.
Reviewer suite (33 tests, fdc025e3): 16 failures, all inherited count-law (D1:
finite identity means, CTV counts, repeated origins, finite-.9999 sentinel
mean) or the temporal batch; every supplemental repro (projected binding,
positive variance, proof/TV binding, provenance, source constraint, Assuming
constraint, law identity) passes. Tokens: core +1564, third_party +379 (target <= 0 missed;
the per-reader c = 1 branches and the publication boundary are the cost).

## Open / follow-ups

1. **Temporal batch (BLOCKER, inherited A):** query_many of Front t1..t4 at
   1600/4000 gives .271/.615 (exact .642/.831), same means as base; now
   reported .9999 instead of base .9996. Not root-caused.
2. **Factored updates carry variance through confidence round trips**, so a
   point-likelihood update leaves a rounding residue (c = 1 - 1e-14) instead of
   a point; two such near-points then revise by arbitrary counts
   (twoWayKb .9036 vs exact .9070; base .9030). Fix: carry the update's
   variance (or its point provenance) in the factored-revision record.
3. Endpoint finite rules (STV 1 .75) now show c .9999999 (clipped ideal-var,
   D1).
4. Contradicting points average (pre-existing); D1 count law untouched.
