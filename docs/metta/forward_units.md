# Forward compute in row units

Status: built, October 2026.

## Problem

A forward run's budget counts derived keys taken. A taken key's readers are
then computed in full, for free, and seeds cost nothing. Measured on
StationOps (seed 1, 20 shifts, dormant rules with answers by index, query
budget 50, replayed):

| steps per fact | forward time | keys taken | rows computed | rows per key |
|---|---|---|---|---|
| 0 | 1.2 s | 0 | 200 | – |
| 0.5 | 3.5 s | 247 | 1,799 | 6.5 |
| 1 | 4.5 s | 495 | 2,291 | 4.6 |
| 2 | 6.1 s | 952 | 3,419 | 3.6 |
| 4 | 7.2 s | 1,674 | 4,449 | 2.7 |

- **A step has no fixed cost.** The first keys a run takes cost about six rows
  each, the last ones about one. A row computation, on the other hand, costs
  about 1.7 ms throughout, from 0 to 4 steps per fact, so the row is the unit
  with a fixed cost.
- **Work a budget cuts off is lost.** The agenda lives for one call, and the
  game calls once per batch of new facts. Keys left on it when the budget runs
  out are dropped, and they are found again only if a later run happens to
  reach the same reader. Compute cannot be given in small slices to be
  continued later, and a slice cannot go to the best work across batches.

## Unit

Every row a forward run computes costs one unit, at any depth, its seeds'
readers included. A row the allowance cannot pay for is left stale, as a
query leaves one. Joins keep their own allowance of ten rows per unit: a row
they create that the units cannot compute is left stale and computed by a
later run (see Waves), whereas a row the join allowance refuses would wait
for a query's walk.
`(forward-chain $units $kb $facts)` keeps its signature; `$steps` becomes
units.

The parked `forward-row-budget` branch (acd15f43) counted forward work the
same way. It was parked because the cost of a row grew over a game, through
dependency sets. Since dependency sets became interned ids (30734720), the
cost per row is flat, as the table shows.

## One agenda across calls

The agenda outlives the call. A key a run leaves on it keeps its priority,
and a later run continues from the best item. A call with no facts spends
its units on the agenda alone, so compute can be given at fact-add time,
later, or both.

Items:
- `(sk-fwd-seed key)` and `(sk-fwd-key key)`, as now, ranked by the KL
  divergence of the key's value from the value a run last built on.
- `(sk-fwd-rest key)`, for a key whose readers a run left stale when its
  allowance ran out, ranked as the key was when taken. Taking it computes
  those readers and starts no joins: the key's joins ran when it was taken.

An item is checked when popped, not when stored: a key whose value equals
the value last built on, or that rests on less than the minimum evidence, is
dropped then, as now.

### New seeds are not starved

A run spends its units in two parts:
1. **Its own seeds first.** A run works the agenda its new facts start, alone,
   until that agenda is empty or a share of the units is spent
   (`set-forward-seed-share`, default 0.5).
2. **Then everything by priority.** What is left of its own agenda joins the
   carried agenda, and the rest of the units go to the best items of both.

So a share of every run's units goes to its own facts, however much higher the
carried items rank. With share 1 a run is today's run, plus its leftovers
being carried. With share 0 there is one ranking for everything.

### Bounded

The carried agenda keeps its best `bounded-agenda-target-size` items (1,000).
The worst ones are dropped when it is stored at the end of a run. A dropped
item is lost the way every cut-off item is lost today: a later run that
reaches the key finds it again. Loading and storing the carried agenda costs
time proportional to its size, so this bound keeps the per-call cost fixed.

## Waves

Keys are still taken in waves, so a row several keys reach is computed once.
With a fine budget, a large wave would be cut in creation order rather than in
order of value. So a wave takes keys in priority order only while the readers
they bring fit the units left. It always takes at least one key, and a lone
key may overrun the units left.

If the allowance still runs out during the evaluation, the rows left stale
stay stale readers of their keys, as now. Each key of the wave goes back on
the agenda as `(sk-fwd-rest key)`, so a later run computes the readers it
missed. A rest item whose key has no stale readers costs nothing.

## Callers

- Python: `forward_chain(facts, steps)` with no facts runs on the carried
  agenda instead of returning at once.
- StationOps harness: `CG_FORWARD_STEPS` becomes units per fact, and an
  optional `CG_FORWARD_SLICE` gives units per shift to a call without
  facts.

## Evaluation

1. Unit tests:
   - a run's rows computed never exceed its units plus one key's readers;
   - a new seed gets its share while the carried agenda holds items that rank
     higher;
   - a cut run's readers are computed by the next call without facts;
   - the carried agenda stays within its bound;
   - with the units of a full run, the results are those of a full run.
2. Full suite and examples. Expectations that depended on step counts are
   rescaled one by one: same values at a matching budget.
3. Replayed grid on the plain and distractor-chain games:
   - units per fact 1, 2, 3, 4, 6, 8 and 12, at query budgets 50 and 200;
   - seed share 1, 0.5 and 0 at two cells.

   Success means the Brier-vs-compute curve has points between today's 1 and
   2 steps per fact (0.0611 at 11.2 s, 0.0590 at 14.0 s), lies on or to the
   left of today's points, and that time per unit stays flat over a game.
