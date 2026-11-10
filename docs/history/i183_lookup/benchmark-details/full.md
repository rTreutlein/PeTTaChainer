# 8538013b vs 8538013b-d8ea83011 (full)

**PASS**

accuracy identical in all 22 cases.

- base: `8538013b` = 8538013b18de3e7bdbc94b298d964e821e5c342f, runtime tree dd6a51d81d24, runs build `0b15c356-dc39c2b78` (same tree)
- candidate: `8538013b-d8ea83011` = 8538013b18de3e7bdbc94b298d964e821e5c342f+8ea83011, runtime tree 16e27adca7c2
- ChainerGame: supply `3daf989e93 supply-network`, replay `d274b45767 bench-hooks`; PeTTa runtime 18c99706738d76f4
- 23 cases; 2 runs executed, 43 of 45 results reused from the store; 441 s wall, 273 CPU-s
- load: 17-17 pool slots held during this comparison's runs (cpu target 24)

Thresholds: error/Brier worse by >5% relative and >0.002 absolute (per row, also per kind); coverage drop >0.001; regret worse by >5% and >0.05 (agreement reported, never flagged); mined-rule search paid steps >10% and >1 more; fuzz flagged KBs up by any; seconds >10% and >1 s worse; peak RSS >35% and >300 MB higher; a run that fails only for the candidate. A timing flag counts only if a paired rerun repeats it. Timing not taken side by side, at loads whose calibrated slowdowns differ by more than 5%, is marked `load differs` and not flagged. `reused` marks results from the store (the same code ran this case before).

## Cases

Each case's points along its budget curve, low to high budget.

| suite | case | budgets | base error | candidate error | base s | candidate s |
|---|---|---|---|---|---|---|
| supplynet | stage 1 s3 | 100 | 0.005123 | 0.005123 | 4.847 | 4.587 |
| supplynet | stage 3 timed s3 | 25 / 50 / 100 | 0.00382 / 0.001339 / 0.0007757 | 0.00382 / 0.001339 / 0.0007757 | 7.075 / 11.47 / 13.81 | 7.045 / 12.01 / 13.29 |
| supplynet | stage 3 untimed s4 | 25 / 100 | 0.0003946 / 0.0003946 | 0.0003946 / 0.0003946 | 8.468 / 15.91 | 7.406 / 14.26 |
| supplynet | stage 3 timed soft0.9 s3 | 100 | 0.01055 | 0.01055 | 34.06 | 34.1 |
| supplynet | stage 3 untimed soft0.9 s4 | 100 | 0.01481 | 0.01481 | 44.25 | 41.24 |
| scale | l s1 | 4 / 16 | 0.003808 / 0.0009284 | 0.003808 / 0.0009284 | 53.73 / 119.2 | 52.46 / 118.2 |
| scale | s s1 | 1 | 0.01837 | 0.01837 | 2.759 | 2.587 |
| conflict | pln-sources m s2 | 4 | 0.07541 | 0.07541 | 20.41 | 16.74 |
| conflict | pln-sources m s3 | 4 | 0.1776 | 0.1776 | 13.31 | 13.08 |
| conflict | pln-reliable l s1 | 4 | 0.05407 | 0.05407 | 65.83 | 61.79 |
| learned | stage 3 timed learned s1 | 200 | 0.08152 | 0.08152 | 19.48 | 18.58 |
| supplynet | stage 4 extend s2 | 50 | 7.354e-17 | 7.354e-17 | 17.67 | 16.47 |
| learned | stage 3 timed learned s2 | 200 | 0.06016 | 0.06016 | 23.46 | 21.33 |
| learned | stage 3 untimed learned mined s3 | 50 | 0.2392 | 0.2392 | 77.99 | 78.15 |
| replay | s1 | 25 | 0.1076 | 0.1076 | 5.173 | 5.122 |
| replay | s4 | 25 | 0.1269 | 0.1269 | 5.623 | 5.432 |
| combinet | n2 s1 |  | 0.09231 | 0.09231 | 0.888 | 0.638 |
| fuzz | all s22 |  | 0.008164 | 0.008164 | 32 | 36 |

## Suite totals

