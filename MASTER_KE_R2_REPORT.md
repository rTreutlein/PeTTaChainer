# Master KE R2: identity grouping + the .818 fix

Brief: `bench/results/fresh-design/master-ke-r2-brief.md`; design: `master-ke-correctness-design.md`
(targets C and D). Branch `master-ke-r2`, worktree `.claude/worktrees/master-ke-r2`, base `dad80ddc`.
Parallel-reviewer pilot: checkpoints `master-ke-r2-checkpoints/cp1..cp4.patch`; reviewer files in
`master-ke-r2-review/`.

## Commits

- `c1ecd14e` Read KE identity worlds as one compound with the graph posterior (runtime + tests).
- this report.

## Diagnosis (on `dad80ddc`, confirmed)

| probe | master | reference |
|---|---|---|
| soft identity Q (report s=1, bridge) | 1.0 / c .8177 | <= P(I) = 7201/7208 = .99903 |
| same, s = .8 / .5 / .2 | .8 / none / .2 | .36352 / .125 / .03450 |
| hard Not(I): ground Q | .0562 / c .0042 | 0 |
| reviewer computed world beside certain judgment (O/C, A) | .9762 / .6 | .8912891216 / .7071122230 |

C: the conjunction's parts were read one by one (product of marginals). D: the bridge's uncertain-STV
producer made discovery reject the whole identity model, and Q's conditioning weight read the raw
stored report.

## Design (one mechanism per target)

1. **Grouping** (`compiler/source_lowering.metta`, `compound-parts`): in an `And` with an implication
   part and >= 2 world parts, the world parts become one `And` key read first; judgments and
   computations follow in order. Computations (`source-computation-head?`, Not excepted) are not world
   parts. A variable-headed part is a world part (guard needed: the Atom-typed `case` otherwise binds
   the head to `Compute`).
2. **Barren pruning** (`prolog/event_graph.pl`, `graph_barren`): an unsupported, non-goal statement is
   dropped when its region beyond the discovered statements (catalog neighbours, compound projections
   included, bounded at 48) holds no evidence. A source counts as evidence unless its Pearl factor is
   exactly .5 (cp2 reviewer blocker). A model needing a pruned statement as a parent still fails in
   `graph_atoms`. The region is watched.
3. **One value per compound** (`runtime/evaluator/core.metta`, `sk-report-posterior`): every compound
   key the graph models takes its posterior whoever reads it outside a condition — in `sk-merge-key`
   and in `sk-compatible-value` (the stored-pin conditioning weight). cp4 widened this from stored
   compounds to all compounds (cp3 reviewer blocker).
4. Admission fixes the wider reads exposed: family admission needs a *sourced antecedent* (was: any
   sourced root anywhere — leaked .75 into an Assuming world); a sourceless root goal no factor or rule
   reads is refused (kept `(Implemented Split1)` unanswered).
5. Neutral node messages are kept (`event_values.pl`) and existential folds keep confidence-0
   witnesses (`folds.metta`), so s = .5 and the KE existential positives publish.

Rejected (measured): the graph posterior for *every* key (atoms too) in `sk-merge-key`: 9-10 MeTTa
files move (instance folds read graph values of their own members, .75 -> .50; positive-only roots
answered; base-rate cache, forgetting, foldall). Without exclusions only: 9 files still move. So the
design's deletion (the root-only graph call in `sk-root-key-value`, and `upward.metta`'s) is **not**
taken: atom roots still need it.

## Gates

- `scripts/verify.sh`: **PASS** (key `884085e0f886`; 163 MeTTa files, 1,087 Python tests).
- Fuzzer `--quick` seed 1 (36.6 s, 21 cases, 61 runs): only **3 `flip`** (target F, known
  uncertain-STV follow-up); the 3 identity blockers are gone; ProbLog 0/3 flagged.
  `scratch/fuzz-quick/summary.md`.
- Reviewer tests: frozen suite 10 methods, only the 4 unsupported-STV leaf subtests fail (target F);
  `supplemental_neutral.py`, `supplemental_compound_neutral.py`, `supplemental_readers.py` PASS.
- `compare.sh master --quick`: **PASS**, accuracy changed in 0 cases
  (`bench/results/compare/dad80ddc_vs_c1ecd14e_quick/report.md`).
- `compare.sh master --full`: **PASS**, accuracy changed in 0 cases
  (`bench/results/compare/dad80ddc_vs_c1ecd14e_full/report.md`).
- Canary `compare.sh anchor --canary`: **PASS** (4 accuracy changes vs the anchor, inherited: 0 vs
  master in --quick/--full) (`bench/results/compare/anchor-b4065459_vs_c1ecd14e_canary/report.md`).

## Moved test values (all to independent references)

| test | old | new | reason |
|---|---|---|---|
| test_conditional_world_facts (KE 9/9) derived_ground/existential_bridge, explicit_conditional, existential_identity_control | 1.0, c > 0 | 7201/7208, c >= 0 | report is a likelihood on 3 uniform parts; c 0 is the graph's conservative bound (Q2, c-0 published). Still 9/9 positives, 0 false positives |
| test_double_negation_evidence.py explicit + overlapping bridge | 1.0 / .8177 (.4735) | P(I) at c .9 / .5 (.99903 / .99134), c <= .1 | same; proof still conditions once on the report |
| test_double_negation_evidence.metta ev68Explicit | (1.0 .8178) | (.99903 0.0) | same |
| test_bridge_query_order | c .8177 | strength 7201/7208, c <= .1 | same |
| test_or_inversion LocalProblem | .69768 / .911 (factored revision) | .6976447619735168 / .7907 (graph node) | exact enumeration at count-law means, matches to 1e-16 |
| test_compound_key_reads V (orderKb, order2Kb) | .5668 | .5912 = .2 + .5 * P(Or) | consistent with the Or's own root answer .7824 |
| test_conjunction_implication_query, test_query_compute_in_compound | proof (conjunction a b r) | (conjunction (conjunction a b) ... r) | proof shape only; TV unchanged |
| test_quantified_judgments ground witness | (conjunction (by gen ..) (by mark ..)) | (node (conjunction (ctx proof) ..)) | proof shape only; TV 1 |

New `tests/test_identity_worlds.py`: certain-judgment equality at s = 1/.8/.5/.2, bridge bound incl.
both neutral spellings, hard-false zero, and the reviewer's computed-world readers (O/C, A).

## Limits

- **Tokens: +924 core** (source_lowering +302, event_graph +370, core +272, -20 elsewhere) against the
  ~+400 budget; the root-call deletion did not survive (see Rejected).
- Atom keys read inside rules still take the ordinary value; only compounds have the one-value rule.
- Identity answers publish at c ~ 0 (conservative compound variance bound); tightening is a follow-up.
- Hard Not(I) existential gives no answer (allowed); target F (uncertain-STV flips) not addressed.
