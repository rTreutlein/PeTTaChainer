# fc-integrate: inverse witnesses and forward publication (#180, #181)

Branch `fc-integrate`, worktree `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer-fc-integrate`, from master
`b6aacc68`. It integrates two reviewed fix branches into one landable branch with one inverse-exclusion
mechanism: `i181-fc-cycle` (`20b01337`, report `e2f957b7:I181_REPORT.md`) and `i180-chain-conf` (`3151ada7`,
report `43298a24:I180_CHAIN_CONF_REPORT.md`). Their full diagnoses, ablations and traces stay in those reports
and in their worktrees' `scratch/`; this report keeps what the landing needs.

## Diagnoses

**#181, forward chain cycle drift** (three defects, from the i181 round):

1. *Forward premise keys were not registered.* A forward join reads stored facts directly
   (`sk-forward-keys`) and extends its partial; unlike a backward answer it never called
   `sk-register-key!`. The fact's dependency hash then resolved to no shared statement, so `sk-pair-facts`
   treated two routes over one uncertain fact as independent. Case 2's parent went to `(0.914, 0.948)`.
2. *Publication switched the evaluation policy too early.* `execution-forward-run` cleared `sk_forward_run`
   before collecting its results, so a needed depth-0 key became eligible for backward deep-root
   conditioning and the publication read replaced the merge the forward run had evaluated with an unpaid
   fallback. Case 3's sibling confidence collapsed to `0.004`.
3. *An inverse witness hid the antecedent that produced its observation.* `son(x, y) -> male(x)` loses `y`
   when inverted, so its inverse concludes `son(elliott, (exists male_son 0 (elliott)))`. The row excluded
   only that generated key, so the known `son(elliott, stanley)` that predicted `male(elliott)` was read as
   independent evidence for a new son. Case 1 invented existential sons at `(0.727, 0.008)`.

**#180, rule over derived conjunction** (two defects, from the i180 round):

1. *The same witness feedback* (defect 3 above), through `male_son`, fed the sibling/completion paths and the
   shared-evidence conditioning magnified it: case 4 uncle `(0.999, 0.055)`, and case 6 (after an `aunt_or_uncle`
   query) `(0.99999, 0.470)`.
2. *Fallback reconstruction starved conditioning.* `sk-coarse-roots!` runs before `sk-pay-conditions!` and
   could spend the whole remaining allowance on representative reads. With the two unrelated brother rules
   (case 5), master spent 7,424 representative reads and 12 conditioned evaluations, and the conjunction
   returned `[]`.

**Review findings on both branches** (i181 reviewer, round 1):

1. *A part of lost variables alone excluded independent evidence.* For
   `r2: (And (Works $x $c) (Located $c paris)) -> (LivesIn $x paris)`, both branches excluded the open part
   `(Located $c paris)`, which matches the observed `(Located eiffel paris)` supporting `LivesIn` through `r1`.
   Master answers the r2 witness compound at `(0.736, 0.0072)`; both branches gave none.
2. *`test_nonseed_fact_in_forward_join_keeps_dependency_identity` passed on master.*

**Codex review of the first integration** (round 2, `bench/results/codex-logs/fc-integrate-review/review.md`):

1. *High: the fallback slice erased answers at 257+ roots.* The slice `min(256, allowance)` was divided
   equally and floored, so every share became 0 at 257 roots; a 257-root batch at 200 steps answered 0 of the
   200 master answers.
2. *Medium: generalizing the city lost the answer again.* With `$city`, `(Located $c $city)` holds a retained
   variable, so the round-1 retained-variable filter kept it; once bound it excluded `(Located eiffel paris)`.
   A structural filter over bound parts cannot tell `r2`'s `(Located $c $city)` from `sib`'s
   `(Kin parent $y $z)`; only provenance can.
3. *Medium: a variable-headed forward inverse published a self-supported witness* (also on master): the
   witness exclusion ran only in the row's open context, not in MAIN where its input was.
4. *Medium: an inverse retaining no variable excluded nothing* (also on master): the filter also dropped the
   canonical antecedent.

**Codex re-review** (round 3, `bench/results/codex-logs/fc-integrate-review2/review.md`):

