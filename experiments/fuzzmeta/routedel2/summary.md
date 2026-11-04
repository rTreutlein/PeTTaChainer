# Event differential + metamorphic fuzzing

```json
{
  "seconds": 162.84,
  "mode": "quick",
  "target": "/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295",
  "runtime_paths": [
    "/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295/pettachainer/__init__.py"
  ],
  "runtime_commits": {
    "/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295/pettachainer/__init__.py": "3a990295e5eace9c735911d501440b4a15fc09c9"
  },
  "fuzzer_sha256": "8e7d97cd23a4dca9fe1e88938cadb17110e141a2c3015f2835c902d06e8093ef",
  "inputs_changed": false,
  "seed": 1,
  "cases": 19,
  "worker_runs": 187,
  "violations": {
    "BLOCKER:wrong_strength": 8,
    "BLOCKER:overconfident_error": 4,
    "BLOCKER:overconfident_variance": 8,
    "BLOCKER:neutral": 2,
    "BLOCKER:flip": 3,
    "BLOCKER:inactive": 4,
    "BLOCKER:frechet": 1,
    "BLOCKER:false": 2,
    "BLOCKER:class-rule": 4,
    "BLOCKER:bounded_work": 1
  },
  "problog_cases": 3,
  "problog_flagged": 0,
  "settings": {
    "budgets": [
      100,
      500
    ],
    "k": 800,
    "threshold": 0.001,
    "timeout": 45
  },
  "under_ten_minutes": true
}
```

