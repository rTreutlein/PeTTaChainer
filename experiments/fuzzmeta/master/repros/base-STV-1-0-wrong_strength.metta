;; BLOCKER: wrong_strength
;; {"severity": "BLOCKER", "invariant": "wrong_strength", "query": 0, "expected": 0.8400000000000001, "actual": 0.8864878559605446}
;; deletion minimal: True, trials: 3
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 0.8 0.5)))
!(compileadd kb (: ra (Implication (O e) (A e)) (STV 1 1)))
!(set-base-rate kb (A e) (STV 0.2 1))
!(query 500 kb (: $prf (A e) $tv))
