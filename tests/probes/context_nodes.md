# Issue 60, Round 1

Run these probes in the worktree's copied/repointed environment through
`bench/capped --priority review`, with `DISPLAY` unset, `ulimit -v 16000000`,
and the process-group timeout/reaping procedure in `docs/agent_workflow.md`.

`test_context_nodes.py` runs the acceptance campaign in a fresh SWI runtime.
Python unittest's `expectedFailure` retains the contracts that require
later rounds; an unexpected success fails the suite.

| Test | Contract | Status in Round 1 |
|---|---|---|
| T1, full TV | cold = warm = warm-all within 1e-12 | expected failure until Round 3, after H1 removal in Round 2 |
| T1, three repeats | unchanged TVs and zero evaluation work | required |
| T2 | base-rate loop terminates with zero work | required |
| T3 | deep persistence history has the same cold/warm TV | expected failure until Round 3 |
| T4 | C1 insertion orders and all 3/4-cycle permutations agree on full TVs within 1e-12 | required |

Two additional H1 contracts retain their original assertions as expected
failures until Round 2: shared-source quantified judgment strength/confidence,
and the many-root high-budget posterior error bound. Their numeric fixture
guards run outside expected failures. The main Python suite also retains
materialization history equality as an expected failure until Round 3;
replacement and zero-budget read-back checks remain required.

T1 preserves the stronger regression's histories and budgets, 2,000 and
20,000. Each history has its own process. Its prefix is constructed once,
then SWI forks independent copies for the final budgets: neither budget warms
the other. Settling stops after three consecutive identical, zero-work
queries, with the original 24-query limit. The shared results serve both TV
and work assertions. This removes duplicate setup, without dropping a history,
budget, truth-value component, or repeat check.

Work includes row computations, context-node creation, merged-cache misses,
conditioned evaluations, and unpaid conditions. Fixture checks sit outside
expected failures. T2 checks actual node subscriptions to a base-rate fold;
T3 checks quiet repeats and the presence of deep t1 rows. The publication
audit checks dependency/exclusion disjointness while proof and dependency
handles are live, and requires a positive publication count.

`exclusion_state.py` checks exact reuse, pending misses without inline row
evaluation, node-local subscriptions, proof-independent republication,
dependency-set equality, statistical value/coverage comparison, canonical
aliasing, row-key collisions, class growth beyond eight entries, H1 forcing,
and interruption cleanup. These are executable contracts for the new store;
the deleted branch helpers are not retained as test scaffolding.

## Census

`context_census.py CASE ABSOLUTE_OUTPUT.json` instruments only its owning
process. `--plain` runs the same benchmark without wrappers for an observer
neutrality check. Its workload arguments and seeds come from `bench/compare.py`.
The Round-0 census and cap decision are archived in
`bench/results/codex-logs/ctxnodes.round0.result.md`.

The probe retains cumulative published cut classes and raw exclusion requests,
including nodes later canonicalized away. The union is a conservative demand
envelope, not an end-of-run cache count. The JSON also reports per-query
exclusion merges and conditioned evaluations within those merges.

The production query metrics `context_node_count`, `context_classes_max`, and
`context_classes_mean` count retained row nodes, including pending/stale nodes,
at each query boundary. The Round-1 cyclic-fuzzer census uses these metrics
with the standard `scripts/fuzz_vs_problog.py` generator and worker. These
retained counts are reported separately from the Round-0 cumulative envelope.
