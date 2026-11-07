# master-budgetstatus: "ran out of budget" status for query answers (#155, option D)

Branch master-budgetstatus, base 2a6dbb9d. `query_many_with_status` and `(query-many-with-status)` say whether this call ran out of budget or refused work. Status names: `ran-out`, `did-not-run-out`. The docs state plainly that the second does not mean correct.

## Design
One cell, `sk_ran_out`, zeroed per `execute-backward-run` and always on, so no metrics and no mode: the status call is `query-many` followed by a read, and answers cannot differ.

Bumped at a refusal, O(1) each: unpaid row (`sk-work-pop!`), unpaid branch build, refused representative read, nested claim closed exhausted, `conditions-unpaid` above 0 at the end of `sk-evaluate!`, refused graph read (admission or unaffordable), unpaid world refresh.

Read at the end of a run, and of each `Assuming` context: a queued delivery, an open branch request, search work at or below a root (`diagnostic-work?`, moved to skeleton.metta so execution can call it). One lookup per root.

Rejected: enabling metrics for the call (they overwrite `conditions-unpaid` per evaluation, so a context hides main's debt); differencing `sk_branch_unpaid` (it also counts a row that waits and is then paid); scoping sites to needed keys (a nested build's dependency is not needed, so it would under-report).

## Acceptance (73d15a32, metrics off; the Python path has not changed since)
| Case | Budget | Status | Answers |
|---|---:|---|---:|
| ProductDebut, KE cold-50 | 1000 | ran-out, both calls | 5, 6 |
| ProductDebut | 3000 | did-not-run-out, both calls | 7 |
| ProductDebut | 20000 | did-not-run-out, both calls | 7 |
| plant(4) | 400 | ran-out, all three calls | 1 |
| (P a), #172 | 3000 | did-not-run-out | 1, the wrong .3 |
| ProductDebut, plant(4) | 0 | ran-out | 0, 1 |

## Evidence
- Answers: byte-identical to master on 174 calls (KE, plant(4), the quick fuzz KBs, budgets 0 to 3000, cold and warm), through both `query_many` and the status call. Run on 9e1875c4; later commits add only the Python empty-batch return and the MeTTa form's grouping, and --quick is identical on the final code. Grouping is covered by a test of positions and binding order. The reviewer's cp1 run found the same on 98 jobs.
- Meter, inferences at 1 step, master / query_many / status: 10 bindings 23634 / 23732 / 23759; 1000 bindings 1831998 / 1832094 / 1832121. Added work is flat: +98 and +96, then +27. The reviewer's meter on cp1 is also flat.
- Sweep: 750 calls, 15 budgets, 21 fuzz KBs, plant(2..5), an Assuming KB. 372 did-not-run-out; 1 differs from a fresh b20000, explained under Limits.

- MeTTa form, reviewer's rawmeter.py with 100 extra roots, added inferences at 1 step, 10 / 1000 bindings: cp1 +2,432 / +76,682 (`query-answer-groups` scanned all rows per root, the reviewer's cp1 blocker); now +638 / -23,324. With one root: -64 / -23,824. The extra 100 roots cost about 5 to 7 inferences each at both sizes. Negative means printing one term costs less than printing many rows.

## Gates
On 8c21a8a2, the final code:
- verify.sh: PASS, key e84f2cd0b917.
- compare.sh master --quick: PASS, accuracy identical in all 9 cases. Report: bench/results/compare/2a6dbb9d_vs_8c21a8a2_quick/report.md

--full and the canary were not rerun on 8c21a8a2, as the coordinator's rule allows: the runtime diff from 73d15a32 is one native predicate only the MeTTa one-term form calls. land.sh runs both. Their results on 73d15a32:
- compare.sh master --full: PASS, accuracy identical in all 22 cases; fuzz 8 to 8 flagged, none new. Report: bench/results/compare/2a6dbb9d_vs_73d15a32_full/report.md
- Canary against anchor: PASS. "Accuracy changed in 4 of 6" is master against the anchor: `anchor_vs_2a6dbb9d_canary` has the same six errors. Report: bench/results/compare/anchor-b4065459_vs_73d15a32_canary/report.md
- Curves not run: nothing changes scheduling, budgets or answers.

## Tokens
Core +1,028 by scripts/core_count.py (330172 to 331200). Estimate +600 to +700; stop line about +1,050. Over the estimate, 22 under the line. Python +239 of it. The one-pass grouping cost +81.

## Moved test values
None. tests/test_query_status.py is new, 16 tests, adapted from master-truncation's API tests. No existing test changed.

## Limits
- Under-reports (documented): a silent need decline, and old debt from earlier calls that this call does not reach.
- Over-reports (documented): open branch requests are process-wide and served from the next call's allowance, on any KB. A cheap call right after a hard one can report ran-out until they drain, three calls in the one case traced. Scoping would under-report, the worse error for this contract.
- did-not-run-out is not settled (documented, master behaviour): plant(5) at b20000 gives c .98305 on its first call and .98384 on its next, nothing refused in either.
- Sites not seen firing on any probed workload, kept from reading the code: representative read, closed nested claim, world refresh alone. Graph admission fired only when forced in a test. Graph affordability (KE), end-of-run read, unpaid row, build and conditions all fired naturally.
- `query_with_diagnostics` keeps its own `termination.reason`, which misses refused graph work. Not unified here: changing it is a public behaviour change outside this brief.
- Only the Python empty batch short-circuits. MeTTa `(query-many-with-status n kb ())` runs as `query-many` on `()` does and reports what that run left.
