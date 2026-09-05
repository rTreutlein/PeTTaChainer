# Benchmark Notes

`particle_vs_nat.py` benchmarks direct distribution folding and threshold probability evaluation.

`particle_merge_resampling.py` benchmarks the structured-particle merge
compressor without depending on a finance-specific coefficient representation.
Its primary workload incrementally inserts arbitrary structured numeric
observations in deterministic shuffled order. It varies observation count,
maximum support, and dimensionality one axis at a time. One-shot batch
compression is reported separately as a baseline for every configuration.

Every workload runs in a fresh process and calls the normalized
`coalesce-pairs-to-budget` core directly. It intentionally excludes
`ParticleDist` allocation, particle-store retention, inference, and
finance-specific terms. Timing also excludes point generation, MeTTa source
construction, runtime loading, and benchmark-helper definition. The benchmark
rejects results unless support is exactly the requested budget, mass is
conserved, values are finite, and repeated runs produce the same final
particles. It also reports mean error, covariance error, and nearest-centroid
reconstruction error.

`forward_vs_backward.py` benchmarks a simple unary implication chain with optional distractor branches.
It reports:

- `backward_s`: query-only backward chaining time for the target
- `forward_goal_s`: forward chaining time with just enough steps to derive the target chain
- `forward_full_s`: forward chaining time with enough steps to drain all reachable derived facts

This is useful when forward chaining feels unexpectedly slow, because it separates:

- the cost of reaching the goal facts
- the cost of materializing unrelated reachable facts that backward search never touches

`backward_materialize.py` benchmarks the fact-materializing backward chainer.
In its default `same-target` mode, the plain run answers the same deep target repeatedly with normal
backward queries. The materialized run answers it once with `query-materialize`, which stores the
proof tree facts, then answers the remaining repetitions with a low step budget.

It also has `--mode sibling-targets`, which builds several related targets that all depend on the
same deepest chain fact. That mode measures reuse of a materialized intermediate fact rather than
reuse of the exact materialized target.

It compares:

- `NatDist`: exact fold via `NatDistAddBernoulliFromSTV`
- `ParticleDist`: approximate fold via `ParticleAddBernoulliFromSTV`

Both modes evaluate:

```metta
(DistGreaterThanFormula (fold-flat ... ) threshold)
```

## Run

```bash
python pettachainer/benchmarks/particle_vs_nat.py --sizes 100,500,1000 --particle-budgets 128,256,512 --repeats 2
```

```bash
.venv/bin/python pettachainer/benchmarks/particle_merge_resampling.py \
  --points 1024 --budget 128 --dimensions 2 --repetitions 1 \
  --point-sweep 256,512,1024,2048,4096 \
  --budget-sweep 32,64,128,256 \
  --dimension-sweep 1,2,4,8,16 \
  --json-out /tmp/particle-merge-scaling.json
```

Scaling mode uses shuffled incremental input as the primary workload and a
shuffled batch compression as its baseline. It varies one axis at a time and
deduplicates the shared base configuration. Besides raw time and throughput,
it reports nanoseconds per estimated candidate-coordinate comparison, based on
`(points - budget) * budget * dimensions`.

```bash
.venv/bin/python pettachainer/benchmarks/forward_vs_backward.py --depths 10,25,50 --noise-branching 8 --repeats 3
```

```bash
.venv/bin/python pettachainer/benchmarks/backward_materialize.py --depths 5,10 --queries 200 --repeats 3
```

```bash
.venv/bin/python pettachainer/benchmarks/backward_materialize.py --mode sibling-targets --depths 5 --queries 20 --repeats 3
```

`incremental_ordinary_base_rates.py` is optional and is not part of `core_suite` or
`scripts/ab_bench.sh`. It times the inversion case those suites skip: a computed
`P($x)` snapshot, then one-step forward patches of new `P` facts.

```bash
PYTHONPATH=pettachainer/benchmarks .venv/bin/python \
  pettachainer/benchmarks/incremental_ordinary_base_rates.py \
  --initial-facts 128 --deltas 32 --query-steps 2000
```

## Output Columns

