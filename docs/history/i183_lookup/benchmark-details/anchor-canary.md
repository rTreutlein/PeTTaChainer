# b4065459 vs 8538013b-d61d9289e (canary)

**PASS**

accuracy changed in 4 of 6 cases: live b50 5 shifts s1, conflict pln-stated l spq4 s1, conflict pln-reliable l spq4 s1, scale m spq4 r10 s1.

Anchor flags block only where the candidate is also worse than master `8538013b` beyond the master thresholds (its comparison with the candidate on this profile: 0 runs executed, 0 CPU-s; false timing flags: 0).

Behind the anchor, on master too (not blocking, 6): ona identitymatching s8 seconds vs anchor 5.725 -> 8.316; live b50 5 shifts s1 error vs anchor 0.09813 -> 0.105; live b50 5 shifts s1 brier vs anchor 0.02632 -> 0.03195; live b50 5 shifts s1 regret vs anchor 59.78 -> 72.78; conflict pln-stated l spq4 s1 seconds vs anchor 9.124 -> 16.01; conflict pln-reliable l spq4 s1 seconds vs anchor 8.895 -> 38.14.

Progress toward the anchor (candidate better than master, 1): conflict pln-reliable l spq4 s1 seconds vs anchor 8.895 -> 38.14: master 68.54 -> candidate 61.79.

- base: `b4065459` = b40654592d561bdc91e27c1a50365571720ae137, runtime tree cc5754d2bc48, runs build `4b41839b` (same tree)
- candidate: `8538013b-d61d9289e` = 8538013b18de3e7bdbc94b298d964e821e5c342f+61d9289e, runtime tree 16e27adca7c2
- ChainerGame: supply `3daf989e93 supply-network`, replay `d274b45767 bench-hooks`; PeTTa runtime 18c99706738d76f4
- 6 cases; 11 runs executed, 6 of 12 results reused from the store; 103 s wall, 105 CPU-s
- load: 1-24 pool slots held during this comparison's runs (cpu target 24)

Thresholds: error/Brier worse by >5% relative and >0.002 absolute (per row, also per kind); coverage drop >0.001; regret worse by >5% and >0.05 (agreement reported, never flagged); mined-rule search paid steps >10% and >1 more; fuzz flagged KBs up by any; seconds >10% and >1 s worse; peak RSS >35% and >300 MB higher; a run that fails only for the candidate. A timing flag counts only if a paired rerun repeats it. Timing not taken side by side, at loads whose calibrated slowdowns differ by more than 5%, is marked `load differs` and not flagged. `reused` marks results from the store (the same code ran this case before).

Against the anchor: seconds worse by >15% and >1 s per case, each run's seconds divided by the calibrated slowdown of its load (the anchor's timing is stored once); a slowdown beyond 30%, or a peak RSS over twice the anchor's, is flagged without a rerun, a smaller one only if a paired rerun repeats it. Accuracy thresholds as above. A case the anchor cannot run is not compared.

## Cases

Each case's points along its budget curve, low to high budget.

| suite | case | budgets | base error | candidate error | base s | candidate s |
|---|---|---|---|---|---|---|
| ona | conditioning s1 |  | 0 | 0 | 4.555 | 9.094 |
| ona | identitymatching s8 |  | 0.4375 | 0.4375 | 5.725 | 13.47 |
| live | s1 | 50 | 0.09813 | 0.105 | 4.755 | 8.691 |
| conflict | pln-stated l s1 | 4 | 0.3895 | 0.0321 | 9.124 | 25.94 |
| conflict | pln-reliable l s1 | 4 | 0.107 | 0.05407 | 8.895 | 61.79 |
| scale | m s1 | 4 | 0.003034 | 0.002646 | 19.37 | 33.31 |

## Suite totals

| suite | base s | candidate s | delta | base peak MB | candidate peak MB |
|---|---|---|---|---|---|
| ona | 10.3 | 22.6 | +12.3 (+120%) | 179 | 248 |
| live | 4.8 | 8.7 | +3.9 (+83%) | 208 | 291 |
| conflict | 18.0 | 87.7 | +69.7 (+387%) | 243 | 363 |
| scale | 19.4 | 33.3 | +13.9 (+72%) | 460 | 643 |

## StationOps replay belief streams

| case | beliefs | changed | max belief shift |
|---|---|---|---|
| b50 5 shifts s1 | 50 | 50 | 0.1137 |

## Quality per second

Error and chainer seconds side by side (seconds as measured; `s/round` where the case has rounds). `SLOWER AT EQUAL OR BETTER ERROR` marks a case whose error did not regress but whose seconds did: time spent for nothing.

