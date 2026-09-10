# Which derivation gives reuse-only its lower error?

The benefit comes from completing the alarm-conditioned local-fault proof for
M01, the old coolant pump, using independent evidence from its upstream power
converter M03. In seed 7, shift two, inspection confirms that M01 really has a
seal leak. The early estimate of 0.834438 therefore scores much better than the
historical-inheritance answer of 0.220508.

Crucially, the 0.5/0.5 run never constructs that good local-fault proof within
its budget. It does not find it and then replace it with the historical answer.
Changing refinement in both shifts changes the proof graph entering shift two.
The crossed experiment below separates those effects.

## Exact successful derivation

For the 0/0 run, durable proof IDs below refer to the captured second-shift
store. The returned root is proof **394**, strength 0.8344381662774413,
confidence 0.000001.

1. M01's current alarm is true (fact `alarm-shift-02-M01`, proof 356).
   Inverting `problem-alarm-old-coolant-pump` gives a problem probability of
   **0.8437510194243352** (proof 360). The stored calculation uses the problem
   base rate 0.375, sensitivity 0.92, and cached alarm marginal
   0.4088883948672236: `0.92 * 0.375 / 0.4088883948672236`.
2. `bi-backward problem-from-disjunction-shift-02-M01` identifies that problem
   with `Or(LocalProblem M01, ProblemDependency M01)`, preserving 0.8437510194
   (proof 362).
3. M03's current alarm is false (fact `alarm-shift-02-M03`, proof 388).
   Inverting its sensor rule, with problem base rate 0.25, sensitivity 0.85,
   and cached alarm marginal 1/3, gives **0.05625** for its problem
   (proof 389): `(1 - 0.85) * 0.25 / (1 - 1/3)`.
   `bi-forward dependency-problem-shift-02-M03-M01` carries that value to
   M01's upstream dependency (proof 390).
4. `OrProjection`, proof 393, computes the local cause:

   ```text
   (0.8437510194243352 - 0.05625) / (1 - 0.05625)
     = 0.8344381662774413
   ```

The current positive pump alarm and negative upstream alarm both appear in the
root's evidence. This is a noisy-OR projection under the implemented formulas;
it is not a claim that 0.834438 is the exact posterior of the hidden simulator.
Its confidence is at the runtime floor.

The pump's squared error drops from `(1 - 0.220508)^2 = 0.607608` to
`(1 - 0.834438)^2 = 0.027411`. Averaged over four roots this accounts for
0.145049 of Brier improvement. The other roots offset a small part of that
gain; aggregate shift-two Brier is 0.163889 for 0.5/0.5 versus 0.021940 for 0/0.

## What the weak derivation actually does

In the 0.5/0.5 store, the root's successive durable candidates are proofs
819, 892, 1101 and 1196, all from the historical inheritance route, with strengths
0.248286, 0.220506, 0.220508 and 0.220508. The final root is proof **1196**.
There is no 0.834438 alarm-projection root in this store.

The final route begins with the fact that the current module is equipment of
type old coolant pump. It inverts `state-equipment-h-0000-M01` to estimate
membership in that historical state at 0.008116893422417473, then applies
`state-leak-h-0000-M01`. That historical state was a non-leak (`STV 0 1`).
The generated conditional's other branch is 0.22231241995250775, based on the
folded leak marginal 0.22051957785611656. Its modus ponens is:

```text
0 * 0.008116893422417473
  + 0.22231241995250775 * (1 - 0.008116893422417473)
  = 0.22050793373327351
```

`bi-forward local-problem-shift-02-M01` transfers that estimate to the queried
local problem. Its returned proof includes historical leak evidence, the
current equipment-type fact, and a previous-shift inference in the base-rate
fold. It does not use either current alarm as diagnostic evidence.

