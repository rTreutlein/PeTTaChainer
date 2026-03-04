!(import! &self ../benchgen_pln_compare)

!(BenchGenerateWithPrint demoCompare
   (depth 10)
   (width 1)
   (paths 6)
   (noise-factor 10)
   (backward-ratio 0)
   (backward-chain-len 3)
   (forward-chain-len 3)
   (print True))

; Side-by-side result plus wall-clock seconds for each solver.
!(BenchTimedTargetProvedCompare demoCompare 1 200)

!(BenchTimedTargetProvedCompare demoCompare 2 200)

!(BenchTimedTargetProvedCompare demoCompare 3 200)

!(BenchTimedTargetProvedCompare demoCompare 4 200)

!(BenchTimedTargetProvedCompare demoCompare 5 200)

!(BenchTimedTargetProvedCompare demoCompare 6 200)

;!(BenchTimedTargetProvedCompare demoCompare 2 10000)
;!(BenchTimedTargetProvedCompare demoCompare 3 10000)
;!(BenchTimedTargetProvedCompare demoCompare 4 10000)
;!(BenchPLNKB demoCompare)
;!(PLN.Derive (BenchPLNKB demoCompare) (BenchPLNKB demoCompare) 10000)
