!(import! &self ../petta_chainer)

(= (BenchListCount ()) 0)
(= (BenchListCount (cons $_x $tail)) (+ 1 (BenchListCount $tail)))

(= (BenchPow $base $exp) (if (== $exp 0) 1 (* $base (BenchPow $base (- $exp 1)))))

(= (BenchIntDiv $num $den) (if (< $num $den) 0 (+ 1 (BenchIntDiv (- $num $den) $den))))

(= (BenchMin $a $b) (if (< $a $b) $a $b))

(= (BenchBool? $x) (or (== $x true) (== $x false)))

(= (BenchCycle1 $idx $max) (if (<= $idx $max) $idx (BenchCycle1 (- $idx $max) $max)))

(= (BenchGlobalConf) (random-float 0.45 0.98))

(=
   (BenchValidParams? $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len)
   (and (>= $depth 1)
      (and (>= $width 1)
         (and (>= $paths 1)
            (and (>= $noise-factor 0)
               (and (>= $backward-ratio 0)
                  (and (<= $backward-ratio 100) (and (>= $backward-chain-len 1) (>= $forward-chain-len 1)))))))))

(= (BenchChildIndex $parent-idx $width $slot) (+ (* (- $parent-idx 1) $width) $slot))

(= (BenchPremiseRef $bench $path $level $idx)
   (if (== $level 0) (BenchFact $bench $path $idx) (BenchNode $bench $path $level $idx)))

(= (BenchRulePremisesRemaining $bench $path $level $parent-idx $width $slot $remaining)
   (if (== $remaining 0) ()
      (let*
         (($child-level (- $level 1))
           ($child-idx (BenchChildIndex $parent-idx $width $slot))
           ($child (BenchPremiseRef $bench $path $child-level $child-idx)))
         (cons $child
            (BenchRulePremisesRemaining $bench
               $path
               $level
               $parent-idx
               $width
               (+ $slot 1)
               (- $remaining 1))))))

(= (BenchRulePremises $bench $path $level $idx $width)
   (BenchRulePremisesRemaining $bench
      $path
      $level
      $idx
      $width
      1
      $width))

(= (BenchRuleConclusion $bench $path $level $idx $depth)
   (if (== $level $depth) (BenchTarget $bench $path) (BenchNode $bench $path $level $idx)))

(= (BenchMaybePrint false $_stmt) done)
(= (BenchMaybePrint true $stmt) (println! $stmt))

(= (BenchCompileAdd $print-this-stmt $stmt)
   (let $_print (BenchMaybePrint $print-this-stmt $stmt) (collapse (compileadd kb $stmt))))

(= (BenchMetaAdd $stmt) (progn (add-atom &bench_meta $stmt) done))

(= (BenchAddBaseFact $bench $path $idx $print-before-compile)
   (let*
      (($conf (BenchGlobalConf))
        ($_
           (BenchCompileAdd $print-before-compile
              (: (bench-base-fact $bench $path $idx) (BenchFact $bench $path $idx) (STV 1.0 $conf)))))
      done))

(= (BenchGenerateBaseFactsRemaining $bench $path $idx $remaining $print-before-compile)
   (if (== $remaining 0) done
      (let $_fact (BenchAddBaseFact $bench $path $idx $print-before-compile)
         (BenchGenerateBaseFactsRemaining $bench
            $path
            (+ $idx 1)
            (- $remaining 1)
            $print-before-compile))))

(= (BenchGenerateBaseFacts $bench $path $depth $width $print-before-compile)
   (BenchGenerateBaseFactsRemaining $bench
      $path
      1
      (BenchPow $width $depth)
      $print-before-compile))

(= (BenchAddMainRule $bench $path $level $idx $depth $width $print-before-compile)
   (let*
      (($premises (BenchRulePremises $bench $path $level $idx $width))
        ($conclusion (BenchRuleConclusion $bench $path $level $idx $depth))
        ($rule-type (Implication (cons Premises $premises) (cons Conclusions (cons $conclusion ()))))
        ($conf (BenchGlobalConf)))
      (let*
         (($_meta (BenchMetaAdd (bench-main-rule-meta $bench $path $level $idx $width $conf)))
           ($_rule
              (BenchCompileAdd $print-before-compile
                 (: (bench-main-rule $bench $path $level $idx) $rule-type (STV 1.0 $conf)))))
         done)))

(= (BenchGenerateLevelRulesRemaining $bench $path $level $idx $remaining $depth $width $print-before-compile)
   (if (== $remaining 0) done
      (let $_rule (BenchAddMainRule $bench $path $level $idx $depth $width $print-before-compile)
         (BenchGenerateLevelRulesRemaining $bench
            $path
            $level
            (+ $idx 1)
            (- $remaining 1)
            $depth
            $width
            $print-before-compile))))

