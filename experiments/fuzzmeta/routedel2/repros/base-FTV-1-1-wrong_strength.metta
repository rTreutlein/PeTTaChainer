;; BLOCKER: wrong_strength
;; {"severity": "BLOCKER", "invariant": "wrong_strength", "query": 0, "expected": 0.772, "actual": 0.8091902847684356}
;; deletion minimal: True, trials: 2
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 0.8 0.5)))
!(compileadd kb (: ra (Implication (O e) (A e)) (FTV 1 1)))
!(compileadd kb (: rc (Implication (A e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(set-base-rate kb (A e) (STV 0.2 1))
!(query 500 kb (: $prf (C e) $tv))
