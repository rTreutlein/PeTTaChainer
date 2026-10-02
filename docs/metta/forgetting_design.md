# Forgetting: bounding memory and per-step cost

Status: design, October 2026.

## Why

The chainer keeps everything it ever built: every key's rows, views, merged
values, proofs and dependency nodes, and every fact. On StationOps with the
temporal model (20 modules, seed 7, 30734720) memory and the late forward
call keep growing with the number of shifts, though answers per shift need
only the recent past:

| | shift 10 | shift 20 | shift 40 | shift 60 |
|---|---|---|---|---|
| peak memory | 2.1 GB | 3.8 GB | 7.3 GB | 10.7 GB |
| largest forward call | 1.3 s | 1.3 s | 1.8 s | 1.6–2.4 s |

Census of the stores (bytes / rows):

| store | shift 10 | shift 20 | shift 40 | shift 60 |
|---|---|---|---|---|
| `&sk_link` | 1,243 MB / 150k | 2,488 MB / 300k | 5,005 MB / 602k | 7,402 MB / 891k |
| `deps_node` | 163 MB / 24k | 320 MB / 46k | 639 MB / 92k | 938 MB / 136k |
| `&sk_row` | 44 MB / 8k | 87 MB / 16k | 175 MB / 31k | 256 MB / 46k |
| `deps_leaf_hash` | 41 MB | 82 MB | 164 MB | 244 MB |
| `&sk_latest` | 17 MB | 38 MB | 86 MB | 142 MB |
| `&sk_forward_taken` | 18 MB | 39 MB | 84 MB | 135 MB |
| `&sk_merged` | 17 MB | 36 MB | 79 MB | 124 MB |
| `&sk_forward_stored` | 13 MB | 30 MB | 66 MB | 109 MB |
| `&kb_prefix` | 15 MB | 33 MB | 62 MB | 101 MB |

Everything grows linearly with history. Two stores are representation costs
rather than history, and come first.

## Stage 0: representation (no forgetting)

1. **Join links.** `sk-extend!` records that a join was extended by an answer
   as `(sk-join-link <the whole partial join> <key>)` in `&sk_link`: about
   8 KB per row, 15,000 rows per shift, 70% of memory. The record only needs
   to identify the join and the key. A join waits under its owner node with a
   stable row in `&sk_wait`; the link can name that row by an id (a counter
   assigned when the waiter is stored) and the key by its hash, verified by
   variant on the stored waiter when the ids are equal.
2. **Dependency masks.** A 65,536-bit mask is stored per node, 7 KB each,
   0.9 GB at shift 60. A leaf needs no stored mask (its bit is computed); a
   node over few keys can keep its keys' bits as a short list and only build
   a mask past a size. Same answers, a fraction of the memory.

Stage 0 changes no answer; it removes most of the memory and leaves the
linear growth of what history really costs.

## Stage 1: freezing settled keys

Time is marked by the caller: `(advance-epoch $kb)` ends an epoch (StationOps:
a shift). A key records the last epoch a query or forward run needed it.

At an epoch boundary every key not needed for H epochs is **frozen**:

- Its current merged open value becomes one summary fact for the key, with
  the proof `(forgotten <key-hash> <epoch>)`, the evidence of one summary
  symbol, and a dependency set of the exact keys within d = 2 derivation
  steps of the key plus the summary symbol. (Every self-support exclusion
  measured on StationOps was at distance 1; d = 2 keeps them exact with
  margin.)
- Its rows, views, merged values, waiters, join links, support and stale
  marks are removed, and its forward-stored copy is replaced by the summary.
  The key becomes a leaf; the rows reading it keep reading it.
- The dependency nodes and proofs only it reached become unreachable and are
  swept (mark from the live values at the boundary).

Freezing a key costs its own rows once, so it is amortized constant per key.

**Decay.** A summary's confidence decays with its age: its observation count
n = c·k/(1−c) becomes n·λ^age, read when the summary is read. So:

- what the forgotten past contributes shrinks the further it lies back, as a
  filter's state forgets old measurements;
- evidence counted twice because a summary hides an overlap (a cycle longer
  than d through forgotten keys, or a new derivation into a frozen key that
  shares the summary's sources) enters with geometrically shrinking weight.
  Double counting biases toward overconfidence and does not cancel by itself;
  decay is what bounds it.

**Late evidence.** A new fact about a frozen key (StationOps: an inspection
label resolved a shift later) is revised against the summary, as a filter
takes a late measurement. A new rule row concluding a frozen key is computed
as usual and merged with the summary; the overlap is not detected, which decay
bounds. A frozen key is never re-expanded.

**Parameters.** H (epochs idle before freezing), λ (decay per epoch), d
(exact window). Defaults to be set from the sweep below; H = ∞ is today's
behavior.

## Stage 2: forgetting absorbed facts

Facts of old epochs that every reader has absorbed (base-rate aggregates keep
their contributions; their keys are frozen) can be dropped from `&kb` and its
indexes. Optional; measure after Stage 1.

## Evaluation

StationOps, 20 modules, 60 shifts, seeds 3 and 7, two jobs at a time
(a run grows to 11 GB today):

- Stage 0 against 30734720: identical scores per seed; peak memory; largest
  forward call per shift.
- Stage 1, sweep H ∈ {2, 4, 8} and λ ∈ {1, 0.95, 0.8}: score, Brier, log
  loss, peak memory, and whether the largest forward call stays flat over 60
  shifts.

The goal is a step whose cost and memory stop depending on how long the run
has been, while the answers move as little as possible from H = ∞.
