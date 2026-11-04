;; BLOCKER: wrong_strength
;; {"severity": "BLOCKER", "invariant": "wrong_strength", "query": 0, "expected": 0.6429592566118656, "actual": 1, "variant": "neutral"}
;; deletion minimal: True, trials: 1
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 1 0.001)))
!(compileadd kb (: rc (Implication (O e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(query 500 kb (: $prf (O e) $tv))
