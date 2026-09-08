# Cached fold startup experiment

This follows the [regression investigation](stationops_regression_2026-09-08.md).
The question was whether keeping the previous fold answer, while avoiding
replacement by a cached seed, removes enough work to justify a runtime change.
The experiment is confined to isolated source archives; production runtime
code is unchanged.

## What the experiment changes

The baseline is `c47e7800`, whose runtime is unchanged from `ccf0862d`.
In `ba-refine`, the candidate commits the cached aggregate candidate only when
`current-fold-snapshot` is empty. It still creates the source goal, registers
the waiter with `cached-aggregate-demand`, and wakes that source. The user
base-rate override path is unaffected. No proof is retired.

The candidate replaces the agenda binding with:

```metta
($s
  (if (== (current-fold-snapshot $c (CPU FoldAllCompiled $e $f)) ())
    (commit-proof-candidate-heap $a $c
      (aggregate-result-candidate (CPU FoldAllCompiled $e $f) () ()))
    $a))
```

Both archives include identical probe counters immediately before this
binding. The counters classify each attempted non-user seed as first,
replacement, or unchanged using `current-fold-snapshot` and
`snapshot-changed?`. Thus the candidate's replacement counter counts skipped
replacement attempts, not committed replacements.

In shift one, all 20 attempts are first seeds. In shift two, 20 are first
seeds, 38 are unchanged, and 12 would replace an existing snapshot. The
existing common commit path already rejects the 38 unchanged seeds. There
are 50 computed and 20 forward-approximation seeds in total. The probes do
not record source and replacement classification jointly. Source counts alone do not
establish that one estimate contains better evidence than the other.

Skipping the 12 replacements changes the finite-budget search and returned
truth values. This is a search-policy candidate, not a behavior-preserving
duplicate-check optimization. Demand still uses the cached TV, even where
the candidate retains a different incumbent TV; the experiment does not
resolve that policy choice.

## Results and decision

Two interleaved pairs (baseline/candidate, candidate/baseline) give:

| Shift-two diagnosis | Baseline | Retain incumbent |
| --- | ---: | ---: |
| Seconds, individual runs | 92.285 / 94.018 | 79.705 / 80.265 |
| Median seconds | 93.151 | 79.985 |
| Prolog inferences | 489,095,529 | 483,129,205 |
| Demand evaluations | 139,235 | 103,515 |
| Agenda pops | 842 | 804 |
| Proof candidates stored | 1,349 | 1,244 |
| Diagnosis coverage | 100% | 100% |
| Brier score (lower is better) | 0.03103582 | 0.03114126 |
| Log loss (lower is better) | 0.14247159 | 0.14273232 |

All four episodes have score 637, zero regret, and zero search aborts. Each
side repeats its inference counts, complete normalized proof answers, and
belief metrics exactly. Shift-one answers are equal across sides; shift-two
answers differ. The first diagnosis root changes from strength 0.7222996590,
confidence 0.0001815568 to strength 0.7215114840, confidence 0.0001758433.
Lower confidence alone does not prove a worse estimate; the slightly higher
observed Brier score and log loss are the relevant quality tradeoff here.

Median latency improves by 14.13%, demand evaluations by 25.65%, but total
inferences by only 1.22%. Different inference mixes can have different costs;
these counters do not attribute the whole latency saving to demand calculation.
Two repetitions of one seed establish a repeatable local screening result,
not a general speed/quality improvement. Nearly all the excess inference work
relative to the historical baseline remains.

Do not adopt the unconditional retain-incumbent policy from this experiment.
It is a plausible partial mitigation, but the existence of an incumbent does
not tell us whether the cached estimate is useful. A policy change would need
refinement/convergence checks and broader seeds/budgets, including the mismatch
between retained answer TV and cached demand TV. Avoiding repeated structural
proof work while preserving candidate acceptance would be a less policy-sensitive
optimization target.

### Focused validation

The baseline passes three existing Python integration tests: refined
materialization replacing a zero-budget incumbent, reconstructible shared
evidence after materialization, and saving derived proof trees. The candidate
passes the latter two but fails the refinement test's exact 100-step answer:
strength 0.4524654658 instead of 0.4626503433, at unchanged confidence. Its
fresh-handler answer also changes: strength 0.4649852974 instead of 0.4753966096,
with confidence approximately 2e-6 instead of 4e-6. Thus this guard can affect
folds with stored snapshots even in the fresh-handler setup; it is not limited
to the second query of an episode.

Those finite-budget differences do not by themselves establish invalid proofs,
but prevent treating this as an internal cleanup with unchanged answers.
The production tests were not edited. No full-suite acceptance is claimed for
the candidate.

An exploratory rerun bypassed only the two baseline-specific 100-step TV
assertions in the isolated test harness, leaving the remaining checks intact.
The candidate then failed the existing settling assertion: its second and
third 200-step re-queries differed after context-number normalization. The
baseline passes this assertion. This establishes that the candidate does not
settle within the tested window, not that it can never converge. Zero-budget
retention and zero-abort checks preceding that assertion passed.

## Reproduction and evidence

The workload is the real ChainerGame `99fc56e` episode: seed 7, two shifts,
four modules, diagnosis budget 600, action budget 1. Both sides use the same
repository-pinned virtual environment and vendored PeTTa runtime. Nothing was
fetched or rebuilt. The game has only an untracked `benchmark-runs/` directory;
the primary chainer checkout's three pre-existing untracked items are preserved.

Full run JSON, logs, the probe runner, and exact archive patches are retained
locally in `scratch/stationops-fold-startup-2026-09-08/`. The committed compact
results retain environment data, all query counters, belief metrics, and hashes
of complete normalized proof answers. The probes add overhead on both sides,
so compare these runs to each other, not directly to uninstrumented timings.

Compact evidence: [fold-startup-results-2026-09-08.json](../../benchmarks/stationops/fold-startup-results-2026-09-08.json).
