# Consumer-specific live proof delivery experiment

Both prototypes underperform the control and remain isolated. The delivery
trace identifies a further obstacle: the useful partial proof path is already
dead before the independent evidence reaches the local diagnosis.

A focused regression confirms that live delivery can discard an independent
proof when its published merged representative also contains a proof depending
on the receiving goal. The receiver correctly rejects the circular merge, but
previously had no fallback to the compatible components. Conditioned replay can
still recover those components.

## Candidate

The isolated candidate first tries the normal published proof. Only when a
merged representative fails the receiving frontier's existing admissibility
check does it select compatible current components, using the existing
conditioned-proof selection and revision machinery. Every selected proof still
passes the normal frontier acceptance check. The experiment does not disable
cycle rejection or change truth-value formulas, priority coefficients, or public
API signatures.

Selection is limited to the published output key, with goal compatibility still
checked. An open child goal therefore does not replay all its bindings on every
notification. Each selected proof gets a copied frontier waiter so unification
for one branch cannot bind another. Dead frontier paths return before selection.
Aggregate notification and priority-revision invalidation remain as before.

A separate typed helper is required at the stored waiter boundary: using an
explicit runtime AndBundle check attached type constraints to free variables,
which failed when the existing index hash copied and normalized them. Passing
the reconstructed FrontierWaiter through a typed helper avoids that failure.

Two focused assertions cover:

- A circular G-to-H component cannot prove G; an independent H publication
  reaches G, while an unrelated observer still receives the full merged H proof.
  The control fails because the independent live result is absent; conditioned
  replay still finds it.
- Publishing one binding of an open child goal delivers that binding only.

The combined candidate adds exactly the previously recorded shorter-path patch.
That combination tests the two identified obstacles together: reaching the alarm
branch and delivering its independent evidence to the local consumer.

## Results and recommendation

Do not adopt either candidate. They repair the isolated delivery case but do
not recover the desired seed-7 local diagnosis, and coverage worsens on the
other seeds as well. No exploration parameter or depth default should be
selected from these results.

The following are fresh, sequential, single-run screening measurements, not
repeated performance acceptance tests. All runs use two shifts, four modules,
action budget 1, and diagnosis budget 600 for seed 7 or 300 for seeds 11 and 23.
Time is total diagnosis time over both shifts. Coverage and Brier are for shift
two. Brier is measured over evaluated beliefs, so compare it alongside coverage.

| Seed | Setting | Diagnosis seconds | Shift 2 coverage | Shift 2 Brier |
|---:|---|---:|---:|---:|
| 7 | Control | 48.58 | 100% | 0.163581 |
| 7 | Delivery fallback | 88.76 | 100% | 0.163879 |
| 7 | Shorter paths + fallback | 85.02 | 75% | 0.218479 |
| 11 | Control | 5.28 | 75% | 0.005095 |
| 11 | Delivery fallback | 10.64 | 50% | 0.007537 |
| 11 | Shorter paths + fallback | 10.20 | 50% | 0.007502 |
| 23 | Control | 4.40 | 75% | 0.003922 |
| 23 | Delivery fallback | 5.47 | 50% | 0.005913 |
| 23 | Shorter paths + fallback | 7.68 | 50% | 0.005913 |

Scores and regrets match control: seed 7 scores 637 with zero regret; seed 11
scores 642 with regret 17.292347; seed 23 scores 642 with zero regret. All 18
final diagnosis batches report zero search aborts. Fresh control answer/proof
strings match the earlier shorter-path controls after normalizing KB UUIDs.

An earlier candidate conditioned every merged notification, even an admissible
one. On seed 7 it used 98.44 seconds of diagnosis, with the same beliefs as the
narrow fallback's 88.76 seconds. This is a single-run comparison; it supports
avoiding unconditional conditioning, not a precise speedup claim. That earlier
candidate is separate from the final matrix.

## Validation

- Delivery fallback: 72 MeTTa files pass, 1 fails (`flyingraven`). The first
  assertion changes from strength/confidence 0.978660812909457 /
  0.6432519164525251 to 0.9800455814752682 / 0.8632876134913046, with the same
  displayed proof structure. Later assertions in that file are not reached.
- Combined shorter-path/fallback: 73 files pass, 1 fails
  (`test_or_inversion_conditioned_merge`). Its existing OR result assertion
  differs. Both new focused delivery assertions and all three shorter-path
  assertions pass.