1. *High: the 256-unit fallback ceiling still lost answers.* Past 512 cheap reads (two per unit) the batch
   stopped: 600 roots at 600 steps answered 511 (master 599), 1,024 at 1,000 answered 510 (master 998).
2. *Medium: a stored r2 witness cut r1's independent route.* With `(Works alice eiffel)` stored, r2's row
   passed the support filter and its premise `(Located eiffel paris)`, shared with r1's row, became a global
   key exclusion: master `(.4148, .0314)`, branch `[]`, also after forward saturation, with reversed seeds,
   under Assuming and when the row appeared late.
3. *Medium: Assuming support was invisible.* The support filter read MAIN's `&sk_latest`, so a compound
   supported only by an assumption counted as no witness and the inverse read r's own prediction
   (`(.909, .0011)` on both builds; the MAIN control was `[]`).

**Codex re-review 3** (round 4, `bench/results/codex-logs/fc-integrate-review3/review.md`):

1. *High: the allocation still lost answers master returns* when a root's reconstruction needs more than
   one unit: 129 roots / 600 steps / 3 links answered 127 (master 129), 260 / 1,000 / 3 answered 0 (master
   220), a single root over a 600-link chain 0 (master 1). Three allocation rules had each met a new
   counterexample, so the allocation change itself was withdrawn.
2. *Medium, equal to master: a second rule with the same antecedent defeats the exclusion.* Recorded under
   Limits, not fixed.

## Fixes

- **One inverse-witness exclusion, by provenance** (replaces both branch mechanisms and the round-1
  pattern list). An inverse of rule r excludes, besides its own key and parts as on master, the statement
  premise keys that set r's rows concluding an observed key apart from that key's other derivations
  (`sk-witness-hashes`). The rows come from the existing row store (`&sk_row`, indexed by the observed key's
  hash); r's rows are those of the catalog applications sharing the inverse's source (`rule-forward-ids`,
  `source_catalog.pl`). `sk-row-exclusions` takes the row's ident `(sk-ident rule premise-keys owner)`, so it
  knows the observed keys. A premise r's row shares with another rule's forward row at the same key (r1's
  `(Located eiffel paris)`) is no mark of r's derivation and cuts nothing, so another rule's route stays
  independent evidence (round 3, finding 2). Inversion, completion and report rows only relay their
  observation as evidence of another antecedent, so they set nothing apart: an `s_son` completion of `Male`
  from `Son(elliott, stanley)` does not shield `male_son`'s own row (#181 case 1). A refined rule's truth
  premise is r's parameter, not a witness. Views carry their premises' keys transitively, so a prediction that
  reaches the consequent through another rule (a symmetric relation, a converse) is refused as well. Premise
  keys carry their own context, so Assuming, the variable-headed forward case and the no-retained-variable case
  need nothing of their own, and no view store is read (round 3, finding 3: the support filter and its MAIN
  read are gone). The `reverse-source` role, the compiler and the raw-ingress role are master's again.
- **Root fallbacks: master's, unchanged (round 4).** i180's bound on fallback reconstruction and the three
  allocation rules tried after it are all withdrawn; `work.metta`'s fallback path, `allowances.metta` and
  the design text are master's. Each rule lost answers master returns: a 256-unit batch slice floored equal
  shares to zero at 257 roots; one unit a root within that slice stopped at 512 reads; one unit a root plus
  the ceiling for reconstruction lost every root needing more than a unit. Budget-proportional bounds (half
  of the remaining allowance, an eighth per root, conditioning first, reserving what pending conditioning is
  owed) each regressed `supplynet stage 3 timed soft0.9 b100 s3` (error .01055 -> .0151 to .0207).
  Consequence: #180 case 5 returns `[]` as on master (see Limits).
