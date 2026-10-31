# Structure round 8 hand-back

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct8`.
Branch: `struct8`; baseline: `baae773ce633d8edac88f70505a80157b0eb6269`.
Scope: structure round 8 only. No numerical correction, public API change,
posterior modification, push, merge or GitHub action.

## Result

The brief's initial partition measured **26 reciprocal pairs, width 126**.
The final semantic partition measures **5 reciprocal pairs, width 41**.
The partition changed, so this is not presented as a fixed-boundary comparison:
using the final script on *both* revisions gives **22 → 5 pairs (−77.3%)**
and **57 → 41 widest interface (−28.1%)**. Cross-boundary references on that
fixed partition are **632 → 638 (+6)**; splitting genuine owners adds some
one-way interfaces. No source file remains in `Other runtime`.

Two remaining pairs involve protected posterior code; three are lexical data
references, described below. This is a substantial reduction, not a claim that
the whole architecture is now an acyclic hierarchy or that the protected
posterior has its eventual three-function interface.

## Commits

```
d0612706 Complete store ownership and expose measured internal interfaces
165e4364 Give evaluation and invocation control distinct owners
d1346314 Separate shared fact and proof storage from search
```

Each commit carries the brief's two requested trailers. The final report and
interface inventory receive a separate documentation commit.

## Diagnosis and design as built

The initial partition mixed engine recursion with external interfaces and put
proof meaning, term constructors, key indexes, fact publication, ingestion,
query wrappers and numerical context reads in overlapping owners. The 122-name
core-to-values edge crosses an internal mutually recursive numerical component;
calling those files separate subsystems obscures the actual boundary.

- Put the numerical core, version selection, merge, folds, sampling, demand and
  value-change engine in `runtime/evaluator/`. Its equations and the named row
  fold boundaries are unchanged. Early instruction scoring remains loaded at
  its original stage in `runtime/values.metta` and `scheduling.metta`.
- Move numerical context reads out of the invocation controller. Move root
  producer installation and indexing into search. The executor owns brackets,
  worlds and presentation, rather than providing callbacks to numerical reads.
- Put shared key/reader/row operations in `runtime/store/`. Certainty and
  completeness policy, unifier indexes, retained versions and physical row or
  copy retirement are lower operations used by both search and evaluation.
- Separate compiled installation from physical publication, and public query
  compilation from scoped presentation. The input journal records changes;
  shared nominal adapters and pure TV normalization have their own lower owner.
- Aggregate storage consumes supplied contributions. Numerical stored-fact
  merging and aggregate seeding belong to the evaluator. Rule identity and
  proof meaning are distinct from statistical learning. Rate descriptor plans
  are distinct from the ledger that maintains their estimates.
- Move native metadata marking/removal and immutable functional-key lookup
  alongside physical state. Move DAG presentation beside proof semantics.
- Move forward declarations into the bootstrap ABI where necessary. PeTTa
  registration/specialization order remains explicit. The first split exposed
  an import-order warning; the corrected split passed the strict loader/suite.

There are no forwarding implementations or compatibility modules at old paths.
A generic subsystem multiplexer was rejected: it would hide existing protocols
behind dispatch and add work to hot reads. The implementation instead moves
existing operations to their owners without adding runtime helper functions.

[Ownership and explicit entry-point lists](docs/metta/module_dependencies.md)
cover every subsystem. Those are internal contracts; [API.md](docs/metta/API.md)
is unchanged.

## Interfaces, using one partition for both revisions

`A / B` below means A→B / B→A distinct referenced function names.
Reproduce with `python3 scripts/coupling.py baae773c --json` and
`python3 scripts/coupling.py HEAD --json`. The algorithm is unchanged: lexical
names, unique owner, distinct functions per edge, union per target interface.
Only the ownership map was updated; historical paths let it measure baseline.

| Owner | External names before | After |
|---|---:|---:|
| API | 10 | 6 |
| Allowances | 16 | 16 |
| Bootstrap/ABI | 0 | 0 |
| Compiler | 13 | 12 |
| Compiler plans | 13 | 13 |
| Core types | 31 | 32 |
| Evaluator | 43 | 39 |
| Executor | 8 | 8 |
| Fact store | 29 | 41 |
| Input journal | 7 | 7 |
| Installation | 6 | 5 |
| Native stores | 20 | 18 |
| Posterior | 2 | 2 |
| Proof search | 41 | 15 |
| Proofs | 35 | 29 |
| Runtime terms | 0 | 21 |
| Search state | 12 | 38 |
| Statistics | 57 | 40 |
| Value store | 25 | 25 |

## Every reciprocal pair in the fixed-partition baseline

| A | B | Before A→B / B→A | After A→B / B→A | Result |
|---|---|---:|---:|---|
| API | Executor | 1 / 3 | 1 / 0 | one-way or removed |
| API | Native stores | 1 / 2 | 1 / 2 | retained |
| Compiler | Evaluator | 7 / 1 | 7 / 0 | one-way or removed |
| Core types | Executor | 1 / 10 | 0 / 9 | one-way or removed |
| Evaluator | Executor | 2 / 24 | 0 / 19 | one-way or removed |
| Evaluator | Fact store | 12 / 1 | 20 / 0 | one-way or removed |
| Evaluator | Input journal | 4 / 1 | 3 / 0 | one-way or removed |
| Evaluator | Installation | 1 / 3 | 0 / 2 | one-way or removed |
| Evaluator | Posterior | 1 / 4 | 1 / 4 | retained |
| Evaluator | Proof search | 25 / 1 | 0 / 1 | one-way or removed |
| Evaluator | Proofs | 26 / 2 | 21 / 0 | one-way or removed |
| Evaluator | Search state | 3 / 1 | 19 / 0 | one-way or removed |
| Evaluator | Statistics | 38 / 2 | 30 / 0 | one-way or removed |
| Evaluator | Value store | 23 / 1 | 22 / 1 | retained |
| Executor | Installation | 2 / 1 | 1 / 0 | one-way or removed |
| Executor | Proof search | 20 / 1 | 13 / 0 | one-way or removed |
| Fact store | Native stores | 1 / 1 | 0 / 1 | one-way or removed |
| Native stores | Posterior | 2 / 2 | 2 / 2 | retained |
| Native stores | Proofs | 2 / 5 | 0 / 3 | one-way or removed |
| Native stores | Search state | 1 / 2 | 0 / 3 | one-way or removed |
| Posterior | Statistics | 1 / 1 | 0 / 1 | one-way or removed |
| Proofs | Statistics | 4 / 4 | 0 / 2 | one-way or removed |
| Installation | Search state | 1 / 0 | 1 / 1 | new lexical pair; see below |

## Decisions for the brief's original 26 pairs

The old pair names do not survive the new owner map, so their after-state is
reported as the actual ownership decision rather than invented same-name counts.
The numerical per-pair table above applies one map to both revisions.

| Original pair | Lower owner / after-state |
|---|---|
| Compiler ↔ Evaluator: values/merge/folds | Pure ExistentialFloor is a shared core operation; compiler emits evaluator instructions. No reciprocal compiler/evaluator pair remains. |
| Compiler ↔ Other runtime | Compilation belongs to API; numerical instruction adapters belong to evaluator. Physical stores do not compile public requests. |
| Core types ↔ Evaluator: core/work | Controller declarations belong to Bootstrap/ABI, not core types. |
| Core types ↔ Forgetting | Retirement contract is ABI; physical retirement belongs to Value store. |
| Core types ↔ Other runtime | Shared term/collection primitives and invocation allowances have explicit lower owners. |
| Core types ↔ Prolog stores | Native declarations are Bootstrap/ABI; shared syntax stays core. |
| Core types ↔ Proof search | Query/controller forward declarations are ABI; primitive constructors and counters are shared terms. |
| Evaluator: core/work ↔ Evaluator: values/merge/folds | One recursive Evaluator owner; value publication remains an explicit lower store boundary. |
| Evaluator: core/work ↔ Forgetting | Dependency-root enumeration is a Value store operation; freezing policy stays in Executor. |
| Evaluator: core/work ↔ Other runtime | Numerical context reads move into Evaluator; installation, fact reads and allowances have separate owners. |
| Evaluator: core/work ↔ Posterior | Protected posterior callbacks remain; same Evaluator/Posterior pair as the values side. |
| Evaluator: core/work ↔ Proof search | Root installation belongs to search; shared indexes belong to Search state. Evaluator no longer calls Proof search. |
| Evaluator: core/work ↔ Statistics/learning | Numerical stored-fact merge/seeding belongs to Evaluator; contribution maintenance remains lower Statistics. |
| Evaluator: values/merge/folds ↔ Other runtime | Shared fact/policy/term operations are lower; public readers and context reads are upper API or Evaluator. |
| Evaluator: values/merge/folds ↔ Posterior | Protected posterior callbacks remain; not edited in this branch. |
| Evaluator: values/merge/folds ↔ Proof search | Shared certainty/completeness and key/reader operations moved below both engines. |
| Forgetting ↔ Other runtime | Freezing policy is Executor; physical publication and copy retirement are lower stores. |
| Forward ↔ Other runtime | Forward trigger schemas and aggregate-fold links belong to Fact store; upward execution remains Executor. |
| Other runtime ↔ Posterior | Instruction adapters are Evaluator; prefix lookup is lower fact indexing. Protected posterior is unchanged. |
| Other runtime ↔ Prolog stores | DAG presentation belongs to Proofs; native metadata lifetime and immutable key lookup are physical store operations. |
| Other runtime ↔ Proof search | Public query/presentation are upper API/Executor; matching and key operations are lower Search state. |
| Other runtime ↔ Statistics/learning | Installation is a controller; numerical reads are Evaluator; journal and fact schema are lower stores. |
| Posterior ↔ Prolog stores | Native reset/context/index reciprocal pair remains in protected integration. |
| Posterior ↔ Statistics/learning | Predicate/rule policy is separated from tallies; protected posterior references remain unchanged under the new owners. |
| Prolog stores ↔ Proof search | Shared functional-key lookup is native state; proof metadata callbacks are lower physical operations; key/reader state is no longer the search engine. |
| Proof search ↔ Statistics/learning | Review queries belong to API; numerical seeding is Evaluator; dirty notifications belong to Input journal. |

## The five remaining pairs

| Pair | Reason |
|---|---|
| API ↔ Native stores | `compileadd` and `query` occur in native validation error `context(Name/Arity,...)` terms. Native validation does not call those APIs. |
| Evaluator ↔ Value store | The cache volatility check recognizes the CPU instruction name `rule-likelihood-read`; the value store never invokes it. |
| Installation ↔ Search state | Native base-rate validation names `set-base-rate` in its error context. Installation calls application-source discovery downward. |
| Evaluator ↔ Posterior | Protected posterior admission/filter/leaf/cavity callbacks; retained for the parallel posterior owner. |
| Native stores ↔ Posterior | Native evaluation reset and posterior context/index integration; protected boundary retained. |

The metric still counts those names. None is suppressed to improve the score.
The unchanged lexical analyzer also omits quoted Prolog definitions and counts
some data tags; this is a structural signal, not a complete resolved call graph.
Native retirement still reads fact-selection policy, and compiler/runtime dynamic
instruction dispatch remains. A full DAG proof or final posterior interface is
outside the achieved result.

## Behaviour evidence and tokens

- Source audit: **2,608** parsed MeTTa equations/declarations/datatype forms
  unchanged, including every public signature. Native audit: **608 predicates,
  950 clauses**, identical per-predicate clause lists, including order.
- Four protected files (`event_node.pl`, `event_graph.pl`, `event_values.pl`,
  `source_catalog.pl`) are byte-identical to `baae773c`. No third-party changes.
- Core o200k tokens (`scratch/core_count.py`): **325,471 → 325,654 (+183,
  +0.056%)**. Third-party tokens remain **17,685**. Added imports and ownership
  comments explain the small net increase; no runtime helper was added.
- All strict MeTTa checkpoints: **162 passed, 0 failed**. The first final
  verification passed every runtime gate but failed the coupling fixture's old
  `Forward` label. That fixture now uses `runtime/backward/upward.metta` and
  `Executor`; its 4 edges, 5 references, 1 reciprocal pair and width 2 are
  unchanged. Focused coupling tests pass. Final verification is recorded below.
- No numerical/proof/scheduler expected value or calibration expected-failure
  entry changed. No model-behaviour test was removed or weakened.

Static audit artifacts: `scratch/struct8/equivalence.json`,
`coupling-before.json` (original map), `coupling-fixed-before.json`,
`coupling-after.json`, `tokens-before.txt`, `tokens-after.txt`.

## Gates and benchmarks

`scripts/verify.sh`: **PASS** (240 s), cache key `96f3b6e2096c`.
All six gates pass. MeTTa: 162 passed; Python: 1,043 tests in 74 files,
634 units, 24 expected failures and 1 nightly skip. Query metrics: 4,554 rows,
zero aborts. Log: `scratch/struct8/verify-final.log`.

Anchor canary: **PASS**, six cases, 13 runs executed, 731 s wall.
`accuracy changed in 4 cases` relative to the older anchor: live,
conflict stated, conflict reliable and scale m. The harness's master check
classifies all nine anchor gaps as already present on `baae773c`; no new
regression is accepted. All base/candidate runs exited zero. The report records
48/50 live beliefs changed versus the old anchor, maximum shift 0.1137; that is
an anchor comparison, not a change introduced by this branch.

Canary report:
`/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_d0612706_canary/report.md`.
Log: `scratch/struct8/compare-canary.log`.

Full comparison against `master` (`baae773c`): **PASS**.
`accuracy changed in 0 cases`; the report says `accuracy identical in all
22 cases`. Both 200-belief replay streams are identical (zero changed beliefs,
maximum shift 0). Fuzzer: 5 → 5 flagged KBs, none newly flagged, zero unsupported
KBs and zero crashes on both sides. All present base/candidate runs exited zero.

23 cases; 62 runs executed, 3 of 45 results reused, 1,635 s wall. Paired timings
were collected on the dedicated host with `BENCH_TIMING_FULL=1`. No timing
regression or false flag was reported. Representative measured wall times:
scale l spq16, 158.86 → 158.15 s; learned/mined history, 90.59 → 91.10 s.
No speedup is claimed.

The brief's stricter RSS gate was checked separately across every comparable
per-case **accuracy and timing** record: maximum increase **0.7442%**, at
SupplyNet stage 1 b100 s3, **174.7 → 176.0 MB**. The worst paired-host increase
is **0.6195%**, replay b25 s1, **226.0 → 227.4 MB**. Both are below **+5%**.
This does not rely on the harness's looser default RSS threshold.

Full report:
`/nexus/Dev/OpenCog/bench/results/compare/baae773c_vs_d0612706_full/report.md`.
Log: `scratch/struct8/compare-full-final.log`.
Structured gate/RSS audit: `scratch/struct8/benchmark-summary.json`.
Build provenance: candidate `d0612706`, runtime tree `6b6aa6f08b86`; base runtime
tree `e4687497add0`; PeTTa `eec735bf4d1d3e31`; ChainerGame supply `3daf989e93`,
replay `d274b45767`. The report-only commit does not change these runtime inputs.

All runs use the prescribed admission wrapper, worker count, 16,000,000 KiB
virtual-memory limit, unset DISPLAY and closed stdin. `compare.sh` manages
admission and frozen builds itself. No seeds, runner or frozen build was improvised.
The first full comparison's local accuracy runs all succeeded, but its remote
timing attempts exited 127: the timing host lacks this worktree's interpreter
path when `PETTACHAINER_REPO` points here. Its nominal PASS is not used as the
final timing gate. The worktree/shared installed PeTTa packages were checked
byte-identical (source-tree SHA-256 in `scratch/struct8/runtime-hash.txt`), and
standard comparisons were rerun with the default shared interpreter path.

## Limits and hand-back

Only round 8 was attempted, and all prescribed gates passed. All jobs started
for this work have finished; no background waiter remains. The remaining
protected posterior integration and
three lexical pairs above are retained explicitly. No complete acyclic hierarchy,
new posterior semantics, or performance speedup is claimed. Curves were not run:
no scheduling rule, allowance, search order or anytime policy changed. All
source changes are focused ownership moves; source audits and behavioural gates
are complementary evidence, not substitutes for one another.
