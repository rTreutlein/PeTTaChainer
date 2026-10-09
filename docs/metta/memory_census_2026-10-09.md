# Where SupplyNet scale memory goes (October 2026)

Second round after [evidence_sets.md](evidence_sets.md) and the 4,096-bit
dependency masks ([dependency_tracking_design.md](dependency_tracking_design.md)).
Measured on SupplyNet scale, seed 1, master b873bdbc, by a probe that logs SWI
`statistics/2` and `mallinfo2` after every `query_many` and, at exit, every
dynamic predicate's clauses, bytes (`predicate_property(_, size(_))`) and
subterm classes.

## Census

| | m/4 | l/4 | xl/8 |
|---|---|---|---|
| peak RSS | 1,141 MB | 1,422 MB | 5,311 MB |
| Prolog stacks allocated | 537 MB | 940 MB | 3,758 MB |
| malloc in use (clauses, atoms, indexes) | 350 MB | 582 MB | 2,019 MB |
| dynamic predicates (`size`) | 283 MB | 449 MB | 1,561 MB |
| of which compiler and checker tables (fixed) | ~70 MB | ~70 MB | ~70 MB |
| erased clauses reclaimed by `garbage_collect_clauses` at exit | 24 MB | 0 MB | 0 MB |
| malloc free (fragmentation), last query | 28 MB | 5 MB | 20 MB |

Largest stores at xl/8: `&sk_wait` 261 MB (63,726 rows, 513 cells a row),
`&sk_row` 185 MB (387 cells), `ev_set` 160 MB, `&kb_prefix` 102 MB, `deps_node`
96 MB, `ev_entry` 52 MB, `&sk_child` 49 MB, `&kb` 44 MB, `&sk_stale_reader`
42 MB, `&proof` 37 MB, `deps_interned` 32 MB, `&sk_link` 30 MB. The 2026-10-02
finding that `&sk_link` join records were 70% of memory no longer holds: links
are digests since forgetting stage 0. Repeated terms: the KB context
`[kb…, 'MAIN', 'Nil']` occurs 1.6 million times at xl/8 (about 116 MB of
clause code), `sk-key` terms 359,000 times over 38,200 distinct keys (about
78 MB).

So the stores are a third of RSS. The rest is the Prolog stacks, and they are
not live data: at m/4 a query never holds more than 52 MB after a garbage
collection (`trace_gc`). SWI collects only when an area is full and grows it
when what survives is large, so every page of the area is touched and stays
resident; the area is sized by the largest live moment of any query, which
is one of:

- **Open choice points.** When a query's answers are presented, 23,000 to
  46,000 choice points are open at m/4, each keeping its frames and the terms
  they reach from collection. PeTTa compiles every function as a dynamic
  predicate whose first argument is the function passed to a library fold;
  SWI's clause selection for dynamic code looks at that argument only, so
  `fold-flat`, `foldr-flat`, `map-flat`, `fold-nested` and `foreach-flat`
  leave a choice point each time they reach `()`. The static two-clause
  `[]`/`[_|_]` special case does not apply to dynamic code. A det function
  commits to its clause (PeTTa's `clause_commit_cut`) but not to what its body
  leaves open.
- **Printing answers.** PeTTa's `swrite/2` renders each result through a code
  list (24 bytes a character) with one choice point per printed list. A query
  at m/4 returns 3.2 MB of text (66 answers, proofs as DAGs), about 220 MB of
  stack while it prints.

`trim_stacks` after each query returns the area between queries but not the
peak, and costs 17% time (each query regrows it).

## What changed

- **Partial joins hold each premise once.** `(sk-partial owner rule concl
  done remaining keys)`: the premises taken, most recent first, apart from the
  ones left. The former shape kept the whole premise list beside the
  remaining suffix; a stored clause copies both. `&sk_wait` at m/4: 506 → 322
  cells a row, 31.9 → 20.7 MB.
- **One clause per interned item.** `deps_node(Id, Key, Children, Mask)`,
  `deps_leaf(Id, Hash)`, `ev_set(Id, Hash, Ordered, Sorted, Excluded)`,
  `ev_entry(Id, Hash, Entry)`: found by id or by hash in one clause, where
  each was two (`deps_interned`, `deps_leaf_hash`, `ev_set_key`,
  `ev_entry_key`). m/4: these tables 79 → 51 MB.
- **Support checks by mask first.** `deps-within?` answered whether a new
  view brings a key its row lacks by collecting the support's closure; 97% of
  calls are decided by a mask bit the support lacks.
- **Det walks where the library folds left choice points.** `extract-vars`
  (in every join step) walks with its own det function; the settling test
  scans premises with a det function. Open choice points at presentation,
  m/4: 42,000 → 23,700; GC 5.6 → 4.8 s a run.

Scale sweep, seed 1, one run each, master d0be7108 against the four changes
(answers identical in every cell; `compare.sh --full`: accuracy identical in
all 73 cases and every StationOps replay stream identical):

| size/spq | ms/query before → after | peak MB before → after |
|---|---|---|
| s/1 | 14.0 → 13.9 | 184 → 182 |
| s/4 | 29.8 → 27.6 | 191 → 201 |
| s/8 | 49.8 → 48.0 | 312 → 302 |
| m/1 | 27.7 → 26.5 | 674 → 658 |
| m/4 | 50.7 → 42.5 | 1,088 → 1,064 |
| m/8 | 60.8 → 57.9 | 983 → 974 |
| l/1 | 11.8 → 11.4 | 790 → 790 |
| l/4 | 39.0 → 36.9 | 1,383 → 1,345 |
| l/8 | 50.1 → 47.6 | 1,522 → 1,472 |
| xl/4 | 82.6 → 76.9 | 4,768 → 4,644 |
| xl/8 | 108.0 → 97.2 | 5,086 → 4,943 |

Peak memory moves little: the stores shrank, but the stacks set the peak.

## Not changed, and why

- **Interning keys or the KB context as ids.** Worth about 190 MB at xl/8 (12%
  of the stores, 4% of RSS), but it changes the shape every skeleton and
  evaluation reader destructures; the stack is the larger lever.
- **`&kb_prefix` rows referring to `&kb` rows.** Each prefix row copies the
  fact (102 MB at xl/8); a reference needs a fact id in `&kb`, which every
  `&kb` reader matches.
- **Evidence sets as union trees** (parent set plus the entries it adds):
  `ev_set` is 160 MB at xl/8, but set tests would rebuild sorted lists along
  a chain on every call.
- **Clause churn.** Erased clauses not yet reclaimed are 0–24 MB and malloc
  fragmentation 5–28 MB; neither is where the memory is.

## In PeTTa

Both stack drivers are in PeTTa, and both were measured as probes that leave
results byte-identical (all 710 printed results of an m/4 run, after
normalizing KB ids and variable names):

| m/4 | peak | stack | ms/query |
|---|---|---|---|
| as is | 1,079 MB | 537 MB | 41.6 |
| function predicates made static after loading | 775 MB | 470 MB | 39.4 |
| static, and `swrite/2` writing to a string stream | 504 MB | 102 MB | 37.1 |

Static predicates stand in for a translator change: committing a det
function's calls to effect-polymorphic folds, or compiling fold
specializations with a det step as det. The printer change writes with
`with_output_to/2` and `format/2`, deterministically.
