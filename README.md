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

## Python API: Language Spec String

```python
from pettachainer import get_language_spec

llm_spec = get_language_spec(llm_focused=True)
full_spec = get_language_spec(llm_focused=False)
```

## Python API: Shared PLN Validator

```python
from pettachainer import check_query, check_stmt

check_stmt("(: s1 (Dog fido) (STV 1.0 1.0))")
check_stmt("!(compileadd kb (: s2 (HeightDist g1 alice) (PointMass 170.0)))")
check_query("!(query 20 kb (: $prf (Dog fido) $tv))")
```
