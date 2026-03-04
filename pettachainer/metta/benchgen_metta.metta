!(import! &self petta_chainer)

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

(= (BenchTrackPLNAtom $bench $tag $stmt)
   (BenchCompileAdd false (: (bench-pln-atom $bench $tag) (BenchPLNAtom $bench $stmt) (STV 1.0 1.0))))

(= (BenchCompileAddTracked $bench $print-this-stmt $tag $stmt)
   (let $_compiled (BenchCompileAdd $print-this-stmt $stmt) (BenchTrackPLNAtom $bench $tag $stmt)))

(= (BenchAddBaseFact $bench $path $idx $print-before-compile)
   (let $conf (BenchGlobalConf)
      (let $stmt (: (bench-base-fact $bench $path $idx) (BenchFact $bench $path $idx) (STV 1.0 $conf))
         (let $_ (BenchCompileAddTracked $bench $print-before-compile (base-fact $path $idx) $stmt) done))))

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
        ($conf (BenchGlobalConf))
        ($stmt (: (bench-main-rule $bench $path $level $idx) $rule-type (STV 1.0 $conf))))
      (let $_meta
         (BenchCompileAdd false
            (: (bench-main-meta $bench $path $level $idx) (BenchMainRule $bench $path $level $idx $width) (STV 1.0 1.0)))
         (let $_prem-meta
            (BenchCompileAdd false
               (: (bench-main-premise-meta $bench $path $level $idx) (BenchMainPremiseCount $bench $path $level $idx $width) (STV 1.0 1.0)))
            (let $_conf-meta
               (BenchCompileAdd false
                  (: (bench-main-conf $bench $path $level $idx) (BenchMainConf $bench $path $level $idx $conf) (STV 1.0 1.0)))
               (let $_rule
                  (BenchCompileAddTracked $bench $print-before-compile (main-rule $path $level $idx) $stmt)
                  done))))))

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
      (let $node-count (BenchPow $width (- $depth $level))
         (let $_rules
            (BenchGenerateLevelRulesRemaining $bench
               $path
               $level
               1
               $node-count
               $depth
               $width
               $print-before-compile)
            (BenchGenerateLevelsLoop $bench
               $path
               (+ $level 1)
               $depth
               $width
               $print-before-compile)))))

(= (BenchGeneratePathTree $bench $path $depth $width $print-before-compile)
   (let $_facts (BenchGenerateBaseFacts $bench $path $depth $width $print-before-compile)
      (BenchGenerateLevelsLoop $bench
         $path
         1
         $depth
         $width
         $print-before-compile)))

