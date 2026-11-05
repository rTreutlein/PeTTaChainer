# Master round: graph width after folding (Nov 5)

Branch `master-width`, base master `0fa2dafe`. Commits: `87521dd2` (bound after folding, budget
admission) and `b090315a` (per-key answer memo).

## Diagnosis (cp1)

The hypothesis held. In `event_graph.pl`, discovery (`graph_observations`, `Seen < 24`; `graph_barren`,
region `< 48`) and the unfolded model (`graph_atoms`, `M0 < 24`) counted raw statements before
`graph_fold`. In KE's two-report case, discovery visits 40 statements and builds 38 atoms (36 roots
plus 2 report conditionals), so the plan is `none`. Unveiling, Actor and their `And` got no proof, and
the joint fell back to the ordinary .8879. When the probe removes the bounds, the folded model is
6 atoms and 8 parameters.

## Fix

1. **Bound after folding.** `graph_blocks` computes the occurrence signatures, the structural half of
   `graph_fold`. `graph_model` rejects a plan whose folded parameter count (models − folded + one
   extra branch per conditional) is above 12. The check runs once per cached plan. The per-read
   `NA =< 12, NV =< 12` check is deleted. Discovery and the unfolded model keep a memory guard of 256
   statements and atoms. In a wide case that does not fold (30 chained reports), warm reads stay
   close to master: 0.016 s against 0.010 s.
2. **Budget zero (reviewer BLOCKER).** A key is admitted to the graph (`event_graph_admitted`)
   once a query with `sk_eval_budget > 0` needs or reads it. Admission costs one unit if the key has
   a model. `sk-need-roots!` calls `event-graph-prepay!`, which admits the root keys before
   `sk-evaluate!` spends the allowance. The roots are read after that. Admitted keys refresh at no
   step, as the `fact_absorption.md` contract requires. Unadmitted keys keep the ordinary read. A
   new `graph-evaluations` counter counts graph computations.

On master, budget 0 also computed graph answers for admitted small models (19 parts). That is
now gone as well.
3. **Warm budget zero (reviewer cp3 BLOCKER).** Every `sk-evaluate!` (through `sk-force-reset!`)
   and every epoch change cleared the numerical memo, so warm budget-0 reads recomputed unchanged
   graphs. The memo now keeps one answer per key and replaces it only when that key's numerical
   input changes. That also bounds its size by the number of keys. With budgets 0, 500, 0, 0, the
   reviewer's probe gives 0, 4, 0, 0 graph evaluations and full answers in the warm rounds. The
   test is `test_overlapping_reports_above_the_discovery_width_answer_exactly`.

## Results

- KE two reports: 8/8 answered. Unveiling and Actor .5000060005753695, `And` .2500090008630542,
  joint 1.39e-5. Subset bounds hold and repeats are stable. Confidence is .00062 against .00105
  with one report (a variance bound over more blocks).
- #150: master already answers it (STV 1 .9999, 0.03 s query). No change.
- Exactness: new tests check the folded result against unfolded `graph_moments` with partial
  overlap, Or and signed literals. An end-to-end test with 16+16 parts, 6 shared (26 roots, above
  the old bound), matches block enumeration to 1e-12, and budget 0 gives no answer there.
- Moved pin: `test_atomic_posterior` wide uncertain 30-part conjunction, c 0 → .0024905229.
  The test now computes this from the contract's moment formula. Strength is unchanged.
- Gates: verify PASS (key 0975ddccaedb). The fuzzer `--quick` run flags 3 `BLOCKER:flip`, as on
  master. compare `--quick` against master `5fb95905` PASS with 0 accuracy changes. `--full`
  PASS: one supplynet case changes by 1e-17 (float noise), and the fuzzer's flagged KBs stay at
  8 → 8. Canary against anchor `b4065459` PASS: the anchor flags (ona seconds, live b50 error)
  do not block, because the candidate is not worse than master.
- Reviewer tests: all pass except the neutral 40-part report.

## Deferred: inherited on master, assigned to later rounds

- The neutral 40-part report erases answers (the neutrality family, after #106). On master too, a
  certain `(STV .5 1)` compound wider than 12 parts loses every answer in its KB once any report
  is present (width 12 passes, 13 fails).
- Direct wide reports lose cold answers: the first batch is empty and the repeat is fine. This is
  likely #106's batch starvation, where one unsliced closed read consumes the allowance.
- The shared-rate error (#168).

## Limits

- Net core tokens +418, mostly comments. The round adds rather than deletes.
- Admitting more atoms brings more cases under #168, where instances that share a rate are treated
  as independent.
- The memo has one slot per key, so reads of one key under alternating exclusions recompute. Those
  recomputations are free once the key is admitted.
