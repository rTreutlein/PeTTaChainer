# Numeric retirement performance regression (#23)

The expensive ownership lookup introduced by the memory-retirement series is
already repaired on the requested master, `580acf21`, by `8a62fe49` (remove the
copied ownership key; validate the owned clause after selecting its scalar hash).
This branch adds a deterministic regression for that repair. It does not change
runtime behavior or duplicate the older four-column representation.

## Reproduction and attribution

All experiments use the copied `ChainerGame-mining` harness at `45bfdaa9`, the
worktree's pinned interpreter/VM, budget 40, seed 1, and historical input ordering
matching the issue's paired reproduction. The mining checkout and GitHub were
read-only. Processes used normal admission priority, the 16,000,000 KiB virtual
memory limit, DISPLAY unset and stdin closed. Raw evidence is in
`/nexus/Dev/OpenCog/bench/results/numeric-perf/`; its `summary.json` records the
explicit revision pins, source trees, timings, CPU, RSS, input hashes and VM hashes.

Eight width-32 decisions do not expose the regression: synchronized mining
means are 1.802 vs 1.880 s/step (1.04x). The smallest synchronized prefix tested
that clearly separates the endpoints is **32 decisions**:

| Revision | Mining s/step | Total active wall s/step | Active CPU s/step | Peak MiB |
|---|---:|---:|---:|---:|
| `7925f8d5` | 2.040 | 3.425 | 3.576 | 1438.5 |
| `171b2820` | 4.087 | 7.079 | 8.869 | 1741.2 |

This reproduces a 2.00x mining slowdown at the smaller size, not the reported
5.60x at 64 decisions. Sample logs are byte-identical, generated-data and VM
hashes match, and maximum start skew is 0.173 ms. These are one-seed diagnostics,
not population confidence intervals. The original 64-decision evidence remains
unchanged.

The original five commit hashes in the brief are available and runnable.
Their exploratory width-8, 16-decision measurements are:

| Revision | Change | Mining s/step |
|---|---|---:|
| `4e6b059b` | original series parent | 3.791 |
| `a4eadfb3` | known-conclusion retirement | 3.746 |
| `85738929` | keep rule truths live | 4.126 |
| `d0a0ca76` | preserve shared premise work | 9.975 |
| `67b616c2` | bounded checks and digest reuse | 6.188 |
| `0f73f1ce` | remove reverse reference index | 6.445 |

The large increase enters with shared-premise preservation; bounded checks
recover part of it. These runs were not synchronized, so small adjacent timing
differences are not causal claims. Those original commits precede the provenance
rebase onto `7925f8d5`. The corresponding rebased middle commits are
`5b2c069e`, `7f7ea3d9`, `4e8d18e7`, `dd6191aa`, `715e78ca`; they have a parse error
in `sk-advance!` corrected by the final `171b2820` integration, which also repairs
join-store integration. They cannot provide an unmodified runnable linear bisect.
The original-series measurements and the targeted selector experiment are kept
separate from the synchronized endpoint comparison.

The unpaired width-8 endpoint means were 5.233 (`7925f8d5`), 11.396 (`171b2820`),
and 5.832 s/step (`580acf21`). These suggested recovery on master and motivated
checking the actual ownership index rather than reverting memory retirement.

## Mechanism

SWI sampling of 12 width-8 decisions on `171b2820` attributes **27.76% of all
self ticks to `sk_search_clause/4`**, its largest individual predicate. The
realized indexes in `direct-profile-171b.tsv.indexes` show a selective index on
clause reference (column 4), and deep list indexes into the copied key (column 2).
There is **no root index on the scalar hash in column 1**. The deepest key index
has estimated speedup only 7.76 over a store whose clause-reference index has
69,253 distinct entries. Ownership existence checks for new facts consequently
pay for unrelated retained history.

`8a62fe49` changes the ownership row to `(Hash, Kind, ClauseRef)`. Its callers
select by `Hash` before checking the actual key on the owned clause; delivered
joins retain their existing 60-bit digest contract. SWI then realizes a root hash
index. The later-layout profile's index has speedup 300.65 and ownership uses only
0.38% of self ticks. That latter diagnostic also included the discarded enqueue
experiment below; the three-column representation is unchanged by that experiment.
The new regression independently verifies the requested master's lookup layout.

A two-line historical selector patch is retained as
`171b-hash-selector.patch`: read the four-column store with its key column
unbound, then compare the stored ground key after selection. It isolates index
selection without changing retained records, truth refinement, budgets or shared
premise work. In a synchronized width-8, 16-step pair, mining falls **12.601 to
6.762 s/step** and active CPU **22.908 to 11.517 s/step**. Predictions, verdict
events and recorded work totals are exactly identical. Maximum start skew is
0.193 ms. This is an experiment against the historical runtime, not code kept
for compatibility on master.

A further two-line simplification of master's enqueue existence checks was
rejected: synchronized 32-step mining means were 2.705 vs 2.677 s/step, about 1%.
Its raw artifacts use the names `candidate`, `cheap-owner-candidate` and
`direct-profile-candidate`. They do not describe a landed runtime patch.

## Regression and memory contract