(= (BenchGenerateLevelsLoop $bench $path $level $depth $width $print-before-compile)
   (if (> $level $depth) done
      (let*
         (($node-count (BenchPow $width (- $depth $level)))
           ($_rules
              (BenchGenerateLevelRulesRemaining $bench
                 $path
                 $level
                 1
                 $node-count
                 $depth
                 $width
                 $print-before-compile)))
         (BenchGenerateLevelsLoop $bench
            $path
            (+ $level 1)
            $depth
            $width
            $print-before-compile))))

(= (BenchGeneratePathsRemaining $bench $path $remaining-paths $depth $width $print-before-compile)
   (if (== $remaining-paths 0) done
      (let*
         (($_facts (BenchGenerateBaseFacts $bench $path $depth $width $print-before-compile))
           ($_levels (BenchGenerateLevelsLoop $bench $path 1 $depth $width $print-before-compile)))
         (BenchGeneratePathsRemaining $bench
            (+ $path 1)
            (- $remaining-paths 1)
            $depth
            $width
            $print-before-compile))))

(= (BenchGeneratePaths $bench $paths $depth $width $print-before-compile)
   (BenchGeneratePathsRemaining $bench
      1
      $paths
      $depth
      $width
      $print-before-compile))

(= (BenchForwardPremiseFact $bench $paths $depth $width $noise-idx)
   (let*
      (($path (BenchCycle1 $noise-idx $paths))
        ($fact-max (BenchPow $width $depth))
        ($fact-idx (BenchCycle1 $noise-idx $fact-max)))
      (BenchFact $bench $path $fact-idx)))

(= (BenchAddBackwardHeadRule $bench $noise-idx $paths $premise $print-before-compile)
   (let*
      (($path (BenchCycle1 $noise-idx $paths))
        ($rule-type
           (Implication (cons Premises (cons $premise ()))
              (cons Conclusions (cons (BenchTarget $bench $path) ()))))
        ($conf (BenchGlobalConf)))
      (let*
         (($_meta (BenchMetaAdd (bench-noise-back-rule-meta $bench $noise-idx 0)))
           ($_rule
              (BenchCompileAdd $print-before-compile
                 (: (bench-noise-back-head $bench $noise-idx) $rule-type (STV 1.0 $conf)))))
         done)))

(= (BenchBackwardTailPremise $bench $noise-idx $step $last-step)
   (if (== $step $last-step) (NoiseBlocker $bench $noise-idx) (NoiseBackStep $bench $noise-idx (+ $step 1))))

(= (BenchAddBackwardTailRules $bench $noise-idx $step $last-step $print-before-compile)
   (if (> $step $last-step) done
      (let*
         (($premise (BenchBackwardTailPremise $bench $noise-idx $step $last-step))
           ($rule-type
              (Implication (cons Premises (cons $premise ()))
                 (cons Conclusions (cons (NoiseBackStep $bench $noise-idx $step) ()))))
           ($conf (BenchGlobalConf)))
         (let*
            (($_meta (BenchMetaAdd (bench-noise-back-rule-meta $bench $noise-idx $step)))
              ($_rule
                 (BenchCompileAdd $print-before-compile
                    (: (bench-noise-back-rule $bench $noise-idx $step) $rule-type (STV 1.0 $conf)))))
            (BenchAddBackwardTailRules $bench
               $noise-idx
               (+ $step 1)
               $last-step
               $print-before-compile)))))

(= (BenchGenerateBackwardChain $bench $noise-idx $chain-len $paths $print-before-compile)
   (let*
      (($head-premise
           (if (== $chain-len 1) (NoiseBlocker $bench $noise-idx) (NoiseBackStep $bench $noise-idx 1)))
        ($_head (BenchAddBackwardHeadRule $bench $noise-idx $paths $head-premise $print-before-compile)))
      (if (== $chain-len 1) done
         (BenchAddBackwardTailRules $bench
            $noise-idx
            1
            (- $chain-len 1)
            $print-before-compile))))

(= (BenchNoiseSpan $remaining-statements $chain-len)
   (BenchMin $remaining-statements (if (< $chain-len 1) 1 $chain-len)))

(= (BenchForwardChainPremise $bench $noise-idx $step $paths $depth $width)
   (if (== $step 1) (BenchForwardPremiseFact $bench $paths $depth $width $noise-idx)
      (NoiseForward $bench $noise-idx (- $step 1))))

(= (BenchForwardChainConclusion $bench $noise-idx $step $chain-len)
   (if (== $step $chain-len) (NoiseDeadEnd $bench $noise-idx) (NoiseForward $bench $noise-idx $step)))

