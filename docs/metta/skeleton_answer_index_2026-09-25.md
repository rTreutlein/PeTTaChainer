# Proof-indexed root answers and session measurements

## Scope

This follow-up compares local `skeleton-core` at
`4f2ec882ad7e8fc705996591b8b4b5e5574b8778` with the uncommitted changes in that
worktree. The baseline is a `git archive`; both sides use the repository's
`.venv/bin/python` and its installed PeTTa runtime. No source was fetched and no
runtime was rebuilt. Existing untracked scratch files were excluded and left
alone. The machine is a Ryzen 7 5700X3D under WSL2.

The [measurement artifact](skeleton_answer_index_2026-09-25.json) records runtime
file hashes, the production diff hash, branch/dirty state, commands' source
paths, raw wide-query samples, session summaries, and downstream comparisons.
Raw per-call session data, downstream answers, logs, and profiler data remain
under `/tmp/skeleton-answer-index`; validation logs are under `/tmp/skeleton-subsumption-final`, and the
differential fixture is under `/tmp/skeleton-subsumption`.

## Implementation and contracts

`prune_answer_instances` builds a local balanced-tree index from ground proof
terms to candidate answers. Each answer only checks its own proof group.
Index keys are complete terms, so there is no hash-collision approximation.
Candidate order within each group is also preserved, so an early general
answer remains an early exit. No persistent space, invalidation rule, or public
API is added.

The filter retains the previous semantics:

- Variant answers, including exact duplicates, do not eliminate each other.
- An answer is eliminated when a different answer has the same proof and its
  statement can unify without specializing the answer's statement.
- Proofs containing variables cannot be identical after independent copies,
  so they pass through without comparisons.
- Context and TV remain part of the initial full-answer variant test, but are
  not added as new restrictions on statement subsumption.
- Inputs remain unbound. Each surviving answer is copied independently, as by
  the former `collapse`, preserving internal sharing and isolation between
  returned answers. Survivor order and materialization selection are unchanged.

For bounded-size terms, indexing costs O(n log n), followed by O(sum(k_i^2))
comparisons in the worst case, where k_i is one proof group's size. Distinct
proofs no longer incur all-pairs comparisons or repeated copying. A large group
of identical proofs with mutually incomparable statements remains quadratic.
Index storage is O(n) and dies with the call.

This is primarily an algorithmic performance improvement. Production source
under `pettachainer/metta` goes from 7,164 to 7,174 physical lines (+10), including
comments and blanks. Two MeTTa equation names disappear (513 to 511), and three
native predicate arities implement the index and filter. This pass does not
claim a further net code-size reduction; it removes the old implementation
without a compatibility path.

## Broad stored-fact queries

Three alternating fresh-process pairs per size; ingestion and library loading
are outside timing. Every returned proof, statement, truth value, and answer
count is checked. No other test or benchmark process was run concurrently.

| Answers and query | Baseline seconds | Candidate seconds | Speedup |
| --- | ---: | ---: | ---: |
| 100, cold | 0.030530 | 0.012021 | 2.5x |
| 100, warm | 0.027681 | 0.009166 | 3.0x |
| 600, cold | 0.752359 | 0.063243 | 11.9x |
| 600, warm | 0.736713 | 0.047937 | 15.4x |
| 1,800, cold | 6.418778 | 0.193338 | 33.2x |
| 1,800, warm | 6.351621 | 0.142706 | 44.5x |

Three candidate-only runs at 5,400 answers have medians 0.584506 seconds cold
and 0.434741 seconds warm. Tripling the answer count from 1,800 therefore takes
3.02x the cold time and 3.05x the warm time on this distinct-proof workload.
There is no measured baseline speedup claim at 5,400 answers.

## Validation

- `scripts/test_metta.sh`: 71 passed, 0 failed, including new subsumption cases.
- `scripts/strict_check_metta.sh`: strict typing and determinism pass.
- `scripts/verify.sh`: all four gates pass in 128 seconds; 58 Python tests,
  50 recorded query rows and zero aborts, import-scaling ratio 0.987 against a
  1.5 limit, and exactly two ConceptNet answers.
- 1,500 seeded generated cases match the old compiled MeTTa filter. These cover
  shared variables, open proofs, varying TVs/contexts, general/specific
  statements, and non-fact result shapes. The oracle was extracted from the
  archived baseline into `/tmp`; no retired helper is retained in production
  or the committed tests.

## Long-lived sessions

`skeleton_sessions.py` uses one KB for 40 rounds, with three unchanged queries
following each growth query. These are exploratory single fresh-process pairs,
not three-pair application performance gates. In both modes, baseline and
candidate produce the same complete normalized proof/TV sequence and the same
state counts. Small timing differences are approximately neutral.

