;; BLOCKER: repeat
;; {"severity": "BLOCKER", "invariant": "repeat", "query": 0, "expected": "same strength and answer availability", "actual": [0.8413650923962147, 0.9495998858943859]}
;; deletion minimal: True, trials: 5
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O1 e) (STV 0.7200000000000001 0.01)))
!(compileadd kb (: f1 (O2 e) (STV 0.64 0.01)))
!(compileadd kb (: rB1 (Implication (O1 e) (B e)) (FTV 1 1)))
!(compileadd kb (: rB2 (Implication (O2 e) (B e)) (FTV 1 1)))
!(query 500 kb (: $prf (B e) $tv))
