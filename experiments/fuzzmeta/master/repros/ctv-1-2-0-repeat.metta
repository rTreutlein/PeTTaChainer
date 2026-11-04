;; BLOCKER: repeat
;; {"severity": "BLOCKER", "invariant": "repeat", "query": 0, "expected": "same strength and answer availability", "actual": [0.33820142912613627, null]}
;; deletion minimal: True, trials: 1
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O e) (STV 0.5909557836336579 0.5)))
!(compileadd kb (: f1 (B e) (STV 0.6 1)))
!(compileadd kb (: ra (Implication (O e) (A e)) (CTV (STV 0.85 0.5) (STV 0.15 1))))
!(query 500 kb (: $prf (And (A e) (B e)) $tv))
