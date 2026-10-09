# Dependency tracking that does not grow with history

Status: option A built, October 2026. Branch `dependency-tracking`.

## Problem

Every skeleton value carries a dependency set: the hashes of the keys its
derivation went through. A row's view starts from its own key (`sk-acc` starts
with `(cons $khash ())`) and adds every premise value's set; a stored fact adds
its own key; a fold adds its own hash and, except for base rates, its members'
sets. The sets are SWI ordered lists, so the set is the transitive closure of
the derivation.

On StationOps with the temporal model the closure covers the whole station
history. A module's shift-end state passes through each shift's shortfall
posterior, a FoldAllTruth over every candidate of that shift, and each
candidate carries its own chain back to shift 1. Measured at 20 modules, seed
7, merged head 0b4a4576:

| | shift 2 | shift 10 | shift 19 |
|---|---|---|---|
| dependency set, mean (max) | 17 (91) | 101 (913) | 177 (1,699) |
| `SealLeak` dependency set, mean | 18 | 176 | 340 |
| evidence list, mean (max) | 5 (9) | 8 (41) | 10 (77) |
| value term size, mean | 267 | 640 | 921 |
| row term size, mean | 590 | 643 | 646 |
| proof term size, mean | 22 | 25 | 25 |

The largest set at shift 19 (M01) holds 1,697 keys over all 20 modules and all
19 shifts. Every row computation unions, copies and type-checks sets of that
size, so a late forward call takes 2.4 times an early one while computing
fewer rows (profile of forward calls 8 and 113: copying in findall 27 to 330
ticks, garbage collection 94 to 380, runtime type checks 142 to 380).

## What the sets are used for

1. **Self-support exclusion** (`sk-admits?`, `sk-value`, `sk-leaf-step`,
   `sk-given-view`, `sk-given-meets?`): does a value depend on any key of an
   exclusion list? The list is the reader's own key, keys unifying with it,
   compound parts for inverted rules, given statements, or the base-rate folds
   a forward take updates.
2. **Change propagation** (`sk-reader-affected?`, `sk-fold-changed`): does a
   change's value depend on one key (the reader's or the fold's)?
3. **View dominance** (`sk-dominated?`, at every `sk-store-view!`): an older
   view is dropped when the new view's set is a subset of its set.
4. **Termination** (`sk-new-support?`): a recomputed view whose value did not
   change is kept only when it brings a key the row's views never had. The
   keys are finite, so cyclic evaluation ends.
