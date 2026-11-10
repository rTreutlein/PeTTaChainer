# 8538013b vs 9f794665-db37ba993 (quick)

**PASS**

accuracy identical in all 9 cases.

- base: `8538013b` = 8538013b18de3e7bdbc94b298d964e821e5c342f, runtime tree dd6a51d81d24, runs build `0b15c356-dc39c2b78` (same tree)
- candidate: `9f794665-db37ba993` = 9f794665c2cf87fa4cd7c0649f279fb0959fa0e2+b37ba993, runtime tree 78b6248a80d8
- ChainerGame: supply `3daf989e93 supply-network`, replay `d274b45767 bench-hooks`; PeTTa runtime 18c99706738d76f4
- 10 cases; 9 runs executed, 10 of 19 results reused from the store; 76 s wall, 146 CPU-s
- load: 16-24 pool slots held during this comparison's runs (cpu target 24)

Thresholds: error/Brier worse by >5% relative and >0.002 absolute (per row, also per kind); coverage drop >0.001; regret worse by >5% and >0.05 (agreement reported, never flagged); mined-rule search paid steps >10% and >1 more; fuzz flagged KBs up by any; seconds >10% and >1 s worse; peak RSS >35% and >300 MB higher; a run that fails only for the candidate. A timing flag counts only if a paired rerun repeats it. Timing not taken side by side, at loads whose calibrated slowdowns differ by more than 5%, is marked `load differs` and not flagged. `reused` marks results from the store (the same code ran this case before).

## Cases

Each case's points along its budget curve, low to high budget.

| suite | case | budgets | base error | candidate error | base s | candidate s |
|---|---|---|---|---|---|---|
| supplynet | stage 1 s2 | 25 | 0.01419 | 0.01419 | 1.793 | 2.349 |
| supplynet | stage 3 timed s3 | 100 | 0.0007757 | 0.0007757 | 13.81 | 12.3 |
| supplynet | stage 3 untimed s4 | 50 | 0.0003946 | 0.0003946 | 9.545 | 11.8 |
| scale | l s1 | 4 | 0.003808 | 0.003808 | 47.67 | 47.12 |
| conflict | pln-sources m s2 | 1 | 0.07448 | 0.07448 | 9.511 | 11.64 |
| learned | stage 3 timed learned s1 | 50 | 0.08152 | 0.08152 | 13.55 | 16.95 |
| replay | s4 | 25 / 50 | 0.1269 / 0.1163 | 0.1269 / 0.1163 | 5.623 / 6.783 | 4.821 / 8.341 |
| combinet | n2 s1 |  | 0.09231 | 0.09231 | 0.888 | 1.005 |

## Suite totals

| suite | base s | candidate s | delta | base peak MB | candidate peak MB |
|---|---|---|---|---|---|
| supplynet | 25.1 | 26.4 | +1.3 (+5%) | 229 | 229 |
| scale | 47.7 | 47.1 | -0.5 (-1%) | 994 | 995 |
| conflict | 9.5 | 11.6 | +2.1 (+22%) | 257 | 258 |
| learned | 13.5 | 16.9 | +3.4 (+25%) | 297 | 295 |
| replay | 12.4 | 13.2 | +0.8 (+6%) | 252 | 251 |
| combinet | 0.9 | 1.0 | +0.1 (+13%) | 151 | 149 |

## StationOps replay belief streams

| case | beliefs | changed | max belief shift |
|---|---|---|---|
| b25 s4 | 200 | identical | 0 |
| b50 s4 | 200 | identical | 0 |

## Metrics

