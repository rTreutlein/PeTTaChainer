# 8538013b vs 9f794665-dc054a3b9 (full)

**PASS**

accuracy identical in all 22 cases.

- base: `8538013b` = 8538013b18de3e7bdbc94b298d964e821e5c342f, runtime tree dd6a51d81d24, runs build `0b15c356-dc39c2b78` (same tree)
- candidate: `9f794665-dc054a3b9` = 9f794665c2cf87fa4cd7c0649f279fb0959fa0e2+c054a3b9, runtime tree 78b6248a80d8, runs build `9f794665-db37ba993` (same tree)
- ChainerGame: supply `3daf989e93 supply-network`, replay `d274b45767 bench-hooks`; PeTTa runtime 18c99706738d76f4
- 23 cases; 37 runs executed, 8 of 45 results reused from the store; 150 s wall, 1442 CPU-s
- load: 21-24 pool slots held during this comparison's runs (cpu target 24)

Thresholds: error/Brier worse by >5% relative and >0.002 absolute (per row, also per kind); coverage drop >0.001; regret worse by >5% and >0.05 (agreement reported, never flagged); mined-rule search paid steps >10% and >1 more; fuzz flagged KBs up by any; seconds >10% and >1 s worse; peak RSS >35% and >300 MB higher; a run that fails only for the candidate. A timing flag counts only if a paired rerun repeats it. Timing not taken side by side, at loads whose calibrated slowdowns differ by more than 5%, is marked `load differs` and not flagged. `reused` marks results from the store (the same code ran this case before).

## Cases

Each case's points along its budget curve, low to high budget.

| suite | case | budgets | base error | candidate error | base s | candidate s |
|---|---|---|---|---|---|---|
| supplynet | stage 1 s3 | 100 | 0.005123 | 0.005123 | 4.057 | 3.805 |
| supplynet | stage 3 timed s3 | 25 / 50 / 100 | 0.00382 / 0.001339 / 0.0007757 | 0.00382 / 0.001339 / 0.0007757 | 7.817 / 11.41 / 13.81 | 6.786 / 12.14 / 12.3 |
| supplynet | stage 3 untimed s4 | 25 / 100 | 0.0003946 / 0.0003946 | 0.0003946 / 0.0003946 | 8.622 / 13.5 | 8.288 / 14.58 |
| supplynet | stage 3 timed soft0.9 s3 | 100 | 0.01055 | 0.01055 | 29.79 | 28.75 |
| supplynet | stage 3 untimed soft0.9 s4 | 100 | 0.01481 | 0.01481 | 43.29 | 46.08 |
| scale | l s1 | 4 / 16 | 0.003808 / 0.0009284 | 0.003808 / 0.0009284 | 56.87 / 120.4 | 47.12 / 120.1 |
| scale | s s1 | 1 | 0.01837 | 0.01837 | 2.315 | 2.35 |
| conflict | pln-sources m s2 | 4 | 0.07541 | 0.07541 | 17.83 | 16.02 |
| conflict | pln-sources m s3 | 4 | 0.1776 | 0.1776 | 13.53 | 13.35 |
| conflict | pln-reliable l s1 | 4 | 0.05407 | 0.05407 | 62.04 | 65.52 |
| learned | stage 3 timed learned s1 | 200 | 0.08152 | 0.08152 | 20.04 | 18.99 |
| supplynet | stage 4 extend s2 | 50 | 7.354e-17 | 7.354e-17 | 19.11 | 16.41 |
| learned | stage 3 timed learned s2 | 200 | 0.06016 | 0.06016 | 21.75 | 21.94 |
| learned | stage 3 untimed learned mined s3 | 50 | 0.2392 | 0.2392 | 81.65 | 76.22 |
| replay | s1 | 25 | 0.1076 | 0.1076 | 4.199 | 4.413 |
| replay | s4 | 25 | 0.1269 | 0.1269 | 5.623 | 4.821 |
| combinet | n2 s1 |  | 0.09231 | 0.09231 | 0.888 | 1.005 |
| fuzz | all s22 |  | 0.008164 | 0.008164 | 34 | 34 |

