# Skeleton-core size, complexity, and performance review

## Scope and baseline

Reviewed local `skeleton-core` at `60bff8d1b34476ad954fbb78deb8ea32059769fb`.
The candidate is the uncommitted optimization on that same branch/worktree.
The baseline was a `git archive` of that commit under `/tmp`, using the same
repository `.venv`. No fetching, runtime rebuilding, or ConceptNet export
regeneration was performed. Existing untracked scratch benchmarks were excluded
from the comparison and preserved.

The machine is an AMD Ryzen 7 5700X3D, 16 logical CPUs, under WSL2. Both sides
use the installed PeTTa runtime through the project's shared `.venv`; the
runtime source path is `.venv/lib/python3.10/site-packages/petta/_runtime`.
`uv.lock` resolves PeTTa from the local `../../PeTTa` package. These measurements
are local comparisons, not claims about the latest upstream runtime.

## Size and complexity

The rework at the baseline, compared with local `master` (`5aa0db34`):

| Scope | master | skeleton baseline |
| --- | ---: | ---: |
| Production `.metta` and `.pl` files under `pettachainer/metta` | 30 | 23 |
| Physical lines, including comments and blanks | 7,535 | 7,351 |
| Distinct MeTTa equation names | 602 | 537 |
| Backward implementation files | 10 | 2 |
| Backward implementation lines | 3,087 | 2,625 |

The skeleton additionally has a 248-line journal/types module. Counting that
module is necessary when assessing the apparent reduction in the backward
folder. The overall rework reduces lines by 2.4% and equation names by 10.8%.
Its structural simplification is larger than its textual shrinkage.

Construction and evaluation are separated clearly. Durable rows avoid rebuilding
completed joins; ingestion journals additions; root demand limits which stale
rows are refreshed. However, the journal declares 42 spaces. Correctness still
spans construction, retained versions, consumer-specific exclusions, folding,
and invalidation. Flattening these into a single store would hide these
responsibilities and weaken indexing rather than simplify the algorithm.

The optimization removes 186 production lines (2.5%) and reduces production size to **7,165 lines** and MeTTa equation
names to **513**. Twenty-four MeTTa helpers disappear; the native variant utility adds
two Prolog predicate arities. Across production code, syntactic `if`/`case`
expressions fall from 745 to 729. These
counts describe source structure, not a formal cyclomatic-complexity proof.

## Changes

1. **Root-key deduplication uses a temporary variant trie.** Previously, both
   demand discovery and result collection folded over the growing list of
   accepted keys, comparing every preceding key. For fixed-size keys that was
   quadratic. Trie insertion is proportional to the represented key size and
   retains the first occurrence. It strips checker attributes on a copy, keeps
   the original returned term, preserves variable sharing, and compares full
   variants rather than treating hashes as identities. Cleanup runs on failure
   and exceptions as well as success. No durable index is added.
2. **Stored rows contain only premises evaluation needs.** Ground CPU calls
   already evaluated while constructing a join are removed when storing its
   row. Previously every row evaluation, including a retry after an evidence
   clash, filtered and reversed the same immutable premise list. Formula and
   aggregate premises requiring live evaluation remain, in their original
   order. This removes two traversals and their temporary lists per evaluation,
   and reduces retained row payloads when a rule contains ground computation.
3. **Result processing avoids redundant passes.** Conversion already skips
   missing values, so the preliminary filter and reversal disappear. A
   materializing query finds its first proven value lazily. Subsumption stops
   at its first witness instead of traversing the remainder with a boolean
   accumulator. Answer order is preserved.
4. **Fold finalization builds its view directly.** An intermediate fold-state
   object, a singleton proof list, and two single-use helpers disappear.
   Evidence and dependency rules for base rates and uniform priors are retained.
5. **Demand checks use the work item's existing hash.** They no longer extract
   the key through a wrapper and hash it again for every scheduling check.
6. **Retired runtime machinery is removed.** The consumer audit found obsolete
   backward scoring functions, goal classification/key helpers, agenda and fold
   row types, and unused evidence/forward-maintenance helpers. Tests that only
   exercised retired helpers were dropped; live merge and Member tests now call
   their actual implementation. The queue benchmark now measures expansions and
   expanded skeleton nodes instead of querying the deleted arena or expecting
   retired counters. Forward pruning retains its fixed 1,000-entry target and
   no longer reads a backward root counter that production never writes.
   The documented tuning API remains callable and its description now names
   the forward chainer, which is its actual consumer.

Replacing `fold-semidet`/`map-semidet` with the library's effect-polymorphic
walkers failed the pinned compiler's strict determinism check. That experiment
was reverted immediately. These helpers remain a demonstrated compiler boundary.

## Remaining costs

- Answer subsumption still has a quadratic worst case when no answer subsumes
  another. The new trie removes the two key-deduplication scans; it does not make
  the whole broad query linear. Indexing subsumption by proof identity is a
  separate possible optimization, requiring careful treatment of open proofs.
- Warm queries still walk their reachable skeleton and reconstruct the needed
  key set. Root-selective evaluation saves work on unrelated old queries, but
  does not make a repeated query constant time.
- `sk-new-support?` unions dependencies from a row's retained versions. Its
  cost grows with that history. Older versions also serve compatibility-filtered
  consumers, so dropping history is not a safe size optimization.
