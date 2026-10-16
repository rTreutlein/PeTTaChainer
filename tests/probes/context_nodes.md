# Issue 60, Round 0

These probes specify the adopted context-node design without changing runtime
behavior. Run them in the worktree's copied/repointed environment under
`bench/capped --priority review`, with `DISPLAY` unset, `ulimit -v 16000000`,
and a process-group timeout as in `docs/agent_workflow.md`.

`test_context_nodes.py` runs `context_nodes.py` in a fresh runtime. Python
unittest's `expectedFailure` mechanism makes the four outstanding contracts
visible and treats an unexpected success as a failure. Remove the corresponding
decorator in the round that implements the contract:

| Test | Current defect | Passing round |
|---|---|---|
| T1, full TV | cold/warm confidence differs by about 5.89e-7 | 3 (after 1-2) |
| T1, three repeats | warm-all rebuilds/conditions forever | 1 |
| T2 | four-rule, four-period base-rate/branch loop is non-quiet | 1 |
| T3 | five-link persistence chain retains deep stale history | 3 |

T1 follows `round6/stronger-regression.patch`: budgets 2,000 and 20,000;
cold, warm, warm-all; 24 settling queries; full STV equality within 1e-12;
three unchanged queries with zero row computations, branch builds, conditioned
evaluations, or unpaid conditions. The existing branch soundness audits remain
in the suite's original history-replay test. T2's positive fixture check verifies
that a branch subscribes to a fold. T3 separately verifies quiescence and the existence of deep
t1 rows, four links from the t5 root; the guard does not require staleness to
persist once round 3 refreshes them. These positive checks are not expected
failures. Round 1 must rewire the branch-store audit to the context store when
it deletes the branch machinery; it must not retain old helpers for this audit. T3 runs unchanged against pre-54 `22bd1a09` too.

T4 checks all six C1 rule insertion orders and all six/24 three/four-cycle
permutations, with and without interleaved queries. Every member's full STV is
compared with the cold graph, after three settling queries. The existing
proof-term and self-support regressions remain in place. T4 already passes.

## Census

`context_census.py CASE ABSOLUTE_OUTPUT.json` instruments the runtime only in
its owning process. `--plain` runs the same workload without Prolog wrappers to
check observer neutrality. SupplyNet/conflict/replay arguments come from
`bench/compare.py`, including its standard seeds and workload sizes. Replay is
`fv_s4`, 20 shifts/10 modules, diagnosis budget 50, action 1, shortfall 25.
The u4 census covers cold/warm/warm-all at budget 2,000, 12 final repeats each,
and warm-all's three sweeps of prior snapshots at 20,000.

Counts are cumulative for the workload, keyed by owner digest and row digest,
and include classes later pruned or evicted. They are not an end-state cache
census. `observed_cuts` counts the empty ordinary class and every freshly
published branch's canonical recorded cuts. `raw_exclusions` records every
exclusion set E at a `sk-value` read against its existing latest rows;
`demand_envelope` unions these with the observed classes. This conservative
bound retains demand whose exact cut class is still undiscovered, including
unpaid misses, excluded owners, and reads inside conditioning. It intentionally
overstimates distinct semantic classes. The observed count alone must not be
used as a complete census of pending class demand: master's fallbacks can serve
an older view without ever computing the requested exact context.

The JSON includes per-row total/maximum/mean/histogram for all three counts,
each query's exclusion merges and conditioned evaluations within an exclusion
merge, query-only totals, and totals including forward calls. A conditioned
evaluation is counted once when its claim charge succeeds under at least one
nonempty-exclusion merge; nested merges do not multiply that count. Forward
calls are excluded from the per-query mean. These are work counts, not timing
measurements; probe overhead invalidates performance comparisons.
