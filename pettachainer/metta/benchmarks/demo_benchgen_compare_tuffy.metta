!(import! &self ../benchgen_pln_compare)

!(BenchGenerateWithPrint demoCompare
   (depth 2)
   (width 2)
   (paths 1)
   (noise-factor 0)
   (backward-ratio 0)
   (backward-chain-len 3)
   (forward-chain-len 3)
   (print false))

; Side-by-side result plus wall-clock seconds for each solver.
!(BenchTimedTargetProvedCompare demoCompare 1 20)

;!(BenchTimedTargetProvedCompare demoCompare 2 10000)
;!(BenchTimedTargetProvedCompare demoCompare 3 10000)
;!(BenchTimedTargetProvedCompare demoCompare 4 10000)
;!(BenchPLNKB demoCompare)
;!(PLN.Derive (BenchPLNKB demoCompare) (BenchPLNKB demoCompare) 10000)
