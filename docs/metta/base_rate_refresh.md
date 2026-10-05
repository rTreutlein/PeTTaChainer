# Base-rate refresh

Status: rejected by its go/no-go measurement, October 2026. Not built.

## Problem

A base rate is one estimate per pattern, kept as each member's contribution
(`sk-fold-view`, `runtime/forward/aggregates.metta`). A member's contribution
is updated when the member's value changes during an evaluation
(`sk-fold-changed` records it in `&sk_rate_dirty`) and the rate is next needed
(`sk-need-below!` takes the dirty members).

A member whose inputs changed but that nothing needs is only marked stale.
Its value is not recomputed, so it never changes, never becomes dirty, and
the rate keeps its old contribution. `sk-stale-key!` deliberately does not
stale a rate fold over it: the rate keeps what it has. The member is
recomputed only when some unrelated reader happens to need it.

So what a base rate counts depends on which other queries and rules happened
to read its members. Dormant rules show this. They remove rows that read
`SealLeak` instances. Fewer member refreshes happen, and on the plain game
the oxygen-scrubber `SealLeak` rate stays at 0.350 where head reaches 0.389.
On the replayed grid the plateau is 0.0599 against head's 0.0591. Low forward
chaining with a high query budget is worse still (f 0.5, q 300: 0.0655
against 0.0607), where refreshes depend on query readers alone.

Head lags as well, only less. Neither keeps the rate at what its members'
current values say.

## Rule

Refreshing a stale member of a base rate is its own unit of work. It is
scheduled by the value it can bring, from a budget the caller gives, and no
longer happens as a side effect of other reads.

### Candidates

When `sk-stale-key!` reaches a key that is a member of a base-rate fold (an
`&sk_use` edge to a rate fold), it records a candidate `(F, m)`: rate fold F,
member m. It does not drop F's view; that stays as today. A candidate is
removed when m's contribution is taken (`sk-rate-take-step`), or when m is
frozen or buried. A frozen member's summary is fixed, so it has nothing to
refresh.

### Priority

Refreshing m can move F by at most m's share of F's evidence: w_m / W, where
w_m is m's observation count in the aggregate and W the total, since
|Δs_m| ≤ 1. A rate matters in proportion to what reads it: r_F, the number
of rows reading F.

    priority(F, m) = r_F · w_m / W

This is an upper bound on the improvement, available without recomputing
anything. A tighter estimate would also carry the size of the change that
staled m: |Δs| at the key where the cascade began, an upper bound for one
step of a rule. Add it only if the grid shows refreshes spent on members that
did not move.

A rate nobody reads (r_F = 0) gets no refreshes. That is the laziness
principle: compute only what something reads.

### Store

The refresh takes the highest priority first, across all rates. A scan over
all candidates would cost in proportion to their number, so candidates are
kept in buckets keyed by ⌊−log₂ priority⌋, the first argument of
`&sk_rate_stale (bucket fold-hash fold member)`. A step reads the lowest
non-empty bucket: a lookup over at most about 32 buckets, one indexed match.
Within a bucket, the oldest candidate goes first. A candidate's priority is
fixed when it is recorded; a member staled again keeps one entry, the higher
priority.

### Step

`(refresh-base-rates $rows)` spends up to `$rows` row evaluations.

1. Pop the best candidate (F, m).
2. Need m at depth 0 and evaluate, as a query would. The walk brings m's
   stale rows and their stale premises back within the usual depth, so a
   change two steps upstream reaches m. Every row is paid from the refresh
   allowance: the free evaluation depth is 0 for a refresh. Each unit then
   costs one row, the currency `sk_eval_budget` already counts, and the
   allowance bounds the step.
3. If m changed, `sk-fold-changed` makes it dirty as today. Take F's dirty
   members (`sk-rate-take!`) and mark F dirty, so its readers see the new
   estimate at the next query.
4. Repeat until the allowance or the candidates run out. Return the rows
   spent.

Nothing else changes. Queries still take dirty members when they need a
rate, and forward runs still only mark stale. The refresh is one more place
compute can go, and the caller decides how much.

### Why a caller budget, not a share of each query

The chainer cannot yet compare a refresh with a query row in one currency
of value. A query row's value is not estimated at all. Until it is, the
refresh budget is a separate knob, called once per batch of new knowledge,
and swept on the quality-vs-compute grid like the forward and query budgets.
Folding it into one scheduler is the later step that the anytime principle
asks for.

## Correctness

A refresh computes values the chainer would compute anyway if a query needed
the member. It uses the same rows, the same self-support exclusion and the
same take, so it introduces no new kind of value. The only effect is which
members' current values the estimate reflects. With an unbounded allowance,
every read rate reflects all its members' current values. That fixed point
does not depend on which other readers ran.

## API

| | |
|---|---|
| `(refresh-base-rates $rows)` | Recompute stale members of read base rates, highest expected effect first, for at most `$rows` row evaluations; returns the rows spent. Python: `PeTTaChainer.refresh_base_rates(rows)`. |

ChainerGame calls it once per shift, after the shift's facts and forward run
and before the queries, with `CG_RATE_REFRESH` rows. The knob lives in the
scratch harness like the others until the curve says what it should be.

## Evaluation

0. **Is it worth it at all?** Run an unbounded allowance at f 2, q 300 and
   f 0.5, q 300 on the replays, with and without dormancy. If exact rates do
   not beat head's 0.0591, the lag is not what limits quality, and the step
   is not built further.
1. Unit tests:
   - a member staled through a rule changes the rate after
     `refresh-base-rates` and not before;
   - a rate with no reader takes no refresh;
   - the allowance is respected and the rows spent are returned;
   - a frozen member leaves the candidates.
2. Replayed grid, dormancy, refresh allowance R ∈ {0, 25, 100, 400} at the
   frontier settings. Compute counts the refresh time. Success:
   - the plateau is at or below head's 0.0591;
   - the f 0.5, q ≥ 200 cells recover;
   - the frontier lies left of dormancy alone.

## Go/no-go result

A prototype refreshed every member of every base rate before each shift's
queries: it needed all members at depth 0 with unbounded budgets, evaluated,
and took the dirty members. Replayed StationOps, 8 seeds, 10 modules, 20
shifts. Each cell is Brier, and compute per seed (queries + refresh):

| | head | head + refresh | dormancy | dormancy + refresh |
|---|---|---|---|---|
| f 2, q 300 | 0.0591 (20 s) | 0.0591 (46 + 26 s) | 0.0600 (19 s) | 0.0601 (41 + 25 s) |
| f 0.5, q 300 | 0.0607 (24 s) | 0.0608 (42 + 26 s) | 0.0655 (15 s) | 0.0654 (36 + 25 s) |
| f 0.5, q 200 | 0.0615 (14 s) | 0.0614 (34 + 23 s) | 0.0728 (12 s) | 0.0722 (27 + 22 s) |

The refresh moves rates (by up to 0.025 under dormancy, seed 1), but quality
does not change, and the head-dormancy gap stays: rates still differ by up to
0.07 between the two with refresh. Stale member values are not what
separates them.

What does is membership. On seed 1, shift 2, the rate `SealLeak new
ore-feed-pump` holds observations of h-0000..0003 and shift-01 under head,
but only h-0000..0003 under dormancy (forward aggregate 13), although the
shift-01 key exists in both and another aggregate over the same pattern
(80) has it in both. A key joins a rate only when it is delivered as an
answer to the rate's open member node. Deliveries are paid from the row
budget, and parked ones resume only when a later search walks that node. So
which instances a rate counts depends on how search spent its budget.
