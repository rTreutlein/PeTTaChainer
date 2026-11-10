# 8538013b vs adcd18f0-df7f4f432 (canary)

**PASS**

accuracy identical in all 6 cases.

- base: `8538013b` = 8538013b18de3e7bdbc94b298d964e821e5c342f, runtime tree dd6a51d81d24, runs build `0b15c356-dc39c2b78` (same tree)
- candidate: `adcd18f0-df7f4f432` = adcd18f027eae75ad7499ca780464574ea4ae8c4+f7f4f432, runtime tree c151b12d6114, runs build `7ecfdad9-dbeb6a684` (same tree)
- ChainerGame: supply `3daf989e93 supply-network`, replay `d274b45767 bench-hooks`; PeTTa runtime 18c99706738d76f4
- 6 cases; 6 runs executed, 6 of 12 results reused from the store; 9 s wall, 0 CPU-s
- load: 1-1 pool slots held during this comparison's runs (cpu target 24)

Thresholds: error/Brier worse by >5% relative and >0.002 absolute (per row, also per kind); coverage drop >0.001; regret worse by >5% and >0.05 (agreement reported, never flagged); mined-rule search paid steps >10% and >1 more; fuzz flagged KBs up by any; seconds >10% and >1 s worse; peak RSS >35% and >300 MB higher; a run that fails only for the candidate. A timing flag counts only if a paired rerun repeats it. Timing not taken side by side, at loads whose calibrated slowdowns differ by more than 5%, is marked `load differs` and not flagged. `reused` marks results from the store (the same code ran this case before).

## Cases

Each case's points along its budget curve, low to high budget.

| suite | case | budgets | base error | candidate error | base s | candidate s |
|---|---|---|---|---|---|---|
| ona | conditioning s1 |  | 0 | 0 | 9.949 | 10.41 |
| ona | identitymatching s8 |  | 0.4375 | 0.4375 | 13.75 | 12.43 |
| live | s1 | 50 | 0.105 | 0.105 | 9.857 | 9.267 |
| conflict | pln-stated l s1 | 4 | 0.0321 | 0.0321 | 26.23 | 22.57 |
| conflict | pln-reliable l s1 | 4 | 0.05407 | 0.05407 | 68.54 | 54.15 |
| scale | m s1 | 4 | 0.002646 | 0.002646 | 33.27 | 26.58 |

## Suite totals

| suite | base s | candidate s | delta | base peak MB | candidate peak MB |
|---|---|---|---|---|---|
| ona | 23.7 | 22.8 | -0.9 (-4%) | 251 | 252 |
| live | 9.9 | 9.3 | -0.6 (-6%) | 291 | 294 |
| conflict | 94.8 | 76.7 | -18.0 (-19%) | 364 | 363 |
| scale | 33.3 | 26.6 | -6.7 (-20%) | 644 | 642 |

## StationOps replay belief streams

| case | beliefs | changed | max belief shift |
|---|---|---|---|
| b50 5 shifts s1 | 50 | identical | 0 |

## Quality per second

Error and chainer seconds side by side (seconds as measured; `s/round` where the case has rounds). `SLOWER AT EQUAL OR BETTER ERROR` marks a case whose error did not regress but whose seconds did: time spent for nothing.

| suite | case | base error | candidate error | base s | candidate s | candidate/base s | base s/round | candidate s/round | verdict |
|---|---|---|---|---|---|---|---|---|---|
| ona | conditioning s1 | 0 | 0 | 9.949 | 10.41 | 1.05 |  |  | ok |
| ona | identitymatching s8 | 0.4375 | 0.4375 | 13.75 | 12.43 | 0.9 |  |  | ok |
| live | b50 5 shifts s1 | 0.105 | 0.105 | 9.857 | 9.267 | 0.94 | 1.971 | 1.853 | ok |
| conflict | pln-stated l spq4 s1 | 0.0321 | 0.0321 | 26.23 | 22.57 | 0.86 |  |  | ok |
| conflict | pln-reliable l spq4 s1 | 0.05407 | 0.05407 | 68.54 | 54.15 | 0.79 |  |  | ok |
| scale | m spq4 r10 s1 | 0.002646 | 0.002646 | 33.27 | 26.58 | 0.8 | 3.327 | 2.658 | ok |