The test builds 33 numeric-shaped prediction rules, asks 33 queries per period,
and ingests 33 one-hot labels (32 false) at another time. Unanswered prediction
ownership grows over four periods. It checks that the actual runtime realizes a
root hash index and that its estimated candidate count tracks the work of an
owner rather than the number of unrelated ownership keys. It has no wall-time
threshold. A fresh subprocess isolates the global JIT-index estimate from KBs
retained by other unit tests. The measured `(rows, keys, speedup)` values are
`(33,33,33)`, `(66,66,33)`, `(99,99,99)`, `(132,132,99)`: at most two estimated
candidates per lookup as unrelated history grows. The schema-adjusted historical
test fails on `171b2820` because the
hash index is absent; it passes on master. The schema adjustment exists only in
scratch evidence, not in the committed test.

The supplied Pong growth workload must enable the `NextPeriod` and `At`
functional declarations to reproduce the cited 0.65 GB figure. The copied
`mem-round2/growth.py --encoding history --decisions 1000 --functional` on master
ends at **653,287,424 bytes RSS (0.653 GB)**. The discarded enqueue experiment ends
at 652,255,232 bytes. No forgetting, forced collection, horizon change or source
filtering was added. The final branch has the exact master's `pettachainer/`
tree and therefore retains the existing memory repair. At decisions 500 and
1,000, master's last-100 mean decision cost is 65.259 and 65.464 ms respectively.
This is one finite replay; it does not establish constant total memory or a
universal bound on all mining work.

## Full 64-decision validation

| Revision | Mining s/step | Total wall s/step | Active CPU s/step | Peak MiB |
|---|---:|---:|---:|---:|
| 171b2820 | 31.148 | 40.201 | 52.814 | 4288.4 |
| master | 4.630 | 7.286 | 8.182 | 3030.7 |

Master is **6.73x faster in mining** with an **84.5% reduction in active CPU per decision** relative to the historical revision in this synchronized pair. Both workers exit 0.
Maximum start skew is 9.067 ms. Both see byte-identical sample logs and identical installed VM content.

The full comparison includes later miner correctness changes on master; the
historical selector pair above isolates indexing while preserving predictions.
These timings are shared-load, single-seed diagnostics, not an idle-machine
estimate or a population confidence interval.

| Decision interval | Historical mining s/step | Master mining s/step |
|---|---:|---:|
| 1-16 | 3.294 | 2.689 |
| 17-32 | 6.644 | 2.411 |
| 33-48 | 47.245 | 6.864 |
| 49-64 | 67.409 | 6.555 |

The deterministic gate bounds ownership lookup work as retained history grows.
A finite 64-step mining stream does not establish constant end-to-end cost.

Raw terminal records: `pair64-171b-master/status.json`,
`pair64-171b-master/synchronization.json` and each arm's `active_timing.json`
under the evidence directory.

## Reproduction commands and provenance

From this worktree, the narrow CLI is:

```bash
unset DISPLAY
ulimit -v 16000000
export PYTHONDONTWRITEBYTECODE=1 MININGBENCH_CAPPED=1 TMPDIR="$PWD/scratch"
export PYTHONPATH="BUILD:$PWD/scratch/harness/src"
/nexus/Dev/OpenCog/bench/capped --priority normal --slots 1 --peak-mb 2000 \
 timeout --kill-after=10 600 .venv/bin/python \
 scratch/harness/benchmarks/mining/numeric_review.py --worker \
 --width 8 --samples 16 --historical-order --out FRESH_OUTPUT
```

`paired_worktrees.py` is the scratch copy of the harness's synchronized runner,
with explicit build paths, labels and width options instead of hard-coded paths.
Its barrier, measured step boundaries and CPU measurements are unchanged. See
`pair32-prefix/synchronization.json`, `pair-master-candidate/synchronization.json`
and the other pair directories for the protocol records.

Frozen builds were made/resolved through `bench.compare.resolve`. Git lookup in
the unmodified mining adapter reports the enclosing bench checkout for a frozen
build; the original metadata is preserved, and `summary.json` supplies the
explicit frozen identity and `pettachainer/` tree. Runtime identity hashes the
installed VM content rather than inferring a VM revision from an enclosing Git
repository. Early diagnostics used the pinned runtime's default load cache; final
verification sets `PETTA_LOAD_CACHE` to the worktree's `scratch/load-cache`. Startup
is outside the paired step timers.

No mm2 changes, GitHub writes, push or merge were made.

## Validation

`capped --priority normal --slots 4 env PETTA_JOBS=4 scripts/verify.sh` passes
all six gates: lint, 133 strict MeTTa files, 124 Python unittests, import scaling,
judgment scaling and ConceptNet. There are zero aborts. The earlier shared-process
version of the new test failed because other tests skewed the global JIT estimate;
the final probe has an explicit fresh-runtime boundary. Raw final log:
`/nexus/Dev/OpenCog/bench/results/numeric-perf/verify.log`.

`compare.sh master <worktree> --full`, at normal priority, passes all 28 cases
with identical accuracy in all 27 scored cases. Its report is
`/nexus/Dev/OpenCog/bench/results/numeric-perf/compare-full-report.md`. The final
`pettachainer/` tree is exactly master's `a5282a41537a6b455fd20574305c93a0dff9ec92`.
There is no runtime timing change in this branch requiring a new curve sweep.

All three temporary bisect worktrees were removed by literal path. Frozen
source identities and the historical selector patch remain with the evidence.
