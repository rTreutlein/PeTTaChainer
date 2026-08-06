# MM2 Follow-up Candidates

This note records optimization and caching ideas found in the committed history
of the sibling `mm2-chainer` checkout. It is a handoff list, not a request to
copy the native Rust implementation into PeTTaChainer. The comparison was made
on 2026-08-06 against PeTTaChainer `5052580` and committed MM2 history through
`a97a10b`. Uncommitted files in the sibling checkout were not treated as
designs or evidence.

## Status summary

| MM2 change | PeTTaChainer status | Follow-up |
| --- | --- | --- |
| `1a397fc` cache empty Member-inheritance folds | Adopted by `5052580`, then simplified to one mutable best-budget optimization row per identity | Keep the focused regression and add a larger controlled benchmark when this path is revisited |
| `7e80b80` make Member-cache updates population independent | The current forward cache is already object-keyed and updates sufficient statistics by affected object | Benchmark update cost as population size grows; remove any remaining list-shaped or broad interest scans only when the profile identifies them |
| `21d1e70` batch forward seed deltas | Already present in structure: `forward-chain` builds one deduplicated heap for all supplied seeds and processes their closure together | Retain; add a scaling benchmark if a real workload shows batch overhead |
| `dc95ec1` incremental forward base-rate caches | PeTTaChainer is the semantic source of this design; `2f45e50` fixed preservation of a complete computed snapshot across partial forward deltas | No port. Preserve the existing computed/forward-approx distinction |
| `9cfa68b` compiler and incremental cache alignment | Primarily an MM2 parity port from PeTTaChainer | No reverse port; compare individual behavior only when a regression demonstrates a gap |
| `2df2a80` bounded FoldAll proof fanout | Solves MORK's compact-expression arity limit | Not directly applicable. Consider balanced proof trees only if PeTTa profiling shows large flat proof terms are costly |
| `cd72100`, `814911e`, `f20107d` guided lazy backward refinement | Not currently exposed as an equivalent query policy | Candidate after cache-update scaling: refine cached subgoals within an explicit budget while retaining incumbent proofs |
| `003dcec`, `236bf06`, `1c7ca31` bounded/fused native scheduling | Implemented in MORK/MM2 scheduler primitives rather than the MeTTa chainer | Do not translate mechanically. Reassess only through a profile of the PeTTa/SWI execution path or a dependency upgrade |
| `a97a10b` registered native Compute/FoldAll extensions | PeTTaChainer already dispatches `CPU` through `cpu-call`, including MeTTa-defined functions, and now has restricted reversible-Compute declarations | No general registry port. A native fast path remains optional for a measured expensive operator |

## Recommended next experiments

### 1. Prove population-independent incremental cache maintenance

The next useful cache experiment is not another semantic rewrite. Measure one
new or refined `Member` fact against increasing unrelated population sizes and
increasing numbers of registered inheritance interests. Separate:

- knowledge insertion;
- selective forward maintenance;
- the first cached read;
- repeated cached reads.

The intended result is work proportional to the affected object's proofs and
matching indexed interests, not to the full Member population. If the result
scales with population size, profile the exact `match` or list operation before
changing storage. This is the closest PeTTaChainer analogue of MM2 `7e80b80`.

The weighted-subset posterior DP is a separate problem. Its current eager
prefix/postfix construction and list-based DP cell lookup should receive its
own benchmark and data-structure work; the Member-inheritance cache does not
make that computation incremental automatically.

### 2. Add opt-in cached-proof refinement

MM2's refinement experiment keeps the incumbent answer available while a
bounded query explores independent alternatives. A PeTTaChainer version should
reuse the normal goal scheduler and proof store, and should make refinement a
query policy rather than a new inference engine. Its identity must include at
least the KB, goal, evidence policy, and search budget. Deterministic exploration
needs an explicit seed if sampling is introduced.

This fits append-only semantics only if refinement adds proof support. It must
not retract an incumbent proof or mutate historical evidence merely because a
new representative answer is stronger.

### 3. Consider a batch-query API only for demonstrated workloads

MM2 has a specialized `query_many` path that amortizes setup and handles cached
empty Member folds without repeating broad fallback scans. PeTTaChainer already
shares state inside one query and can express batches at the MeTTa level, so a
new public API is not automatically beneficial. Add one only after a benchmark
shows repeated host/query-arena setup is material.

## Append-only constraints for all ports

- Knowledge, proofs, and evidence are historical facts and must only be added.
- A cache row is a derived materialized view, not part of logical history. It
  may be replaced or discarded when doing so changes only performance.
- Later knowledge refines an applicable cached result through selective
  contribution updates. It does not invalidate an older approximation merely
  because the KB grew.
- Budget-limited failure is not logical falsity. A result learned at a larger
  budget may subsume smaller-budget work, but not the reverse.
- Administrative removal and cache-clear APIs remain legacy escape hatches.
  New reasoning or ingestion features must not depend on them.

## Validation rule

Before adopting an MM2 optimization, compare serialized inputs, rule inventory,
proof/evidence components, final truth values, and step budgets. A faster result
with different proof semantics is not a successful port.
