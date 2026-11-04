;; BLOCKER: overconfident_error
;; {"severity": "BLOCKER", "invariant": "overconfident_error", "query": 0, "expected": 0.9533248000000001, "actual": 0.7269399419237443, "claimed_sd": 0.09932541871968345}
;; deletion minimal: True, trials: 14
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: f0 (O3 e) (STV 0.56 0.01)))
!(compileadd kb (: f1 (O4 e) (STV 0.48000000000000004 0.01)))
!(compileadd kb (: f2 (O5 e) (STV 0.4 0.01)))
!(compileadd kb (: f3 (O6 e) (STV 0.32000000000000006 0.01)))
!(compileadd kb (: rA3 (Implication (O3 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rA4 (Implication (O4 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rA5 (Implication (O5 e) (A e)) (FTV 1 1)))
!(compileadd kb (: rA6 (Implication (O6 e) (A e)) (FTV 1 1)))
!(query 500 kb (: $prf (A e) $tv))
