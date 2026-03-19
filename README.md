To install, clone this repo and its dependency into the same directory:

```bash
git clone https://github.com/patham9/PeTTa.git
git clone https://github.com/rTreutlein/PeTTaChainer.git
```

## Benchmarks

Run the NatDist vs ParticleDist benchmark:

```bash
python pettachainer/benchmarks/particle_vs_nat.py --sizes 100,500,1000 --particle-budgets 128,256,512 --repeats 2
```

Optional JSON export:

```bash
python pettachainer/benchmarks/particle_vs_nat.py --json-out /tmp/particle_bench.json
```

## Profiling MeTTa Runs

Profile a `.metta` file through the underlying SWI-Prolog invocation that `petta` uses:

```bash
./profile_petta.sh tests/testmining.metta
./profile_petta.sh --mode time tests/testmining.metta
./profile_petta.sh --mode perf benchmarks/demo_benchgen_forward_backward_compare.metta
```

Relative paths are resolved from `pettachainer/metta` by default.

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