- Delivery fallback Python: 49 tests run, 1 fails. The materialization test
  expects 0.47191878015453864 / 3.999988000035998e-06 but receives
  0.45184371761362274 / 2.9999940000119994e-06.

- Combined Python: 49 tests run, 1 fails, at the same materialization assertion.
  It receives 0.47331709337991223 / 3.999988000035998e-06.

These result differences are unresolved finite-budget behavior changes. Existing
expected outputs have not been rewritten to accept them.

## Remaining proof-path problem

A separate small counterexample fails in both control and candidate. G needs A
and H. Its partial derivation consumes an independent A proof and waits for H.
Adding a G-dependent A proof changes A's global merged representative. The
independent A remains a current proof, but publishing independent H still does
not finish G. Both runs return `(true (false) ())`: A is current, its partial
path is dead, and no gated G proof was created. The desired regression result
is `(true (true) (true))`; the probe deliberately remains failing.

The runtime invalidates paths built from the previous representative when
`store-proof-candidate` or `refresh-result!` replaces that representative.
`ensure-frontier-path` reuses the existing path for the same parent path and
proof ID, including when that path has already been marked dead. Conditioning a
new delivery back down to the same independent proof therefore does not by
itself restore a usable path.

This needs a precise distinction between a changed global representative and a
proof that is no longer suitable for a particular consumer. Simply keeping all
old paths, reviving all dead paths, or disabling cycle checks has not been
validated and is not recommended. The next bounded experiment should preserve
or replace a partial path only when its selected evidence is still compatible
with that consumer, and test both retained-independent and truly superseded
premises before another scheduler sweep.

## StationOps delivery trace

The combined seed-7 run still returns the historical local diagnosis,
0.2205084996268721 with confidence 1e-6. The independent upstream alarm proof
1869 exists at strength 0.05625. Its published representative 1870 also contains
root-dependent proof 1866, and the runtime dependency checks confirm that 1869
is noncyclic for root 0 while 1870 is cyclic for that root.

The instrumented replay records this decisive sequence:

```text
(delivery-waiter 196 1866 0 1549 true)
(delivery-publication 196 1870 0)
(delivery-sources 1870 5 28 (1869))
(delivery-sources 1870 54 28 (1869))
(delivery-waiter 196 1870 0 1549 false)
```

The waiter fields are child goal, published proof, receiving goal, partial-path
ID, and path liveness. Publication fields are child goal, published proof, and
synchronous re-entry depth. Source fields are published proof, receiving goal,
partial path, and selected proof IDs.

Thus the local projection's path 1549 is live for the earlier circular-only
publication, but already dead by the time it receives the independent-evidence
publication. The latter publication starts at re-entry depth zero; it is not
suppressed by the bounded synchronous-delivery guard. Other consumers receive
independent proof 1869, while root 0 is skipped before fallback selection.
This is a delivery-time observation, not merely an inference from the final
stored proof graph. The traced replay matches both batches of normalized
answer/proof strings and every non-timing query metric exactly. Both traced
batches also have zero search aborts.

## Reproduction and artifacts

The baseline is local `experiment/no-base-rate-success-prior` at `b4d6ee51`.
The archives use the repository-pinned `.venv/bin/petta`; PeTTa tree is
`502d08ba468480093d22e710db17f21ab4c3ac59`, and ChainerGame is
`99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`. No fetch or rebuild occurred.
The baseline had only the pre-existing untracked `.claude/`,
`baseline_agenda_incumbent.json`, and `tmp.txt`. Runtime source in the working
branch and local master remain unchanged by this experiment.

The [machine-readable evidence](../../benchmarks/stationops/consumer-delivery-results-2026-09-09.json)
contains the complete final patches, focused fixtures, failing path probe,
runner, selected proof/goal/waiter stores, metrics, and validation logs. Apply
`fallback.patch` to an archive of `b4d6ee51` for delivery alone; additionally
apply `shorter-path.patch` for the combined candidate. `trace.patch` applies to
the combined tree. `candidate.patch` is the earlier unconditional-filter variant,
not the final candidate. Run MeTTa with `PETTA_STRICT=1 PETTA_JOBS=8
scripts/test_metta.sh`; the Python archive metadata setup is in `validate.sh`.

Full local snapshots and logs are mirrored under
`scratch/stationops-consumer-delivery-2026-09-09/` (gitignored). Timing measurements
exclude the post-diagnosis store snapshots. The traced replay is kept separate
from the performance matrix.