## Suite totals

| suite | base s | candidate s | delta | base peak MB | candidate peak MB |
|---|---|---|---|---|---|
| supplynet | 151.4 | 149.2 | -2.3 (-1%) | 259 | 262 |
| scale | 179.6 | 169.6 | -10.0 (-6%) | 1503 | 1505 |
| conflict | 93.4 | 94.9 | +1.5 (+2%) | 324 | 325 |
| learned | 123.4 | 117.1 | -6.3 (-5%) | 603 | 602 |
| replay | 9.8 | 9.2 | -0.6 (-6%) | 233 | 233 |
| combinet | 0.9 | 1.0 | +0.1 (+13%) | 151 | 149 |
| fuzz | 34.0 | 34.0 | +0.0 (+0%) | 161 | 159 |

## StationOps replay belief streams

| case | beliefs | changed | max belief shift |
|---|---|---|---|
| b25 s1 | 200 | identical | 0 |
| b25 s4 | 200 | identical | 0 |

## Fuzzer

Fuzz all n100 s22: 8 -> 8 flagged KBs; newly flagged: none; no longer flagged: none.
- base: 0 unsupported KBs (none); 0 crashes.
- candidate: 0 unsupported KBs (none); 0 crashes.

## Metrics

| suite | case | metric | base | candidate | delta | flag | reference | note |
|---|---|---|---|---|---|---|---|---|
| supplynet | stage 1 b100 s3 | error | 0.005123 | 0.005123 | 0 |  |  |  |
| supplynet | stage 1 b100 s3 | brier | 0.01031 | 0.01031 | 0 |  |  |  |
| supplynet | stage 1 b100 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 1 b100 s3 | seconds | 4.057 | 3.805 | -0.252 |  |  |  |
| supplynet | stage 1 b100 s3 | peak_mb | 193.2 | 193.1 | -0.1 |  |  |  |
| supplynet | stage 3 timed b25 s3 | error | 0.00382 | 0.00382 | 0 |  |  |  |
| supplynet | stage 3 timed b25 s3 | brier | 0.1726 | 0.1726 | 0 |  |  |  |
| supplynet | stage 3 timed b25 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 timed b25 s3 | seconds | 7.817 | 6.786 | -1.031 |  |  |  |
| supplynet | stage 3 timed b25 s3 | peak_mb | 201.3 | 200.7 | -0.6 |  |  |  |
| supplynet | stage 3 timed b50 s3 | error | 0.001339 | 0.001339 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | brier | 0.1712 | 0.1712 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 timed b50 s3 | seconds | 11.41 | 12.14 | 0.739 |  |  |  |
| supplynet | stage 3 timed b50 s3 | peak_mb | 216.9 | 218.8 | 1.9 |  |  |  |
| supplynet | stage 3 timed b100 s3 | error | 0.0007757 | 0.0007757 | 0 |  |  | reused load differs |
| supplynet | stage 3 timed b100 s3 | brier | 0.1711 | 0.1711 | 0 |  |  | reused load differs |
| supplynet | stage 3 timed b100 s3 | coverage | 1 | 1 | 0 |  |  | reused load differs |
| supplynet | stage 3 timed b100 s3 | seconds | 13.81 | 12.3 | -1.506 |  |  | reused load differs |
| supplynet | stage 3 timed b100 s3 | peak_mb | 228.9 | 228.6 | -0.3 |  |  | reused load differs |
| supplynet | stage 3 untimed b25 s4 | error | 0.0003946 | 0.0003946 | 0 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | brier | 0.1319 | 0.1319 | 0 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | seconds | 8.622 | 8.288 | -0.334 |  |  |  |
| supplynet | stage 3 untimed b25 s4 | peak_mb | 191.2 | 192.1 | 0.9 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | error | 0.0003946 | 0.0003946 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | brier | 0.1319 | 0.1319 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | seconds | 13.5 | 14.58 | 1.081 |  |  |  |
| supplynet | stage 3 untimed b100 s4 | peak_mb | 217.2 | 217.8 | 0.6 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | error | 0.01055 | 0.01055 | 0 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | brier | 0.1731 | 0.1731 | 0 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | coverage | 0.9975 | 0.9975 | 0 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | seconds | 29.79 | 28.75 | -1.04 |  |  |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | peak_mb | 252.9 | 254.9 | 2 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | error | 0.01481 | 0.01481 | 0 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | brier | 0.1376 | 0.1376 | 0 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | coverage | 0.984 | 0.984 | 0 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | seconds | 43.29 | 46.08 | 2.787 |  |  |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | peak_mb | 259.4 | 261.9 | 2.5 |  |  |  |
| scale | l spq4 s1 | error | 0.003808 | 0.003808 | 0 |  |  |  |
| scale | l spq4 s1 | brier | 0.0432 | 0.0432 | 0 |  |  |  |
| scale | l spq4 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | l spq4 s1 | seconds | 56.87 | 47.12 | -9.747 |  |  |  |
| scale | l spq4 s1 | peak_mb | 994.3 | 994.9 | 0.6 |  |  |  |
| scale | l spq16 s1 | error | 0.0009284 | 0.0009284 | 0 |  |  |  |
| scale | l spq16 s1 | brier | 0.04303 | 0.04303 | 0 |  |  |  |
| scale | l spq16 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | l spq16 s1 | seconds | 120.4 | 120.1 | -0.328 |  |  |  |
| scale | l spq16 s1 | peak_mb | 1503 | 1505 | 2.4 |  |  |  |
| scale | s spq1 s1 | error | 0.01837 | 0.01837 | 0 |  |  |  |
| scale | s spq1 s1 | brier | 0.1587 | 0.1587 | 0 |  |  |  |
| scale | s spq1 s1 | coverage | 1 | 1 | 0 |  |  |  |
| scale | s spq1 s1 | seconds | 2.315 | 2.35 | 0.035 |  |  |  |
| scale | s spq1 s1 | peak_mb | 171.8 | 172.2 | 0.4 |  |  |  |
| conflict | pln-sources m spq4 s2 | error | 0.07541 | 0.07541 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | brier | 0.1078 | 0.1078 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | coverage | 0.9875 | 0.9875 | 0 |  |  |  |
| conflict | pln-sources m spq4 s2 | seconds | 17.83 | 16.02 | -1.816 |  |  |  |
| conflict | pln-sources m spq4 s2 | peak_mb | 258.7 | 260.7 | 2 |  |  |  |
| conflict | pln-sources m spq4 s3 | error | 0.1776 | 0.1776 | 0 |  |  |  |
| conflict | pln-sources m spq4 s3 | brier | 0.1352 | 0.1352 | 0 |  |  |  |
| conflict | pln-sources m spq4 s3 | coverage | 1 | 1 | 0 |  |  |  |
| conflict | pln-sources m spq4 s3 | seconds | 13.53 | 13.35 | -0.173 |  |  |  |
| conflict | pln-sources m spq4 s3 | peak_mb | 265.6 | 265.2 | -0.4 |  |  |  |
| conflict | pln-reliable l spq4 s1 | error | 0.05407 | 0.05407 | 0 |  |  |  |
| conflict | pln-reliable l spq4 s1 | brier | 0.07161 | 0.07161 | 0 |  |  |  |
| conflict | pln-reliable l spq4 s1 | coverage | 1 | 1 | 0 |  |  |  |
| conflict | pln-reliable l spq4 s1 | seconds | 62.04 | 65.52 | 3.488 |  |  |  |
| conflict | pln-reliable l spq4 s1 | peak_mb | 324.4 | 325 | 0.6 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | error | 0.08152 | 0.08152 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | brier | 0.1162 | 0.1162 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | coverage | 1 | 1 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | seconds | 20.04 | 18.99 | -1.055 |  |  |  |
| learned | stage 3 timed learned b50 r200 s1 | peak_mb | 297.1 | 296.9 | -0.2 |  |  |  |
| supplynet | stage 4 extend b50 s2 | error | 7.354e-17 | 7.354e-17 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | brier | 0.1894 | 0.1894 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | coverage | 1 | 1 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | seconds | 19.11 | 16.41 | -2.695 |  |  |  |
| supplynet | stage 4 extend b50 s2 | regret | 0 | 0 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | agreement | 1 | 1 | 0 |  |  |  |
| supplynet | stage 4 extend b50 s2 | peak_mb | 233.7 | 232.8 | -0.9 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | error | 0.06016 | 0.06016 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | brier | 0.1837 | 0.1837 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | coverage | 1 | 1 | 0 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | seconds | 21.75 | 21.94 | 0.188 |  |  |  |
| learned | stage 3 timed learned b50 r200 s2 | peak_mb | 297.6 | 299.2 | 1.6 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | error | 0.2392 | 0.2392 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | brier | 0.2906 | 0.2906 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | coverage | 0.9643 | 0.9643 | 0 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | seconds | 81.65 | 76.22 | -5.428 |  |  |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | peak_mb | 603.4 | 602.2 | -1.2 |  |  |  |
| replay | b25 s1 | error | 0.1076 | 0.1076 | 0 |  |  |  |
| replay | b25 s1 | brier | 0.04388 | 0.04388 | 0 |  |  |  |
| replay | b25 s1 | coverage | 1 | 1 | 0 |  |  |  |
| replay | b25 s1 | regret | 627.5 | 627.5 | 0 |  |  |  |
| replay | b25 s1 | seconds | 4.199 | 4.413 | 0.2138 |  |  |  |
| replay | b25 s1 | peak_mb | 232.1 | 231.7 | -0.4 |  |  |  |
| replay | b25 s4 | error | 0.1269 | 0.1269 | 0 |  |  | reused load differs |
| replay | b25 s4 | brier | 0.07751 | 0.07751 | 0 |  |  | reused load differs |
| replay | b25 s4 | coverage | 1 | 1 | 0 |  |  | reused load differs |
| replay | b25 s4 | regret | 229.4 | 229.4 | 0 |  |  | reused load differs |
| replay | b25 s4 | seconds | 5.623 | 4.821 | -0.8019 |  |  | reused load differs |
| replay | b25 s4 | peak_mb | 233.3 | 233.2 | -0.1 |  |  | reused load differs |
| combinet | n2 s1 | error | 0.09231 | 0.09231 | 0 |  | 0.06702 | reused load differs |
| combinet | n2 s1 | brier | 0.1727 | 0.1727 | 0 |  | 0.175 | reused load differs |
| combinet | n2 s1 | coverage | 0.91 | 0.91 | 0 |  | 1 | reused load differs |
| combinet | n2 s1 | seconds | 0.888 | 1.005 | 0.117 |  |  | reused load differs |
| combinet | n2 s1 | peak_mb | 151.1 | 149.4 | -1.7 |  |  | reused load differs |
| fuzz | all n100 s22 | flagged | 8 | 8 | 0 |  |  |  |
| fuzz | all n100 s22 | unsupported | 0 | 0 | 0 |  |  |  |
| fuzz | all n100 s22 | crashed | 0 | 0 | 0 |  |  |  |
| fuzz | all n100 s22 | error | 0.008164 | 0.008164 | 0 |  |  |  |
| fuzz | all n100 s22 | answered | 365 | 365 | 0 |  |  |  |
| fuzz | all n100 s22 | seconds | 34 | 34 | 0 |  |  |  |
| fuzz | all n100 s22 | peak_mb | 161.4 | 158.8 | -2.6 |  |  |  |

