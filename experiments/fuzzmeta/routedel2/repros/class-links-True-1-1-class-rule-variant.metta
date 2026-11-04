;; BLOCKER: class-rule
;; {"severity": "BLOCKER", "invariant": "class-rule", "query": 0, "expected": "inactive derived link preserves an existing classification", "actual": [1.0, null]}
;; deletion minimal: True, trials: 9
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: trans (Implication (And (Inheritance $a $b) (Inheritance $b $c)) (Inheritance $a $c)) (STV 1 0.99)))
!(compileadd kb (: cf (Member grace pilot) (STV 1 0.99)))
!(compileadd kb (: cg (Inheritance pilot person) (STV 1 0.99)))
!(compileadd kb (: licrule (Implication (Licensed person) (Inheritance person animal)) (STV 1 0.99)))
!(query 500 kb (: $prf (Member grace person) $tv))
