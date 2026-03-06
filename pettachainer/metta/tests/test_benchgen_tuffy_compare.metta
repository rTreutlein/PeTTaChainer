!(import! &self benchmarks/benchgen_pln_compare)

!(BenchGenerate benchCompare
   (depth 1)
   (width 1)
   (paths 1)
   (noise-factor 0)
   (backward-ratio 50)
   (backward-chain-len 1)
   (forward-chain-len 1))

!(test (BenchBool? (BenchTargetProvedPLN? benchCompare 1 40)) true)

!(test
   (let $cmp (BenchTargetProvedCompare benchCompare 1 40)
      (and (or (not (== (is-member (ours true) $cmp) ())) (not (== (is-member (ours false) $cmp) ())))
         (or (not (== (is-member (lib_pln true) $cmp) ())) (not (== (is-member (lib_pln false) $cmp) ())))))
   true)

!(test
   (let $timed (BenchTimedTargetProvedCompare benchCompare 1 40)
      (not (== (is-member (total (seconds $secs)) $timed) ())))
   true)