- **Forward fixes (#181)**: `sk-extend-waiter-step` registers the key of a join extension during a forward
  run; `execution-forward-run` turns forward mode off only after publication.

## Mechanism choice

Four designs were tried; the measurements decided.

| Mechanism | Literal city | `$city` | #181 case 3 | review 3/4 | quick bench |
|---|---|---|---|---|---|
| i180: original pattern only (compiler role) | lost | lost | ok | missed | 0 changes |
| i181 / round 1: pattern plus retained-variable parts | ok | lost | ok | missed | 0 changes |
| whole bound antecedent only | ok | ok | existential witnesses published | ok | not run |
| r's rule evidence (`rule-excluded`, as instance samples use) | ok | ok | ok | ok | replay b25 s4 error .1269 -> .1353, 43/200 beliefs moved |
| provenance: all premise keys of r's rows, with a support filter (round 2) | ok | ok | ok | ok | 0 changes; round 3 findings 2 and 3 |
| **provenance: premise keys that set r's rows apart (chosen)** | ok | ok | ok | ok | see gates |

- The whole bound antecedent fails because a forward rule reads a conjunction's parts as its premises, not
  through the compound key, so views through r never depend on the compound key.
- Rule evidence names r for both its forward and its inverse derivations. Excluding it also refuses
  smoothing through r's own inverse (a later observation read back through r), which moved replay beliefs.
  It also hit refined truths until those were exempted.
- Excluding all of r's row premises cut other rules' routes through a shared premise; a support filter
  guarded only some of those cases and read one context's views.
- The chosen criterion excludes what only r's own derivation reads, found by index lookups in the row
  store. Dependency sets hold keys, not rows, so this is as close to "exclude r's row" as the existing
  machinery gets without a structural change (rows or applications as dependency nodes).

Deleted from the earlier states: `rule-cycle-key`, `rule-exclusion-key`, `rule-witness-exclusions`, the
4-element role, the compiler's witness list, and the move of `statement-parts` to the vocabulary. There is
one `sk-row-exclusions (ident khash key proof)`.

## Values

Branch values (2,000 steps; negative branch `(STV 0 0.001)`):

| Fixture | Master | fc-integrate |
|---|---|---|
| #180 case 3 uncle (male stored) | .999999521, .895384479 | .999996028, .943752520 |
| #180 case 4 uncle | .999176854, .055362725 | 1, .891878369 |
| #180 case 5 uncle and conjunction (cycle present) | `[]` | `[]` (known limitation, expected failure) |
| #180 case 6 repeats (3 re-queries) | drift | equal to cold case 4 to 1e-12 |
| #180 case 6 uncle after aunt_or_uncle | .999991416, .469581656 | 1, .891878369 |
| #181 case 1 child / male (forward) | existential sons at .727, .008 | .8, .899910 each; no existential fact |
| #181 case 2 parent (forward) | .914, .948 | .7999999, .9000000 |
| #181 case 3 sibling (forward) | .914, .004 | .7999999, .8998199 |
| Fallback batches, all three reviews (see below) | | equal to master in answers, indices and representative reads |
| Review 2: r2 witness, literal and `$city`, 10 / 2,000 / 20,000 steps, cold, forward, Assuming | .736417387, .007249012 | same everywhere (first integration: `$city` `[]`) |
| Review 3: variable-headed forward inverse | publishes `(P alice (exists r 0 (alice P)))` at .896, .318 | no P witness |
| Review 4: no retained variable, 2,000 / 20,000 steps and forward | generated son at .818, .004 by `(inverted r (by r s))` | population prior only; no witness published |
| Finding 2 fixture `(R a)` (forward) | .941176, .007721 | .8, .9 |
| Round 3, stored r2 witness `w`, 10 / 2,000 / 20,000 steps | .414835, .031400 (includes r2's own route) | .736417, .007249 by r1 (round 2: `[]`) |
| Round 3, Assuming Or, and the stored control | .909157, .001138 both | `[]` both (round 2: Assuming .909157, .001138) |

Fallback rows (roots / steps / chain links: answers, representative reads; master = branch in every row,
conditioned evaluations and answered indices too): 256, 257, 260 / 200: 200, 200. 512 / 400: 400, 400.
600 / 600: 599, 600. 1,024 / 1,000: 998, 1,000. 20 / 10 uneven: 6, 6. 300 / 200 uneven: 133, 133.
128 / 600 / 3: 128, 512. 129 / 600 / 3: 129, 516. 260 / 1,000 / 3: 220, 880. 260 / 2,000 / 6: 260, 1,820.
100 / 2,000 / 10: 100, 1,100. 1 / 2,000 / 600: 1, 601. Tiny budgets (2 / 0, 2 / 1, 5 / 2, 260 / 1, 260 / 10)
equal master as well.

## Tests

- `tests/test_forward_cycles.py` (#181): the three issue fixtures with negative confidence `.001` and `1`,
  forward against cold backward, repeated saturation and zero-budget reads; the forward witness test; the
  non-seed test, two routes `(And (Start $x) (P $x))` and `(And (Go $x) (P $x))` over the unselected
  `(P a)` into `(R $x)` (fails on master and with only the registration reverted).
- `tests/test_issue180.py`: `DerivedKinshipTests`: cases 3 and 4; case 6 equals case 4 across re-queries;
  `test_case_five_answers_beside_an_unrelated_cycle`, an expected failure marked `#180 case 5`.
  `InverseWitnessTests`: the backward generated-witness test;
  `test_another_rules_prediction_supports_the_inverse` (literal and `$city`, cold, forward and Assuming, at
  master's value to 1e-9); `test_inverse_retaining_no_variable_rejects_its_own_prediction` (2,000 and 20,000
  steps, forward); `test_variable_headed_forward_inverse_rejects_its_own_prediction`.
- `tests/test_ingestion.py`: the variable-head non-binding probe passes a row ident to `sk-row-exclusions`.

No existing expected value moved.

## Gates and benchmarks

All on `0b15c356`.

- `scripts/verify.sh`: **PASS** (150 s), key `4781fb1d9057`: lint, 164 MeTTa files, 1,143 Python tests in 87
  files (23 expected failures, one of them #180 case 5; 4 skips), import and judgment scaling, ConceptNet,
  fuzzer gate (no new or fixed BLOCKER; the three known `BLOCKER:flip` remain).
- `compare.sh master <wt> --quick`: **PASS**, accuracy changed in 0 cases
  (`bench/results/compare/b6aacc68_vs_0b15c356-dc39c2b78_quick/report.md`).
- `compare.sh master <wt> --full`: **PASS**, accuracy changed in 0 cases
  (`bench/results/compare/b6aacc68_vs_0b15c356-dc39c2b78_full/report.md`).
- `compare.sh anchor <wt> --canary`: **PASS**, accuracy changed in 4 of 6 cases against the anchor, the same
  existing deficits as master (`bench/results/compare/anchor-b4065459_vs_0b15c356-dc39c2b78_canary/report.md`).
- `compare.sh master <wt> --curves`: 56 budget points; one moved, replay s3 at budget 10 `.1513 -> .1519`
  (`bench/results/compare/b6aacc68_vs_0b15c356-dc39c2b78_curves/curves.md`). It moves with master's
  fallbacks too, so it comes from the forward or exclusion changes, not from the fallback bound earlier
  states of this report named.
- Rejected designs' runs: rule evidence, `bench/results/compare/b6aacc68_vs_7ae189d4-d9c004ef9_quick/report.md`;
  half-share fallback, `bench/results/compare/b6aacc68_vs_0dcce79f-d61b3890b_full/report.md`.
- Codex repros of all three reviews rerun on the branch: every fallback row equals master (table above);
  the kinship and duplicate-forward repros equal master's failing sequence (Limits); the other differing
  lines are the accepted ones (recycled witnesses gone, r1's route kept).

## Limits

- The provenance exclusion sees r's rows that exist when the inverse is read. A row of r concluding the
  observed key that appears later changes that key's value, so the inverse is read again; a forward run that
  already published a witness before such a row existed does not retract it.
- With a stored r2 witness, the r2 route of the round-3 fixture is excluded as r2's own prediction, so the
  answer is r1's `(.736, .0072)` rather than master's `(.415, .031)`.
- **#180 case 5 is not fixed.** With the two unrelated brother rules, uncle and the premise conjunction
  return `[]` at 2,000 steps, as on master: the roots' waiting-answer reconstruction spends the allowance
  (7,484 representative reads, 7 conditioned evaluations) before conditioning runs. Every bound tried on
  that reconstruction lost answers elsewhere. The test is an expected failure.
- **A second rule with the same antecedent defeats the exclusion** (review 3, finding 2; equal to master).
  The excluded keys are those no other rule's forward row at the observed key reads, so two rules over the
  same premises shield each other. Reviewer's repro: #180 case 4 plus
  `(: male_son_other (Implication (Kin son $x $y) (Member $x male)) (CTV (STV 1 0.99) (STV 0 0.001)))`.
  Master and branch alike: cold uncle `(.99999977, .89795)`, immediate repeat `(.98767, .01285)`;
  aunt_or_uncle first, then uncle `[]`, its repeat `(.98767, .01285)`. Forward, on #181 case 1 with the same
  extra rule, the branch publishes `(Kin son elliott (exists male_son 0 (elliott)))` at `(.72733, .00765)`
  (master `(.72733, .00765)`), though male and child stay at `(.8, .9)`. Excluding r's row itself needs
  rows or applications as dependency nodes, a structural change not made here.
- An inverse added as a raw addition, with no source in the catalog, has no forward applications and keeps
  master's exclusions.
- Not a convergence fix (from #180): with a zero-confidence negative branch the cycle variant can still run
  out at 2,000 steps; `(STV 0.5 0)` still shows budget-order transients; repeated queries keep nonzero
  conditioning debt.
- Forward and backward runs share formulas and dependency checks but not schedules or deep-root allowances;
  parity is measured on the issue fixtures (within `0.001`), not promised in general.
- The general shared-premise confidence model (#175) and the overlap cap are unchanged.

## Draft reply to the #181 reporter (not posted)

Thanks for the precise repro; all three outputs reproduced. Three defects interacted. Forward joins did not
register the stored facts they read, so two routes over one uncertain fact looked independent and were merged
as if they were two observations (case 2). Publishing the forward results switched the evaluation policy
before reading them, so an already conditioned merge was replaced by an unpaid fallback (case 3). And the
automatic inverse of `male_son` concludes a son with a generated parent; it excluded only that generated
son, so the known `son(elliott, stanley)` that predicted `male(elliott)` came back as evidence for a new son
(case 1). Now forward joins use the same dependency registry as backward answers, forward mode stays on
until publication, and an inverse no longer reads its own rule's prediction as an observation: it excludes the facts
that rule used to predict what it inverts. After `forward_chain(all_facts(), steps=2000)` the stored son stays `(0.8 0.9)`,
the child, male, parent and sibling consequences are about `(0.8 0.9)` and agree with backward queries, and no
existential term is created. An independently observed `male` can still support an inverse witness, which is
intended. Regression tests cover repeated saturation and both negative branches. With `(STV 0.0 1.0)` the
same values hold.

## Draft reply to the #180 reporter (not posted)

Thanks for the complete repro. Two separate problems caused it. An inverse could take a consequence of an
existing witness as an observation for a new witness (`son -> male` inverted into a son with a generated
parent), and that contaminated the sibling and completion chains feeding uncle (cases 4 and 6). And the
reconstruction of waiting answers could use the whole budget before shared-evidence conditioning ran, which
left the cycle case empty (case 5). The first is fixed: an inverse refuses its
own rule's prediction as an observation. Cases 3, 4 and 6 answer uncle, case 4 and case 6 both at
`(1, 0.892)`, each within .02 of its premise conjunction asked in a fresh engine, and re-queries no longer
move the answer. The second is not fixed: the cycle case (your case 5) still returns nothing at 2,000 steps.
Bounding that reconstruction lost other answers, so it is left as on master for now.

On "nothing follows when the premise fails": the neutral unknown branch is `(STV 0.5 0)`, not `(STV 0 1)`,
which says the conclusion never holds without the premise. A CTV is a conditional probability model, not an
execution guard, so finite-confidence premises still propagate uncertainty through both branches, and
confidence need not stay identical along a chain. For a positive-only extracted kinship KB, declare the
sampling policy before adding the rules (`h.set_positive_only_predicate("Kin")`,
`h.set_positive_only_predicate("male")`) and use plain STV rules: the stored positive examples then do not
estimate a population prior, and cases 4-6 answer identically with no conditioning debt. A rule meant to be
one-way can be named `(no_inverse g_son)`. The `(STV 0.5 0)` spelling alone still has budget-sensitive cases;
the fix covers your reported default-CTV cases 3, 4 and 6, not case 5 and not every branch policy.