| suite | case | metric | base | candidate | delta | flag | reference | note |
|---|---|---|---|---|---|---|---|---|
| supplynet | stage 1 b25 s2 | error | 0.01419 | 0.01419 | 0 |  |  | base reused load differs |
| supplynet | stage 1 b25 s2 | brier | 0.0431 | 0.0431 | 0 |  |  | base reused load differs |
| supplynet | stage 1 b25 s2 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| supplynet | stage 1 b25 s2 | seconds | 1.793 | 2.349 | 0.556 |  |  | base reused load differs |
| supplynet | stage 1 b25 s2 | peak_mb | 177 | 177.4 | 0.4 |  |  | base reused load differs |
| supplynet | stage 3 timed b100 s3 | error | 0.0007757 | 0.0007757 | 0 |  |  | base reused load differs |
| supplynet | stage 3 timed b100 s3 | brier | 0.1711 | 0.1711 | 0 |  |  | base reused load differs |
| supplynet | stage 3 timed b100 s3 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| supplynet | stage 3 timed b100 s3 | seconds | 13.81 | 12.3 | -1.506 |  |  | base reused load differs |
| supplynet | stage 3 timed b100 s3 | peak_mb | 228.9 | 228.6 | -0.3 |  |  | base reused load differs |
| supplynet | stage 3 untimed b50 s4 | error | 0.0003946 | 0.0003946 | 0 |  |  | base reused load differs |
| supplynet | stage 3 untimed b50 s4 | brier | 0.1319 | 0.1319 | 0 |  |  | base reused load differs |
| supplynet | stage 3 untimed b50 s4 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| supplynet | stage 3 untimed b50 s4 | seconds | 9.545 | 11.8 | 2.251 | load differs |  | base reused load differs |
| supplynet | stage 3 untimed b50 s4 | peak_mb | 211.1 | 210.5 | -0.6 |  |  | base reused load differs |
| scale | l spq4 s1 | error | 0.003808 | 0.003808 | 0 |  |  | base reused |
| scale | l spq4 s1 | brier | 0.0432 | 0.0432 | 0 |  |  | base reused |
| scale | l spq4 s1 | coverage | 1 | 1 | 0 |  |  | base reused |
| scale | l spq4 s1 | seconds | 47.67 | 47.12 | -0.55 |  |  | base reused |
| scale | l spq4 s1 | peak_mb | 994 | 994.9 | 0.9 |  |  | base reused |
| conflict | pln-sources m spq1 s2 | error | 0.07448 | 0.07448 | 0 |  |  | base reused load differs |
| conflict | pln-sources m spq1 s2 | brier | 0.1053 | 0.1053 | 0 |  |  | base reused load differs |
| conflict | pln-sources m spq1 s2 | coverage | 0.9875 | 0.9875 | 0 |  |  | base reused load differs |
| conflict | pln-sources m spq1 s2 | seconds | 9.511 | 11.64 | 2.134 | load differs |  | base reused load differs |
| conflict | pln-sources m spq1 s2 | peak_mb | 257.4 | 257.9 | 0.5 |  |  | base reused load differs |
| learned | stage 3 timed learned b50 s1 | error | 0.08152 | 0.08152 | 0 |  |  | base reused load differs |
| learned | stage 3 timed learned b50 s1 | brier | 0.1162 | 0.1162 | 0 |  |  | base reused load differs |
| learned | stage 3 timed learned b50 s1 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| learned | stage 3 timed learned b50 s1 | seconds | 13.55 | 16.95 | 3.4 | load differs |  | base reused load differs |
| learned | stage 3 timed learned b50 s1 | peak_mb | 296.6 | 295 | -1.6 |  |  | base reused load differs |
| replay | b25 s4 | error | 0.1269 | 0.1269 | 0 |  |  | base reused load differs |
| replay | b25 s4 | brier | 0.07751 | 0.07751 | 0 |  |  | base reused load differs |
| replay | b25 s4 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| replay | b25 s4 | regret | 229.4 | 229.4 | 0 |  |  | base reused load differs |
| replay | b25 s4 | seconds | 5.623 | 4.821 | -0.8019 |  |  | base reused load differs |
| replay | b25 s4 | peak_mb | 233.3 | 233.2 | -0.1 |  |  | base reused load differs |
| replay | b50 s4 | error | 0.1163 | 0.1163 | 0 |  |  | base reused load differs |
| replay | b50 s4 | brier | 0.0753 | 0.0753 | 0 |  |  | base reused load differs |
| replay | b50 s4 | coverage | 1 | 1 | 0 |  |  | base reused load differs |
| replay | b50 s4 | regret | 229.4 | 229.4 | 0 |  |  | base reused load differs |
| replay | b50 s4 | seconds | 6.783 | 8.341 | 1.558 | load differs |  | base reused load differs |
| replay | b50 s4 | peak_mb | 252.2 | 250.6 | -1.6 |  |  | base reused load differs |
| combinet | n2 s1 | error | 0.09231 | 0.09231 | 0 |  | 0.06702 | base reused load differs |
| combinet | n2 s1 | brier | 0.1727 | 0.1727 | 0 |  | 0.175 | base reused load differs |
| combinet | n2 s1 | coverage | 0.91 | 0.91 | 0 |  | 1 | base reused load differs |
| combinet | n2 s1 | seconds | 0.888 | 1.005 | 0.117 |  |  | base reused load differs |
| combinet | n2 s1 | peak_mb | 151.1 | 149.4 | -1.7 |  |  | base reused load differs |

