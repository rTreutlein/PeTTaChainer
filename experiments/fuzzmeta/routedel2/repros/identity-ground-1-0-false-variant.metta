;; BLOCKER: false
;; {"severity": "BLOCKER", "invariant": "false", "query": 0, "expected": 0, "actual": [1.0, 0.0562265722615577]}
;; deletion minimal: True, trials: 1
!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta/scratch/routedel2-3a990295/pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 800)
!(compileadd kb (: report0 (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit)) (STV 1 0.9)))
!(compileadd kb (: report1 (Not (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit))) (STV 1 1)))
!(compileadd kb (: bridge (Implication (And (Member $e StockSplit) (Implemented $e)) (Not (Dilutes $e))) (STV 1 0.9)))
!(query 500 kb (: $prf (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit) (Implication (Implemented Split1) (Not (Dilutes Split1)))) $tv))
