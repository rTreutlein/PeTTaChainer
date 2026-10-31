# Structure step 7: application discovery and a smaller global cycle

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct7`.
Branch: `struct7`; actual base: **77cce1fa971ddb8aab5fe0da5de3add55c95a185**.
This implementation/report checkpoint precedes final acceptance. The final
verification, full comparison, curves and canary results are recorded below
when finished; this checkpoint alone is not a completed hand-back.

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
- Final standalone Python suite: **pending**.
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **pending**.
- `compare.sh master <worktree> --full`: **pending**.
- `compare.sh master <worktree> --curves`: **pending**.
- `compare.sh anchor <worktree> --canary`: **pending**.
- Fresh paired dev-server retimes for flagged cases: **pending if flagged**.

The runner makes `--full` and `--curves` mutually exclusive; the brief's combined
notation is executed as these two separate required comparisons. The report is
committed before final verification. Final results, commit ids, exact benchmark
paths and process cleanup status are added after all required gates finish.