## Error per kind

| suite | case | kind | base | candidate | delta | flag |
|---|---|---|---|---|---|---|
| supplynet | stage 1 b100 s3 | blocked | 0.0007851 | 0.0007851 | 0 |  |
| supplynet | stage 1 b100 s3 | storm | 0.0172 | 0.0172 | 0 |  |
| supplynet | stage 3 timed b25 s3 | blocked | 5.516e-11 | 5.516e-11 | 0 |  |
| supplynet | stage 3 timed b25 s3 | degraded | 0.008598 | 0.008598 | 0 |  |
| supplynet | stage 3 timed b25 s3 | previous_storm | 2.596e-10 | 2.596e-10 | 0 |  |
| supplynet | stage 3 timed b25 s3 | producing | 0.002064 | 0.002064 | 0 |  |
| supplynet | stage 3 timed b25 s3 | producing_unstocked | 0.01786 | 0.01786 | 0 |  |
| supplynet | stage 3 timed b25 s3 | storm | 6.007e-11 | 6.007e-11 | 0 |  |
| supplynet | stage 3 timed b50 s3 | blocked | 5.099e-11 | 5.099e-11 | 0 |  |
| supplynet | stage 3 timed b50 s3 | degraded | 0.008651 | 0.008651 | 0 |  |
| supplynet | stage 3 timed b50 s3 | previous_storm | 2.4e-10 | 2.4e-10 | 0 |  |
| supplynet | stage 3 timed b50 s3 | producing | 0.001932 | 0.001932 | 0 |  |
| supplynet | stage 3 timed b50 s3 | producing_unstocked | 2.082e-17 | 2.082e-17 | 0 |  |
| supplynet | stage 3 timed b50 s3 | storm | 5.554e-11 | 5.554e-11 | 0 |  |
| supplynet | stage 3 timed b100 s3 | blocked | 5.099e-11 | 5.099e-11 | 0 |  |
| supplynet | stage 3 timed b100 s3 | degraded | 0.003897 | 0.003897 | 0 |  |
| supplynet | stage 3 timed b100 s3 | previous_storm | 2.4e-10 | 2.4e-10 | 0 |  |
| supplynet | stage 3 timed b100 s3 | producing | 0.00377 | 0.00377 | 0 |  |
| supplynet | stage 3 timed b100 s3 | producing_unstocked | 2.082e-17 | 2.082e-17 | 0 |  |
| supplynet | stage 3 timed b100 s3 | storm | 5.554e-11 | 5.554e-11 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | blocked | 2.177e-17 | 2.177e-17 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | degraded | 0.001459 | 0.001459 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | previous_storm | 5.265e-17 | 5.265e-17 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | producing | 0.002016 | 0.002016 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | producing_unstocked | 0 | 0 | 0 |  |
| supplynet | stage 3 untimed b25 s4 | storm | 4.435e-17 | 4.435e-17 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | blocked | 2.674e-17 | 2.674e-17 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | degraded | 0.001459 | 0.001459 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | previous_storm | 6.221e-17 | 6.221e-17 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | producing | 0.002016 | 0.002016 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | producing_unstocked | 0 | 0 | 0 |  |
| supplynet | stage 3 untimed b100 s4 | storm | 5.962e-17 | 5.962e-17 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | blocked | 1.475e-09 | 1.475e-09 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | degraded | 0.007942 | 0.007942 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | previous_storm | 3.642e-09 | 3.642e-09 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | producing | 0.01038 | 0.01038 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | producing_unstocked | 0.06338 | 0.06338 | 0 |  |
| supplynet | stage 3 timed soft0.9 b100 s3 | storm | 1.311e-09 | 1.311e-09 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | blocked | 2.674e-17 | 2.674e-17 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | degraded | 0.001263 | 0.001263 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | previous_storm | 6.026e-17 | 6.026e-17 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | producing | 0.01998 | 0.01998 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | producing_unstocked | 0.09483 | 0.09483 | 0 |  |
| supplynet | stage 3 untimed soft0.9 b100 s4 | storm | 5.892e-17 | 5.892e-17 | 0 |  |
| scale | l spq4 s1 | blocked | 0.003087 | 0.003087 | 0 |  |
| scale | l spq4 s1 | front | 0.0113 | 0.0113 | 0 |  |
| scale | l spq4 s1 | past_front | 0.01026 | 0.01026 | 0 |  |
| scale | l spq4 s1 | past_storm | 0.002409 | 0.002409 | 0 |  |
| scale | l spq4 s1 | storm | 0.005013 | 0.005013 | 0 |  |
| scale | l spq16 s1 | blocked | 0.0009419 | 0.0009419 | 0 |  |
| scale | l spq16 s1 | front | 0.003009 | 0.003009 | 0 |  |
| scale | l spq16 s1 | past_front | 4.813e-05 | 4.813e-05 | 0 |  |
| scale | l spq16 s1 | past_storm | 1.104e-05 | 1.104e-05 | 0 |  |
| scale | l spq16 s1 | storm | 0.001499 | 0.001499 | 0 |  |
| scale | s spq1 s1 | blocked | 0.01205 | 0.01205 | 0 |  |
| scale | s spq1 s1 | front | 0.04346 | 0.04346 | 0 |  |
| scale | s spq1 s1 | past_front | 0.03911 | 0.03911 | 0 |  |
| scale | s spq1 s1 | past_storm | 0.01197 | 0.01197 | 0 |  |
| scale | s spq1 s1 | storm | 0.02221 | 0.02221 | 0 |  |
| conflict | pln-sources m spq4 s2 | component | 0.1201 | 0.1201 | 0 |  |
| conflict | pln-sources m spq4 s2 | system | 0.03076 | 0.03076 | 0 |  |
| conflict | pln-sources m spq4 s3 | component | 0.1745 | 0.1745 | 0 |  |
| conflict | pln-sources m spq4 s3 | system | 0.1808 | 0.1808 | 0 |  |
| conflict | pln-reliable l spq4 s1 | component | 0.05288 | 0.05288 | 0 |  |
| conflict | pln-reliable l spq4 s1 | system | 0.05527 | 0.05527 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | blocked | 0.09388 | 0.09388 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | degraded | 0.06221 | 0.06221 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | previous_storm | 0.1073 | 0.1073 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | producing | 0.04969 | 0.04969 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | producing_unstocked | 0 | 0 | 0 |  |
| learned | stage 3 timed learned b50 r200 s1 | storm | 0.1125 | 0.1125 | 0 |  |
| supplynet | stage 4 extend b50 s2 | blocked | 4.933e-17 | 4.933e-17 | 0 |  |
| supplynet | stage 4 extend b50 s2 | degraded | 6.617e-17 | 6.617e-17 | 0 |  |
| supplynet | stage 4 extend b50 s2 | previous_storm | 1.507e-16 | 1.507e-16 | 0 |  |
| supplynet | stage 4 extend b50 s2 | storm | 7.922e-17 | 7.922e-17 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | blocked | 0.05229 | 0.05229 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | degraded | 0.106 | 0.106 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | previous_storm | 0.0759 | 0.0759 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | producing | 0.06372 | 0.06372 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | producing_unstocked | 0 | 0 | 0 |  |
| learned | stage 3 timed learned b50 r200 s2 | storm | 0.08071 | 0.08071 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | blocked | 0.2228 | 0.2228 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | degraded | 0.1102 | 0.1102 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | previous_storm | 0.2493 | 0.2493 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | producing | 0.3481 | 0.3481 | 0 |  |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | storm | 0.2405 | 0.2405 | 0 |  |
| combinet | n2 s1 | causes | 0.07404 | 0.07404 | 0 |  |
| combinet | n2 s1 | interacting | 0.1196 | 0.1196 | 0 |  |
| combinet | n2 s1 | redundant | 0.06379 | 0.06379 | 0 |  |
| combinet | n2 s1 | signs | 0.1119 | 0.1119 | 0 |  |

The CombiNet reference column is the revision backend (independent of the build).
