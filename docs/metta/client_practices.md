# Using the chainer from a long-running client

Practices learned from the StationOps game (ChainerGame), which adds knowledge
every round for hundreds of rounds. Each one has a measured reason.

## One knowledge base

Keep every statement that reasons together in one knowledge base. A knowledge
base cannot be dropped: its facts, skeleton rows, views and forward agenda
stay in the shared runtime for the life of the process. StationOps once built
a knowledge base per decision (about three a shift); after 20 shifts those
held 70% of all skeleton rows, and memory grew 16 MB a shift instead of 5.

## Add rules once

Add the rules a client needs at the start, and add facts after that. A rule
added after nodes are expanded is started on every expanded node its
conclusion matches (`sk-activate-pending!`), so a rule per entity per round
costs a scan that grows with the knowledge base. Prefer one general rule
and a fact per entity over a rule per entity.

## State decisions as conditional queries

A decision reads the current beliefs together with facts that hold only for
the decision: candidates, costs, eligibility. Stated as facts in the
knowledge base, they and the skeleton nodes built over them stay after the
decision is made. StationOps' decision steps left about 10,000 nodes after 20
shifts, and every later query scanned past them (action query time per shift
1.4 s → 5.7 s over 20 shifts at a fixed budget).

Ask the decision as a query under assumptions instead
(`assumption_queries.md`, designed, not built yet): the facts hold only in
the query's context and everything built in it leaves with the query. An
implication query is not a substitute: it reads only premises that share the
query's variables in its context, computes a refuting branch, and keeps its
contexts' nodes.

## Budgets that scale with the question

A query's budget counts node expansions. Give a query whose work grows with
its subject, such as a decision over n candidates, a budget proportional to
n: a StationOps decision needs about ten expansions per candidate.

## Forward chaining in slices

Queue new facts with `(forward-chain 0 kb facts)` and give forward
chaining a fixed number of row computations per round with
`(forward-chain N kb ())`, so its cost does not follow the number of facts a
round brings (`docs/metta/forward_units.md`). Queue only the facts whose
consequences matter; queued facts are never dropped.

## Settings

- `set-forward-seed-share`: 1 (default) serves the queued facts first.
- `set-forgetting`: bounds what idle keys keep; for a client that runs
  indefinitely.
