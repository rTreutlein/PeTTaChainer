# Benchmark Notes

`particle_vs_nat.py` benchmarks direct distribution folding and threshold probability evaluation.

It compares:

- `NatDist`: exact fold via `NatDistAddBernoulliFromSTV`
- `ParticleDist`: approximate fold via `ParticleAddBernoulliFromSTV`

Both modes evaluate:

```metta
(DistGreaterThanFormula (fold-flat ... ) threshold)
```

`forward_backward_compare.py` benchmarks three inference workflows on the same synthetic chain KB:

- `forward`: run `forward-chain` and test if target was derived
- `forward_then_backward`: run `forward-chain` then run a backward `query`
- `backward`: run only backward `query`

## Run

```bash
python pettachainer/benchmarks/particle_vs_nat.py --sizes 100,500,1000 --particle-budgets 128,256,512 --repeats 2
```

```bash
python pettachainer/benchmarks/forward_backward_compare.py --chain-len 10 --noise-chains 10 --noise-chain-len 2 --repeats 3
```

### Forward/Backward Output Columns

- `mode`: one of `forward`, `forward_then_backward`, `backward`
- `mean_s`: mean runtime over repeats
- `median_s`: median runtime over repeats
- `min_s`: fastest run
- `max_s`: slowest run
- `success_rate`: fraction of successful runs (target proved)

## Output Columns

- `n`: number of Bernoulli updates folded into the distribution
- `budget`: particle budget (`ParticleSetBudget`) used for the particle run
- `nat_eval_s`: mean NatDist evaluation time
- `particle_eval_s`: mean ParticleDist evaluation time
- `speedup_nat_over_particle`: `nat_eval_s / particle_eval_s` (>1 means particle is faster)
- `nat_strength`: exact threshold probability
- `particle_strength`: approximated threshold probability
- `abs_err`: absolute difference between strengths
- `nat_conf`: NatDist confidence (currently 1.0)
- `particle_conf`: particle confidence from `N_eff / (N_eff + 20)`
- `particle_atoms`: number of stored particle atoms after evaluation

## Metta Tuffy Deep Variant

Run the deep-proof-tree tunable benchmark variant in-place:

```bash
python pettachainer/metta/benchmarks/bench_tuffy_scale.py --pairs 4,8 --runs 2 --variant deep-proof-tree --deep-depth 4 --deep-branching 2
```
