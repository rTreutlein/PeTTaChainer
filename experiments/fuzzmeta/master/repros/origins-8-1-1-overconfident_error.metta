;; BLOCKER: overconfident_error
;; {"severity": "BLOCKER", "invariant": "overconfident_error", "query": 0, "expected": 0.9955648, "actual": 0.8468222701209775, "claimed_sd": 0.065869154165578}
;; deletion minimal: True, trials: 13
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O0 e) (STV 0.8 0.01)))
!(compileadd kb (: f1 (O1 e) (STV 0.7200000000000001 0.01)))
!(compileadd kb (: f2 (O2 e) (STV 0.64 0.01)))
!(compileadd kb (: f3 (O3 e) (STV 0.56 0.01)))
!(compileadd kb (: rA0 (Implication (O0 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rA1 (Implication (O1 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rA2 (Implication (O2 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rA3 (Implication (O3 e) (A e)) (FTV 1 1)))
!(query 500 kb (: $prf (A e) $tv))
