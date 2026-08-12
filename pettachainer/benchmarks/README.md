# Benchmark Notes

`particle_vs_nat.py` benchmarks direct distribution folding and threshold probability evaluation.

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
.venv/bin/python pettachainer/benchmarks/forward_vs_backward.py --depths 10,25,50 --noise-branching 8 --repeats 3
```

```bash
.venv/bin/python pettachainer/benchmarks/backward_materialize.py --depths 5,10 --queries 200 --repeats 3
```

```bash
.venv/bin/python pettachainer/benchmarks/backward_materialize.py --mode sibling-targets --depths 5 --queries 20 --repeats 3
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

## Bounded Queue Pruning

`bounded_queue.py` stresses priority agenda growth in both the backward and forward chainer paths.
It separates setup time from measured run time so the cost of compiling thousands of generated rules
does not hide the queue behavior.

Run the same command on two commits to compare the bounded queue implementation against the previous
unbounded heap behavior:

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

The backward counterpart expands a chain of hub goals where each hub has only `fanout` dead-end
alternatives plus one link to the next hub:

```bash
.venv/bin/python pettachainer/benchmarks/bounded_queue.py --mode backward_many_small --fanouts 32 --seeds 100 --steps 100 --repeats 3 --compare-pruning
```

Output columns:

- `pruning`: whether bounded agenda pruning was enabled
- `mode`: backward query agenda, forward chaining agenda, or a many-small-fanout variant
- `fanout`: number of generated rules/facts that can accumulate in the agenda
- `seeds`: number of independent seed goals for `forward_many_small`
- `steps`: search or forward steps per run
- `setup_s`: mean KB construction time
- `run_s`: mean measured query/forward time
- `result_count`: number of backward query results or canonical facts changed by the forward run

## Core Runtime Suite

`core_suite.py` runs the stable performance checks used when reviewing runtime
and compiler changes:

- bounded backward agenda;
- bounded forward agenda;
- incremental Member-to-Inheritance updates;
- a 1000-object forward-populated Member-to-Inheritance query.

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
files. Use `--repetitions 1 --population-members 100` for a quick smoke run;
the defaults are three repetitions and 1000 objects.

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
identical repetition and population-size parameters.
