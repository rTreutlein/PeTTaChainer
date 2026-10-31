# Structure step 7: application discovery and a smaller global cycle

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct7`.
Branch: `struct7`; actual base: **77cce1fa971ddb8aab5fe0da5de3add55c95a185**.
Implementation and pre-verification report checkpoint: **05c7a6ad**
(`Separate application discovery and break owner-to-evaluator cycles`).
All required acceptance gates and fresh paired timing follow-ups are complete
and passing. This report-only follow-up records their results. No source or
test input changes follow the implementation checkpoint.

## Design as built

`runtime/application_discovery.metta` owns backward application matching,
contextual premise binding, fixed MAIN-node reuse in judgments, ground binding
guards, forward-trigger matching and late-rule matching. Backward expansion,
forward joins and late activation consume one typed application contract:
`SkeletonMatch = (sk-match rule-id contextualized-premises conclusion)`.
This is the single existing wire representation, now shared by all three
clients. Matching preserves conclusion/premise variable sharing and the distinct
proof/TV selection policies of backward lookup and late activation. Discovery
publishes no inference value and starts no join. The clients construct joins.
Ground CPU prefilters retain their existing binding/pruning semantics.

`runtime/application_policy.metta` supplies `ApplicationInputs`: the derivation
pin policy, shared frontier, node/completion route and an entanglement policy.
The completion input projection remains linked to the actual row's observation,
remaining instructions and output variable. Numerical `sk-row-state` consumes
these fields and returns a row state; `sk-row-result` returns a value. Neither
kernel directly publishes a proof/view, mutates a queue, or schedules readers.
Existing read/conditioning controllers still supply their recursive inputs.
The proof, value and statistical owners retain publication and the scheduler
consumes the existing returned changes. Numerical policies and work amounts
are unchanged.

A result proof can be unbound before premise reads and become an application
while those reads run. `ApplicationEntanglement` therefore retains that live
proof binding. The proof owner reads its role **after** the fold, at the old
semantic point, rather than caching an early Boolean. Read plans are transient
linked views; the durable row has its original shape and no new store/lifetime.
The named `sk-row-state` fold remains in its existing evaluator compilation
boundary. A callback-based extra reduction changed behavior and was reverted.
No compatibility implementation or duplicate kernel remains.

The executor owner, `runtime/execution.metta`, now contains allowances, nested
slices, claim/frame lifetime and the depth/reserve policy. The invocation
controller moved to `runtime/backward/execution.metta`; it consumes those
operations while orchestrating discovery, evaluation, world runs, presentation
and finally cleanup. The owner no longer calls an evaluator, search routine or
query presenter. Public chainer/forward/query signatures are unchanged.

The shared native file previously made every storage client depend on discovery
and controller callbacks. Its implementations are partitioned into:

- `prolog/runtime_state.pl`: physical indexed state, identities, evidence/proof
  lifetime, pending-search ownership, counters and generic term/call utilities.
- `prolog/application_support.pl`: compiled binding projections, input policy
  and support/admission metadata.
- `prolog/event_values.pl`: event-value numerical kernels.
- `prolog/runtime_helpers.pl`: native bootstrap and upper controller/mining
  services, including the existing graph/forcing reset controller.

The declaration factory moved to the existing `prolog/execution.pl` so its
registration operation does not depend on the upper service file. These files
retain the existing shared native namespace, exact clauses and store indexes.
No forwarding facade or old implementation is retained.

`runtime/fact_reads.metta` owns indexed fact filtering, positive projection and
MAIN borrowing subscriptions; it expands/evaluates no search. Node hashing
moved to the journal, shared proof-role operations to the proof owner, and the
pure contextual-CPU classifier to vocabulary. Prefix-key construction belongs
to the fact index. Numerical stored-candidate merging moved out of the forward
schema into aggregation. These changes remove the remaining upward references
from the storage/policy owners, rather than hiding them behind callbacks.

The layer order is vocabulary/physical primitives; storage and policy owners;
application discovery and construction; numerical reads/conditioning;
owner publication and scheduler-consumed changes; invocation/presentation.
The read controllers remain recursive. This is not a claim that every file is
acyclic. Existing generic callback/finally facilities receive explicit callable
parameters and select no fixed upper operation.

## Structural measurements

The supplied `scratch/reference_graph.py`, `reference_terms.pl` and
`core_count.py` are unchanged. The brief's 41-file historical SCC is not the
actual merged base: the same supplied counter measures **46** on 77cce1fa.

| Metric | Actual base | Final implementation |
|---|---:|---:|
| MeTTa/Prolog files | 59 | 66 |
| Defined names | 1,788 | 1,793 |
| Directed file edges | 411 | 471 |
| External callee references | 1,478 | 1,536 |
| Reciprocal file pairs | 16 | 12 |
| Largest file SCC | **46** | **20** |
| Nontrivial SCC sizes | 46 | 20, 18 |
| Owner paths to discovery/evaluation | present | **0** |
| Numerical kernel direct publication/queue writes | 0 | **0** |

All requested owners have **no direct or transitive path** to discovery or the
backward evaluators under the supplied graph's resolution rules: vocabulary,
source catalog, both proof-owner parts, value store, KB publication, both ledger
parts and both executor parts. The new application-policy owner has none either.
The 20-file component contains the inference/controllers; the 18-file component
contains the shared storage/policy primitives. Application discovery, application
policy, the executor owner and the KB/statistical publication owners are outside
the inference component. Full memberships and edges are in the captured graph.

The counter counts static expression/callback references and resolves names
across languages; imports, stores, generated predicates and dynamic call targets
are excluded. It deliberately ignores arity. The mining-only
`generalize_argument/3` was renamed `hypothesis_generalize_argument/3`, distinct
from the physical constant generalizer `generalize_argument/4`. These are
separate operations; the name collision otherwise manufactures an upward edge
after partitioning the native file. No call is hidden by that disambiguation.
The native-equivalence audit normalizes this intentional name change and
compares clauses **per predicate and arity**: **641 predicates / 987 clauses
before and after, zero changed clauses**. All native behavior, indexing and
numerical code is retained.

`o200k_base`, supplied core scope (MeTTa/Prolog and top-level Python):

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core | 329,959 | 329,838 | **-121** |
| Third party | 17,685 | 17,685 | 0 |
| Total | 347,644 | 347,523 | **-121** |

Core size is effectively unchanged; the significant result is the **26-file
SCC reduction** and the absence of owner-to-inference paths, not token savings
or a claimed speedup. The runtime assumptions document records the binding and
ownership boundaries.

Reproduce from this worktree, each command through the pinned environment and
`capped`, with DISPLAY unset, `ulimit -v 16000000`, stdin from `/dev/null`:

```sh
.venv/bin/python scratch/reference_graph.py --revision 77cce1fa
.venv/bin/python scratch/reference_graph.py
.venv/bin/python scratch/structure_audit.py scratch/graph-final.json
.venv/bin/python scratch/native_equivalence.py
.venv/bin/python scratch/core_count.py .
```

The direction audit also checks the two named numerical kernels for direct
publication/queue mutations. It does not pretend recursive reader effects are
pure or that static references measure execution frequency.

## Tests, binding diagnosis and moved values

The strict MeTTa suite passes **162 files, zero failures** on the completed
implementation (`scratch/metta-accepted.log`). It includes all requested
forward, contextual forward, antecedent completion and instance-fold files.
The final verification below repeats the gates on the committed inputs.

Five new Python checks pass (`scratch/application-five.log`): all three clients
produce the same linked application modulo nonbinding attribute-free alpha
identity; late rules/facts preserve open answers; completion plans preserve the
formula/output variable link; transported proof roles are read after binding;
and the late-fact prefix selector grounds its conclusion through its actual
premise. Existing pending-work differential tests now read their physical owner
file, `runtime_state.pl`. No old expected assertion is weakened.

A real compile-boundary defect was caught by the quick comparison. The moved
`sk-premise-rules-step` originally preceded the `nth0` import left in the
skeleton. The pinned compiler silently emitted **`M=[nth0,K,G,N]`**, data rather
than a binding operation; the unused local result let strict checking pass.
Late-fact selection then lost conclusion bindings. Several experimental trees
therefore kept the same scale regression despite changing unrelated plan
boundaries. The import and relational type declaration now move with their
caller. The compiled body now contains **`nth0(K,G,Q,N)`**, and the new late-fact
selector test checks the effect, not that spelling. The accepted quick comparison
has **zero answer movement**.

Adverse evidence is retained in `scratch/compare-quick*.log` and the standard
comparison store. Earlier candidates moved scale l spq4 s1 error **0.003808 ->
0.00881** and changed three quick cases. Representative report:
`/nexus/Dev/OpenCog/bench/results/compare/77cce1fa_vs_77cce1fa-d3d965cc1_quick/report.md`.
The extra callback fold failed **14 of 162** MeTTa files and was reverted
(`scratch/metta-kernel.log`). An over-broad inverse rename also briefly changed
source annotation names; it was immediately reverted. Compiler/source-ingress
files have **zero final diff**, and that invalid experiment is not acceptance
evidence. No benchmark runner, seed, threshold or oracle was changed.

The first standalone Python run found only the new test file's development
errors (old method spelling and Janus attempts to externalize unbound debug
variables); every existing unit passed. It is superseded by final validation.

**No existing strength, confidence, proof expectation, scheduler score,
threshold or EXPECTED_FAILURES entry moved.** There are no moved numerical
values to derive. Existing numerical approximations and legacy routes remain.
This structure enables replacing them later; it does not establish coverage for
deleting inversion, completion, observed-message, Jeffrey or joint routes.

## Acceptance evidence

Every project/test/benchmark process uses the worktree's pinned runtime through
`capped`, with `ulimit -v 16000000`, DISPLAY unset and stdin from `/dev/null`.
Comparisons set `PETTACHAINER_REPO` to this worktree. The remote timing environment
was copied/repointed only under remote **struct7**; the shared environment was
read to make that copy and was not modified. No push, merge or GitHub write is
made; no other worktree or main-checkout code is changed. Prescribed benchmark
outputs and the authorized verification-cache write are shared runner artifacts.

- Accepted quick: **PASS, accuracy changed in zero cases**, 10 cases,
  **9 runs executed / 10 of 19 reused**, **67.9 seconds wall**. Base runtime
  tree **2fa89eb71fc4**; candidate **7f128253662b**; PeTTa runtime
  **eec735bf4d1d3e31**. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/77cce1fa_vs_77cce1fa-d0754e554_quick/report.md`;
  log `scratch/compare-import-fixed.log`. Subsequent runtime edits only clean
  comments/whitespace, with MeTTa forms checked unchanged. Full acceptance uses
  the final committed tree itself.
