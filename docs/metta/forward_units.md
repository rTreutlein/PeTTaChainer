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

A seed is a fact a caller passed to `forward-chain`. A run spends its units in
two parts:
1. **Seeds first.** A run works the seeds no run has taken yet, its own facts
   and the seeds earlier calls queued, with the keys they change, alone,
   until that agenda is empty or a share of the units is spent
   (`set-forward-seed-share`, default 0.5).
2. **Then everything by priority.** What is left of that agenda joins the
   carried derived keys, and the rest of the units go to the best items of
   both.

So a share of every run's units goes to the facts callers chose, however much
higher the carried derived keys rank. Which facts those are stays the
caller's choice: a run without units only queues its facts, so a caller can
choose facts as they arrive and give units later, to a run without facts.
With share 1 the chosen facts always come first; with share 0 there is one
ranking for everything.

### Bounded

The carried agenda keeps every seed, since a caller chose it, and its best
`bounded-agenda-target-size` other items (1,000). The worst ones are dropped
when it is stored at the end of a run. A dropped
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
- StationOps harness: `CG_FORWARD_STEPS` becomes units per fact. With
  `CG_FORWARD_SLICE` set instead, new facts are queued without units and
  each shift gives that many units to one run without facts, so forward
  compute no longer depends on how many facts a shift brings.

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

## Results

Replayed StationOps, 8 seeds, 20 shifts, dormant rules with answers by index;
Brier, then forward plus query compute per seed. f is units per fact, q the
query budget; seed share 0.5 unless noted. Old: steps per fact (37eafc3e's
parent).

| game | setting | Brier | compute |
|---|---|---|---|
| plain | old f1 q50 | 0.0611 | 11.2 s |
| plain | old f2 q50 | 0.0590 | 14.0 s |
| plain | old f2 q200 | 0.0590 | 17.1 s |
| plain | f2 q50 | 0.0861 | 8.9 s |
| plain | f3 q50 | 0.0704 | 9.8 s |
| plain | f4 q50 | 0.0629 | 12.5 s |
| plain | f4 q50, share 1 | 0.0591 | 12.5 s |
| plain | f4 q50, share 0 | 0.0921 | 12.7 s |
| plain | f3 q200 | 0.0599 | 14.4 s |
| plain | f4 q200 | 0.0592 | 14.8 s |
| plain | f8 q200, share 1 / 0.5 / 0 | 0.0591 / 0.0592 / 0.0660 | 19.7 / 17.2 / 19.6 s |
| distractor chains | old f1 q50 | 0.0611 | 11.0 s |
| distractor chains | old f2 q50 | 0.0610 | 14.4 s |
| distractor chains | f3 q50 | 0.0692 | 10.9 s |
| distractor chains | f4 q50 | 0.0668 | 12.7 s |
| distractor chains | f4 q50, share 1 | 0.0605 | 13.7 s |
| distractor chains | f4 q50, share 0 | 0.1015 | 12.5 s |
| distractor chains | f4 q200 | 0.0595 | 15.4 s |

- The knob is finer: points now lie between 8 and 13 s, where steps had
  none, and the plateau is reached from either budget.
- Share 1 is best: on the plain game it reaches the plateau (0.0591) at
  12.5 s, 1.5 s left of the old best point. The carried agenda's priorities
  do not compare with new facts' across calls: with share 0 new facts
  starve (0.09–0.10), and every share below 1 costs quality.
- Peak memory at q 50 rose to 1.1–1.4 GB (old 0.7–0.9 GB); at q 200 it
  is unchanged (0.5 GB). Not yet explained.
- The first grid of this build found a defect: a row a forward run created
  but could not pay for was stale with no value, and queries refreshed stale
  rows only near their roots, so a fold above it lost the member (Brier up
  to 0.16). Fixed in 3f11d9d1; the table is after the fix.

### Fixed slice per shift

Forward compute given as N units per shift to one run without facts, new
facts queued without units (`CG_FORWARD_SLICE`), so it no longer follows the
number of facts a shift brings (about 25). Same games and seeds.

| slice | q | plain, share 1 | plain, share 0.5 | distractor chains, share 1 |
|---|---|---|---|---|
| 25 | 50 | 0.0979 (8.6 s) | 0.1070 (6.6 s) | 0.0979 (8.9 s) |
| 50 | 50 | 0.0607 (11.7 s) | 0.0971 (8.6 s) | 0.0617 (11.7 s) |
| 75 | 50 | 0.0605 (12.4 s) | 0.0671 (11.4 s) | 0.0619 (13.1 s) |
| 100 | 50 | 0.0605 (13.4 s) | 0.0594 (14.1 s) | 0.0610 (13.7 s) |
| 125 | 50 | 0.0601 (14.3 s) | 0.0590 (14.2 s) | 0.0618 (14.3 s) |
| 25 | 200 | 0.0689 (13.3 s) | 0.0714 (12.8 s) | 0.0689 (14.1 s) |
| 50 | 200 | 0.0594 (14.2 s) | 0.0674 (13.7 s) | 0.0594 (16.1 s) |
| 100 | 200 | 0.0593 (14.7 s) | 0.0590 (13.9 s) | 0.0594 (16.0 s) |
| 150 | 200 | 0.0590 (15.6 s) | 0.0591 (14.9 s) | 0.0593 (16.7 s) |
| 300 | 200 | 0.0590 (20.4 s) | 0.0590 (19.5 s) | 0.0594 (21.4 s) |

- The curve is now continuous in the slice and monotone in the query budget
  (q 200 never worse than q 50, unlike the per-fact grid before 3f11d9d1).
- It matches the old steps-per-fact frontier (0.0611 at 11.2 s, 0.0590 at
  14.0 s) rather than moving left of it; the per-fact run at 4 units with
  share 1 (0.0591 at 12.5 s) stays the best single point.
- Share 1 wins at small slices (50: 0.0607 against 0.0971), share 0.5 by a
  little from 100 up (0.0594 against 0.0605): the seeds' consequences are
  worth most, but once they are covered, derived keys of earlier shifts are
  worth more than further seed work. A ranking that knew which keys
  queries read would make the share unnecessary.
- Below about 11 s quality drops fast (slice 25: 0.098): queries alone cost
  about 7 s per seed at q 50, so forward compute is the smaller part.
- Peak memory at q 50 is 1.1–1.4 GB against 0.5 GB at q 200 in both grids;
  not yet explained.

### Relevance by queried statement head (not adopted)

Tried: queries record the statement heads of the keys they need, roots and
premises; a forward item of a head no query needed weighs a twentieth of its
change. Slice grid as above (patch kept outside the repository):

| slice | q | plain, share 1 | without | distractor, share 1 | without |
|---|---|---|---|---|---|
| 50 | 50 | 0.0620 | 0.0607 | 0.0631 | 0.0617 |
| 75 | 50 | 0.0602 | 0.0605 | 0.0629 | 0.0619 |
| 50 | 200 | 0.0607 | 0.0594 | 0.0615 | 0.0594 |
| 150 | 200 | 0.0590 | 0.0590 | 0.0593 | 0.0593 |

With share 0, new facts still starve (0.08–0.10). Queries need 8 heads, and
those cover nearly every key the forward run takes. The only ones demoted
are `PatchPaysOff` and `ImplicationInstanceSample`, which feed base rates
and rule refinement without being queried directly, hence the small loss.
Distractor chains never reach the forward agenda: dormant rules already
keep the run off them. Starvation at share 0 is between relevant keys: a
derived key's change outranks a new fact's. A useful relevance would have
to be finer than the head, such as the keys whose readers queries need.
