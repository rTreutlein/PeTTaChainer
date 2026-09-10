# Reuse-first search with a 0–1 refinement budget

The isolated prototype makes reuse substantially cheaper in some cases and
improves second-shift coverage on seed 11. It is not ready to replace the
scheduler: full refinement almost doubles seed 7's second-shift diagnosis time,
and increasing the setting does not monotonically improve belief quality.
Depth and the existing demand formula were kept unchanged.

Follow-up: the [derivation investigation](stationops_reuse_derivation_2026-09-08.md)
separates the settings between shifts. Keeping shift one at 0 and refining
shift two recovers the alarm-based 0.722300 answer. The weak 0.5/0.5 run never
finishes that local alarm proof; its upstream alarm remains at an extra depth
level. Thus the aggregate table below confounds first-shift history with
second-shift refinement, and is not evidence that extra refinement alone
causes the large quality loss.

## What was tested

The proposed setting `r` is the fraction of the remaining expansion budget spent
on refinement after every concrete query root has an answer:

```
refinement_steps = floor(remaining_steps_at_first_full_coverage * r)
```

`0` stops at first full coverage, `0.5` spends half the remaining steps, and `1`
spends all remaining steps. This is a work allowance, not a probability of
exploration or a fraction of elapsed time. Existing proofs are still checked
for compatibility. During the first phase, expansion of answered concrete goals
and refinement of cached folds can be deferred. The deferred work remains in a
separate heap and can be claimed if the active heap empties before coverage.
Once refinement starts, the heaps are merged. Normal agenda ownership,
retokening, cancellation, proof acceptance and cycle checks remain in use.
The existing beam-pruning trigger counts both heaps together.

An open query does not qualify as complete merely because one binding exists;
it can continue enumeration until its agenda or budget is exhausted. Likewise,
if full coverage is never reached, all three settings have the same allowance.
Thus this is a deliberately narrow interpretation of reuse versus refinement,
not yet a general exploit/explore policy. In particular, deferring a shared
fold source is provisional: another consumer might need further source answers.

The control is the current **experimental branch without the base-rate success
multiplier**, not master or the August revision. Control disables this policy;
`r=1` keeps the reuse-first ordering and therefore need not reproduce control.
The internal `-1` sentinel only selects the control in the experiment; the
proposed user range is 0–1. No public option or production runtime change was
installed.

## StationOps screening

Twelve sequential episodes used the actual ChainerGame workload: two shifts,
four modules, action budget 1. Seed 7 uses diagnosis budget 600; seeds 11 and 23
use 300. Each setting/seed was run once, so these are screening measurements,
not repeated performance acceptance results. Times below are diagnosis only.

| Seed | Setting | Shift 1 seconds | Shift 2 seconds | Coverage, shifts 1 / 2 | Shift 2 Brier, lower better |
|---|---|---:|---:|---|---:|
| 7 | Control | 16.61 | 30.81 | 100% / 100% | 0.16358 |
| 7 | 0 | 3.24 | 0.70 | 100% / 100% | 0.02194 |
| 7 | 0.5 | 5.58 | 9.75 | 100% / 100% | 0.16389 |
| 7 | 1 | 16.50 | 59.49 | 100% / 100% | 0.16381 |
| 11 | Control | 2.14 | 2.88 | 50% / 75% | 0.00510 |
| 11 | 0 | 2.37 | 1.10 | 50% / 100% | 0.00876 |
| 11 | 0.5 | 2.32 | 1.41 | 50% / 100% | 0.00876 |
| 11 | 1 | 2.30 | 1.61 | 50% / 100% | 0.00876 |
| 23 | Control | 2.13 | 2.08 | 50% / 75% | 0.00392 |
| 23 | 0 | 2.29 | 1.88 | 50% / 75% | 0.00499 |
| 23 | 0.5 | 2.26 | 1.84 | 50% / 75% | 0.00499 |
| 23 | 1 | 2.31 | 1.83 | 50% / 75% | 0.00499 |

Brier is evaluated only on answered roots. Seed 11's 75%-coverage control and
100%-coverage candidates therefore do not have a directly comparable average.
The experiment also changes two of the already-answered beliefs there; this
is not merely an extra answer with all prior beliefs preserved.

All settings preserve the same game score and episode regret within each seed:
seed 7 scores 637 with zero regret; seed 11 scores 642 with regret 17.29235;
seed 23 scores 642 with zero regret. Those unchanged decisions do not establish
equivalent beliefs. All 24 diagnosis batches finish with zero search aborts.
Full normalized control proof answers match the previously recorded no-prior
runs on all three seeds.

On seed 7, the first phase finds all roots after 364 claimed operations in
shift 1. Settings 0, 0.5 and 1 then spend 0, 118 and 237 more claims. Their
shift-2 histories differ because shift 1 retained different proof graphs.
For setting 0, shift 2 reaches full coverage after 100 claims, returns the main
belief 0.834438, and stops. Half/full refinement return 0.220508 for that root,
which is worse on this episode. These runs do not establish that 0 is more
accurate in general, nor do they recover the old 0.722300 proof as a general fix.

