Install the project and its commit-locked PeTTa dependency with uv:

```bash
uv sync --frozen
scripts/test_metta.sh
```

Run an individual MeTTa regression from the repository root with:

```bash
.venv/bin/petta tests/metta/test_var_head.metta -s
```

The shipped MeTTa runtime lives in `pettachainer/metta`. Its stable facade is
`petta_chainer.metta`; `bootstrap.metta` loads the internal `core/`, `compiler/`,
and `runtime/` layers plus the vendored libraries in `third_party/` in their
required order. Tests, examples, benchmarks, documentation, and tools live in
their corresponding top-level directories. See
`docs/metta/module_dependencies.md` for module ownership and dependency rules.

`PeTTaChainer()` and the MeTTa suite load this runtime through PeTTa's cached
load: the first process compiles it (about 5 s) and stores a snapshot of the
result; later processes replay that snapshot (about 1 s). The snapshot is
replaced whenever a loaded `.metta` or `.pl` file, its directory listing or
PeTTa itself changes. Snapshots live in `$PETTA_LOAD_CACHE`, or else in
`~/.cache/petta/loads`.

The MeTTa API can also be loaded directly from a pinned Git checkout when
running under PeTTa:

```metta
!(import! &self (library lib_import))
!(git-import!
   "https://github.com/rTreutlein/PeTTaChainer.git"
   ""
   "./repos"
   "<FULL_PETTACHAINER_COMMIT_SHA>")
!(import! &self (library PeTTaChainer lib_pettachainer))
```

In this mode PeTTa is the host runtime, so it must already be installed. The
Python API still requires installing the `PeTTaChainer` package.

## Benchmarks

Run the NatDist vs ParticleDist benchmark:

```bash
python pettachainer/benchmarks/particle_vs_nat.py --sizes 100,500,1000 --particle-budgets 128,256,512 --repeats 2
```

Run the simple forward vs backward chaining benchmark:

```bash
.venv/bin/python pettachainer/benchmarks/forward_vs_backward.py --depths 10,25,50 --noise-branching 8 --repeats 3
```

Run the backward materialization benchmark:

```bash
.venv/bin/python pettachainer/benchmarks/backward_materialize.py --depths 5,10 --queries 200 --repeats 3
```

Run the bounded priority queue benchmark:

```bash
.venv/bin/python pettachainer/benchmarks/bounded_queue.py --fanouts 2000,8000 --steps 100 --repeats 3
```

Add `--compare-pruning` to compare pruning enabled and disabled within the same checkout.

Run the core performance checks used for runtime refactoring reviews:

```bash
.venv/bin/python pettachainer/benchmarks/core_suite.py \
  --json-out /tmp/pettachainer-baseline.json
```

The suite covers bounded backward and forward agendas, fixed-budget evolving
queries with retained durable proofs, incremental Member-to-Inheritance
maintenance, and a 1000-object forward-populated inheritance query. Each
repetition runs in a fresh process so native runtime state cannot leak between
measurements. Compare a later checkout with the saved baseline using:

```bash
.venv/bin/python pettachainer/benchmarks/core_suite.py \
  --baseline-json /tmp/pettachainer-baseline.json \
  --json-out /tmp/pettachainer-current.json
```

The in-repository durable-query workload is a small proxy for the retained-proof
behavior exercised by StationOps. The complete StationOps benchmark remains an
external acceptance workload because it depends on the sibling ChainerGame
repository. Compare its timing only when the per-shift answers and coverage are
the same.

Run the full ConceptNet `Own ∧ Pet` query benchmark:

```bash
./benchmarks/metta/run_conceptnet_own_pet_query.sh
```

The runner discovers a sibling `cnet` checkout automatically. Set `CNET_DIR`
for a different location. If `dumppln.txt` changed or the expected proof is
missing, rerun with `CNET_REFRESH=1` to regenerate and compile `rules_dump`.

Optional JSON export:

```bash
python pettachainer/benchmarks/particle_vs_nat.py --json-out /tmp/particle_bench.json
```

## Profiling MeTTa Runs

Profile a `.metta` file through the underlying SWI-Prolog invocation that `petta` uses:

```bash
./scripts/profile_petta.sh tests/metta/test_best_first_runtime.metta
./scripts/profile_petta.sh --mode time tests/metta/test_best_first_runtime.metta
./scripts/profile_petta.sh --mode perf benchmarks/metta/demo_benchgen_compare_tuffy.metta
```

Relative paths are resolved from the repository root by default.

## Python API: Language Spec String

```python
from pettachainer import get_language_spec

llm_spec = get_language_spec(llm_focused=True)
full_spec = get_language_spec(llm_focused=False)
```

## Python API: Shared PLN Validator

```python
from pettachainer import PeTTaChainer, check_query, check_stmt

handler = PeTTaChainer()

stmt_eval = handler.evaluate_statement("(: s1 (Dog fido) (STV 1.0 1.0))")
check_stmt(stmt_eval)

query_eval = handler.evaluate_query("(: $prf (Dog fido) $tv)")
check_query(query_eval)
```

## Python API: Multi-root Queries

```python
from pettachainer import PeTTaChainer

handler = PeTTaChainer()
handler.add_atom("(: a (A) (STV 1.0 1.0))")
handler.add_atom("(: b (B) (STV 0.8 0.9))")

results = handler.query_many(
    ["(: $prf (A) $tv)", "(: $prf (B) $tv)"],
    steps=10,
)
# results[0] contains answers for A; results[1] contains answers for B.
# The roots share one search arena and one total step budget.

# Use query_many_materialization to retain grounded rule-derived facts from
# each selected proof tree, including intermediate facts, in the live KB.
cached_results = handler.query_many_materialization(
    ["(: $prf (A) $tv)", "(: $prf (B) $tv)"],
    steps=10,
)
```

### Backward-query diagnostics

Set `PETTACHAINER_QUERY_METRICS_PATH` to append one JSON object per live
`query` or `query_many` call. The counters cover durable proof rows, agenda
operations, demand-cache work, proof-liveness checks, candidate comparisons,
and stored proofs. Diagnostics only cover queries run with `timeout_sec=0`;
timed queries run in an isolated subprocess, so they are skipped with a
warning instead of being recorded.

Metrics can also be enabled programmatically with
`handler.set_query_metrics(True)` and read after a query with
`handler.last_query_metrics()`.

## Python API: Forward Chaining

```python
from pettachainer import PeTTaChainer

handler = PeTTaChainer()
handler.add_atom("(: edge_ab (Edge A B) (STV 1.0 1.0))")
handler.add_atom("(: edge_bc (Edge B C) (STV 1.0 1.0))")
handler.add_atom(
    "(: edge_to_path (Implication (Edge $x $y) (Path $x $y)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
)
handler.add_atom(
    "(: path_step (Implication (And (Path $x $y) (Edge $y $z)) (Path $x $z)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
)

seeds = handler.select_facts(["(Edge A B)", "(Edge B C)"])
changed = handler.forward_chain(seeds, steps=50)
result = handler.query("(: $prf (Path A C) $tv)", timeout_sec=0)

# Returned facts directly seed a later run. Selecting the whole KB is the
# full-saturation special case: handler.forward_chain(handler.all_facts()).
handler.forward_chain(changed, steps=1)
```
