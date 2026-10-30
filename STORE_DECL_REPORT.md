# Store declaration simplification

Branch: `store-decl`.
Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/store-decl`.
Baseline: `3c87d737b45e82328ca1c71e9ec3cb7b2423f45e`.

## Diagnosis and design

The baseline repeated 144 skeleton SpaceOf declarations and 99 bindings in
`skeleton_journal.metta`, another 16 physical/read declarations and three
bindings for base-rate/forward stores, and 53 overlay store names, arities and
policies in `context_overlay.pl`. Changing a store required synchronizing these
separate lists.

`pettachainer/metta/prolog/store_schema.pl` now contains one declaration for each
of these 108 physical stores: its physical predicate name, overlay policy and
MeTTa row type. This includes the native fact-watch space, whose old binding had
no row annotation. Its new annotation is `(Number Number SkPattern)`, matching
the existing native hash/digest/node layout. Store descriptions and indexing
contracts moved beside their declarations.

Policies are `plain` (no overlay), `main` (read through to MAIN), `local` (start
empty in an overlay), and `view` (the static native waiter relation; no mutable
space binding). The bootstrap invokes `declare-stores!` once before consumer
modules are analyzed. It generates ordinary MeTTa SpaceOf declarations and
bindings through the pinned runtime's normal source processor. The overlay
bootstrap reads the same schema to derive arities, metadata and static read
facades; MAIN remains a direct call to each separate physical predicate. No
row layout, first lookup column, merge formula, search ordering, budget or
context policy changes. Constructor-headed schemas such as `sk_new` retain the
constructor column when deriving physical arity (six for `sk_new`).

Both the overlay metadata and facades are static after generation. Generation
is idempotent when the native prelude is consulted again during cached loading.
There is no checked-in generated copy or extra build command. The existing
package-data rule includes the new Prolog source. No old declaration lists or
compatibility implementations remain.

A per-store runnable placed inside consumer modules was rejected: PeTTa's
whole-file analysis runs before the module's runnables, so it cannot see those
types in time. Generating all ordinary declarations before importing consumers
keeps the compiler boundary explicit. A mixed tagged store was excluded by the
indexing requirement. A separate build-time artifact would add a synchronization
step and retain redundant generated source.

The write-boundary audit now gets its overlay set from loaded `context_store/3`
metadata and requires it to be nonempty; its previous regex over handwritten
facts would silently stop auditing after this simplification. The existing
cold-load/cache-replay test also checks typed static facades, static waiter
ownership, static metadata and constructor-headed arity.

## Size accounting

Counts use `o200k_base`, matching `scratch/core_count.py`, against Git blobs from
`3c87d737` and this worktree. Tests, reports and scratch files are excluded from
runtime counts; both the new schema and generator are included.

| Measure | Before | After | Change |
|---|---:|---:|---:|
| Explicit generated-interface boilerplate | 4,194 tokens | 0 | -4,194 |
| Core runtime source | 323,230 tokens | 321,129 tokens | -2,101 |
| Unchanged third-party runtime source | 17,685 tokens | 17,685 tokens | 0 |
| Total runtime source | 340,915 tokens | 338,814 tokens | -2,101 |
| Core executable source lines | 16,089 | 15,897 | -192 |

The first row counts the removed 160 explicit SpaceOf forms, 102 bindings and
53 handwritten overlay metadata facts, joined by newlines. It is the gross
interface-source removal, not the net saving. The net rows include the schema,
generator, modified bootstrap, metadata/facade generation and relocated comments.
The schema and its MeTTa generator cost 3,671 tokens; facade generation is counted
in `context_overlay.pl`. Executable lines exclude blank/comment-only lines
(`;` in MeTTa, `%` and block comments in Prolog, `#` in Python). Third-party
source is unchanged, so its executable-line contribution cancels exactly.

Evidence: `scratch/counts.json`, `scratch/count_interfaces.py`,
`scratch/count_changes.py`, `scratch/core-count-after.txt`.

## Validation

All PeTTa, tests and comparisons were launched through
`/nexus/Dev/OpenCog/bench/capped`, under `ulimit -v 16000000`, with `DISPLAY` unset
and stdin from `/dev/null`. The existing pinned `.venv` was used without edits.

- Strict MeTTa suite: 162 files passed, zero failed (inside verify).
- Cold library load and cached replay: PASS, including new interface assertions
  (`scratch/cache-final.log`). Snapshot names and mtimes are identical on replay.
- Baseline schema audit: all 107 original physical schemas match after the
  runtime's type normalization; all 53 overlay policies match; all generated
  facade types and static predicates exist; `sk_new` retains arity six and
  `sk_wait` remains static (`scratch/schema-audit.log`).
- Full verify: **PASS**, all six gates, 574 s wall (`scratch/verify-1.log`).
  Python: 992 tests, 63 files / 623 units, 64 pre-existing expected failures,
  one pre-existing skip, zero failures; 4,496 query metric rows, zero aborts.
  Import scaling late/early median ratio 1.006 (limit 1.500); judgment scaling
  PASS; ConceptNet PASS. The verifier did not record a shared cache entry because
  test auditing and this report were edited during the run. Runtime source was
  unchanged throughout the gate run; the final strengthened cache test also
  passed separately after the test edits. This is a cache-provenance limit, not a failing
  gate; a landing may rerun verification.
