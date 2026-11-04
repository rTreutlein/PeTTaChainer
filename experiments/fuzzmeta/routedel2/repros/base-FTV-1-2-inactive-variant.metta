;; BLOCKER: inactive
;; {"severity": "BLOCKER", "invariant": "inactive", "query": 0, "expected": "same strength and answer availability", "actual": [0.8864878559605446, 0.8400000000000001]}
;; deletion minimal: True, trials: 3
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 0.8 0.5)))
!(compileadd kb (: f1 (Z e) (STV 0 1)))
!(compileadd kb (: ra (Implication (O e) (A e)) (FTV 1 1)))
!(compileadd kb (: inactive (Implication (Z e) (A e)) (FTV 1 1)))
!(set-base-rate kb (A e) (STV 0.2 1))
!(query 500 kb (: $prf (A e) $tv))
