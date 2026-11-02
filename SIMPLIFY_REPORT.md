# simplify-stats report

Branch `simplify-stats` from master 39e41c5e. Subsystem "Statistics" per `scripts/coupling.py`
(statistical_ledger.pl, hypothesis_mining.metta, statistics/{aggregates,base_rates,ledger}.metta).

## Commits
- 9b27e40f Statistics: inline single-use ledger and aggregate helpers
- 880b88e4 Statistics: collapse staging in forward maintenance and member replacement

## Size (o200k tokens)
| | before | after |
|---|---|---|
| Statistics subsystem | 18361 | 17488 (-873, -4.8%) |
| repo core (`scripts/core_count.py`) | 325939 | 325056 (-883) |

Diff vs base: 8 files, +108 / -162 lines. 17 named functions removed.

## Coupling (`scripts/coupling.py`)
Identical to base: 117 subsystem edges, 637 cross-boundary functions, 2 two-way pairs,
largest function SCC 74, 181 functions in cycles; Statistics SCC 0. The external interface did not change
(every name in docs/metta/layers.md's Statistics row is kept with its signature).

## Moves
- `fa-publish-cache!` merged into `store-produced-base-rate!`, which now skips storing a value the cache
  already holds (its only non-test caller always went through that check).
- Single-use wrappers inlined: `remove-produced-base-rate!`, `ledger-remove-member!` (into `fa-remove!`),
  `hm-propose!`, `fa-seed-class-link!`, `forward-maintain-member-aggregates!`, and the Prolog
  `ledger-reset-regime-aliases!` (now a direct `remove-data-rows!`; its native declaration is gone).
- Fold-step helpers removed: `fa-read-step`, `sk-read-members-step`, `sk-member-sample-step`,
  `sk-rate-dirty-step`, `sk-antecedent-fact-entries`, `sk-fact-entry-step`, `fa-register-premise-step!`.
  Accumulator-only folds are now `foreach-flat`, list builds are `collapse`, and order is kept wherever it matters
  (`evidence-set` interns in order).
- `aggregate-readers` (Prolog) takes the whole exclusion list and returns a sorted set, replacing the
  MeTTa fold + `list_to_set` + `sort-atom`.
- `fa-interest`: one trigger-interest lookup shared by `fa-maintain-key!` and `fa-trigger-folds`.
- Hypothesis-mining counters use `chainer-first-or`; `HmOutcome` datatype removed.

## Tried and kept
- `fa-dist-acc` / `fa-ev-acc`: inlining `the` gives a static type conflict (both branches are unified), so they
  stay as typed barriers, now with a comment saying why.

## Tests moved
- tests/test_prior_definition.py: `aggregate-readers` is now called with a list (`[_HA]`). Same assertions.
- tests/test_ingestion.py: the head-dispatch case now calls `forward-maintain-aggregates!`, which took over the
  inlined member function. Same assertion.
No expected values or tolerances changed.

## Gates
- scripts/verify.sh (capped --slots 16): PASS (all 6 gates).
- compare.sh anchor --canary: PASS. Every accuracy or time difference from the anchor also appears on master; nothing is blocking.
- compare.sh master --full: PASS, accuracy identical in all 22 cases, StationOps belief streams identical, suite times within -5%..+1%, no RSS growth (bench/results/compare/39e41c5e_vs_880b88e4_full/report.md).