- Final standalone Python suite: **PASS**, **1,040 tests / 73 files / 600
  units**, **16 workers**, the existing **24 expected failures and one skip**,
  **223.5 seconds wall**. Includes the requested priority-refinement test and
  all five new application tests. Log: `scratch/python-accepted.log`.
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **PASS,
  all six gates**, **272 seconds wall**, verification key **bed23d188b00**.
  Strict MeTTa: **162 files**, zero failures. Python: **1,040 tests / 73 files /
  600 units**, the same **24 expected failures and one skip**; **4,554 query
  metric rows, zero aborts**. Import scaling: **0.998** late/early median ratio,
  chunks **2.662, 2.668, 2.650, 2.668 seconds**. Judgment scaling passes with
  three query rows and zero aborts. ConceptNet returns exactly two results.
  Log: `scratch/verify-final.log`.
- Final `compare.sh master <worktree> --full`: **PASS; accuracy changed in
  zero cases**. All **22 accuracy comparisons** are identical, plus the
  reference/fuzzer gate: **23 cases**, **42 jobs executed / five of 45 records
  reused**, **816 seconds wall including the shared full-size queue**. All
  **45 accuracy records exit 0**, no unsupported marker. The fuzzer retains
  the same five flagged KBs, no newly flagged KB, zero unsupported KBs and
  zero crashes. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/77cce1fa_vs_05c7a6ad_full/report.md`;
  log `scratch/compare-full.log`. One local timing flag did not repeat:
  scale l spq4 s1 inference seconds **56.15 -> 67.36**, local paired rerun
  **45.35 -> 45.55**. It is retained as adverse timing evidence; its required
  fresh dev-server pair is recorded below.
- Final budget curves: **eight workloads / 40 paired budget points**, every
  measured error **exactly equal**, no missing/mismatched budget and no
  unsupported point, **664 seconds wall**. Includes scale m/l through 32
  steps per query, ordinary/soft SupplyNet, ten regions, conflict and replay.
  Report:
  `/nexus/Dev/OpenCog/bench/results/compare/77cce1fa_vs_05c7a6ad_curves/curves.md`;
  adjacent `curves.json`; log `scratch/compare-curves.log`. Times were taken
  at changing local loads; these curves establish error/budget parity and
  are not claimed as a speedup or as isolated timing evidence.
- Fresh paired `compare.sh anchor <worktree> --canary --retime`: **PASS**,
  six cases, **18 jobs executed**, all **12 fresh dev-server timing jobs exit
  0 at load 1**, **349 seconds wall**. All **12 accuracy records exit 0**;
  regression and false-flag lists are empty. The four cases differing from
  the historical anchor and its nine deficits are also present on master;
  none is introduced here. Candidate runtime tree **6ff8d0d26c24**. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_05c7a6ad_canary-retime-20261031T041321/report.md`;
  log `scratch/compare-canary.log`.