(=
   (BenchAddForwardChainRulesRemaining $bench
      $noise-idx
      $step
      $chain-len
      $paths
      $depth
      $width
      $print-before-compile)
   (if (> $step $chain-len) done
      (let*
         (($premise (BenchForwardChainPremise $bench $noise-idx $step $paths $depth $width))
           ($conclusion (BenchForwardChainConclusion $bench $noise-idx $step $chain-len))
           ($rule-type
              (Implication (cons Premises (cons $premise ())) (cons Conclusions (cons $conclusion ()))))
           ($conf (BenchGlobalConf)))
         (let*
            (($_meta (BenchMetaAdd (bench-noise-forward-rule-meta $bench $noise-idx $step)))
              ($_rule
                 (BenchCompileAdd $print-before-compile
                    (: (bench-noise-forward-rule $bench $noise-idx $step) $rule-type (STV 1.0 $conf)))))
            (BenchAddForwardChainRulesRemaining $bench
               $noise-idx
               (+ $step 1)
               $chain-len
               $paths
               $depth
               $width
               $print-before-compile)))))

(=
   (BenchGenerateBackwardNoiseRemaining $bench
      $noise-idx
      $remaining-statements
      $chain-len
      $paths
      $print-before-compile)
   (if (== $remaining-statements 0) done
      (let*
         (($span (BenchNoiseSpan $remaining-statements $chain-len))
           ($_chain (BenchGenerateBackwardChain $bench $noise-idx $span $paths $print-before-compile)))
         (BenchGenerateBackwardNoiseRemaining $bench
            (+ $noise-idx 1)
            (- $remaining-statements $span)
            $chain-len
            $paths
            $print-before-compile))))

(=
   (BenchGenerateForwardNoiseRemaining $bench
      $noise-idx
      $remaining-statements
      $chain-len
      $paths
      $depth
      $width
      $print-before-compile)
   (if (== $remaining-statements 0) done
      (let*
         (($span (BenchNoiseSpan $remaining-statements $chain-len))
           ($_chain
              (BenchAddForwardChainRulesRemaining $bench
                 $noise-idx
                 1
                 $span
                 $paths
                 $depth
                 $width
                 $print-before-compile)))
         (BenchGenerateForwardNoiseRemaining $bench
            (+ $noise-idx 1)
            (- $remaining-statements $span)
            $chain-len
            $paths
            $depth
            $width
            $print-before-compile))))

(= (BenchTrueStatementCount $bench) (+ (BenchBaseFactCount $bench) (BenchMainRuleCount $bench)))

(= (BenchNoiseStatementCount $bench)
   (+ (BenchNoiseBackwardRuleCount $bench) (BenchNoiseForwardRuleCount $bench)))

(=
   (BenchGenerateNoiseByFactor $bench
      $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len
      $print-before-compile)
   (let*
      (($true-count (BenchTrueStatementCount $bench))
        ($noise-total (* $noise-factor $true-count))
        ($desired-backward (BenchIntDiv (* $noise-total $backward-ratio) 100))
        ($backward-budget (if (< $desired-backward 1) 0 (BenchMin $noise-total $desired-backward)))
        ($forward-budget (- $noise-total $backward-budget)))
      (let*
         (($_backward
              (BenchGenerateBackwardNoiseRemaining $bench
                 1
                 $backward-budget
                 $backward-chain-len
                 $paths
                 $print-before-compile)))
         (BenchGenerateForwardNoiseRemaining $bench
            (+ 1 $backward-budget)
            $forward-budget
            $forward-chain-len
            $paths
            $depth
            $width
            $print-before-compile))))

(=
   (BenchGenerateCore $bench
      $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len
      $print-before-compile)
   (if
      (BenchValidParams? $depth
         $width
         $paths
         $noise-factor
         $backward-ratio
         $backward-chain-len
         $forward-chain-len)
      (let*
         (($_spec
              (BenchMetaAdd
                 (bench-spec $bench
                    $depth
                    $width
                    $paths
                    $noise-factor
                    $backward-ratio
                    $backward-chain-len
                    $forward-chain-len)))
           ($_paths (BenchGeneratePaths $bench $paths $depth $width $print-before-compile))
           ($_noise
              (BenchGenerateNoiseByFactor $bench
                 $depth
                 $width
                 $paths
                 $noise-factor
                 $backward-ratio
                 $backward-chain-len
                 $forward-chain-len
                 $print-before-compile)))
         (BenchmarkGenerated $bench
            $depth
            $width
            $paths
            $noise-factor
            $backward-ratio
            $backward-chain-len
            $forward-chain-len))
      (BenchGenerateError invalid-params
         $bench
         $depth
         $width
         $paths
         $noise-factor
         $backward-ratio
         $backward-chain-len
         $forward-chain-len)))

