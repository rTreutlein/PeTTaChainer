;; BLOCKER: neutral
;; {"severity": "BLOCKER", "invariant": "neutral", "query": 1, "expected": "same strength and answer availability", "actual": [0.9347284013035544, 0.9878048780487805]}
;; deletion minimal: True, trials: 1
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 1 0.001)))
!(compileadd kb (: rc (Implication (O e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd kb (: report0 (C e) (STV 0.9 0.9)))
!(query 500 kb (: $prf (C e) $tv))