## Metrics

| suite | case | metric | base | candidate | delta | flag | reference | note |
|---|---|---|---|---|---|---|---|---|
| ona | conditioning s1 | error | 0 | 0 | 0 |  |  | base reused load differs |
| ona | conditioning s1 | seconds | 9.949 | 10.41 | 0.4619 |  |  | base reused load differs |
| ona | conditioning s1 | peak_mb | 227 | 226.7 | -0.3 |  |  | base reused load differs |
| ona | identitymatching s8 | error | 0.4375 | 0.4375 | 0 |  |  | base reused load differs |
| ona | identitymatching s8 | seconds | 13.75 | 12.43 | -1.322 |  |  | base reused load differs |
| ona | identitymatching s8 | peak_mb | 251.2 | 251.6 | 0.4 |  |  | base reused load differs |
| live | b50 5 shifts s1 | error | 0.105 | 0.105 | 0 |  |  | base reused load differs |
| live | b50 5 shifts s1 | brier | 0.03195 | 0.03195 | 0 |  |  | base reused load differs |
| live | b50 5 shifts s1 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| live | b50 5 shifts s1 | regret | 72.78 | 72.78 | 0 |  |  | base reused load differs |
| live | b50 5 shifts s1 | seconds | 9.857 | 9.267 | -0.5894 |  |  | base reused load differs |
| live | b50 5 shifts s1 | peak_mb | 290.9 | 294 | 3.1 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | error | 0.0321 | 0.0321 | 0 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | brier | 0.06763 | 0.06763 | 0 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | seconds | 26.23 | 22.57 | -3.652 |  |  | base reused load differs |
| conflict | pln-stated l spq4 s1 | peak_mb | 364.5 | 363.2 | -1.3 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | error | 0.05407 | 0.05407 | 0 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | brier | 0.07161 | 0.07161 | 0 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | seconds | 68.54 | 54.15 | -14.39 |  |  | base reused load differs |
| conflict | pln-reliable l spq4 s1 | peak_mb | 312.1 | 286.2 | -25.9 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | error | 0.002646 | 0.002646 | 0 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | brier | 0.08221 | 0.08221 | 0 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | seconds | 33.27 | 26.58 | -6.699 |  |  | base reused load differs |
| scale | m spq4 r10 s1 | peak_mb | 644.4 | 642.5 | -1.9 |  |  | base reused load differs |

## Error per kind

| suite | case | kind | base | candidate | delta | flag |
|---|---|---|---|---|---|---|
| ona | conditioning s1 | train | 0.275 | 0.275 | 0 |  |
| ona | conditioning s1 | test | 0 | 0 | 0 |  |
| ona | identitymatching s8 | train | 0.9 | 0.9 | 0 |  |
| ona | identitymatching s8 | test | 0.5 | 0.5 | 0 |  |
| ona | identitymatching s8 | novel | 0.375 | 0.375 | 0 |  |
| conflict | pln-stated l spq4 s1 | component | 0.03092 | 0.03092 | 0 |  |
| conflict | pln-stated l spq4 s1 | system | 0.03328 | 0.03328 | 0 |  |
| conflict | pln-reliable l spq4 s1 | component | 0.05288 | 0.05288 | 0 |  |
| conflict | pln-reliable l spq4 s1 | system | 0.05527 | 0.05527 | 0 |  |
| scale | m spq4 r10 s1 | blocked | 0.002533 | 0.002533 | 0 |  |
| scale | m spq4 r10 s1 | front | 0.01047 | 0.01047 | 0 |  |
| scale | m spq4 r10 s1 | past_front | 5.659e-05 | 5.659e-05 | 0 |  |
| scale | m spq4 r10 s1 | past_storm | 1.401e-05 | 1.401e-05 | 0 |  |
| scale | m spq4 r10 s1 | storm | 0.003985 | 0.003985 | 0 |  |

The CombiNet reference column is the revision backend (independent of the build).