## Error per kind

| suite | case | kind | base | candidate | delta | flag |
|---|---|---|---|---|---|---|
| supplynet | stage 1 b25 s2 | blocked | 0.003856 | 0.003856 | 0 |  |
| supplynet | stage 1 b25 s2 | storm | 0.0414 | 0.0414 | 0 |  |
| supplynet | stage 3 timed b100 s3 | blocked | 5.099e-11 | 5.099e-11 | 0 |  |
| supplynet | stage 3 timed b100 s3 | degraded | 0.003897 | 0.003897 | 0 |  |
| supplynet | stage 3 timed b100 s3 | previous_storm | 2.4e-10 | 2.4e-10 | 0 |  |
| supplynet | stage 3 timed b100 s3 | producing | 0.00377 | 0.00377 | 0 |  |
| supplynet | stage 3 timed b100 s3 | producing_unstocked | 2.082e-17 | 2.082e-17 | 0 |  |
| supplynet | stage 3 timed b100 s3 | storm | 5.554e-11 | 5.554e-11 | 0 |  |
| supplynet | stage 3 untimed b50 s4 | blocked | 2.56e-17 | 2.56e-17 | 0 |  |
| supplynet | stage 3 untimed b50 s4 | degraded | 0.001459 | 0.001459 | 0 |  |
| supplynet | stage 3 untimed b50 s4 | previous_storm | 6.056e-17 | 6.056e-17 | 0 |  |
| supplynet | stage 3 untimed b50 s4 | producing | 0.002016 | 0.002016 | 0 |  |
| supplynet | stage 3 untimed b50 s4 | producing_unstocked | 0 | 0 | 0 |  |
| supplynet | stage 3 untimed b50 s4 | storm | 5.788e-17 | 5.788e-17 | 0 |  |
| scale | l spq4 s1 | blocked | 0.003087 | 0.003087 | 0 |  |
| scale | l spq4 s1 | front | 0.0113 | 0.0113 | 0 |  |
| scale | l spq4 s1 | past_front | 0.01026 | 0.01026 | 0 |  |
| scale | l spq4 s1 | past_storm | 0.002409 | 0.002409 | 0 |  |
| scale | l spq4 s1 | storm | 0.005013 | 0.005013 | 0 |  |
| conflict | pln-sources m spq1 s2 | component | 0.1154 | 0.1154 | 0 |  |
| conflict | pln-sources m spq1 s2 | system | 0.03352 | 0.03352 | 0 |  |
| learned | stage 3 timed learned b50 s1 | blocked | 0.09388 | 0.09388 | 0 |  |
| learned | stage 3 timed learned b50 s1 | degraded | 0.06221 | 0.06221 | 0 |  |
| learned | stage 3 timed learned b50 s1 | previous_storm | 0.1073 | 0.1073 | 0 |  |
| learned | stage 3 timed learned b50 s1 | producing | 0.04969 | 0.04969 | 0 |  |
| learned | stage 3 timed learned b50 s1 | producing_unstocked | 0 | 0 | 0 |  |
| learned | stage 3 timed learned b50 s1 | storm | 0.1125 | 0.1125 | 0 |  |
| combinet | n2 s1 | causes | 0.07404 | 0.07404 | 0 |  |
| combinet | n2 s1 | interacting | 0.1196 | 0.1196 | 0 |  |
| combinet | n2 s1 | redundant | 0.06379 | 0.06379 | 0 |  |
| combinet | n2 s1 | signs | 0.1119 | 0.1119 | 0 |  |

The CombiNet reference column is the revision backend (independent of the build).
