# Event differential + metamorphic fuzzing

```json
{
  "seconds": 71.08,
  "mode": "quick",
  "target": "/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/.venv/bin/python",
  "runtime_paths": [
    "/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/__init__.py"
  ],
  "runtime_commits": {
    "/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/__init__.py": "b694e193387e5ef5d651eaefd863690f4f150319"
  },
  "fuzzer_sha256": "8e7d97cd23a4dca9fe1e88938cadb17110e141a2c3015f2835c902d06e8093ef",
  "inputs_changed": false,
  "seed": 1,
  "cases": 19,
  "worker_runs": 224,
  "violations": {
    "BLOCKER:wrong_strength": 18,
    "BLOCKER:overconfident_variance": 2,
    "BLOCKER:overconfident_error": 5,
    "BLOCKER:neutral": 2,
    "BLOCKER:flip": 3,
    "BLOCKER:inactive": 4,
    "BLOCKER:repeat": 7,
    "BLOCKER:frechet": 4,
    "BLOCKER:false": 2
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
| neutral-1 | BLOCKER | wrong_strength | 0.8912891216043767 | 0.9762111390395556 | [repro](repros/neutral-1-0-wrong_strength.json) |
| neutral-1 | BLOCKER | overconfident_variance | 0.007072119804824868 | 0.0033299342881502854 | [repro](repros/neutral-1-1-overconfident_variance.json) |
| neutral-1 | BLOCKER | wrong_strength | 0.9347284013035543 | 0.9878048780487805 | [repro](repros/neutral-1-2-wrong_strength.json) |
| neutral-1 | BLOCKER | overconfident_error | 0.9347284013035543 | 0.9878048780487805 | [repro](repros/neutral-1-3-overconfident_error.json) |
| neutral-1 | BLOCKER | overconfident_variance | 0.0016848622484831764 | 2.3040911801419533e-07 | [repro](repros/neutral-1-4-overconfident_variance.json) |
| neutral-1 | BLOCKER | neutral | same strength and answer availability | [0.8912891216043766, 0.9762111390395556] | [repro](repros/neutral-1-5-neutral.json) |
| neutral-1 | BLOCKER | neutral | same strength and answer availability | [0.9347284013035544, 0.9878048780487805] | [repro](repros/neutral-1-6-neutral.json) |
| leaf-report-And-1 | BLOCKER | flip | observation flip changes strength down | [0.4, 0.4] | [repro](repros/leaf-report-And-1-0-flip.json) |
| leaf-report-Or-1 | BLOCKER | flip | observation flip changes strength down | [0.4, 0.4] | [repro](repros/leaf-report-Or-1-0-flip.json) |
| leaf-report-Not-1 | BLOCKER | flip | observation flip changes strength up | [0.4, 0.4] | [repro](repros/leaf-report-Not-1-0-flip.json) |
| base-STV-1 | BLOCKER | wrong_strength | 0.9598430255509199 | 0.9797376479439993 | [repro](repros/base-STV-1-0-wrong_strength.json) |
| base-STV-1 | BLOCKER | wrong_strength | 0.968189452988939 | 0.9744685694201395 | [repro](repros/base-STV-1-1-wrong_strength.json) |
| base-STV-1 | BLOCKER | wrong_strength | 0.9598430255509199 | 0.9771459198487928 | [repro](repros/base-STV-1-2-wrong_strength.json) |
| base-STV-1 | BLOCKER | wrong_strength | 0.968189452988939 | 0.972609500798931 | [repro](repros/base-STV-1-3-wrong_strength.json) |
| base-STV-1 | BLOCKER | inactive | same strength and answer availability | [0.9797376479439993, 0.9771459198487928] | [repro](repros/base-STV-1-4-inactive.json) |
| base-STV-1 | BLOCKER | inactive | same strength and answer availability | [0.9744685694201395, 0.972609500798931] | [repro](repros/base-STV-1-5-inactive.json) |
| base-FTV-1 | BLOCKER | wrong_strength | 0.9598430255509199 | 0.9797376479439993 | [repro](repros/base-FTV-1-0-wrong_strength.json) |
| base-FTV-1 | BLOCKER | wrong_strength | 0.968189452988939 | 0.9744685694201395 | [repro](repros/base-FTV-1-1-wrong_strength.json) |
| base-FTV-1 | BLOCKER | wrong_strength | 0.9598430255509199 | 0.9771459198487928 | [repro](repros/base-FTV-1-2-wrong_strength.json) |
| base-FTV-1 | BLOCKER | wrong_strength | 0.968189452988939 | 0.972609500798931 | [repro](repros/base-FTV-1-3-wrong_strength.json) |
| base-FTV-1 | BLOCKER | inactive | same strength and answer availability | [0.9797376479439993, 0.9771459198487928] | [repro](repros/base-FTV-1-4-inactive.json) |
| base-FTV-1 | BLOCKER | inactive | same strength and answer availability | [0.9744685694201395, 0.972609500798931] | [repro](repros/base-FTV-1-5-inactive.json) |
| origins-2-1 | BLOCKER | wrong_strength | 0.972 | 0.8813823305181491 | [repro](repros/origins-2-1-0-wrong_strength.json) |
| origins-2-1 | BLOCKER | wrong_strength | 0.972 | 0.8813823305181491 | [repro](repros/origins-2-1-1-wrong_strength.json) |
| origins-2-1 | BLOCKER | repeat | same strength and answer availability | [0.8813823305181491, 0.9719998946920547] | [repro](repros/origins-2-1-2-repeat.json) |
| origins-2-1 | BLOCKER | repeat | same strength and answer availability | [0.8813823305181491, 0.9719998946920547] | [repro](repros/origins-2-1-3-repeat.json) |
| origins-2-1 | BLOCKER | frechet | [0.7627646610362981, 0.8813823305181491] | 0.9579998946920547 | [repro](repros/origins-2-1-4-frechet.json) |
| origins-3-1 | BLOCKER | wrong_strength | 0.9899200000000001 | 0.8636585285919025 | [repro](repros/origins-3-1-0-wrong_strength.json) |
| origins-3-1 | BLOCKER | wrong_strength | 0.9899200000000001 | 0.8636585285919025 | [repro](repros/origins-3-1-1-wrong_strength.json) |
| origins-3-1 | BLOCKER | repeat | same strength and answer availability | [0.8636585285919025, 0.9899197543767491] | [repro](repros/origins-3-1-2-repeat.json) |
| origins-3-1 | BLOCKER | repeat | same strength and answer availability | [0.8636585285919025, 0.9899197543767491] | [repro](repros/origins-3-1-3-repeat.json) |
| origins-3-1 | BLOCKER | frechet | [0.727317057183805, 0.8636585285919025] | 0.9848797543767491 | [repro](repros/origins-3-1-4-frechet.json) |
| origins-7-1 | BLOCKER | wrong_strength | 0.9990590279680001 | 0.8017152104114795 | [repro](repros/origins-7-1-0-wrong_strength.json) |
| origins-7-1 | BLOCKER | overconfident_error | 0.9990590279680001 | 0.8017152104114795 | [repro](repros/origins-7-1-1-overconfident_error.json) |
| origins-7-1 | BLOCKER | wrong_strength | 0.9990590279680001 | 0.8017152104114795 | [repro](repros/origins-7-1-2-wrong_strength.json) |
| origins-7-1 | BLOCKER | overconfident_error | 0.9990590279680001 | 0.8017152104114795 | [repro](repros/origins-7-1-3-overconfident_error.json) |
| origins-7-1 | BLOCKER | frechet | [0.6034304208229591, 0.8017152104114795] | 0.9985875738783228 | [repro](repros/origins-7-1-4-frechet.json) |
| origins-8-1 | BLOCKER | wrong_strength | 0.99928486125568 | 0.7885474013232553 | [repro](repros/origins-8-1-0-wrong_strength.json) |
| origins-8-1 | BLOCKER | overconfident_error | 0.99928486125568 | 0.7885474013232553 | [repro](repros/origins-8-1-1-overconfident_error.json) |
| origins-8-1 | BLOCKER | wrong_strength | 0.99928486125568 | 0.7885474013232553 | [repro](repros/origins-8-1-2-wrong_strength.json) |
| origins-8-1 | BLOCKER | overconfident_error | 0.99928486125568 | 0.7885474013232553 | [repro](repros/origins-8-1-3-overconfident_error.json) |
| origins-8-1 | BLOCKER | frechet | [0.5770948026465106, 0.7885474013232553] | 0.9989261166352451 | [repro](repros/origins-8-1-4-frechet.json) |
| ctv-1-0 | BLOCKER | repeat | same strength and answer availability | [0.4021098863865393, None] | [repro](repros/ctv-1-0-0-repeat.json) |
| ctv-1-1 | BLOCKER | repeat | same strength and answer availability | [0.2038135349573834, None] | [repro](repros/ctv-1-1-0-repeat.json) |
| ctv-1-2 | BLOCKER | repeat | same strength and answer availability | [0.00017883605266026266, None] | [repro](repros/ctv-1-2-0-repeat.json) |
| identity-ground-1 | BLOCKER | false | 0 | [1.0, 0.0562265722615577] | [repro](repros/identity-ground-1-0-false.json) |
| identity-exists-1 | BLOCKER | false | 0 | [1.0, 0.0562265722615577] | [repro](repros/identity-exists-1-0-false.json) |