- `n`: number of Bernoulli updates folded into the distribution
- `budget`: particle budget (`ParticleSetBudget`) used for the particle run
- `nat_eval_s`: mean NatDist evaluation time
- `particle_eval_s`: mean ParticleDist evaluation time
- `speedup_nat_over_particle`: `nat_eval_s / particle_eval_s` (>1 means particle is faster)
- `nat_strength`: exact threshold probability
- `particle_strength`: approximated threshold probability
- `abs_err`: absolute difference between strengths
- `nat_conf`: NatDist confidence (currently 1.0)
- `particle_conf`: particle computation confidence (currently `1.0`; particle-budget approximation quality is not yet represented)
- `particle_atoms`: number of stored particle atoms after evaluation

For `forward_vs_backward.py`:

- `depth`: length of the goal chain
- `noise_branching`: extra non-goal rules fired from each goal fact
- `rules`: total rules loaded into the KB
- `reachable_facts`: total facts reachable from the seed if forward chaining drains the agenda
- `backward_s`: mean backward query time
- `forward_goal_s`: mean forward time to derive the goal chain
- `forward_full_s`: mean forward time to drain all reachable work
- `goal_over_backward`: `forward_goal_s / backward_s`
- `full_over_backward`: `forward_full_s / backward_s`

For `backward_materialize.py`:

- `mode`: `same-target` or `sibling-targets`
- `depth`: length of the shared implication chain
- `queries`: number of queries answered in the batch
- `rules`: total implication rules loaded into the KB
- `query_steps`: step budget used for the plain queries and first materializing query
- `cached_steps`: step budget used after materialization
- `plain_batch_s`: mean time to answer all targets with normal backward queries
- `materialize_first_s`: mean time for the first `query-materialize`
- `materialized_tail_s`: mean time for the remaining normal queries after materialization
- `materialized_batch_s`: `materialize_first_s + materialized_tail_s`
- `total_speedup`: `plain_batch_s / materialized_batch_s`
- `tail_speedup`: estimated non-materialized tail cost divided by `materialized_tail_s`

## Agenda Growth and Pruning

`bounded_queue.py` measures priority agenda growth in both chainers. Input
generation and runtime loading are outside setup timing; compilation is timed
separately from reasoning. The backward fixture has one productive weak proof
and alternative branches with intermediate producers. Those branches survive
the structural feasibility filter and enter the agenda. Every run checks the
complete productive proof and truth value, zero search aborts, and sufficient
agenda pushes and pops. Backward timings include opt-in query metrics.

Forward runs require exactly the complete derived fact groups for the seeds
processed within the budget, including their proofs and truth values. They do
not use backward queries to validate forward work. Seed groups may appear in
any order because equally ranked seeds have no public ordering guarantee.

Run the same benchmark version on both checkouts:

```bash
.venv/bin/python pettachainer/benchmarks/bounded_queue.py --fanouts 2000,8000 --steps 100 --repeats 3
```

Or compare pruning enabled and disabled within the same checkout:

```bash
.venv/bin/python pettachainer/benchmarks/bounded_queue.py --fanouts 2000,8000 --steps 100 --repeats 3 --compare-pruning
```

To test many goals that each have a small fanout below the pruning factor:

```bash
.venv/bin/python pettachainer/benchmarks/bounded_queue.py --mode forward_many_small --fanouts 32 --seeds 100 --steps 100 --repeats 3 --compare-pruning
```

The backward counterpart connects hubs with small local fanouts. It reports
`expanded_hubs` from the final query arena, outside timing, and rejects a
many-small run that never explores beyond the first hub. Increase `--steps`
if the chosen fanout prevents reaching another hub:

```bash
.venv/bin/python pettachainer/benchmarks/bounded_queue.py --mode backward_many_small --fanouts 32 --seeds 100 --steps 100 --repeats 3 --compare-pruning
```

Output columns:

- `pruning`: whether bounded agenda pruning was enabled
- `mode`: backward query agenda, forward chaining agenda, or a many-small-fanout variant
- `fanout`: number of generated rules/facts that can accumulate in the agenda
- `seeds`: number of forward seeds or backward hubs (one for single-fanout modes)
- `steps`: search or forward steps per run
- `setup_s`: mean KB construction time
- `run_s`: mean measured query/forward time
- `result_count`: number of backward query results or canonical facts changed by the forward run
- `agenda_pushes`, `agenda_pops`: backward work counters (zero for forward runs)
- `expanded_hubs`: distinct backward hubs expanded (zero for forward runs)

