!(import! &self benchmarks/benchgen_metta)

!(BenchGenerate benchCore
   (depth 2)
   (width 2)
   (paths 1)
   (noise-factor 0)
   (backward-ratio 50)
   (backward-chain-len 3)
   (forward-chain-len 2))

!(test (== (BenchBaseFactCount benchCore) 4) true)

!(test (== (BenchMainRuleCount benchCore) 3) true)

!(test (== (BenchNoiseStatementCount benchCore) 0) true)

!(test (BenchTargetProved? benchCore 1 60) true)

!(test (not (== (BenchPLNKB benchCore) ())) true)

!(BenchGenerate benchNoiseMix
   (depth 2)
   (width 2)
   (paths 1)
   (noise-factor 1)
   (backward-ratio 50)
   (backward-chain-len 3)
   (forward-chain-len 2))

!(test (== (BenchTrueStatementCount benchNoiseMix) 7) true)

!(test (== (BenchNoiseStatementCount benchNoiseMix) 7) true)

!(test (== (BenchNoiseBackwardRuleCount benchNoiseMix) 3) true)

!(test (== (BenchNoiseForwardRuleCount benchNoiseMix) 4) true)

!(test
   (not
      (==
         (collapse
            (match &bench_meta (bench-noise-back-rule-meta benchNoiseMix 1 0)
               yes))
         ()))
   true)

!(test
   (==
      (collapse
         (query 100
            kb
            (: (bench-noise-back-head benchNoiseMix 1)
               (BenchTarget benchNoiseMix 1)
               $tv)))
      ())
   true)

!(test
   (==
      (BenchListCount (collapse (query 100 kb (: $prf (NoiseDeadEnd benchNoiseMix $idx) $tv))))
      2)
   true)

!(BenchGenerate benchPaths3
   (depth 2)
   (width 2)
   (paths 3)
   (noise-factor 1)
   (backward-ratio 50)
   (backward-chain-len 3)
   (forward-chain-len 2))

!(test (== (BenchBaseFactCount benchPaths3) 12) true)

!(test (== (BenchMainRuleCount benchPaths3) 9) true)

!(test (== (BenchTrueStatementCount benchPaths3) 21) true)

!(test (== (BenchNoiseStatementCount benchPaths3) 21) true)

!(test
   (and (BenchTargetProved? benchPaths3 1 80)
      (and (BenchTargetProved? benchPaths3 2 80) (BenchTargetProved? benchPaths3 3 80)))
   true)

!(test (let $c (BenchGlobalConf) (and (>= $c 0.45) (<= $c 0.98))) true)

!(test
   (==
      (BenchListCount
         (collapse
            (BenchGenerateWithPrint benchNoDupPrint
               (depth 2)
               (width 2)
               (paths 1)
               (noise-factor 1)
               (backward-ratio 50)
               (backward-chain-len 3)
               (forward-chain-len 2)
               (print true))))
      1)
   true)

!(test (== (BenchTrueStatementCount benchNoDupPrint) 7) true)

!(test (== (BenchNoiseStatementCount benchNoDupPrint) 7) true)
