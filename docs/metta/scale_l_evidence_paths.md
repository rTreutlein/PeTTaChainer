# Late evidence on scale l at 16 steps per query

Analysis only, with no code change. The build is master 2307ca50 with the
held-stale fix (`runtime_design_assumptions.md`, "While a query's evaluation
runs"). The runs are SupplyNet scale l spq16, seeds 1–3, traced with
per-round skeleton dumps and evaluation pops.

## Results

Posterior error (master → fix):

| | s1 | s2 | s3 |
|---|---|---|---|
| spq16 | 0.00083 → 0.00161 | 0.00275 → 0.00024 | 0.00124 → 0.00191 |
| spq32 | 0.00382 → 0.00002 | 0.00329 → 0.00008 | 0.00160 → 0.00000 |

Chainer seconds: master 91–101 at spq16 and 130–144 at spq32; the fix
124–138 at spq16 and 152–157 at spq32.

With twice the allowance, the fix is exact on every seed and master is not.
At 16 steps it loses on two seeds out of three.

## Where the error is

The fix's spq16 error sits in rounds 9–10, on the current period of a single
zone:

- s1: r9 zone 3 0.0072, r10 zone 4 0.0086;
- s3: r9 zone 2 0.0042, r10 zone 4 0.0144.

Its oldest-period roots are exact. Master's errors fall in other rounds: s1 r2
0.0026 and r8 0.0038; s3 r2 0.0112.

Example, s3 round 10, zone 4:

- posterior: (Front z4 t10) 0.169; master 0.169; fix 0.349;
- (Storm g19 t10): 0.264, 0.264, 0.397.

The fix still reads (Front z4 t9) near its value from before the lateness
reports on periods t7–t9 arrived (smoothed posterior 0.109).

## The evidence path

A shipment's lateness for period t(R−ℓ) arrives ℓ = 1–3 rounds late. It
reaches the current root through this path:

    Late (fact) → Delayed tier 2 (inversion) → Delayed tier 1 → Blocked
      → Storm → Front t(R−ℓ) → ℓ persist steps → Front t(R)

So the Late key sits at key depth 5+ℓ from the current root: 6, 7 or 8.

- The need passes freely only through key depth 2, and refreshes stale rows
  only at row depth 3.
- Beyond that it passes only through rows never computed.
- A row computed before the report arrived, and then staled by the new fact,
  is therefore beyond every need.
- Only the oldest-period roots bring that evidence in: Delayed t(oldest) is at
  key depth 2 from them. That is why the oldest roots are exact.

Rows of zone 4 in s3 round 10, by lag (stale / current):

| | fix lag 1 | fix lag 2 | fix lag 3 | master lag 2 |
|---|---|---|---|---|
| Blocked | 40 / 14 | 54 / 0 | 54 / 0 | 26 / 28 |
| Storm | 17 / 25 | 24 / 18 | 42 / 0 | 6 / 36 |
| Delayed | 152 / 28 | 180 / 0 | 180 / 0 | 124 / 56 |

Of the fix's stale lag-2 rows, 28 Blocked and 56 Delayed rows have no view at
all. The need does pass through those, but the allowance ran out first. In
round 10 the fix left 188 lag-1 and 224 lag-2 Delayed rows unpaid; master paid
all of them. Two things block the evidence:

1. **The refresh rule.** Rows that are stale and have a view are never
   reached at depth 4 or more.
2. **Allowance order.** Among the rows the need does reach, the allowance
   went elsewhere first. The fix spent about 250 units on lag-6 rows near the
   oldest root, and about 900 more near-root computations went to the held
   rows' refresh.

Master happened to leave those path rows never computed in earlier rounds,
because its frozen evaluations computed less. Its need then passed through
them, and with the new facts in place it paid them: in s3 round 10, master
spent 836 allowance computations on lag-2 Delayed rows and 178 on lag-2
Blocked rows. That is an accident of starvation, not a policy. On s2 it does
not happen, and master is 11 times worse there.

## Waste in the allowance

Deductions onto the current period's unobserved Late keys take a large share
of the deep pops, paid or unpaid, over the whole s3 run: 38% for the fix
(15,559 of 40,626) and 44% for master.

- Their only rule reader is the Delayed inversion from that Late key.
- That reader excludes every view of the Late key that depends on the same
  Delayed key, so none of those deductions can be used by it.
- They are needed only because the need marks whole premise keys.
- Not checked: whether base-rate folds take these views as members.

## The cost of reaching the evidence

- About 576 lateness facts arrive per round: 72 routes with 8 shipments each.
  They spread over lags 1–3, so every zone-period at lag 1–3 gets new
  evidence each round.
- The upward rows of one zone-period are about 72 Delayed inversions, 18
  Blocked, 18 Storm and 6 Front: about 115.
- Over 4 zones and 3 lags that is about 1,400 computations per round. The
  deep allowance at spq16 is about 4,100 units, and the Late-prediction waste
  alone is 1,500–1,900 units per round.
- Doubling the allowance (spq32) buys exactness at about +20% time.

## Candidate designs

1. **Need a premise key's rows per reader, skipping those its reader
   excludes.**
   - When the need reaches key K from a row R concluding X, it skips K's rows
     that read X: R excludes their views anyway.
   - Cost: constant per need step, and it needs a row-level (not key-level)
     need set.
   - Benefit: frees roughly 40% of the deep allowance at no loss of accuracy.
     It would move spq16 toward the spq32 results without paying for spq32.
2. **Carry each new fact's change up its path, charged to ingestion.**
   - A stored fact already brings its own delivery allowance (ten rows per
     fact and step). Give it an evaluation allowance as well: about two
     computations per level of its upward path. It would refresh stale rows
     on the path nearest the root first, through `&sk_stale_reader`.
   - Cost: about 1,400–2,900 computations per round on scale l, roughly
     +10–20% time, constant per new fact.
   - Benefit: late evidence reaches the current front within a round or two,
     whatever the query asks.
   - My earlier attempt to refresh every stale row from the query's
     allowance, nearest the root first, was worse everywhere (m4 s2 0.0024 →
     0.0049, l16 s1 0.0029 → 0.0058). The refresh has to be targeted at
     changed evidence and paid for separately.
3. **Order the allowance by cause.**
   - Compute rows whose cause is an outside change (new facts) before rows
     an internal change scheduled again.
   - Cost: none beyond a heap key.
   - Benefit: uncertain. Capping deep rows at one computation per evaluation
     made scale l much worse (l16 s1 0.0060, s2 0.0121), so this may only
     reorder, never drop.

Design 1 is pure waste removal: constant cost and better per step, the
anytime principle exactly, so it should come first. Design 2 is the anytime
answer to late evidence: cost proportional to what arrived, and each step
moves the evidence one level nearer the roots. It also replaces master's
accidental reliance on rows it never computed.
