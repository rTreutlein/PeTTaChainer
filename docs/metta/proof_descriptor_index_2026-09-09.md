# Exact derivation descriptors: behavior and measured cost

Retaining immutable derivation descriptors avoids rebuilding the same rule
skeletons and premise output keys during consumer-relative proof selection.
Against the committed waiter-demand index (`30b81192`), three declared seed-11
pairs improve diagnosis wall time by 1.70% and CPU time by 1.93%. Whole-episode
time is essentially unchanged. Full proofs, public results and non-time search
metrics remain exact on all three development workloads.

Core commit: `e33d679c`, on isolated branch `experiment/proof-descriptor-index`.
All 286 validated files remain byte-identical after committing the two runtime
files. Independent static review found no blocking defect. Documentation and
tests are supplied separately; the measured archive remains unchanged.

## Implementation and invariants

The existing `&proof_derivation_hash (pid hash)` stays small. When calculating a
rule PID's hash, the runtime also retains the already-computed normalized shape
and ordered premise keys in `&proof_derivation_descriptor (pid shape keys)`.
Only equal-hash comparisons read that descriptor. Both indexes have one writer
and clear together with the query arena; neither changes durable proof identity.

The descriptor depends only on immutable stored proof kind, children and child
output keys. Normalization still excludes CPU evaluation leaves and collapses
consecutive alpha-equal premise keys. Hash bytes and the two separate nonbinding
alpha comparisons are unchanged, including variable sharing and collision
rejection. Equal-child and evidence-subset checks retain their existing policy.
The successful identity branch in `candidate-step` passes `true` to those checks
instead of repeating the same pure identity comparison.

Consumer eligibility, complete goal constraints, evidence accounting, DAG/path
checks and source revisions remain live. The index does not cache confidence,
priority, path liveness or selected proofs. No public API, scheduling parameter,
truth-value formula, assertion or query budget changes.

A widened hash-row prototype was rejected because ordinary scalar reads copied
unused descriptors. The separate index preserves the original compiled scalar
lookup and its measured allocation/inference cost. A recorded-state probe over
216 actual proof entries and 21,600 hash hits confirms this. The additional
214 descriptor rows occupy 58,752 logical term cells in that probe; this is not
an RSS estimate. The final duplicate-check cleanup leaves the lookup unchanged.

## Validation

The combined candidate was built from clean `30b81192` plus the final descriptor
core and regression. Its runtime differs only in `proof_merge.metta` and the
new index's query-reset entry; the waiter-demand code remains byte-identical.

| Gate | Result |
| --- | --- |
| Focused strict MeTTa | 10 files passed |
| Full unmodified `scripts/verify.sh`: MeTTa | 79 files passed, zero failures |
| Full Python suite | 57 tests passed; 46 query metric rows, zero aborts |
| Import scaling | 1.001 ratio, below 1.500 |
| ConceptNet | Exactly two answers |
| Unchanged separate late-evidence regression | Passed; four query metric rows, zero aborts |

The new regression covers variable sharing, forced hash collisions, independent
evidence, CPU/consecutive-premise normalization, copied-row isolation, both
index resets and durable-history reuse. The unchanged generic regression checks
both root directions and insertion orders, coverage at budget 80, and all four
witnesses with fixed TVs after adding evidence at budget 320.

Seed-7/600, seed-11/300 and seed-23/300 episodes use two shifts, four modules and
action budget one. All full returned proofs, queries, public results including
backend counters, and non-time native metrics equal their retained demand-index
references. Only random KB UUIDs are normalized in strings. All runs exit zero,
without aborts, watchdogs or retries. Existing original-reference quality losses
are preserved; this optimization does not restore those historical outcomes.

## Paired timing and memory

The order was fixed as AB, BA, AB before execution. Our agents' CPU-heavy work
was paused for all six runs. Runtime, game, driver, reference and source hashes,
including the retained parent HEAD and clean status, stayed unchanged. Unrelated
host activity was not controlled.

| Metric | Parent median | Candidate median | Median paired change |
| --- | ---: | ---: | ---: |
| Diagnosis wall, both shifts | 5.552 s | 5.472 s | −1.70% |
| Diagnosis CPU, both shifts | 5.577 s | 5.470 s | −1.93% |
| Second-shift diagnosis wall | 3.766 s | 3.683 s | −2.71% |
| Whole episode | 19.856 s | 19.862 s | −0.18% |
| Peak process RSS | 181,928 KiB | 181,124 KiB | −0.95% |

All three pairs improve total diagnosis wall and CPU time. Paired percentages
are calculated within each pair before taking their median, so they differ
from ratios of the displayed independent medians. Whole-episode time is
essentially unchanged: its ratio of medians is +0.03%. RSS shows no material
observed increase, but includes stack allocation and GC effects; it does not
mean the added descriptors consume no memory. This is a modest exact improvement
on a fixed development workload, not a universal speedup or held-out result.

## Reproduction and evidence

Execution used the repository-pinned `.venv/bin/petta` and `.venv/bin/python`,
frozen PeTTa `e1aac8b791cf70b7843173b613f04b869b666979`, and frozen ChainerGame
`99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`. Nothing was fetched or rebuilt.
The complete source manifest is
`2aeadb8c501c010aff7d0c5ac3cfa5c7c8446dd205b27f8ab60f2b4e9087fa25`.

The measured target-capture driver is byte-identical to the preceding campaign
(SHA-256 `a4ddd7fc26a2d793b411fd6f888abdfba0e1cf85d37e137373327fd58b7de68c`).
It captures targets after scoring, without exposing them during inference.
Exact environments, six commands, run order, measurements, gates and hashes are
in [the compact evidence JSON](../../benchmarks/stationops/proof-descriptor-index-results-2026-09-09.json).
Full logs, proof outputs, plans and per-file manifests remain under
`/tmp/exact-cache-combined/{validation,development,timing}`. The measured archive
is frozen; documentation and evidence are supplied separately for review.