| suite | base s | candidate s | delta | base peak MB | candidate peak MB |
|---|---|---|---|---|---|
| supplynet | 157.6 | 150.4 | -7.2 (-5%) | 262 | 260 |
| scale | 175.7 | 173.3 | -2.4 (-1%) | 1502 | 1501 |
| conflict | 99.6 | 91.6 | -7.9 (-8%) | 289 | 323 |
| learned | 120.9 | 118.1 | -2.9 (-2%) | 603 | 604 |
| replay | 10.8 | 10.6 | -0.2 (-2%) | 233 | 232 |
| combinet | 0.9 | 0.6 | -0.2 (-28%) | 151 | 151 |
| fuzz | 32.0 | 36.0 | +4.0 (+12%) | 160 | 160 |

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
| supplynet | stage 1 b100 s3 | error | 0.005123 | 0.005123 | 0 |  |  | reused |
| supplynet | stage 1 b100 s3 | brier | 0.01031 | 0.01031 | 0 |  |  | reused |
| supplynet | stage 1 b100 s3 | coverage | 1 | 1 | 0 |  |  | reused |
| supplynet | stage 1 b100 s3 | seconds | 4.847 | 4.587 | -0.26 |  |  | reused |
| supplynet | stage 1 b100 s3 | peak_mb | 193.8 | 191.9 | -1.9 |  |  | reused |
| supplynet | stage 3 timed b25 s3 | error | 0.00382 | 0.00382 | 0 |  |  | reused |
| supplynet | stage 3 timed b25 s3 | brier | 0.1726 | 0.1726 | 0 |  |  | reused |
| supplynet | stage 3 timed b25 s3 | coverage | 1 | 1 | 0 |  |  | reused |
| supplynet | stage 3 timed b25 s3 | seconds | 7.075 | 7.045 | -0.03 |  |  | reused |
| supplynet | stage 3 timed b25 s3 | peak_mb | 200.2 | 200.4 | 0.2 |  |  | reused |
| supplynet | stage 3 timed b50 s3 | error | 0.001339 | 0.001339 | 0 |  |  | reused |
| supplynet | stage 3 timed b50 s3 | brier | 0.1712 | 0.1712 | 0 |  |  | reused |
| supplynet | stage 3 timed b50 s3 | coverage | 1 | 1 | 0 |  |  | reused |
| supplynet | stage 3 timed b50 s3 | seconds | 11.47 | 12.01 | 0.533 |  |  | reused |
| supplynet | stage 3 timed b50 s3 | peak_mb | 219.6 | 219 | -0.6 |  |  | reused |
| supplynet | stage 3 timed b100 s3 | error | 0.0007757 | 0.0007757 | 0 |  |  | reused |
| supplynet | stage 3 timed b100 s3 | brier | 0.1711 | 0.1711 | 0 |  |  | reused |
| supplynet | stage 3 timed b100 s3 | coverage | 1 | 1 | 0 |  |  | reused |
| supplynet | stage 3 timed b100 s3 | seconds | 13.81 | 13.29 | -0.517 |  |  | reused |
| supplynet | stage 3 timed b100 s3 | peak_mb | 228.9 | 228.1 | -0.8 |  |  | reused |
| supplynet | stage 3 untimed b25 s4 | error | 0.0003946 | 0.0003946 | 0 |  |  | reused |
| supplynet | stage 3 untimed b25 s4 | brier | 0.1319 | 0.1319 | 0 |  |  | reused |
| supplynet | stage 3 untimed b25 s4 | coverage | 1 | 1 | 0 |  |  | reused |
| supplynet | stage 3 untimed b25 s4 | seconds | 8.468 | 7.406 | -1.062 |  |  | reused |
| supplynet | stage 3 untimed b25 s4 | peak_mb | 191 | 189.6 | -1.4 |  |  | reused |
| supplynet | stage 3 untimed b100 s4 | error | 0.0003946 | 0.0003946 | 0 |  |  | reused |
| supplynet | stage 3 untimed b100 s4 | brier | 0.1319 | 0.1319 | 0 |  |  | reused |
| supplynet | stage 3 untimed b100 s4 | coverage | 1 | 1 | 0 |  |  | reused |
| supplynet | stage 3 untimed b100 s4 | seconds | 15.91 | 14.26 | -1.658 |  |  | reused |
| supplynet | stage 3 untimed b100 s4 | peak_mb | 217.6 | 217.4 | -0.2 |  |  | reused |
| supplynet | stage 3 timed soft0.9 b100 s3 | error | 0.01055 | 0.01055 | 0 |  |  | reused |
| supplynet | stage 3 timed soft0.9 b100 s3 | brier | 0.1731 | 0.1731 | 0 |  |  | reused |
| supplynet | stage 3 timed soft0.9 b100 s3 | coverage | 0.9975 | 0.9975 | 0 |  |  | reused |
| supplynet | stage 3 timed soft0.9 b100 s3 | seconds | 34.06 | 34.1 | 0.044 |  |  | reused |
| supplynet | stage 3 timed soft0.9 b100 s3 | peak_mb | 246.7 | 253.8 | 7.1 |  |  | reused |
| supplynet | stage 3 untimed soft0.9 b100 s4 | error | 0.01481 | 0.01481 | 0 |  |  | reused |
| supplynet | stage 3 untimed soft0.9 b100 s4 | brier | 0.1376 | 0.1376 | 0 |  |  | reused |
| supplynet | stage 3 untimed soft0.9 b100 s4 | coverage | 0.984 | 0.984 | 0 |  |  | reused |
| supplynet | stage 3 untimed soft0.9 b100 s4 | seconds | 44.25 | 41.24 | -3.009 |  |  | reused |
| supplynet | stage 3 untimed soft0.9 b100 s4 | peak_mb | 261.8 | 259.7 | -2.1 |  |  | reused |
| scale | l spq4 s1 | error | 0.003808 | 0.003808 | 0 |  |  | reused |
| scale | l spq4 s1 | brier | 0.0432 | 0.0432 | 0 |  |  | reused |
| scale | l spq4 s1 | coverage | 1 | 1 | 0 |  |  | reused |
| scale | l spq4 s1 | seconds | 53.73 | 52.46 | -1.27 |  |  | reused |
| scale | l spq4 s1 | peak_mb | 994.4 | 994.7 | 0.3 |  |  | reused |
| scale | l spq16 s1 | error | 0.0009284 | 0.0009284 | 0 |  |  | reused |
| scale | l spq16 s1 | brier | 0.04303 | 0.04303 | 0 |  |  | reused |
| scale | l spq16 s1 | coverage | 1 | 1 | 0 |  |  | reused |
| scale | l spq16 s1 | seconds | 119.2 | 118.2 | -1 |  |  | reused |
| scale | l spq16 s1 | peak_mb | 1502 | 1501 | -1.1 |  |  | reused |
| scale | s spq1 s1 | error | 0.01837 | 0.01837 | 0 |  |  | reused |
| scale | s spq1 s1 | brier | 0.1587 | 0.1587 | 0 |  |  | reused |
| scale | s spq1 s1 | coverage | 1 | 1 | 0 |  |  | reused |
| scale | s spq1 s1 | seconds | 2.759 | 2.587 | -0.172 |  |  | reused |
| scale | s spq1 s1 | peak_mb | 172.4 | 172.2 | -0.2 |  |  | reused |
| conflict | pln-sources m spq4 s2 | error | 0.07541 | 0.07541 | 0 |  |  | reused |
| conflict | pln-sources m spq4 s2 | brier | 0.1078 | 0.1078 | 0 |  |  | reused |
| conflict | pln-sources m spq4 s2 | coverage | 0.9875 | 0.9875 | 0 |  |  | reused |
| conflict | pln-sources m spq4 s2 | seconds | 20.41 | 16.74 | -3.67 |  |  | reused |
| conflict | pln-sources m spq4 s2 | peak_mb | 261.3 | 259.1 | -2.2 |  |  | reused |
| conflict | pln-sources m spq4 s3 | error | 0.1776 | 0.1776 | 0 |  |  | reused |
| conflict | pln-sources m spq4 s3 | brier | 0.1352 | 0.1352 | 0 |  |  | reused |
| conflict | pln-sources m spq4 s3 | coverage | 1 | 1 | 0 |  |  | reused |
| conflict | pln-sources m spq4 s3 | seconds | 13.31 | 13.08 | -0.23 |  |  | reused |
| conflict | pln-sources m spq4 s3 | peak_mb | 264.7 | 264.9 | 0.2 |  |  | reused |
| conflict | pln-reliable l spq4 s1 | error | 0.05407 | 0.05407 | 0 |  |  | reused |
| conflict | pln-reliable l spq4 s1 | brier | 0.07161 | 0.07161 | 0 |  |  | reused |
| conflict | pln-reliable l spq4 s1 | coverage | 1 | 1 | 0 |  |  | reused |
| conflict | pln-reliable l spq4 s1 | seconds | 65.83 | 61.79 | -4.04 |  |  | reused |
| conflict | pln-reliable l spq4 s1 | peak_mb | 288.6 | 323 | 34.4 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s1 | error | 0.08152 | 0.08152 | 0 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s1 | brier | 0.1162 | 0.1162 | 0 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s1 | coverage | 1 | 1 | 0 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s1 | seconds | 19.48 | 18.58 | -0.905 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s1 | peak_mb | 296.5 | 295.9 | -0.6 |  |  | reused |
| supplynet | stage 4 extend b50 s2 | error | 7.354e-17 | 7.354e-17 | 0 |  |  | reused |
| supplynet | stage 4 extend b50 s2 | brier | 0.1894 | 0.1894 | 0 |  |  | reused |
| supplynet | stage 4 extend b50 s2 | coverage | 1 | 1 | 0 |  |  | reused |
| supplynet | stage 4 extend b50 s2 | seconds | 17.67 | 16.47 | -1.2 |  |  | reused |
| supplynet | stage 4 extend b50 s2 | regret | 0 | 0 | 0 |  |  | reused |
| supplynet | stage 4 extend b50 s2 | agreement | 1 | 1 | 0 |  |  | reused |
| supplynet | stage 4 extend b50 s2 | peak_mb | 233.7 | 232.8 | -0.9 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s2 | error | 0.06016 | 0.06016 | 0 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s2 | brier | 0.1837 | 0.1837 | 0 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s2 | coverage | 1 | 1 | 0 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s2 | seconds | 23.46 | 21.33 | -2.128 |  |  | reused |
| learned | stage 3 timed learned b50 r200 s2 | peak_mb | 298.3 | 299.6 | 1.3 |  |  | reused |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | error | 0.2392 | 0.2392 | 0 |  |  | reused |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | brier | 0.2906 | 0.2906 | 0 |  |  | reused |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | coverage | 0.9643 | 0.9643 | 0 |  |  | reused |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | seconds | 77.99 | 78.15 | 0.158 |  |  | reused |
| learned | stage 3 untimed learned mined b50 r50 h10 s3 | peak_mb | 602.9 | 604.4 | 1.5 |  |  | reused |
| replay | b25 s1 | error | 0.1076 | 0.1076 | 0 |  |  | reused |
| replay | b25 s1 | brier | 0.04388 | 0.04388 | 0 |  |  | reused |
| replay | b25 s1 | coverage | 1 | 1 | 0 |  |  | reused |
| replay | b25 s1 | regret | 627.5 | 627.5 | 0 |  |  | reused |
| replay | b25 s1 | seconds | 5.173 | 5.122 | -0.05139 |  |  | reused |
| replay | b25 s1 | peak_mb | 230.9 | 232.4 | 1.5 |  |  | reused |
| replay | b25 s4 | error | 0.1269 | 0.1269 | 0 |  |  | reused |
| replay | b25 s4 | brier | 0.07751 | 0.07751 | 0 |  |  | reused |
| replay | b25 s4 | coverage | 1 | 1 | 0 |  |  | reused |
| replay | b25 s4 | regret | 229.4 | 229.4 | 0 |  |  | reused |
| replay | b25 s4 | seconds | 5.623 | 5.432 | -0.1908 |  |  | reused |
| replay | b25 s4 | peak_mb | 233.3 | 231.9 | -1.4 |  |  | reused |
| combinet | n2 s1 | error | 0.09231 | 0.09231 | 0 |  | 0.06702 | reused |
| combinet | n2 s1 | brier | 0.1727 | 0.1727 | 0 |  | 0.175 | reused |
| combinet | n2 s1 | coverage | 0.91 | 0.91 | 0 |  | 1 | reused |
| combinet | n2 s1 | seconds | 0.888 | 0.638 | -0.25 |  |  | reused |
| combinet | n2 s1 | peak_mb | 151.1 | 151.1 | 0 |  |  | reused |
| fuzz | all n100 s22 | flagged | 8 | 8 | 0 |  |  |  |
| fuzz | all n100 s22 | unsupported | 0 | 0 | 0 |  |  |  |
| fuzz | all n100 s22 | crashed | 0 | 0 | 0 |  |  |  |
| fuzz | all n100 s22 | error | 0.008164 | 0.008164 | 0 |  |  |  |
| fuzz | all n100 s22 | answered | 365 | 365 | 0 |  |  |  |
| fuzz | all n100 s22 | seconds | 32 | 36 | 4 |  |  |  |
| fuzz | all n100 s22 | peak_mb | 160 | 159.8 | -0.2 |  |  |  |

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