- New open answer keys invalidate cached unifier sets broadly. This is reasoning
  work, not eager inference at ingestion, but can be significant for workloads
  with many variable-bearing answers.
- `runtime_design_assumptions.md` and parts of `API.md` retain descriptions of
  the previous arena/frontier implementation. They should be reconciled with
  the completed rework before treating their internal-state descriptions as an
  exact account of this branch.

## Measurement and validation

The paired benchmark runs each side in a fresh process, alternates order, and
uses three pairs per workload. Broad-answer loading is outside timing; each
cold and warm zero-step query checks every complete fact, proof, truth value,
and answer count. Durable and Member benchmarks use their existing validation
and unchanged budgets. The [raw result artifact](skeleton_core_optimization_2026-09-25.json) accompanies this report.

Median query times (seconds), three fresh-process pairs:

| Workload | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |

| 100 answers, cold | 0.051383 | 0.030611 | -40.4% |
| 100 answers, warm | 0.049094 | 0.027689 | -43.6% |
| 600 answers, cold | 1.577648 | 0.755448 | -52.1% |
| 600 answers, warm | 1.556938 | 0.732994 | -52.9% |
| 1,800 answers, cold | 14.280785 | 6.539537 | -54.2% |
| 1,800 answers, warm | 14.127763 | 6.424272 | -54.5% |
| Durable: five batches, eight roots, 300 steps | 0.918744 | 0.902663 | -1.8% |
| Member: initial query, 48 members, 400 steps | 0.105639 | 0.104915 | -0.7% |
| Member: four incremental queries, 400 steps each | 0.117885 | 0.115182 | -2.3% |
| Member: four forward steps | 0.003774 | 0.005889 | +56.0% |
| Member: complete incremental work | 0.132078 | 0.131478 | -0.5% |
| ConceptNet: 100 steps, two answers | 3.158443 | 3.271182 | +3.6% |

The broad-query improvement is large and consistent. The 1–4% differences in
ordinary derived workloads are small enough to treat as approximately neutral
on this machine. Durable total query time is 1.8% lower; the final batch is
6.7% faster. ConceptNet is 3.6% slower at the median. Three pairs do not establish
statistical significance for these small differences. Benchmark processes ran
sequentially, without concurrent test suites.

The forward-only phase is 56% slower, an additional 2.1ms across four steps.
This is a real phase-latency measurement, not omitted from the comparison.
Restoring each cleanup module individually did not remove it. Native profiling
reproduced the difference and found a 2ms SWI garbage collection in the
candidate's first forward call; the baseline instead collected during the
following query. Across the four forward calls and intervening queries both
profiled runs collected four times, spending 9ms in GC. Candidate forward calls
used 7,000/6,998 inferences versus baseline 7,024/7,020, including identical
profiling-call overhead. The combined incremental workload is essentially
unchanged (-0.5% median). No GC tuning or forced collection was introduced to
move costs outside a timer. Raw counter snapshots are in the artifact.

Reproduce one broad-answer run with:

```bash
.venv/bin/python pettachainer/benchmarks/skeleton_answers.py \
  --repository /path/to/checkout --facts 600 --json-out /tmp/answers.json
```

Run each pair in alternating order in fresh processes. The other workloads use
`durable_query_many.py --roots 8 --stable-roots 2 --shifts 5 --steps 300` and
`member_inheritance.py --initial-members 48 --deltas 4 --query-steps 400
--forward-steps 1`. Their existing setup, answer-count, and individual timing
metrics are preserved in the raw data.

The baseline checkout can be reconstructed without changing the active worktree:

```bash
baseline_dir=$(mktemp -d /tmp/skeleton-baseline.XXXXXX)
git archive 60bff8d1b34476ad954fbb78deb8ea32059769fb | tar -x -C "$baseline_dir"
ln -s "$(pwd)/.venv" "$baseline_dir/.venv"
```

Use that directory as `--repository` (or `--candidate-repo` for Member), keeping
the benchmark script and interpreter from the candidate checkout on both sides.


## Final validation

- Baseline MeTTa suite: **69 passed, 0 failed**.
- Final `PETTA_JOBS=4 scripts/test_metta.sh`, also repeated through verification:
  **70 passed, 0 failed**. This includes examples and formula/lowering tests.
- `scripts/strict_check_metta.sh`: passed with `--strict --strict-det`.
- `scripts/verify.sh`: all four gates passed; **58 Python tests**, 50 recorded
  query rows with zero aborts, import-scaling late/early ratio **1.006** (limit
  1.5), and exactly **two ConceptNet results**. Total wall time: 128s.
- Repaired queue benchmark: `--mode backward --fanouts 5 --steps 20 --repeats 1`
  passed its complete proof/TV checks and recorded exactly 20 expansions.
- `git diff --check`: passed.

The new key regression checks first-occurrence ordering, alpha-equivalent
variable keys, distinct sharing patterns with the same coarse hash, unchanged
input variables, distinct contexts, constrained queries, and repeated open
queries. Existing aggregate, materialization, sampling, budget, and full-proof
regressions passed after the row and fold changes. Public signatures listed in
`API.md` were retained. Changes remain uncommitted in the `skeleton-core`
worktree; the initial untracked benchmark files were preserved.