- Separate master/candidate canary: **PASS, all six cases exactly identical**,
  12 accuracy records reused, six successful candidate timing jobs at load 1,
  **190 seconds wall**. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/77cce1fa_vs_05c7a6ad-d5c78ae15_canary/report.md`;
  log `scratch/compare-master-canary.log`. Its dirty label captures report-only
  edits; the report records the implementation's identical runtime tree
  **6ff8d0d26c24** and runs build **05c7a6ad**. No gate/source input changed.
- Required fresh paired dev-server retime of **scale l spq4 s1**: **PASS**,
  identical accuracy, both fresh jobs exit 0 at load 1, **169.5 seconds wall**
  including preparation. Process wall seconds **69.93 -> 70.19**, peak RSS
  **991.3 -> 993.0 MB**. Regression and false-flag lists are empty. Command:
  `BENCH_TIMING_FULL=1 compare.sh master <worktree> --full --only
  'scale l spq4 s1' --retime`. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/77cce1fa_vs_05c7a6ad-d5c78ae15_full-scale_l_spq4_s1-retime-20261031T042844/report.md`;
  log `scratch/scale-paired-retime.log`. This clears the full comparison's
  local false flag without changing a threshold.
- Additional fresh paired dev-server retime of **conflict pln-reliable l
  spq4 s1**: **PASS**, identical accuracy, both fresh jobs exit 0 at load 1,
  **195.8 seconds wall**. Process wall seconds **68.68 -> 68.74**, peak RSS
  **323.5 -> 324.5 MB**. The local full comparison's **68.27 -> 84.72**
  inference seconds had mismatched loads and was not a valid timing flag;
  this pair resolves that adverse sample too. Command uses the same supplied
  full/only/retime runner and `BENCH_TIMING_FULL=1`. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/77cce1fa_vs_05c7a6ad-d4334afc0_full-conflict_pln-reliable_l_spq4_s1-retime-20261031T043045/report.md`;
  log `scratch/conflict-paired-retime.log`. No regression or false flag remains.
  Both retime labels capture report-only edits and record runtime tree
  **6ff8d0d26c24**, identical to code commit **05c7a6ad**.

The runner makes `--full` and `--curves` mutually exclusive; the brief's combined
notation was executed as these two separate required comparisons. The report
checkpoint was committed before final verification. Report-only updates retain
that verification key; all source, test, runtime and benchmark inputs are fixed.

## Hand-back and limits

The branch is ready for coordinator review. Every required gate passes, every
full/canary comparison against actual master has identical answers, and all 40
curve budget points have identical measured errors. No old expected value or
EXPECTED_FAILURES entry changes. The native clause audit preserves all indexing
and numerical implementations. No timing or memory regression remains after
fresh paired dev-server checks, and no noisy local time is claimed as a speedup.

The largest measured file SCC shrinks **46 -> 20**; owners have zero upward
paths under the retained graph rules. The remaining **20- and 18-file SCCs**
and the explicit callback/read boundaries are real limits: this is not a global
DAG or proof that arbitrary dynamic user calls cannot recurse. The supplied
static graph does not measure generated predicates, store accesses or runtime
frequency. Application binding still projects the compiler's existing compact
completion recipe at the policy boundary; it does not delete that compiled
route or claim a new numerical model. The original fold boundary remains for
pinned compiler semantics. Later route deletion needs its own semantic coverage.

Implementation **05c7a6ad** contains the design, five new tests, measurement tools
and the pre-verification report. This final update changes the report only.
Every commit has the exact requested Co-Authored-By and Claude-Session trailers.
All processes started for this task have finished; the read-only process audit
is `scratch/processes-final.json`. No push, merge, GitHub write, main-checkout
code edit or other-worktree edit was performed. The prescribed runner outputs
and authorized verification-cache write are the shared artifacts.
