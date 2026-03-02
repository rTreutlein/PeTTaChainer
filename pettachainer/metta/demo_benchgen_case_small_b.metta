!(import! &self benchgen_metta)

!(BenchGenerate demoSmallB (depth 3) (width 3) (paths 2) (noise-factor 1) (backward-ratio 50) (backward-chain-len 3) (forward-chain-len 2))

; Step-budgeted queries and multi-path reachability for inference benchmarking.
!(collapse (query 2 kb (: $prf (BenchTarget demoSmallB 1) $tv)))
!(collapse (query 30 kb (: $prf (BenchTarget demoSmallB 1) $tv)))
!(collapse (query 30 kb (: $prf (BenchTarget demoSmallB 2) $tv)))
