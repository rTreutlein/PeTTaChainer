;; BLOCKER: inactive
;; {"severity": "BLOCKER", "invariant": "inactive", "query": 0, "expected": "same strength and answer availability", "actual": [0.8091902847684356, 0.7977937485423872]}
;; deletion minimal: True, trials: 2
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 0.8 0.5)))
!(compileadd kb (: f1 (Z e) (STV 0 1)))
!(compileadd kb (: ra (Implication (O e) (A e)) (STV 1 1)))
!(compileadd kb (: rc (Implication (A e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd kb (: inactive (Implication (Z e) (A e)) (FTV 1 1)))
!(set-base-rate kb (A e) (STV 0.2 1))
!(query 500 kb (: $prf (C e) $tv))
