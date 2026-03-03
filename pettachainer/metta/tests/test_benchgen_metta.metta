!(import! &self benchgen_metta)

; Core tree semantics unchanged: depth=2,width=2,path=1 -> 4 base facts, 3 main rules.
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

; Factor semantics: noise statements = noise-factor * true statements.
; true statements for depth=2,width=2,paths=1 => 4 + 3 = 7.
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

; Backward-relevant unsat chain exists (decoy conclusion matches target), but cannot prove through decoy proof-id.
!(test
   (not
      (==
         (collapse
            (match &kb
               (: (kb MAIN Nil) (bench-noise-back-meta benchNoiseMix 1 0) (BenchNoiseBackRule benchNoiseMix 1 0) (STV 1.0 1.0))
               yes))
         ()))
   true)

!(test
   (==
      (collapse
         (query 100
            kb
            (: (bench-noise-back-head benchNoiseMix 1) (BenchTarget benchNoiseMix 1) $tv)))
      ())
   true)

; Forward noise is connected+provable and ends in dead ends.
!(test (not (== (collapse (query 100 kb (: $prf (NoiseDeadEnd benchNoiseMix $idx) $tv))) ())) true)

; Path scaling still works with factor noise.
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

; Confidence values come from builtin random-float and stay in configured range.
!(test (let $c (BenchGlobalConf) (and (>= $c 0.45) (<= $c 0.98))) true)

; Print-mode determinism for generation result cardinality.
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
