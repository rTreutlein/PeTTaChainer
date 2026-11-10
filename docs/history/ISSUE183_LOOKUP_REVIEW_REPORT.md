# Issue 183 lookup: November 10 review fix

Historical first review-fix measurements. The [midpoint round](ISSUE183_LOOKUP_MIDPOINT_REPORT.md) supersedes this hand-back and its graded values. The formula below is updated to the final reading; tables and gate measurements retain this round’s results.

This superseded the hand-back conclusions in [the first-round report](ISSUE183_LOOKUP_REPORT.md).
Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer-i183`, branch `i183-lookup`, base `8538013b`.

## Result and formula

The accepted graph admission rule is unchanged. A stored compound reads its
ordinary source merge, and its report remains a likelihood for other keys.
The blocker was missing evidence in that merge: the complete connective join
requires every part, and the existing settling shortcut requires confidence 1.
Thus an independent false conjunct at .99 supplied no refutation of a stored
And, and a true disjunct supplied no proof of a stored Or.

Fact compilation now installs a partial producer for a stored And/Or. It uses
the existing optional `CompoundEvidence` cavity reads, dependency exclusions,
subscriptions, evaluation budget and proof publication. It reads each part
without the compound key. The report is not an input. There is no new store,
source identity, cache route, connective-specific endpoint rule or public API.
The complete producer and certain settling retain their distinct jobs: binding
and combining all parts, and settling with minimal certain evidence.

For each known part use its ordinary STV at both interval endpoints. An unknown
part has endpoints (0,1) and (1,1), which describe possible bounds, not evidence.
Negation complements the known part and its printed proof. Fold each endpoint
list left-to-right using the connective's existing formula, obtaining (L,cL)
and (U,cU). With **d = L + (1 − U)**, the partial evidence is:

- **strength = (L+U)/2**;
- **confidence = d × min(cL,cU)**;
- no proof when d=0, no known source, or no positive confidence;
- when every part is known, this producer gives no value: the existing complete
  proof uses its existing strength and confidence formula.

And uses s1*s2; Or uses 1−(1−s1)(1−s2). Both propagate product variance
V1*V2 + V1*s2² + s1²*V2 (on complemented strengths for Or), with the existing
`ideal-var` and variance-to-count conversion, K=800. Unknown endpoints have
zero variance; they add no proof or evidence. The interval centre is L+(U-L)/2=(L+U)/2; d=1-(U-L) reduces
confidence with its width. This reading does not turn an upper bound into
an observation of falsity.
For A=(.2,.9), B unknown, And bounds are [0,.2], so its partial proof is
(.1,.72). The dual Or with A=(.8,.9) supplies (.9,.72). Adding B replaces this
partial reading with the ordinary complete proof; regression tests pin that.

A false conjunct gives L=U=0, d=1 and its own confidence. A true disjunct gives
L=U=1 with its own confidence. Conversely, a true conjunct or false disjunct
alone gives [0,1], d=0 and no proof. Leading Not and a negated part follow the
same canonical read and complement rules.

The partial producer is installed for stored compounds, the keys diverted
from the graph by this issue. Unreported compounds retain their prior producer
and graph behavior. An initial experiment installed it for every compound;
that changed closed-world and unreported-compound behavior (8 MeTTa files,
2 Python units, quick comparison failed). That implementation was removed,
not retained behind a switch. The scoped producer passes the existing MeTTa
suite without moving a MeTTa expectation in this review round.

## Four blocker rows

| KB / sequence | Master (review) | Before this fix | After |
|---|---|---|---|
| And report (1,.5), A=(0,.99) | (.00503,.0686) | (1,.5) | (.010000000000000009,.9900990099009901) |
| And report (1,.99), A=(0,.99) | (.3333,.00044) | (1,.99) | (.5,.9949748743718593) |
| Or report (0,.99), A=(1,.99) | (.6667,.00044) | (0,.99) | (.5,.9949748743718593) |
| And report (1,.5); query; add A=(0,.99); query | .996→.00503 | (1,.5)→(1,.5) | (1,.5)→(.010000000000000009,.9900990099009901) |

The weak report has n=800 and the part n=79200; ordinary revision yields
800/80000=.01 and confidence 80000/80800=100/101. Equal .99 inputs pool equal
counts: strength .5 and confidence 158400/159200=198/199. These differ from
master because master answered through the graph's loose variance bound.
Independent disagreement is averaged, not confidence-discounted.

Proof: `(merge/revision (conjunction a) report)` (ordering is immaterial).
There is one `a` source and one `report` source. The cavity excludes every
part view depending on the compound, including a rule projecting its own
report back to a part. A report-only compound still prints `report` at its
stored TV. The explicit projected-negative-part regression reads (0,.9),
proof `report`, even after querying the part. Two independent reports plus
one decisive part give (2/3,297/298), proving that installing the producer
for two reports does not count the part twice.

## Review probes

All 58 outputs were rerun from the review's fixtures. Full precision and proofs:
[master](i183_lookup/review/master-before.jsonl),
[pre-fix branch](i183_lookup/review/branch-before.jsonl),
[final branch](i183_lookup/review/after.jsonl).
The [replay script](i183_lookup/review/probes.py) reads a committed fixture file;
run it through the pinned venv and the normal capped/time-limited wrapper.
The [21 original cases](i183_lookup/review/cases-after.jsonl) were rerun too.

Cases 4–9 retain .99; the independent full-parts conflict retains
(.33333052748398234,.9933110088252738). Parts-first and whole-first queries
agree on the new .01 answer. Variable-pattern, rule-premise, both polarities,
Assuming and the review's 0-step/400-step control retain their values. Every
numerical change among the 58 outputs is a blocker row or its negated/order
variant. The unsupported weighted assumption remains unsupported.

| Probe | Query (steps) | Master | Pre-fix branch | Final |
|---|---|---|---|---|
| conflict | `(And A B)` (400) | (0.333331930439, 0.00249380484527) | (0.333330527484, 0.993311008825) | (0.333330527484, 0.993311008825) |
| conflict | `(Not (And A B))` (400) | (0.666668069561, 0.00249380484527) | (0.666669472516, 0.993311008825) | (0.666669472516, 0.993311008825) |
| conflict | `A` (400) | (0.666663860878, 0.00073633851911) | (0.666663860878, 0.00073633851911) | (0.666663860878, 0.00073633851911) |
| conflict | `B` (400) | (0.666663860878, 0.00073633851911) | (0.666663860878, 0.00073633851911) | (0.666663860878, 0.00073633851911) |
| atomic_conflict | `A` (400) | (0.5, 0.994974874372) | (0.5, 0.994974874372) | (0.5, 0.994974874372) |
| rule_conj | `(And A B)` (400) | (0.272723098729, 0.992707342225) | (0.272723098729, 0.992707342225) | (0.272723098729, 0.992707342225) |
| rule_conj | `A` (400) | (1, 0.9999) | (1, 0.9999) | (1, 0.9999) |
| rule_whole | `(And A B)` (400) | (0, 0.99) | (0, 0.99) | (0, 0.99) |
| partial | `(And A B)` (400) | (1.26256249684e-05, 0.000624704195897) | (0, 0.99) | (0, 0.99) |
| partial | `B` (400) | (2.52512499369e-05, 0.000426909474955) | (2.52512499369e-05, 0.000426909474955) | (2.52512499369e-05, 0.000426909474955) |
| partial | `A` (400) | (0.99997474875, 0.0006246687293) | (0.99997474875, 0.0006246687293) | (0.99997474875, 0.0006246687293) |
| hide_weak | `(And A B)` (400) | (0.00503128062109, 0.0686482588401) | (1, 0.5) | (0.01, 0.990099009901) |
| hide_weak | `A` (400) | (0.0050375618703, 0.0687052621767) | (0.0050375618703, 0.0687052621767) | (0.0050375618703, 0.0687052621767) |
| hide_weak | `(Not (And A B))` (400) | (0.994968719379, 0.0686482588401) | (0, 0.5) | (0.99, 0.990099009901) |
| hide_weak2 | `(And A B)` (400) | (0.0100121245437, 0.0582433341301) | (0.0100000000001, 0.990099009901) | (0.0100000000001, 0.990099009901) |
| order_parts_first | `A` (400) | (0.0050375618703, 0.0687052621767) | (0.0050375618703, 0.0687052621767) | (0.0050375618703, 0.0687052621767) |
| order_parts_first | `B` (400) | (0.502512499686, 0.00245182335316) | (0.502512499686, 0.00245182335316) | (0.502512499686, 0.00245182335316) |
| order_parts_first | `(And A B)` (400) | (0.00503128062109, 0.0686482588401) | (1, 0.5) | (0.01, 0.990099009901) |
| order_parts_first | `A` (400) | (0.0050375618703, 0.0687052621767) | (0.0050375618703, 0.0687052621767) | (0.0050375618703, 0.0687052621767) |
| order_whole_first | `(And A B)` (400) | (0.00503128062109, 0.0686482588401) | (1, 0.5) | (0.01, 0.990099009901) |
| order_whole_first | `A` (400) | (0.0050375618703, 0.0687052621767) | (0.0050375618703, 0.0687052621767) | (0.0050375618703, 0.0687052621767) |
| order_whole_first | `B` (400) | (0.502512499686, 0.00245182335316) | (0.502512499686, 0.00245182335316) | (0.502512499686, 0.00245182335316) |
| order_whole_first | `(And A B)` (400) | (0.00503128062109, 0.0686482588401) | (1, 0.5) | (0.01, 0.990099009901) |
| reorder | `(And C A B)` (400) | (1.80372577596e-06, 0.00431827494788) | (1.80372577596e-06, 0.00431827494788) | (1.80372577596e-06, 0.00431827494788) |
| reorder | `(And A B C)` (400) | (1.80372577596e-06, 0.00431827494788) | (0, 0.99) | (0, 0.99) |
| premise_rule | `C` (400) | (0.899625468165, 0.358455898688) | (0.9, 0.989999416981) | (0.9, 0.989999416981) |
| premise_rule | `(And A B)` (400) | (0.999063670412, 6.96664947952e-17) | (1, 0.8) | (1, 0.8) |
| premise_rule_conflict | `C` (400) | (0.9, 0.989999946466) | (0.9, 0.989999946466) | (0.9, 0.989999946466) |
| pattern | `(And (P $x) (Q $x))` (400) | (0.999583564686, 0) | (1, 0.9) | (1, 0.9) |
| pattern | `(P a)` (400) | (0.999722376458, 1.99840144433e-17) | (0.999722376458, 1.99840144433e-17) | (0.999722376458, 1.99840144433e-17) |
| pattern | `(And (P a) (Q a))` (400) | (0.999583564686, 0) | (1, 0.9) | (1, 0.9) |
| pattern_not | `(And (P $x) (Q $x))` (400) | (0.000104430605862, 0.00203862965943); (1, 0.818161154666) | (0, 0.9); (1, 0.818161154666) | (0, 0.9); (1, 0.818161154666) |
| pattern_not | `(Not (And (P $x) (Q $x)))` (400) | (0.999895569394, 0.00203862965943); (0, 0.818161154666) | (1, 0.9); (0, 0.818161154666) | (1, 0.9); (0, 0.818161154666) |
| issue4 | `(Not (And (Member sk_watch_1 watch) (Agent sk_watch_1 sk_group_1) (Ongoing sk_watch_1)))` (400) | (0.999998196274, 0.00431827494788) | (1, 0.99) | (1, 0.99) |
| issue4 | `(And (Member sk_watch_1 watch) (Agent sk_watch_1 sk_group_1) (Ongoing sk_watch_1))` (400) | (1.80372577596e-06, 0.00431827494788) | (0, 0.99) | (0, 0.99) |
| late_evidence | `(And A B)` (400) | (0.996268656716, 7.49400541622e-18) | (1, 0.5) | (1, 0.5) |
| late_evidence | `(And A B)` (400) | (0.00503128062109, 0.0686482588401) | (1, 0.5) | (0.01, 0.990099009901) |
| or_conflict | `(Or A B)` (400) | (0.666668069561, 0.000437340964068) | (0, 0.99) | (0.5, 0.994974874372) |
| or_conflict | `A` (400) | (0.666663860878, 0.000437363316346) | (0.666663860878, 0.000437363316346) | (0.666663860878, 0.000437363316346) |
| hide_strong | `(And A B)` (400) | (0.33333193044, 0.000437340964066) | (1, 0.99) | (0.5, 0.994974874372) |
| hide_strong | `(Not (And A B))` (400) | (0.66666806956, 0.000437340964066) | (0, 0.99) | (0.5, 0.994974874372) |
| hide_strong | `A` (400) | (0.333336139123, 0.000437363316344) | (0.333336139123, 0.000437363316344) | (0.333336139123, 0.000437363316344) |
| or_noreport | `(Or A B)` (400) | [] | [] | [] |
| and_noreport_false | `(And A B)` (400) | [] | [] | [] |
| atomic_premise | `C` (400) | (0.9, 0.989999337713) | (0.9, 0.989999337713) | (0.9, 0.989999337713) |
| or_report_parts | `(Or A B)` (400) | (0.500003156546, 0.00124847093668) | (0.499999999997, 0.994974874372) | (0.499999999997, 0.994974874372) |
| assume_conflict | `(Assuming (Not A) (And A B))` (400) | (0, 0.9999) | (0, 0.9999) | (0, 0.9999) |
| assume_conflict | `(Assuming (: na A (STV 0 0.99)) (And A B))` (400) | unsupported weighted assumption | unsupported weighted assumption | unsupported weighted assumption |
| zero_steps | `(And A B C)` (0) | (0, 0.99) | (0, 0.99) | (0, 0.99) |
| zero_steps | `(And A B C)` (400) | (4.20861250463e-06, 0.00236057723127) | (0, 0.99) | (0, 0.99) |
| shared_atomic | `B` (400) | (0.5, 0.993311008825) | (0.5, 0.993311008825) | (0.5, 0.993311008825) |
| shared_atomic | `(Not B)` (400) | (0.5, 0.993311008825) | (0.5, 0.993311008825) | (0.5, 0.993311008825) |
| cycle | `(And A B)` (400) | (0.8, 0.9) | (0.8, 0.9) | (0.8, 0.9) |
| cycle | `C` (400) | (0.9, 0.04804636966) | (0.9, 0.04804636966) | (0.9, 0.04804636966) |
| proj_part | `(And A B)` (400) | (0.8, 0.9) | (0.8, 0.9) | (0.8, 0.9) |
| proj_part | `A` (400) | (0.799915174473, 0.00109280301314) | (0.799915174473, 0.00109280301314) | (0.799915174473, 0.00109280301314) |
| proj_negpart | `(And A B)` (400) | (0, 0.9) | (0, 0.9) | (0, 0.9) |
| proj_negpart | `A` (400) | (8.92592963089e-21, 1) | (8.92592963089e-21, 1) | (8.92592963089e-21, 1) |

## Test expectation ledger

This review changes no existing MeTTa expected value. The first-round MeTTa,
KE and fuzzer changes are preserved in the original report and its ledgers.
The Python bound assertions are replaced by 1e-12 pins:

| Test / case | Before | After |
|---|---|---|
| bridge query order, report confidence .9 | c≤.9 | c=.8181611546663349 |
| identity bridge, s=1 | s≤1+1e-6, c≤.9 | s=1, c=.8181611546663349 |
| identity bridge, s=.8, including either neutral report | s≤.800001, c≤.9 | s=.8, c=.8999996399380039 |
| identity bridge, s=.5 | s≤.500001, c≤.9 | s=.5, c=.899999909975099 |
| double negation overlapping bridge, source c=.5 | c≤.5 | c=.4736218485431543 |
| double negation overlapping bridge, source c=.9 | c≤.9 | c=.8181611546663349 |
| explicit conditional double negation | .8181611546663349, default unittest tolerance | same value, 1e-12 |
| stored And, X→A explicit CTV (.9,.99)/(.1,.99), MAIN and Assuming X | (0,.99), report only | (0,.990010975730573), revision with independent graded part |
| same CTV fixture, Assuming A | (0,.99) | unchanged |
| stored Or with independently true A | sole-report matrix expected report TV | moved into decisive-part regression, ordinary revision |

The .8181611546663349 pin is the existing And variance propagation of two
(1,.9) inputs: with the runtime clipping arithmetic u=.999999*(1−.999999),
v=u/7201, V=2v+v², n=u/V−1 and c=n/(n+800). The bridge fixtures retain their existing conditioned formula, which in
these fixtures gives the same product propagation of the identity (s,c)
with the bridge branch (1,.9): V=V_identity+ s²*V_bridge+
V_identity*V_bridge. This yields .8999996399380039 at s=.8,
.899999909975099 at s=.5, and .4736218485431543 at (s,c)=(1,.5). Their proofs and
single-source evidence assertions remain tested. The CTV's independent A has strength .9. The historical result in this
ledger treated its upper bound as false evidence; the midpoint round replaces
that with strength .45 at the same confidence and records the revised value. Seven new test methods
cover decisive/late parts, graded-to-complete replacement, Not/patterns,
self-source exclusion, derived evidence, duplicate producer deduplication and
semideterministic native output with multiple unknown parts. The native unknown
membership check uses `memberchk`, so it produces one result regardless of how
many parts are missing; this was caught and corrected during final code review.

## Gates and benchmark measurements

All jobs used the repository-pinned venv through `/nexus/Dev/OpenCog/bench/capped`,
with `ulimit -v 16000000`, DISPLAY unset, stdin `/dev/null`, and outer timeouts.
Comparisons are the standard `compare.sh` profiles, with no custom runners or
seeds. Result artifacts are under [review/benchmarks](i183_lookup/review/benchmarks/).
The final executable runtime tree is `c151b12d6114`; labels retain the pre-amend
HEAD plus the working-tree diff, and therefore identify the same code as the
final code commit. The pinned PeTTa runtime is `18c99706738d76f4`.

| Gate | Final result |
|---|---|
| `scripts/verify.sh` | PASS; 164 MeTTa files, 1158 Python tests in 88 files, 23 expected failures, 4 skipped; import scaling, judgment scaling, ConceptNet and quick seed-1 fuzzer gates PASS. 198 s; recorded PASS key `aed663f5b663`. [Log](i183_lookup/review/verify.log). |
| `compare.sh master <worktree> --quick` | PASS; 0 accuracy changes across 9 scored cases (10 jobs), 81 s. [Report](i183_lookup/review/benchmarks/quick.md). |
| `compare.sh master <worktree> --full` | PASS; 0 accuracy changes across 22 scored cases (23 jobs), 355 s including queueing. [Report](i183_lookup/review/benchmarks/full.md). |
| `compare.sh anchor <worktree> --canary` | PASS; 4 of 6 cases differ from anchor; no accuracy difference from master on the same profile. [Report](i183_lookup/review/benchmarks/anchor-canary.md). |
| `compare.sh master <worktree> --curves` | Completed 10 curves / 56 paired budget points; no unsupported or missing points, 0 changed errors. 815 s including queueing. [Report](i183_lookup/review/benchmarks/curves.md). |

The full profile's initial stage-1 b100 s3 timing flag did not repeat:
4.356→5.572 s initially, 4.164→4.280 s in the paired rerun. No timing flag
remains. The canary lists its inherited anchor deficits explicitly; none is a
new blocking regression against master. Earlier pre-determinism passes were
superseded by these final-tree runs. One intermediate verify passed all gates
but its cache record was withheld because the language specification changed
during the run; the final record above covers the unchanged tree.

The capture audit covers 90 distinct base/candidate comparisons. **No captured
strength or confidence changes against master**, and no added calibration miss.
Every changed captured value is relative to the older anchor: 1,015 rows,
all inherited from master. [Every moved value with before/after TV, reference,
variance and z score](i183_lookup/review/benchmarks/moved-values.jsonl), and
[the complete calibration summary](i183_lookup/review/benchmarks/calibration.json),
were extracted with the existing `compare_details.py` from the standard stores.

| Anchor comparison | Changed capture rows | Outside 2 SD, anchor→candidate |
|---|---:|---|
| live b50 5 shifts s1 | 50 | 18/50→17/50 |
| conflict pln-stated l spq4 s1 | 160 | 60/70→135/160 (coverage differs) |
| conflict pln-reliable l spq4 s1 | 160 | 70/160→2/160 |
| scale m spq4 r10 s1 | 645 | 185/645→186/645 |

The additional [master-canary export](i183_lookup/review/benchmarks/master-canary.md)
confirms identical accuracy on all six cases, using successful same-tree records.
Some frozen-build warm attempts printed exit 127 before retry or store reuse;
the standard comparator's final reports are PASS and its measurement records
come from successful runs. The extra master-canary export used zero measurement
CPU seconds. The required anchor run and full run have their own captured
measurements. Curves report actual timing and best error within each time; its
56 budget errors are identical, not a promise of identical wall-clock timing.


## Commits

`adcd18f0` — code, tests and contracts: `Read stored compound sources and decisive partial proofs (#183)`.

The second commit contains this report, the first-round measurement archive,
review fixtures and ledgers, and the updated rounds/state entries. Final history
has exactly two commits on 8538013b; both carry the requested Co-Authored-By and
Claude-Session trailers. No push, merge, GitHub write or main-checkout edit.

## Updated draft reply (not posted)

> Stored compound reads now use their ordinary source merge, and a decisive
> independent part reaches that merge even when another part is unknown.
> A false conjunct refutes an And and a true disjunct supports an Or at the
> part's confidence; negation follows the same rule. The report and part proof
> revise as independent evidence. A weak positive And report (.5 confidence)
> against a false conjunct at .99 now reads (.01,.990099); equal-confidence
> conflicts read (.5,.994975). A report projected back through a part does not
> supply independent evidence. Cases 4–9 remain at .99, the full-parts conflict
> and review controls retain their values, and deterministic KE confidence
> values are pinned. Child order and the pre-existing shared-evidence issues
> below remain outside this fix.

## Limits

- Shared-evidence conflicting derivations remain overconfident on master and
  here: A, A→B, A→Not B gives B=(.5,.9933110088252248).
- A compound report projected through a rule can still be double-counted at
  the part: A≈(8.92593e-21,.9999999999999996). The compound's own read excludes
  this feedback and retains its report; this task does not repair that part read.
- An atom with its own stored observation can still read at near-zero
  confidence when a compound report on it exists; graph variance is unchanged.
- `canon` does not reorder children. Reordered compounds remain separate keys.
- Partial producers are scoped to stored compounds. Unreported compounds,
  search budgets, closed-world semantics and ordinary report/prediction policy
  retain their existing behavior. Bounds use the ordinary compound's parts;
  this is not a general interval-valued public API or Boolean normalization.
- The confidence projection for an unresolved graded bound is stated explicitly
  above. It is not a claim of universal calibration; the benchmark captures
  retain their pre-existing calibration misses.