(= (BenchWidthArg (width $width)) $width)
(= (BenchWidthArg (widht $width)) $width)

(=
   (BenchGenerate $bench
      (depth $depth)
      $width-arg
      (paths $paths)
      (noise-factor $noise-factor)
      (backward-ratio $backward-ratio)
      (backward-chain-len $backward-chain-len)
      (forward-chain-len $forward-chain-len))
   (let $width (BenchWidthArg $width-arg)
      (BenchGenerateCore $bench
         $depth
         $width
         $paths
         $noise-factor
         $backward-ratio
         $backward-chain-len
         $forward-chain-len
         false)))

(=
   (BenchGenerateWithPrint $bench
      (depth $depth)
      $width-arg
      (paths $paths)
      (noise-factor $noise-factor)
      (backward-ratio $backward-ratio)
      (backward-chain-len $backward-chain-len)
      (forward-chain-len $forward-chain-len)
      (print $print-before-compile))
   (let $width (BenchWidthArg $width-arg)
      (BenchGenerateCore $bench
         $depth
         $width
         $paths
         $noise-factor
         $backward-ratio
         $backward-chain-len
         $forward-chain-len
         $print-before-compile)))

(= (BenchMainRuleCount $bench)
   (BenchListCount
      (collapse (match &bench_meta (bench-main-rule-meta $bench $_path $_level $_idx $_width $_conf) ok))))

(= (BenchBaseFactCount $bench)
   (BenchListCount
      (collapse
         (match &kb ((BenchFact $bench $_path $_idx) $_kb (bench-base-fact $bench $_path $_idx) $_tv)
            ok))))

(= (BenchNoiseBackwardRuleCount $bench)
   (BenchListCount (collapse (match &bench_meta (bench-noise-back-rule-meta $bench $_idx $_step) ok))))

(= (BenchNoiseForwardRuleCount $bench)
   (BenchListCount (collapse (match &bench_meta (bench-noise-forward-rule-meta $bench $_idx $_step) ok))))

(= (BenchTargetProved? $bench $path $steps)
   (not (== (collapse (query $steps kb (: $prf (BenchTarget $bench $path) $tv))) ())))

(= (BenchListAppend () $ys) $ys)
(= (BenchListAppend (cons $x $xs) $ys) (cons $x (BenchListAppend $xs $ys)))

(= (BenchPLNDepth $bench)
   (car-atom
      (collapse
         (match &bench_meta
            (bench-spec $bench
               $depth
               $_width
               $_paths
               $_noise
               $_backward
               $_backward-len
               $_forward-len)
            $depth))))

(= (BenchPLNBaseAtoms $bench)
   (collapse
      (match &kb ($type $_kb (bench-base-fact $bench $path $idx) $tv)
         (: (bench-base-fact $bench $path $idx) $type $tv))))

(= (BenchFirstOr $list $default) (if (== $list ()) $default (car-atom $list)))

(= (BenchPLNMainRuleAtoms $bench)
   (collapse
      (match &bench_meta (bench-main-rule-meta $bench $path $level $idx $width $conf)
         (let*
            (($depth (BenchPLNDepth $bench))
              ($premises (BenchRulePremises $bench $path $level $idx $width))
              ($conclusion (BenchRuleConclusion $bench $path $level $idx $depth))
              ($type (Implication (cons Premises $premises) (cons Conclusions (cons $conclusion ()))))
              ($tv (STV 1.0 $conf)))
            (: (bench-main-rule $bench $path $level $idx) $type $tv)))))

(= (BenchPLNAtoms $bench) (BenchListAppend (BenchPLNBaseAtoms $bench) (BenchPLNMainRuleAtoms $bench)))

(= (BenchPLNBuildImplication () $conclusion) $conclusion)
(= (BenchPLNBuildImplication (cons $head $tail) $conclusion)
   (Implication $head (BenchPLNBuildImplication $tail $conclusion)))

(= (BenchPLNNormalizeType $type)
   (if (= $type (Implication (cons Premises $premises) (cons Conclusions (cons $conclusion ()))))
      (BenchPLNBuildImplication $premises $conclusion)
      $type))

(= (BenchPLNSentencesFromAtoms () $sid) ())
(= (BenchPLNSentencesFromAtoms (cons $head $tail) $sid)
   (if (= $head (: $_prf $type (STV $s $c)))
      (let $pln-type (BenchPLNNormalizeType $type)
         (cons (Sentence ($pln-type (stv $s $c)) ($sid)) (BenchPLNSentencesFromAtoms $tail (+ $sid 1))))
      (BenchPLNSentencesFromAtoms $tail $sid)))

(= (BenchPLNKB $bench) (BenchPLNSentencesFromAtoms (BenchPLNAtoms $bench) 1))