(= (BenchGeneratePathsRemaining $bench $path $remaining-paths $depth $width $print-before-compile)
   (if (== $remaining-paths 0) done
      (let $_path-tree (BenchGeneratePathTree $bench $path $depth $width $print-before-compile)
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

(= (BenchAddBackwardHeadRule $bench $noise-idx $paths $print-before-compile)
   (let*
      (($path (BenchCycle1 $noise-idx $paths))
        ($rule-type
           (Implication (cons Premises (cons (NoiseBackStep $bench $noise-idx 1) ()))
              (cons Conclusions (cons (BenchTarget $bench $path) ()))))
        ($conf (BenchGlobalConf))
        ($stmt (: (bench-noise-back-head $bench $noise-idx) $rule-type (STV 1.0 $conf))))
      (let $_rule (BenchCompileAddTracked $bench $print-before-compile (noise-back-head $noise-idx) $stmt)
         (BenchCompileAdd false
            (: (bench-noise-back-meta $bench $noise-idx 0) (BenchNoiseBackRule $bench $noise-idx 0) (STV 1.0 1.0))))))

(= (BenchAddBackwardBlockedHeadRule $bench $noise-idx $paths $print-before-compile)
   (let*
      (($path (BenchCycle1 $noise-idx $paths))
        ($rule-type
           (Implication (cons Premises (cons (NoiseBlocker $bench $noise-idx) ()))
              (cons Conclusions (cons (BenchTarget $bench $path) ()))))
        ($conf (BenchGlobalConf))
        ($stmt (: (bench-noise-back-head $bench $noise-idx) $rule-type (STV 1.0 $conf))))
      (let $_rule (BenchCompileAddTracked $bench $print-before-compile (noise-back-head $noise-idx) $stmt)
         (BenchCompileAdd false
            (: (bench-noise-back-meta $bench $noise-idx 0) (BenchNoiseBackRule $bench $noise-idx 0) (STV 1.0 1.0))))))

(= (BenchAddBackwardTailRules $bench $noise-idx $step $last-step $print-before-compile)
   (if (> $step $last-step) done
      (let $conf (BenchGlobalConf)
         (if (== $step $last-step)
            (let $rule-type
               (Implication (cons Premises (cons (NoiseBlocker $bench $noise-idx) ()))
                  (cons Conclusions (cons (NoiseBackStep $bench $noise-idx $step) ())))
               (let $stmt (: (bench-noise-back-rule $bench $noise-idx $step) $rule-type (STV 1.0 $conf))
                  (let $_rule
                     (BenchCompileAddTracked $bench
                        $print-before-compile
                        (noise-back-rule $noise-idx $step)
                        $stmt)
                     (BenchCompileAdd false
                        (: (bench-noise-back-meta $bench $noise-idx $step) (BenchNoiseBackRule $bench $noise-idx $step) (STV 1.0 1.0))))))
            (let $rule-type
               (Implication (cons Premises (cons (NoiseBackStep $bench $noise-idx (+ $step 1)) ()))
                  (cons Conclusions (cons (NoiseBackStep $bench $noise-idx $step) ())))
               (let $stmt (: (bench-noise-back-rule $bench $noise-idx $step) $rule-type (STV 1.0 $conf))
                  (let $_rule
                     (BenchCompileAddTracked $bench
                        $print-before-compile
                        (noise-back-rule $noise-idx $step)
                        $stmt)
                     (let $_meta
                        (BenchCompileAdd false
                           (: (bench-noise-back-meta $bench $noise-idx $step) (BenchNoiseBackRule $bench $noise-idx $step) (STV 1.0 1.0)))
                        (BenchAddBackwardTailRules $bench
                           $noise-idx
                           (+ $step 1)
                           $last-step
                           $print-before-compile)))))))))

(= (BenchGenerateBackwardChain $bench $noise-idx $chain-len $paths $print-before-compile)
   (if (== $chain-len 1) (BenchAddBackwardBlockedHeadRule $bench $noise-idx $paths $print-before-compile)
      (let $_head (BenchAddBackwardHeadRule $bench $noise-idx $paths $print-before-compile)
         (BenchAddBackwardTailRules $bench
            $noise-idx
            1
            (- $chain-len 1)
            $print-before-compile))))

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
      (let $conf (BenchGlobalConf)
         (if (== $step 1)
            (let*
               (($premise (BenchForwardPremiseFact $bench $paths $depth $width $noise-idx))
                 ($conclusion
                    (if (== $chain-len 1) (NoiseDeadEnd $bench $noise-idx) (NoiseForward $bench $noise-idx 1)))
                 ($rule-type
                    (Implication (cons Premises (cons $premise ())) (cons Conclusions (cons $conclusion ()))))
                 ($stmt (: (bench-noise-forward-rule $bench $noise-idx $step) $rule-type (STV 1.0 $conf))))
               (let $_rule
                  (BenchCompileAddTracked $bench
                     $print-before-compile
                     (noise-forward-rule $noise-idx $step)
                     $stmt)
                  (let $_meta
                     (BenchCompileAdd false
                        (: (bench-noise-forward-meta $bench $noise-idx $step) (BenchNoiseForwardRule $bench $noise-idx $step) (STV 1.0 1.0)))
                     (BenchAddForwardChainRulesRemaining $bench
                        $noise-idx
                        (+ $step 1)
                        $chain-len
                        $paths
                        $depth
                        $width
                        $print-before-compile))))
            (let*
               (($premise (NoiseForward $bench $noise-idx (- $step 1)))
                 ($conclusion
                    (if (== $step $chain-len) (NoiseDeadEnd $bench $noise-idx)
                       (NoiseForward $bench $noise-idx $step)))
                 ($rule-type
                    (Implication (cons Premises (cons $premise ())) (cons Conclusions (cons $conclusion ()))))
                 ($stmt (: (bench-noise-forward-rule $bench $noise-idx $step) $rule-type (STV 1.0 $conf))))
               (let $_rule
                  (BenchCompileAddTracked $bench
                     $print-before-compile
                     (noise-forward-rule $noise-idx $step)
                     $stmt)
                  (let $_meta
                     (BenchCompileAdd false
                        (: (bench-noise-forward-meta $bench $noise-idx $step) (BenchNoiseForwardRule $bench $noise-idx $step) (STV 1.0 1.0)))
                     (BenchAddForwardChainRulesRemaining $bench
                        $noise-idx
                        (+ $step 1)
                        $chain-len
                        $paths
                        $depth
                        $width
                        $print-before-compile))))))))

(=
   (BenchGenerateBackwardNoiseRemaining $bench
      $noise-idx
      $remaining-statements
      $chain-len
      $paths
      $print-before-compile)
   (if (== $remaining-statements 0) done
      (let*
         (($effective-len (if (< $chain-len 1) 1 $chain-len))
           ($span (BenchMin $remaining-statements $effective-len)))
         (let $_chain (BenchGenerateBackwardChain $bench $noise-idx $span $paths $print-before-compile)
            (BenchGenerateBackwardNoiseRemaining $bench
               (+ $noise-idx 1)
               (- $remaining-statements $span)
               $chain-len
               $paths
               $print-before-compile)))))

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
         (($effective-len (if (< $chain-len 1) 1 $chain-len))
           ($span (BenchMin $remaining-statements $effective-len)))
         (let $_chain
            (BenchAddForwardChainRulesRemaining $bench
               $noise-idx
               1
               $span
               $paths
               $depth
               $width
               $print-before-compile)
            (BenchGenerateForwardNoiseRemaining $bench
               (+ $noise-idx 1)
               (- $remaining-statements $span)
               $chain-len
               $paths
               $depth
               $width
               $print-before-compile)))))

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
      (let $_backward
         (BenchGenerateBackwardNoiseRemaining $bench
            1
            $backward-budget
            $backward-chain-len
            $paths
            $print-before-compile)
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
      (let $_spec
         (BenchCompileAdd $print-before-compile
            (: (bench-spec $bench)
               (BenchSpec $bench
                  $depth
                  $width
                  $paths
                  $noise-factor
                  $backward-ratio
                  $backward-chain-len
                  $forward-chain-len)
               (STV 1.0 1.0)))
         (let $_paths (BenchGeneratePaths $bench $paths $depth $width $print-before-compile)
            (let $_noise
               (BenchGenerateNoiseByFactor $bench
                  $depth
                  $width
                  $paths
                  $noise-factor
                  $backward-ratio
                  $backward-chain-len
                  $forward-chain-len
                  $print-before-compile)
               (BenchmarkGenerated $bench
                  $depth
                  $width
                  $paths
                  $noise-factor
                  $backward-ratio
                  $backward-chain-len
                  $forward-chain-len))))
      (BenchGenerateError invalid-params
         $bench
         $depth
         $width
         $paths
         $noise-factor
         $backward-ratio
         $backward-chain-len
         $forward-chain-len)))

