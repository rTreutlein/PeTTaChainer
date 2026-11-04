;; BLOCKER: overconfident_variance
;; {"severity": "BLOCKER", "invariant": "overconfident_variance", "query": 0, "expected_at_least": 0.002656608625626544, "actual": 0.0013574164692199088, "reference_status": "certified-lower-bound"}
;; deletion minimal: True, trials: 9
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O1 e) (STV 0.7200000000000001 0.01)))
!(compileadd kb (: f1 (O2 e) (STV 0.64 0.01)))
!(compileadd kb (: rA1 (Implication (O1 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rA2 (Implication (O2 e) (A e)) (FTV 1 1)))
!(query 500 kb (: $prf (A e) $tv))
