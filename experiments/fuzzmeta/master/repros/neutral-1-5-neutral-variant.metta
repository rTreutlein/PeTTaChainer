;; BLOCKER: neutral
;; {"severity": "BLOCKER", "invariant": "neutral", "query": 0, "expected": "same strength and answer availability", "actual": [0.8912891216043766, 0.9762111390395556]}
;; deletion minimal: True, trials: 1
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 1 0.001)))
!(compileadd kb (: rc (Implication (O e) (C e)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd kb (: unused (Implication (O e) (Unused e)) (FTV 1 1)))
!(compileadd kb (: report0 (C e) (STV 0.9 0.9)))
!(compileadd kb (: report1 (Unused e) (STV 0.5 0.9)))
!(query 500 kb (: $prf (O e) $tv))
