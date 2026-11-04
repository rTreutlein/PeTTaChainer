;; BLOCKER: wrong_strength
;; {"severity": "BLOCKER", "invariant": "wrong_strength", "query": 0, "expected": 0.972, "actual": 0.8813823305181491}
;; deletion minimal: True, trials: 3
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O0 e) (STV 0.8 0.01)))
!(compileadd kb (: f1 (O1 e) (STV 0.7200000000000001 0.01)))
!(compileadd kb (: rB0 (Implication (O0 e) (B e)) (FTV 1 1)))
!(compileadd kb (: rB1 (Implication (O1 e) (B e)) (FTV 1 1)))
!(query 500 kb (: $prf (B e) $tv))