(=
   (BenchGenerate $bench
      (depth $depth)
      (width $width)
      (paths $paths)
      (noise-factor $noise-factor)
      (backward-ratio $backward-ratio)
      (backward-chain-len $backward-chain-len)
      (forward-chain-len $forward-chain-len))
   (BenchGenerateCore $bench
      $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len
      false))
(=
   (BenchGenerate $bench
      (depth $depth)
      (widht $width)
      (paths $paths)
      (noise-factor $noise-factor)
      (backward-ratio $backward-ratio)
      (backward-chain-len $backward-chain-len)
      (forward-chain-len $forward-chain-len))
   (BenchGenerateCore $bench
      $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len
      false))

(=
   (BenchGenerateWithPrint $bench
      (depth $depth)
      (width $width)
      (paths $paths)
      (noise-factor $noise-factor)
      (backward-ratio $backward-ratio)
      (backward-chain-len $backward-chain-len)
      (forward-chain-len $forward-chain-len)
      (print $print-before-compile))
   (BenchGenerateCore $bench
      $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len
      $print-before-compile))
(=
   (BenchGenerateWithPrint $bench
      (depth $depth)
      (widht $width)
      (paths $paths)
      (noise-factor $noise-factor)
      (backward-ratio $backward-ratio)
      (backward-chain-len $backward-chain-len)
      (forward-chain-len $forward-chain-len)
      (print $print-before-compile))
   (BenchGenerateCore $bench
      $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len
      $print-before-compile))