5. **Clash cost** (`sk-clash-on`): conditioning costs
   2^k × (1 + |value's set|).
6. **Equality** (`sk-same-view?`, `sk-value-same`): a view is unchanged when
   its truth value, evidence and set are equal.

Measured over a 20-shift run (20 modules, seed 7):

- Exclusion: every read with an exclusion list had a list of one key. About
  85% of those reads return the open value unchanged, 12–14% return nothing
  (every view depends on the reader), under 1% return a different value
  (|Δstrength| ≤ 0.04). The rates do not change over the run.
- In a sample of 1,012 fully excluded reads over all 20 shifts, the excluded
  key was always at distance 1: a row of the key read has the reader's key as a
  direct premise (a rule and its inversion reading each other).
- Dominance: about 3,000 checks per 5 shifts, 40% prune. Replaced views kept
  in `&sk_view`: 1,411 at shift 20 against 10,065 latest views.
- Termination check: 2 calls in the whole run.

## The constraint

Exact transitive membership cannot be had with both constant-size values and
constant-time queries in general: that is DAG reachability indexing. A
representation chooses where the cost goes:

- **Flat sets (today):** query O(log n), but building each value costs its
  closure, and values carry it.
- **Interned DAG of set nodes:** a value carries one node id; union is a new
  node over its operands (O(premises)); equal operand lists hash-cons to one
  id. Membership walks the DAG. A negative answer, the 85–88% case, has to
  visit the whole closure unless pruned; memoizing per (node, key) stores up to
  closure × distinct keys facts.
- **Bounded provenance:** a value keeps the keys within d derivation steps,
  exactly, and nothing older. Size is bounded by fan-in^d, independent of
  history. Self-support through a cycle longer than d is not detected, so
  evidence on such a cycle can count twice.

## Options

### A. Exact: interned DAG with summary-pruned membership

A value's set is an integer node id (0 for the empty set). Prolog tables:
`deps_leaf(Id, Hash)`, `deps_node(Id, Key, Children, Mask)` with the children's
ids sorted, interned by the children list under its hash `Key` (one clause
found by id or by key). Each node also stores a fixed-width
bitmask (bits of its leaves' hashes, OR of its children's masks).

- Membership: a clear bit answers no at once; otherwise walk the children
  whose masks have the bit. Small subtrees have sparse masks, so the walk
  prunes most branches; large nodes saturate and are always entered.
- Dominance: equal ids are a subset at once; otherwise exact subset by walking
  the new node with a visited set. Dominance stays linear in the closure for
  unequal sets, about as costly as today but without carrying the sets.
- Termination: exact, by the same subset walk (rare).
- Clash cost: exact closure size, memoized per node (immutable).
- Equality: id equality, which is weaker than set equality. A recomputed row
  over recomputed premises gets a new id for an unchanged set, so the change
  reaches its readers once more; termination still holds through (4).

Cost: values become constant size (removes the copying, GC and type-check
growth). Membership is fast when masks prune, linear in the worst case. Dominance stays
linear for unequal sets. No accuracy change.

### B. Bounded provenance with forgetting

A value keeps the exact keys within d steps of it (its own key, its premises'
keys, their premises' keys, up to d), as a flat sorted list, plus the epoch
summary symbols of what it absorbed beyond d. A summary's contribution to a
value's confidence decays with its age, so evidence counted twice through a
cycle longer than d enters with geometrically shrinking weight: the error is
bounded, not cancelled. (Double counting biases toward overconfidence; it does
not average out on its own.)

- d = 2 covers every exclusion measured on StationOps (all at distance 1),
  with margin.
- Size is bounded by fan-in^d, independent of history: constant per row.
- Membership, dominance, termination, clash cost and equality keep today's
  code on small flat lists.

Cost: constant per row. Accuracy: identical where all cycles are shorter than
d; beyond that, bounded double counting. This needs a decision on the decay
(forgetting rate per epoch) and on what an epoch is (a forward run, a shift).

### C. Exact flat sets, interned

Values carry an id of an interned flat set; union is computed once per
distinct operand pair. Removes copying and type checks; union stays linear in
the closure. Does not meet the goal.

## Recommendation

Build A first: it is exact, removes most of the measured growth (values stop
carrying the sets), and needs no decision on forgetting. Measure the late
forward call against the merged head. If membership or dominance walks then
dominate the profile, B is the fallback that is constant by construction, and
the measurements above say it would change no StationOps exclusion at d = 2.

## Result (option A, October 2026)

Exact dominance made option A slower than flat sets: collecting an old view's
closure (about 11,000 nodes for a late value) at every view store was 58% of
a late forward call. Dominance now compares the masks (`deps-mask-within?`,
65,536 bits): exact when the new view has a key the old one lacks, which keeps
the old view; a collision can drop an older view a consumer could have read,
never admit a self-supporting one. Termination and the clash cost stay exact
(rare). Peak memory of a 20-module run: 4.0 GB against 3.8 GB with flat sets.

StationOps against flat sets (0b4a4576), same batches:

| | score | Brier | forward | queries |
|---|---|---|---|---|
| 10 modules, 8 seeds | identical per seed | 0.0591 / 0.0591 | 408 → 416 s | 136 → 136 s |
| 20 modules, seeds 3, 7 | identical per seed | 0.0504 / 0.0503 | 177 → 174 s | 44 → 38 s |

Largest forward call per shift at 20 modules (shifts 1, 5, 10, 15, 20), seed
7: flat sets 1.0, 1.3, 1.5, 1.6, 1.8 s; option A 1.1, 1.2, 1.3, 1.3, 1.3 s.

A mask's fill grows as 1 − e^(−n/65536) with closure size n (2.6% at 1,700
keys, 53% at 50,000), so masks only postpone the growth: past a closure size
they stop pruning membership and stop deciding dominance. Bounding closures
by forgetting into decaying summaries (option B) is what keeps a step constant
for good; the node DAG lets it cut old subtrees off at epoch nodes.

## Mask width: 4,096 bits (October 2026)

65,536 bits was chosen so that masks stay sparse on the largest closures then
measured, StationOps at 20 modules (up to about 1,700 keys: 2.6% fill), since
a collision in `deps-mask-within?` drops an older view a consumer could have
read. The price is 8 KB stored per interned node: 256 MB for 31,476 nodes on
SupplyNet m at 4 steps per query, the largest store once evidence sets were
interned ([evidence_sets.md](evidence_sets.md)).

At 4,096 bits the same closure fills 34% of its mask, so dominance can drop an
older view by collision more often and a membership walk prunes less.
Measured against 65,536, both with interned evidence:

- `compare.sh master <build> --full`: accuracy identical in all 73 cases and
  every StationOps replay belief stream identical, for both widths.
- StationOps live, 20 modules, 20 shifts, seeds 3 and 7, the setting the
  width was sized for, four runs side by side: game streams identical; peak
  memory 894 → 709 MB and 815 → 661 MB; forward plus query time 52.5 → 53.6 s
  and 48.8 → 49.2 s (`query_many` +7–10%, forward unchanged).
- SupplyNet scale, seed 1: peak memory m/4 1,345 → 1,087 MB, l/4
  1,651 → 1,354 MB, l/16 5,075 → 4,299 MB; seconds m/4 39.2 → 35.9, l/8
  82.6 → 66.3.

16,384 bits gave the same StationOps streams. 4,096 is kept: no measured
answer changes, and memory and time drop everywhere except a 1–2% slower
StationOps run at 20 modules. A closure ten times larger fills most of a
4,096-bit mask (1 − e^(−n/4096)); then most newer views look within older
ones, so dominance drops older views a consumer could read, and membership
walks most of the closure. Bounding closures (option B) is the remedy, as
above.
