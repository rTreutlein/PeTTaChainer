!(import! &self benchgen_metta)

!(BenchGenerate demoSmallA (depth 3) (width 1) (paths 1) (noise-factor 0) (backward-ratio 50) (backward-chain-len 3) (forward-chain-len 2))

; Query-focused benchmark check: target is reachable only at sufficient step budget.
!(collapse (query 2 kb (: $prf (BenchTarget demoSmallA 1) $tv)))
!(collapse (query 30 kb (: $prf (BenchTarget demoSmallA 1) $tv)))
