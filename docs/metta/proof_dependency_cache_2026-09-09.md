# Recursive proof dependency memoization

The previous query-local cycle cache memoized only an entry-point traversal.
Recursive children bypassed it and repeatedly walked shared proof subgraphs,
carrying a path-local list of visited proof IDs. The replacement memoizes each
visited `(proof ID, receiving goal ID, cycle key)` subproblem. Positive results
retain the existing child-order short circuit. Missing proof IDs remain semidet
failure and are not cached as negative answers.

## Why recursion terminates without a visited list

The production writer audit starts at `store-proof-record!` in
`runtime/backward/proof_store.metta`. It is the only code that inserts a
`stored-proof-row`. It obtains a fresh `next-pid` after callers have assembled
the children. The global `bwd_pid` counter increases monotonically and ordinary
query reset does not reset it. No production writer replaces proof-row children.

All production candidate constructors satisfy the ordering requirement:

- `leaf-result-candidate` supplies an empty child list.
- Rule completion in `commit-frontier-result-heap` reverses an existing frontier
  path, whose entries were created from selected stored proof IDs.
- Fold snapshots use the selected stored source IDs accumulated in their group.
- Synthetic merged representatives use an existing output group's preferred IDs.

Consequently every stored child exists before its parent is allocated. Proof
rows form a physical DAG even when their statement-level rule graph is cyclic.
The existing receiving-goal/output-key comparison still rejects logical
self-support; removing the visited-PID list does not remove that check.

The memo remains query-local because receiving goal IDs belong to that arena.
Query reset clears all rows. Goal and output keys keep their existing matching
semantics, including distinct output bindings of an open goal. The replaced
helper is internal and absent from `docs/metta/API.md`; every production/test
caller uses the new three-argument helper, with no compatibility definition.

## Validation

The isolated candidate starts at `d927e5f4`, with no scheduler, goal-identity,
or truth-value formula changes. It uses the repository-pinned executable and
frozen supported PeTTa `e1aac8b791cf70b7843173b613f04b869b666979`.

Focused tests cover a shared diamond, cached negative reuse by a new parent,
positive short-circuit order, separate closed-goal and output-binding keys,
missing-PID failure, and unchanged consumer delivery. Full `scripts/verify.sh`
passed: 76 MeTTa files, 57 Python tests, 46 metric rows with zero search aborts,
import ratio 0.998, and exactly two ConceptNet answers; 176 seconds overall.

The controlled screen used one sequential pair per seed, alternating order,
with no concurrent agent runtime work. Workloads were two shifts, four modules,
action budget 1, and the diagnosis budgets below. The frozen game revision was
`99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`. No fetching or runtime rebuilding
occurred. All three seeds preserve complete normalized proof strings, every
non-time episode result, and every non-time query metric against both fresh
and previously retained baseline artifacts. Only random KB UUIDs are normalized.

| Seed / diagnosis budget | Diagnosis seconds, base → candidate | Inferences, millions | Shift-two cache rows | Shift-two peak RSS, MiB |
|---|---:|---:|---:|---:|
| 7 / 600 | 74.505 → 70.836 (-4.9%) | 397.387 → 370.298 | 17,694 → 31,742 | 516.5 → 586.9 |
| 11 / 300 | 6.168 → 5.760 (-6.6%) | 29.688 → 27.170 | 1,667 → 3,663 | 175.0 → 164.8 |
| 23 / 300 | 4.381 → 4.093 (-6.6%) | 20.179 → 18.705 | 1,081 → 2,415 | 156.4 → 181.2 |

The external driver recorded query-local cache rows and Linux process peak RSS
after each diagnosis. It also checked every stored child exists with a lower
PID: all twelve checks passed. These read-only diagnostics occurred after timed
inference and did not alter public metrics. The inference reductions are
consistent; elapsed time and peak RSS are single-pair screening observations.
Peak RSS includes Prolog stack sizing and GC effects, not just cache storage.

The change is a modest exact optimization, with roughly 1.8–2.2 times as many
shift-two cache rows. The largest observed memory increase was 70.4 MiB on
seed 7. Adoption should retain that explicit memory tradeoff; this experiment
does not establish a large performance recovery or change the scheduling policy.

Raw artifacts, metadata, source hashes, driver, and comparisons are retained at
`/tmp/proof-dependency-results`. Core and docs/tests patches are separate.
