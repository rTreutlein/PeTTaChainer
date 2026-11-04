;; BLOCKER: flip
;; {"severity": "BLOCKER", "invariant": "flip", "query": 0, "expected": "observation flip changes strength up", "actual": [0.4, 0.4]}
;; deletion minimal: True, trials: 0
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (C e) (STV 0.4 0.9)))
!(compileadd kb (: f1 (D e) (STV 0.5 0)))
!(compileadd kb (: ra (Implication (C e) (A e)) (STV 1 0.9)))
!(compileadd kb (: report0 (Not (Or (A e) (D e))) (STV 0 0.9)))
!(query 500 kb (: $prf (C e) $tv))