On seed 11, the reuse-first phase reaches all four roots with 57 steps left in
shift 2. Spending none, half or all of those steps returns the same beliefs.
On seed 23 it never reaches full coverage, so the setting never takes effect;
all three reuse-first variants return identical answers. Their shared queue
policy still changes the result relative to control. No StationOps run needs
the empty-active-heap fallback, so these measurements do not validate that path
under a workload that requires it.

## Validation

The final prototype passes strict type/determinism loading. With `r=1` as the
isolated archive's default, `PETTA_STRICT=1 PETTA_JOBS=8 scripts/test_metta.sh`
passes **72 files, 0 failures**, including `flyingraven` and `smokes`. The suite's
fixtures were not altered. This is not a full-suite claim for the deliberately
early-stopping settings 0 and 0.5, nor a full Python-suite acceptance run.

A generic two-root fixture runs 16 queries across control and the three
settings: cold query, unchanged repeat, addition of independent contradictory
evidence, and resuming full refinement. Every root is answered with zero
recorded search aborts. At 0, the repeat consumes no claimed expansions, and the
added evidence does not update the returned answer until refinement is enabled.
Switching to 1 incorporates the added evidence.

The existing Python materialization scenario was also exercised as a separate
28-query probe, without replacing its logical fixture. Starting with three
state observations and then adding a fourth, control settles at strength
0.4719187802. Setting 0 holds strength 0.1998401277 across repeated queries and
the evidence addition, then reaches 0.4719187802 when switched to 1. Setting
0.5 reaches that value on the first subsequent 200-step query. Setting 1 first
returns 0.4705270890, then 0.4754021746, and settles at 0.4719187802 after a
second 200-step query. Increasing effort is not a monotonic numerical
refinement even in this small fixture. The probe was rerun with metrics enabled;
its correctness checks overlapped suite/pruning validation, so its recorded
wall times are not performance evidence.

Combined-heap pruning passes a focused strict test with 32 active and 33 held
stale entries, where only their combined size exceeds the trigger. This uses
a separate test archive with the minimum beam width reduced from 1000 to 1;
the 64-times trigger and queue/pruning code are unchanged. The corresponding
64,001-entry test at the production beam size was interrupted after roughly
two minutes without a result. Actual-threshold pruning scalability therefore
remains unvalidated; the small test establishes the combined-count behavior,
not acceptable cost at that size.

All diagnosis claim counts respect the existing budget convention (up to
`budget + 1`, including initial work). Once coverage starts the refinement
phase, its claimed work never exceeds `floor(remaining_steps * r)`. These
checks do not establish fairness under unlimited workloads or exercise a case
where deferred fallback is essential to complete a missing root.

## Recommendation and reproduction

Keep the 0–1 interface idea as an explicit refinement-work allowance, but do not
adopt this prototype as the default. Reuse-first scheduling and early stopping
are currently combined; the next useful isolation is **ordinary scheduling
with the same coverage stopping rule**, compared with reuse-first ordering.
That separates the benefit of doing fewer steps from the effect of deferring
existing proofs. It should use the same generic evidence-update fixtures and
multiple workloads, rather than selecting a default from seed 7's lucky early
estimate. A quality guarantee would require a different stopping criterion;
merely having some proof says little about how informative that proof is.

Source revision: `135fca5ed937779c29961d8349ff813a8f282cbc` on
`experiment/no-base-rate-success-prior`; the isolated patch is based on that
exact committed archive. ChainerGame revision:
`99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`. Pinned PeTTa tree:
`502d08ba468480093d22e710db17f21ab4c3ac59`, executed through the repository's
`.venv/bin/petta` and `.venv/bin/python`. No fetch or rebuild occurred. The
pre-existing untracked `.claude/`, `baseline_agenda_incumbent.json`, and `tmp.txt`
were excluded. Master remains unchanged.

The compact evidence, `reuse-refinement-results-2026-09-08.json` (removed from the tree to keep it small; retrieve it with `git show 205ef1ac:benchmarks/stationops/reuse-refinement-results-2026-09-08.json`),
contains the final runtime patch, exact local drivers, all diagnosis answers,
metrics, environments, and validation logs. Raw files are retained locally in
`scratch/stationops-reuse-2026-09-08/`. To reproduce locally, archive the named
revision to `/tmp/stationops-reuse/runtime`, apply the included patch there,
link its `.venv` to the repository's pinned environment, extract the drivers
from the evidence to `/tmp/stationops-reuse/`, and run `run.py` with that Python.
The suite uses a second identical archive with the experiment's default
`probe_refinement` set to `1`; fixtures remain unchanged.
