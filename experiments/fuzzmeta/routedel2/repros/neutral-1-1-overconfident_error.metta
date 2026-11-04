;; BLOCKER: overconfident_error
;; {"severity": "BLOCKER", "invariant": "overconfident_error", "query": 0, "expected": 0.6429592566118656, "actual": 0.9999999999987512, "claimed_sd": 8.327313463975507e-07, "variant": "neutral"}
;; deletion minimal: True, trials: 1
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 1 0.001)))
!(compileadd kb (: rc (Implication (O e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(query 500 kb (: $prf (O e) $tv))
