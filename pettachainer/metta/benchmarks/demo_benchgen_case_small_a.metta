!(import! &self ../benchgen_metta)

!(BenchGenerateWithPrint demoSmallA
   (depth 3)
   (width 3)
   (paths 3)
   (noise-factor 10)
   (backward-ratio 50)
   (backward-chain-len 3)
   (forward-chain-len 2)
   (print False))

; Query-focused benchmark check: target is reachable only at sufficient step budget.
!(let*
   (($t1 (current-time))
     ($res1 (collapse (query 1000 kb (: $prf1 (BenchTarget demoSmallA 1) $tv1))))
     ($res2 (collapse (query 1000 kb (: $prf2 (BenchTarget demoSmallA 2) $tv2))))
     ($res3 (collapse (query 1000 kb (: $prf3 (BenchTarget demoSmallA 3) $tv3))))
     ($t2 (current-time)))
   (Found $res in seconds (- $t2 $t1)))