(= (BenchMainRuleCount $bench)
   (BenchListCount
      (collapse
         (match (kbspace)
            ((BenchMainRule $bench $_path $_level $_idx $_width) $_kb
               (bench-main-meta $bench $_path $_level $_idx)
               $_tv)
            ok))))

(= (BenchBaseFactCount $bench)
   (BenchListCount
      (collapse
         (match (kbspace) ((BenchFact $bench $_path $_idx) $_kb (bench-base-fact $bench $_path $_idx) $_tv)
            ok))))

(= (BenchNoiseBackwardRuleCount $bench)
   (BenchListCount
      (collapse
         (match (kbspace)
            ((BenchNoiseBackRule $bench $_idx $_step) $_kb (bench-noise-back-meta $bench $_idx $_step) $_tv)
            ok))))

(= (BenchNoiseForwardRuleCount $bench)
   (BenchListCount
      (collapse
         (match (kbspace)
            ((BenchNoiseForwardRule $bench $_idx $_step) $_kb
               (bench-noise-forward-meta $bench $_idx $_step)
               $_tv)
            ok))))

(= (BenchTargetProved? $bench $path $steps)
   (not (== (collapse (query $steps kb (: $prf (BenchTarget $bench $path) $tv))) ())))

(= (BenchListAppend () $ys) $ys)
(= (BenchListAppend (cons $x $xs) $ys) (cons $x (BenchListAppend $xs $ys)))

(= (BenchPLNDepth $bench)
   (car-atom
      (collapse
         (match (kbspace)
            ((BenchSpec $bench $depth $_width $_paths $_noise $_backward $_backward-len $_forward-len) $_kb
               (bench-spec $bench)
               $_tv)
            $depth))))

(= (BenchPLNBaseAtoms $bench)
   (collapse
      (match (kbspace) ($type ($_kbid $_ctx $_vars) (bench-base-fact $bench $path $idx) $tv)
         (: (bench-base-fact $bench $path $idx) $type $tv))))

(= (BenchFirstOr $list $default) (if (== $list ()) $default (car-atom $list)))

(= (BenchMainConfValue $bench $path $level $idx)
   (BenchFirstOr
      (collapse
         (match (kbspace)
            ((BenchMainConf $bench $path $level $idx $conf) $_kb
               (bench-main-conf $bench $path $level $idx)
               $_tv)
            $conf))
      1.0))

(= (BenchPLNMainRuleAtoms $bench)
   (collapse
      (match (kbspace)
         ((BenchMainRule $bench $path $level $idx $width) $_kb
            (bench-main-meta $bench $path $level $idx)
            $_meta-tv)
         (let*
            (($depth (BenchPLNDepth $bench))
              ($premises (BenchRulePremises $bench $path $level $idx $width))
              ($conclusion (BenchRuleConclusion $bench $path $level $idx $depth))
              ($type (Implication (cons Premises $premises) (cons Conclusions (cons $conclusion ()))))
              ($conf (BenchMainConfValue $bench $path $level $idx))
              ($tv (STV 1.0 $conf)))
            (: (bench-main-rule $bench $path $level $idx) $type $tv)))))

(= (BenchPLNAtoms $bench)
   (collapse (match (kbspace) ((BenchPLNAtom $bench $stmt) $_kb (bench-pln-atom $bench $_tag) $_tv) $stmt)))

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