- `git diff --check`: PASS.

## Benchmarks

Candidate runtime tree: `f8de432a4256a23db5e4acbbfb6c9252220005d9`.
The first frozen label is `3c87d737-d8691694a`. The harness may print later labels
when tests change, because labels hash the whole Git diff; its runtime-tree
check resolves those labels to the same frozen runtime and reuses its results.

Quick comparison: **PASS**, accuracy changed in **0 cases** (10 cases, 78 s wall).
Report:
`/nexus/Dev/OpenCog/bench/results/compare/3c87d737_vs_3c87d737-d8691694a_quick/report.md`.

Full comparison: **PASS**, **accuracy identical in all 22 paired cases**;
23 profile cases including the CombINet reference-only case, 36 runs executed,
9 results reused, 223 s wall. No timing, accuracy or RSS flags, and no false flags.
Report:
`/nexus/Dev/OpenCog/bench/results/compare/3c87d737_vs_3c87d737-d8691694a_full/report.md`.

The brief's stricter per-row RSS check also passes: every one of the 22 paired
rows stays below +5%. The maximum increase is **+0.3175%**, replay b25 s1,
220.5 -> 221.2 MB. Other largest increases: stage 3 timed b50 s3, 210.2 ->
210.8 MB (+0.2854%); fuzz all n100 s22, 152.7 -> 153.1 MB (+0.2620%).
The CombINet reference-only row has no candidate/base RSS comparison.
Evidence: `scratch/rss-full.json`. No full-profile case needs a flagged-case
retime.

Anchor canary: its first report printed PASS and four expected differences from
the older anchor, but all six remote timing launches failed with exit 127:
the worktree interpreter path did not exist on dev-server. This is not accepted
as timing evidence. A private copy of the timing host's matching pinned runtime
was created under this worktree's own remote `.venv` path; the source and runtime
of the main checkout were not changed. A standard `--canary --retime` comparison
completed successfully: **PASS**, all **12** paired timing runs exited **0**,
load 1 throughout, 300 s wall, no regression or false-timing flags. Its report is
`/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_3c87d737-d90b6df15_canary-retime-20261030T045501/report.md`.
The accuracy line reads **changed in 4 of 6 cases** against the old anchor:
live, stated conflict, reliable conflict and scale. The harness classifies all
nine anchor accuracy/timing flags as already present on master, not introduced
by this branch. Examples of anchor/current seconds are 4.708 -> 7.452 (live),
8.778 -> 61.05 (reliable conflict), and 19.08 -> 30.51 (scale). These gaps are
reported, not presented as improvements or waived candidate regressions.
The original failed-host report is retained for provenance but superseded by
this successful paired retime. No benchmark script, seed or frozen build was
modified by hand.

A supplementary direct master canary also passes: **accuracy identical in all
6 cases**, no timing/RSS/accuracy flags, all runs successful, load 1 throughout.
This compares the committed implementation `6e8f10e9` directly with `3c87d737`,
confirming that the four old-anchor answer differences were already on master.
It executed six fresh candidate timing runs and reused six master results, 171 s
wall. Maximum per-row RSS change is +0.2736% (219.3 -> 219.9 MB for ONA
conditioning); the other five rows are unchanged or smaller. Report:
`/nexus/Dev/OpenCog/bench/results/compare/3c87d737_vs_6e8f10e9_canary/report.md`.

## Moved expectations and overlap

No expected truth value, proof, benchmark answer or EXPECTED_FAILURES entry was
changed. The two modified Python tests strengthen interface/cache auditing only.
`git diff 3c87d737 -- tests/test_tv_calibration.py` is empty.

No edits to `prolog/event_graph.pl`, `prolog/event_node.pl` or their evaluation
callers. Runtime overlap is confined to the bootstrap, core base-rate store
annotations, skeleton store/type journal, forward store annotations and overlay
metadata bootstrap. No event-node or key-evaluation behavior was edited.
No master, main-checkout or other-worktree code was changed; no push, merge or
GitHub write was performed. External writes were limited to required benchmark outputs, the verify runner's
allowed shared cache, and this worktree's private runtime copy on the timing host.

## Commits and limits

`6e8f10e9` — Declare skeleton and overlay stores from one schema. Implements
and validates the schema, native generators, bootstrap and auditing/cache tests.
The documentation-only commit titled `Record store declaration gates and provenance`
records this report and the final timing results.
Both commits use the brief's requested Co-Authored-By and Claude-Session trailers.
No scheduling/budget/anytime behavior changed, so curves are outside this brief.
The schema covers the journal stores and every existing overlay store; unrelated
compiler/runtime spaces outside that scope retain their existing declarations.

All jobs launched for this task completed and were reaped before hand-back.
