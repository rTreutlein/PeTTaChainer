;; BLOCKER: frechet
;; {"severity": "BLOCKER", "invariant": "frechet", "query": 2, "expected": [0.7627646610362981, 0.8813823305181491], "actual": 0.9579998946920547}
;; deletion minimal: True, trials: 9
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O0 e) (STV 0.8 0.01)))
!(compileadd kb (: f1 (O1 e) (STV 0.7200000000000001 0.01)))
!(compileadd kb (: rA0 (Implication (O0 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rB0 (Implication (O0 e) (B e)) (FTV 1 1)))
!(compileadd kb (: rA1 (Implication (O1 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rB1 (Implication (O1 e) (B e)) (FTV 1 1)))
!(query 500 kb (: $prf (A e) $tv))
!(query 500 kb (: $prf (B e) $tv))
!(query 500 kb (: $prf (And (A e) (B e)) $tv))
