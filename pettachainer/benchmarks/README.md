# Benchmark Notes

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

`backward_materialize.py` benchmarks the fact-materializing backward chainer.
In its default `same-target` mode, the plain run answers the same deep target repeatedly with normal
backward queries. The materialized run answers it once with `query-materialize`, which stores the
proof tree facts, then answers the remaining repetitions with a low step budget.

It also has `--mode sibling-targets`, which builds several related targets that all depend on the
same deepest chain fact. That mode measures reuse of a materialized intermediate fact rather than
reuse of the exact materialized target.

```bash
.venv/bin/python pettachainer/benchmarks/backward_materialize.py --depths 5,10 --queries 200 --repeats 3
```

```bash
.venv/bin/python pettachainer/benchmarks/backward_materialize.py --mode sibling-targets --depths 5 --queries 20 --repeats 3
```

`incremental_ordinary_base_rates.py` is optional and is not part of
`scripts/ab_bench.sh`. It times the inversion case that script skips: a computed
`P($x)` snapshot, then one-step forward patches of new `P` facts.

```bash
PYTHONPATH=pettachainer/benchmarks .venv/bin/python \
  pettachainer/benchmarks/incremental_ordinary_base_rates.py \
  --initial-facts 128 --deltas 32 --query-steps 2000
```

## Output Columns

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

## Durable and Member-inheritance workloads

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

The Member-inheritance workloads:

```bash
.venv/bin/python pettachainer/benchmarks/member_inheritance.py

.venv/bin/python pettachainer/benchmarks/member_inheritance.py \
  --population-mode forward-populate \
  --initial-members 1000 \
  --query-steps 2 \
  --forward-steps 2
```

Both workloads validate the expected public truth value before reporting a
successful timing. `scripts/ab_bench.sh` times them against a base ref.

## Skeleton broad-answer queries

`skeleton_answers.py` checks every complete proof and truth value returned by a
cold and a warm zero-step query over stored facts. It measures result processing
separately from expansion and ingestion. Launch a fresh process for each repeat:

```bash
.venv/bin/python pettachainer/benchmarks/skeleton_answers.py \
  --facts 600 --json-out /tmp/skeleton-answers.json
```

Use `--repository /path/to/checkout` to compare another checkout with the same
harness and interpreter; sweep `--facts 100`, `600`, and `1800` for scaling.

## Skeleton sessions

`skeleton_sessions.py` measures 40 rounds in one KB, with three unchanged
queries after each addition. `unrelated` grows six disjoint derived roots per
round while probing two stable roots. `history` adds members to an inheritance
fold and queries it together with a downstream rule. Every unchanged query must
preserve the complete answers; the fold's confidence is checked against its
member count. Proof digests allow comparisons across fresh processes.

```bash
.venv/bin/python pettachainer/benchmarks/skeleton_sessions.py \
  --mode unrelated --json-out /tmp/skeleton-unrelated.json
.venv/bin/python pettachainer/benchmarks/skeleton_sessions.py \
  --mode history --json-out /tmp/skeleton-history.json
```

Both modes record query time, Prolog inferences, skeleton/view counts, and peak
process RSS. Inspection runs outside query timing. Use `--repository` for
paired comparisons; `--rounds` and `--repeats` control session length.

The 2026-09-25 answer-index report
(`git show 39e41c5e:docs/metta/skeleton_answer_index_2026-09-25.md`) includes
broad-query scaling, session measurements, and the StationOps comparison.