| suite | case | base error | candidate error | base s | candidate s | candidate/base s | base s/round | candidate s/round | verdict |
|---|---|---|---|---|---|---|---|---|---|
| ona | conditioning s1 | 0 | 0 | 4.555 | 9.094 | 2 |  |  | ok |
| ona | identitymatching s8 | 0.4375 | 0.4375 | 5.725 | 13.47 | 2.35 |  |  | SLOWER AT EQUAL OR BETTER ERROR |
| live | b50 5 shifts s1 | 0.09813 | 0.105 | 4.755 | 8.691 | 1.83 | 0.951 | 1.738 | worse error |
| conflict | pln-stated l spq4 s1 | 0.3895 | 0.0321 | 9.124 | 25.94 | 2.84 |  |  | SLOWER AT EQUAL OR BETTER ERROR |
| conflict | pln-reliable l spq4 s1 | 0.107 | 0.05407 | 8.895 | 61.79 | 6.95 |  |  | SLOWER AT EQUAL OR BETTER ERROR |
| scale | m spq4 r10 s1 | 0.003034 | 0.002646 | 19.37 | 33.31 | 1.72 | 1.937 | 3.331 | ok |

## Metrics

| suite | case | metric | base | candidate | delta | flag | reference | note |
|---|---|---|---|---|---|---|---|---|
| ona | conditioning s1 | error | 0 | 0 | 0 |  |  | base reused load differs |
| ona | conditioning s1 | seconds | 4.555 | 9.094 | 4.539 | load differs |  | base reused load differs |
| ona | conditioning s1 | peak_mb | 167.5 | 227.1 | 59.6 |  |  | base reused load differs |
| ona | identitymatching s8 | error | 0.4375 | 0.4375 | 0 |  |  | base reused load differs |
| ona | identitymatching s8 | seconds | 5.725 | 13.47 | 7.747 | REGRESSION |  | base reused load differs |
| ona | identitymatching s8 | peak_mb | 178.8 | 247.6 | 68.8 |  |  | base reused load differs |
| live | b50 5 shifts s1 | error | 0.09813 | 0.105 | 0.006893 | REGRESSION |  | base reused load differs |
| live | b50 5 shifts s1 | brier | 0.02632 | 0.03195 | 0.00563 | REGRESSION |  | base reused load differs |
| live | b50 5 shifts s1 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| live | b50 5 shifts s1 | regret | 59.78 | 72.78 | 13 | REGRESSION |  | base reused load differs |
| live | b50 5 shifts s1 | seconds | 4.755 | 8.691 | 3.936 |  |  | base reused load differs |
| live | b50 5 shifts s1 | peak_mb | 208.3 | 291.2 | 82.9 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | error | 0.3895 | 0.0321 | -0.3574 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | brier | 0.2322 | 0.06763 | -0.1645 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | coverage | 0.4375 | 1 | 0.5625 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | seconds | 9.124 | 25.94 | 16.82 | REGRESSION |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | peak_mb | 243.2 | 362.9 | 119.7 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | error | 0.107 | 0.05407 | -0.05294 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | brier | 0.08485 | 0.07161 | -0.01324 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | seconds | 8.895 | 61.79 | 52.9 | REGRESSION |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | peak_mb | 243.1 | 323 | 79.9 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | error | 0.003034 | 0.002646 | -0.0003874 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | brier | 0.08236 | 0.08221 | -0.0001577 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | seconds | 19.37 | 33.31 | 13.95 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | peak_mb | 459.7 | 643 | 183.3 |  |  | base reused load differs |

## Error per kind

| suite | case | kind | base | candidate | delta | flag |
|---|---|---|---|---|---|---|
| ona | conditioning s1 | train | 0.275 | 0.275 | 0 |  |
| ona | conditioning s1 | test | 0 | 0 | 0 |  |
| ona | identitymatching s8 | train | 0.9 | 0.9 | 0 |  |
| ona | identitymatching s8 | test | 0.5 | 0.5 | 0 |  |
| ona | identitymatching s8 | novel | 0.375 | 0.375 | 0 |  |
| conflict | pln-stated l spq4 s1 | component | 0.3432 | 0.03092 | -0.3123 |  |
| conflict | pln-stated l spq4 s1 | system | 0.4358 | 0.03328 | -0.4025 |  |
| conflict | pln-reliable l spq4 s1 | component | 0.0976 | 0.05288 | -0.04473 |  |
| conflict | pln-reliable l spq4 s1 | system | 0.1164 | 0.05527 | -0.06115 |  |
| scale | m spq4 r10 s1 | blocked | 0.002887 | 0.002533 | -0.0003542 |  |
| scale | m spq4 r10 s1 | front | 0.01172 | 0.01047 | -0.001254 |  |
| scale | m spq4 r10 s1 | past_front | 0.0005941 | 5.659e-05 | -0.0005375 |  |
| scale | m spq4 r10 s1 | past_storm | 0.0001208 | 1.401e-05 | -0.0001068 |  |
| scale | m spq4 r10 s1 | storm | 0.004474 | 0.003985 | -0.0004892 |  |

The CombiNet reference column is the revision backend (independent of the build).
