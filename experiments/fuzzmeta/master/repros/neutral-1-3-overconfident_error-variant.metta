;; BLOCKER: overconfident_error
;; {"severity": "BLOCKER", "invariant": "overconfident_error", "query": 0, "expected": 0.6143674052894924, "actual": 0.9, "claimed_sd": 0.0006055139129077557, "variant": "neutral"}
;; deletion minimal: True, trials: 1
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 1 0.001)))
!(compileadd kb (: rc (Implication (O e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd kb (: unused (Implication (O e) (Unused e)) (FTV 1 1)))
!(compileadd kb (: report0 (Unused e) (STV 0.5 0.9)))
!(query 500 kb (: $prf (C e) $tv))
