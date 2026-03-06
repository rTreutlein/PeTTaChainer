!(import! &self benchgen_metta)

!(BenchGenerate demoSmallA
   (depth 3)
   (width 3)
   (paths 3)
   (noise-factor 10)
   (backward-ratio 50)
   (backward-chain-len 3)
   (forward-chain-len 2))

!(let*
   (($t1 (current-time))
     ($res (collapse (query 300 kb (: $prf (BenchTarget demoSmallA 1) $tv))))
     ($t2 (current-time)))
   (Found $res in seconds (- $t2 $t1)))