| Session phase, total seconds | Baseline | Candidate |
| --- | ---: | ---: |
| Unrelated growth: 40 growing-root batches | 68.681 | 69.552 |
| Unrelated growth: first stable query after each batch | 9.354 | 9.489 |
| Unrelated growth: remaining 80 stable queries | 0.341 | 0.362 |
| Member history: 40 growth queries | 1.237 | 1.249 |
| Member history: first unchanged query after each addition | 0.704 | 0.720 |
| Member history: remaining 80 unchanged queries | 1.384 | 1.411 |

The unrelated-growth fixture retains two stable roots and adds six roots per
round using the existing durable-query benchmark's rules. Its skeleton grows
from 35 to 620 expanded nodes and from 52 to 1,924 rows. Retained older views
reach 9,594; latest views reach 962. Only eight keys are needed after the stable
query. Candidate peak RSS rises from 132.9 to 896.5 MiB; baseline reaches
898.4 MiB. RSS is a whole-process high-water mark, not a measurement of view
payload size or proof of a leak.

The first stable query after a growth batch becomes expensive: its last-ten-round
median is 460 ms for the candidate. The two subsequent repeats stay at 3.34 ms.
That difference is also present at baseline. The first stable query reaches
2.15 million inferences by the final round; later repeats use 21,930. Caching an
eight-key reachability set is therefore not automatically the right fix for
this transition cost.

The Member fixture grows from 16 to 55 members and reads both the inheritance
fold and a downstream conclusion. Needed keys grow from 51 to 168; older views
reach 118. Candidate steady-query medians grow from 8.90 ms in the first ten
rounds to 25.42 ms in the last ten. Peak RSS stays at 132.8 MiB. This is the
separate case in which walking the reachable fold remains a plausible cache
target; no new reachability cache was added without an invalidation design.

## StationOps downstream gate

The real ChainerGame source is archived at
`db031348f395926e2ff9da6e6d7a89ceef0025d2`. The workload is seed 7, two shifts,
four modules, diagnosis budget 600, and action budget 1. Both revisions use the
same game archive and installed runtime. The runner now supports the pinned
installed runtime when `--petta` is omitted and records per-batch peak RSS.

All six runs (three alternating pairs) pass. Episode results are exactly equal
apart from timing/counters, and full proof answers match after normalizing KB
UUIDs. Every shift answers all four diagnosis roots. Coverage is 100%, score is
637, and regret is zero. This preserves beliefs/TVs and actions as well as score.

| Diagnosis median | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Shift 1 seconds | 12.519458 | 12.466539 | -0.42% |
| Shift 2 seconds | 23.973102 | 23.970936 | -0.01% |
| Shift 1 inferences | 49,624,635 | 49,624,640 | +5 |
| Shift 2 inferences | 96,853,567 | 96,853,571 | +4 |

The existing 5% per-shift timing/inference gate passes. There is no meaningful
StationOps speedup claim: each root returns one answer, so the broad-answer
bottleneck is absent. Median peak RSS is essentially equal: about 610 MiB after
shift one and 1,742 MiB after shift two. This application also warrants further
session-cost work, independently of the root-answer improvement.


## Profile and next target

A separate run profiles the last growth query and its three stable probes. The
profiler captured call-entry counts but no statistical time samples; these
counts identify extra work, not percentages of CPU time. Raw redo fields are
not used. Profiling is excluded from the timing comparisons above.

| Call count | Final growth | First stable probe | Second stable probe |
| --- | ---: | ---: | ---: |
| `sk-need!` | 6,533 | 12 | 12 |
| `sk-search!` | 3,090 | 15 | 15 |
| `sk-force-cause!` | 186,552 | 0 | 0 |
| `remove-atom-proven` | 183,364 | 182,426 | 18 |
| `sk-mark-stale!` | 0 | 10,800 | 0 |
| `sk-older-views` | 2,634 | 0 | 0 |

`sk-new-support?` is not called in these four profiled queries. The support-union
history scan therefore does not explain this fixture's transition cost.
The first stable query performs the same small need/search traversal as the
second, but additionally clears evaluation bookkeeping and propagates stale
marks. `sk-evaluate!` currently removes queued/forced/used-cause records one atom
at a time; the preceding growth query makes 186,552 force-cause calls.

The next targeted experiment should reduce forced-cause bookkeeping and the
cost of clearing these disposable evaluation stores, while preserving
per-cause forcing and stale propagation. A reachability cache would miss most
of the observed root-switch work. Retained-view memory and the Member fixture's
growing reachable fold remain separate follow-ups. No such cache or lifecycle
change is bundled into this answer-index optimization.
