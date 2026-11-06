# master-106b: lost Producing answers at KE's budget (#106)

Branch `master-106b` on 6138c0de. `be2524d8` runtime and docs, `aa9db100` regression test and fixture, `c1e9a3d1` c=0 rule and replay tariff.

## Diagnosis (21 missing keys: 7 timed, 14 untimed; 200 steps, k=800)

All 21 are Producing plant-a or plant-b. The row clashes (premises share history evidence through the soft reports), the graph declines (12-bit admission), and the plants are sink consequents with no population prior. The documented coarse answer also failed: rows never reached are not pending; `sk-compute` dropped the debt before an unpaid recompute; the discount needs an independent read, which fails when a premise has only a waiting answer.

| Where the budget went | Keys | Evidence |
|---|---|---|
| C2: one inline nested claim, no slice, never settles | 17 (4 timed, 13 untimed) | timed op 115: 400/400 units at b200, 2000/2000 at b1000, 8000/8000 at b4000, returns nothing |
| C3: identical claims repeated per consumer and retry | 3 timed | op 83: 8 claims, 3 distinct, 251 of 400 units repeats |
| C4: cold ordinary work | 1 untimed | op 72: 203 expansions, 811 row computes, no claims |

Plant-a t16 (.87175 against .87335) is the soft-report law on the ordinary route, not arithmetic: with hard reports the replay gives exactly .87335. Left as the documented ordinary-report-path deviation; this build gives .87234.

## Fix rules

- Only a row computation that left nothing unpaid settles its conditioning debt (`sk-compute`; `sk-pay!` no longer drops it).
- An unanswered public root reads its waiting answer from every row without a view that waits or was never computed. A computed, paid row that derived nothing does not qualify.
- With no independent read nothing measures the error, so the answer is the representative's mean at c=0. (cp2's c/2 published plant-a t6 at 4.4 sd from exact; coordinator's rule.)
- Representative reads are billed to the evaluation allowance at the conditioned-row tariff, two rows per unit. Before the conditions phase each root without a value buys its answer from an equal share of what is left: roots with no answer first, then roots with only their prior. The fixed 256/128 allowance is gone.
- A nested conditioned read outside a claim takes its approximation and its row waits as debt; only a row the conditions phase granted opens the claim. `sk-deepen` starts at depth 1 and deepens only after a depth cut. The depth-64 cap and marker are gone. This also removes C3's repeats.

Rejected: D3, a clash keeping its independent read. It had lower error, but counts shared facts twice and reverses a standing decision (coordinator).

## KE replay (200 steps, k=800), 6138c0de to this build

| Replay | Answered | Error | Producing unstocked error | Per key |
|---|---|---|---|---|
| Timed | 396/403 to **403/403** | .014508 to **.006520** | .0882 to .0352 | 106 changed, 95 better, 2 worse |
| Untimed | 362/376 to **375/376** | .024064 to **.005692** | .1608 to .0283 | 66 changed, 55 better, 7 worse |

Worse keys are budget trade-offs: plants are funded first, so some mine and power-plant keys keep their prior instead of a waiting STV 0. Scored error also rises where an answer replaces the .5 fill near .5 (plant-a t17, .005 to .104; published at c=0).

KE saved requests (240): lost 0, gained 0, changed 0 against d6207b87. Capacity replays (42): nothing lost against d6207b87; the six isolation requests answer in both modes, and owners-13 at budget 1 gains one answer. The d6207b87 baseline predates #169, so the isolation recovery is not attributed to this round.

## Calibration against exact references

- Reviewer's `test_clash_calibration` (plant-a t6, t14): passes. t6 is STV(.0414, 0), t14 STV(0, 0).
- Timed, all 80 Producing keys: beyond 2 sd 12 to 9, none new; mean error against exact .0637 to .0265.
- Waiting answers with an independent read, timed (measured on the same code path before the tariff): 8, of which 2 are beyond 2 sd, both identical on baseline: power-plant t19 STV(.547, .108) exact .738 (3.8 sd), plant-b t20 STV(.337, .118) exact .199 (3.1 sd). No discount added.
- No independent read (c=0), timed: 10 keys, 0 beyond 2 sd.
- Untimed cannot be judged: the reference program does not fit that history (differs from the world posterior by more than .2 on 22 of 80 keys).

## Gates (code c1e9a3d1)

- `verify.sh`: PASS, key 90ddf6cd5375.
- `compare.sh master --quick`: PASS, accuracy changed in 0 cases.
- `compare.sh master --full --no-fail-fast`: PASS, 2 of 22 changed, both better. Stage 3 timed soft0.9 b100: error .01454 to .01055, coverage .9826 to .9975. Untimed: .01894 to .01483, .9707 to .984. One timing flag, not repeated by its paired rerun.
- Canary: PASS, changed in 4 of 6. `live b50` is flagged against the anchor (.09813 to .105) with the same values on 6138c0de, so it is inherited.
- `--curves`: 9 cases, 7 unchanged. Stage 3 timed soft0.9: b25 .01598 to .02323 (worse), b100 .01454 to .01055, b400 .01453 to .00629; error now falls with budget, flat on base. Conflict m s1: b4 .09345 to .09706, 3.9%, below the flag threshold.
- Multi-seed aggregate: not run, no flag looked like lucky-master.

Reports: `bench/results/compare/6138c0de_vs_c1e9a3d1_{quick,full,curves}`, `anchor-b4065459_vs_c1e9a3d1_canary`.

## b76000 stack overflow

Not repaired by C2. Mine t18 + Storm north t17 at op 131 still exceeds 7.5 GB on both trees, after about 360 s, at about 650-670K choice points. The stack now reaches the dependency-mask folds with far fewer conditioned rows (1,146 on the first candidate run). b4000 and b20000 answer on both with matching values and RSS (about 6 GB at b20000); memory growth with budget is inherited.

## Keys left unanswered

| Budget | Keys |
|---|---|
| b200, k=800 | untimed plant-b t3 |
| b100, k=5 | timed plant-a t6; untimed plant-a t4, plant-b t13, both plants t15, both plants t16 |
| b25, k=5 | timed plant-a t6, t10, t13, t14, t15, t17; plant-b t13, t19, t20 |

Baseline answered plant-a t10 and plant-b t20 at b25, so those two are lost answers, a direct cost of billing representative reads. At b100 and b200 coverage is up everywhere measured.

## Tokens

Core o200k +521 (329,651 to 330,172). Estimate -40 to +120, +478 accepted by the coordinator; the c=0 clause adds +43 because it must destructure the value. Moved code (`sk-clash-waiting`, `sk-waiting-root-value`, `sk-population-prior`, to `work.metta`) is neutral.

## Moved test values

None. New: `tests/test_issue106_batch_coverage.py` (3 tests, all fail on 6138c0de), `tests/fixtures/issue106_timed_prefix.json`.

## Limits

- Waiting answers with an independent read can still be overconfident (2 of 8 timed, inherited).
- Population-prior answers are also beyond 2 sd on several keys (mine t14, t15, t17), inherited.
- Low-budget cost at b25 as above. Representative shares can be wasted on roots the graph would answer; not measured.
- Reviewer's inherited blockers untouched: budget-0 plan construction, three fuzzer flips.
- Untimed calibration unverified. Curves were run at k=5, the KE replay at k=800.