The current beam floor is 1000 and pruning starts only above 64000 pending
entries. The default core workload has fanout 500: it measures agenda growth,
not pruning throughput. `test_best_first_runtime.metta` exercises the actual
64000/64001 threshold, retained size and best entry, plus disabled pruning.
For optional end-to-end pruning stress, use a fanout above the threshold, e.g.
`--mode forward --fanouts 64001 --steps 2 --repeats 1 --compare-pruning`.
That workload is substantially larger than the core suite.

## Core Runtime Suite

`core_suite.py` runs the stable performance checks used when reviewing runtime
and compiler changes:

- backward and forward agenda growth with checked results;
- repeated multi-root queries across monotonic additions;
- cold and warm lifting-merge queries;
- incremental Member-to-Inheritance updates;
- a 1000-object forward-populated Member-to-Inheritance cache and budgeted query;
- repeated refinement of one sampling derivation over unchanged evidence.

Every repetition is launched in a fresh Python process. This is required for a
valid comparison because combining several Janus/PeTTa workloads in one process
can retain native state and has caused process crashes during benchmark runs.

Record a baseline:

```bash
.venv/bin/python pettachainer/benchmarks/core_suite.py \
  --json-out /tmp/pettachainer-baseline.json
```

Then compare another commit or worktree:

```bash
.venv/bin/python pettachainer/benchmarks/core_suite.py \
  --baseline-json /tmp/pettachainer-baseline.json \
  --json-out /tmp/pettachainer-current.json
```

Use `--repository /path/to/worktree` to benchmark another checkout while using
the current virtual environment. Both checkouts must contain these benchmark
files. Use `--repetitions 1 --population-members 12 --population-query-steps 100`
for a smaller smoke run. The defaults are three repetitions, 1000 objects, and
a two-step population query that measures reuse of the forward cache.

Schema version 2 changes the agenda fixtures and records the population query
budget explicitly. Old JSON baselines are rejected before benchmarks run. The
population workload checks and times its cached base rate before any backward
query; cache reads and budgeted public queries are reported separately. Every
query must return the full expected truth value within the chosen budget.
Small populations can have a correct forward cache but need more than two
query steps to expose a complete answer: 12 objects with 100 steps is checked
by the Python suite. `--population-query-steps` (standalone `--query-steps`)
never adapts silently, and insufficient budgets fail validation.

Large budgets can trigger expensive live refolding after reading the cache.
Use the explicit query budget to study that separate workload; a larger budget
can expose a partial refold before the full population has been processed.

`refinement_query.py` repeats a Map2Dist query 25 times with the same evidence.
Each answer must carry the complete proof and a new ParticleDist draw with the
expected truth value; final particle mass and mean are also checked. It reports
early and late query medians plus retained derivation-index and durable-proof
row counts. This catches work that grows with obsolete sampling results even
when every individual query still returns the right answer.

`durable_query_many.py` keeps one PeTTaChainer instance alive across five
fixed-budget batches. Two roots reuse completed proofs in every batch while six
structurally identical roots evolve with small monotonic statement additions.
Every batch must prove all eight roots. This keeps the requested work and answer
cardinality fixed while the durable proof graph grows, exposing accidental
whole-history scans without requiring the external StationOps fixture.

Run that workload directly with:

```bash
.venv/bin/python pettachainer/benchmarks/durable_query_many.py
```

The underlying Member-inheritance workloads are also directly runnable:

```bash
.venv/bin/python pettachainer/benchmarks/member_inheritance.py

.venv/bin/python pettachainer/benchmarks/member_inheritance.py \
  --population-mode forward-populate \
  --initial-members 1000 \
  --query-steps 2 \
  --forward-steps 2
```

Both workloads validate the expected public truth value before reporting a
successful timing. `core_suite.py` writes the raw values plus mean, median,
minimum, and maximum for every metric. The terminal comparison uses medians to
reduce sensitivity to isolated noisy runs. The JSON also records the Git commit
and whether the measured checkout was dirty. Baseline comparisons require
identical repetition, population-size, and population-query-budget parameters.