| case | severity | invariant | expected | actual | repro |
|---|---|---|---|---|---|
| neutral-1 | BLOCKER | wrong_strength | 0.8912891216043767 | 0.9999999999997257 | [repro](repros/neutral-1-0-wrong_strength.json) |
| neutral-1 | BLOCKER | overconfident_error | 0.8912891216043767 | 0.9999999999997257 | [repro](repros/neutral-1-1-overconfident_error.json) |
| neutral-1 | BLOCKER | overconfident_variance | 0.007072119804824868 | 1.5231051979206562e-13 | [repro](repros/neutral-1-2-overconfident_variance.json) |
| neutral-1 | BLOCKER | wrong_strength | 0.9347284013035543 | 0.9877900084672666 | [repro](repros/neutral-1-3-wrong_strength.json) |
| neutral-1 | BLOCKER | overconfident_error | 0.9347284013035543 | 0.9877900084672666 | [repro](repros/neutral-1-4-overconfident_error.json) |
| neutral-1 | BLOCKER | overconfident_variance | 0.0016848622484831764 | 6.52753783658328e-14 | [repro](repros/neutral-1-5-overconfident_variance.json) |
| neutral-1 | BLOCKER | neutral | same strength and answer availability | [0.8912891216043766, 0.9999999999997257] | [repro](repros/neutral-1-6-neutral.json) |
| neutral-1 | BLOCKER | neutral | same strength and answer availability | [0.9347284013035543, 0.9877900084672666] | [repro](repros/neutral-1-7-neutral.json) |
| leaf-report-And-1 | BLOCKER | flip | observation flip changes strength down | [0.4, 0.4] | [repro](repros/leaf-report-And-1-0-flip.json) |
| leaf-report-Or-1 | BLOCKER | flip | observation flip changes strength down | [0.4, 0.4] | [repro](repros/leaf-report-Or-1-0-flip.json) |
| leaf-report-Not-1 | BLOCKER | flip | observation flip changes strength up | [0.4, 0.4] | [repro](repros/leaf-report-Not-1-0-flip.json) |
| base-STV-1 | BLOCKER | wrong_strength | 0.9598430255509199 | 0.9761764813930421 | [repro](repros/base-STV-1-0-wrong_strength.json) |
| base-STV-1 | BLOCKER | wrong_strength | 0.968189452988939 | 0.9761617868557364 | [repro](repros/base-STV-1-1-wrong_strength.json) |
| base-STV-1 | BLOCKER | inactive | same strength and answer availability | [0.9761764813930421, 0.9598430255509199] | [repro](repros/base-STV-1-2-inactive.json) |
| base-STV-1 | BLOCKER | inactive | same strength and answer availability | [0.9761617868557364, 0.9681894529889391] | [repro](repros/base-STV-1-3-inactive.json) |
| base-FTV-1 | BLOCKER | wrong_strength | 0.9598430255509199 | 0.9761764813930421 | [repro](repros/base-FTV-1-0-wrong_strength.json) |
| base-FTV-1 | BLOCKER | wrong_strength | 0.968189452988939 | 0.9761617868557364 | [repro](repros/base-FTV-1-1-wrong_strength.json) |
| base-FTV-1 | BLOCKER | inactive | same strength and answer availability | [0.9761764813930421, 0.9598430255509199] | [repro](repros/base-FTV-1-2-inactive.json) |
| base-FTV-1 | BLOCKER | inactive | same strength and answer availability | [0.9761617868557364, 0.9681894529889391] | [repro](repros/base-FTV-1-3-inactive.json) |
| origins-2-1 | BLOCKER | overconfident_variance | 0.0011481893109923542 | 0.0006651419832442668 | [repro](repros/origins-2-1-0-overconfident_variance.json) |
| origins-2-1 | BLOCKER | overconfident_variance | 0.0011481893109923542 | 0.0006651419832442668 | [repro](repros/origins-2-1-1-overconfident_variance.json) |
| origins-3-1 | BLOCKER | overconfident_variance | 0.00019782921157670213 | 0.00012297030868252637 | [repro](repros/origins-3-1-0-overconfident_variance.json) |
| origins-3-1 | BLOCKER | overconfident_variance | 0.00019782921157670213 | 0.00012297030868252637 | [repro](repros/origins-3-1-1-overconfident_variance.json) |
| origins-7-1 | BLOCKER | overconfident_variance | 2.815018505205952e-06 | 1.8899067876528958e-06 | [repro](repros/origins-7-1-0-overconfident_variance.json) |
| origins-7-1 | BLOCKER | overconfident_variance | 2.815018505205952e-06 | 1.8899067876528958e-06 | [repro](repros/origins-7-1-1-overconfident_variance.json) |
| origins-8-1 | BLOCKER | wrong_strength | 0.99928486125568 | 0.7885474013232553 | [repro](repros/origins-8-1-0-wrong_strength.json) |
| origins-8-1 | BLOCKER | overconfident_error | 0.99928486125568 | 0.7885474013232553 | [repro](repros/origins-8-1-1-overconfident_error.json) |
| origins-8-1 | BLOCKER | wrong_strength | 0.99928486125568 | 0.7885474013232553 | [repro](repros/origins-8-1-2-wrong_strength.json) |
| origins-8-1 | BLOCKER | overconfident_error | 0.99928486125568 | 0.7885474013232553 | [repro](repros/origins-8-1-3-overconfident_error.json) |
| origins-8-1 | BLOCKER | frechet | [0.5770948026465106, 0.7885474013232553] | 0.9989261166352451 | [repro](repros/origins-8-1-4-frechet.json) |
| identity-ground-1 | BLOCKER | false | 0 | [1.0, 0.0562265722615577] | [repro](repros/identity-ground-1-0-false.json) |
| identity-exists-1 | BLOCKER | false | 0 | [1.0, 0.0562265722615577] | [repro](repros/identity-exists-1-0-false.json) |
| class-links-False-1 | BLOCKER | class-rule | inactive derived link preserves an existing classification | [1.0, None] | [repro](repros/class-links-False-1-0-class-rule.json) |
| class-links-False-1 | BLOCKER | class-rule | inactive derived link preserves an existing classification | [1.0, None] | [repro](repros/class-links-False-1-1-class-rule.json) |
| class-links-True-1 | BLOCKER | class-rule | inactive derived link preserves an existing classification | [1.0, None] | [repro](repros/class-links-True-1-0-class-rule.json) |
| class-links-True-1 | BLOCKER | class-rule | inactive derived link preserves an existing classification | [1.0, None] | [repro](repros/class-links-True-1-1-class-rule.json) |
| producer-cost-1 | BLOCKER | bounded_work | doubling producers must not repeatedly quadruple catalog work | [{'n': 64, 'inferences': 11065, 'seconds': 0.0005439459999999988}, {'n': 128, 'inferences': 38457, 'seconds': 0.002998409666666646}, {'n': 256, 'inferences': 142393, 'seconds': 0.010763483666666573}, {'n': 512, 'inferences': 546873, 'seconds': 0.03102620099999953}] | [repro](repros/producer-cost-1-0-bounded_work.json) |