The pump's current alarm *is* processed elsewhere: the engine derives the
problem disjunction at 0.843751, later 0.737176. But its dependency candidates
are reverse projections from this disjunction and the historical local answer
(e.g. proof 861 derives dependency 0.792143 from disjunction 842 and local
proof 819). They are not independent upstream-alarm evidence. Feeding such a
candidate back into the local projection would re-use the local answer's own
proof ancestry; it cannot supply the missing independent diagnostic route.

## The crossed test isolates the history effect

All four are fresh two-shift seed-7 episodes, diagnosis budget 600, action budget
1, identical pinned runtime and prototype. Store inspection happens after each
measured query. Original 0/0 and 0.5/0.5 proof answers reproduce exactly after
KB-UUID normalization; crossed runs reproduce their corresponding first-shift
answers exactly. All eight diagnosis batches finish without aborts.

| Shift 1 setting | Shift 2 setting | Main belief in shift 2 | Shift 2 Brier | Main derivation |
|---:|---:|---:|---:|---|
| 0 | 0 | 0.834438 | 0.021940 | Current alarms, cached marginal estimates |
| 0 | 0.5 | 0.722300 | 0.031224 | Same alarm path, refined marginal estimates |
| 0.5 | 0 | 0.248286 | 0.156413 | Historical inheritance |
| 0.5 | 0.5 | 0.220508 | 0.163889 | Refined historical inheritance |

With shift one held at 0, adding refinement in shift two preserves the
successful proof family. The alarm marginals refine from 0.408888 to
0.468002 for the pump and from 1/3 to 0.3 for the upstream converter. The final
projection is then:

```text
(0.7371764629894552 - 0.05357142857142858)
  / (1 - 0.05357142857142858)
  = 0.7222996590077262
```

Its confidence rises from 0.000001 to 0.00018155676508922256. This recovers the
earlier benchmark's main belief and proof family. It scores slightly worse
than 0.834438 on this realized leak; that does not establish that the less
refined estimate is better calibrated in general.

The arena snapshots identify the same bottleneck as the
[earlier depth trace](stationops_refinement_trace_2026-09-08.md):

| MAIN-context prerequisite | 0/0 depth | 0.5/0.5 depth | 0.5/0.5 status |
|---|---:|---:|---|
| M01 dependency | 1 | 2 | Expanded |
| M03 problem | 2 | 3 | Expanded |
| M03 alarm | 3 | 4 | Queued, unexpanded |

The 0/0 and 0/0.5 runs expand all three. In 0.5/0.5, alarm goal 202 has
positive issued demand 4.166666666666666e-08 but remains unexpanded. Stored
depth is only lowered while a goal is unexpanded
(`ensure-goal-at-depth`, `runtime/backward/search.metta`); priority strongly
prefers smaller depths (`backward-agenda-priority`, `runtime/scheduling.metta`).
The present snapshots and crossed outcomes support that previously traced
mechanism; this turn does not add a new per-operation scheduling trace or prove
that depth is the only allocation cost.

## Consequence

The next target should be the late discovery of a shorter path to an already
expanded shared goal and its pending descendants. The useful alarm proof is
available, and the mixed run shows that it can also be refined successfully.
Treating the entire difference as evidence that refinement is harmful would
miss the history-dependent scheduling failure. No production code, depth
coefficient, truth-value formula, or public API was changed in this investigation.

The compact proof evidence, `reuse-derivation-results-2026-09-08.json` (removed from the tree to keep it small; retrieve it with `git show ca15dd98:benchmarks/stationops/reuse-derivation-results-2026-09-08.json`),
contains all root-proof ancestry, relevant goal snapshots, crossed settings,
answers, metrics, and read-only dump driver. Full raw stores and logs are local
in `scratch/stationops-derivation-2026-09-08/`. The runtime is the unchanged
isolated prototype documented in the preceding reuse report; the report-only
repository HEAD at investigation start was `205ef1ac`. ChainerGame remains
`99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`, pinned PeTTa tree
`502d08ba468480093d22e710db17f21ab4c3ac59`; no fetching or rebuilding occurred.
