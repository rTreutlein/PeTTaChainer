!(import! &self benchgen_metta)

(= (BenchResetForwardAgenda) (change-state! fwd_agenda_kb (empty_heap)))

(= (BenchResetInferenceState)
   (progn
      (remove-all-atoms &kb)
      (remove-all-atoms &prem_index)
      (remove-all-atoms &ccls_index)
      (remove-all-atoms &rules)
      (BenchResetForwardAgenda)))

(=
   (BenchGenerateIsolated $bench
      $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len)
   (progn (BenchResetInferenceState)
      (BenchGenerate $bench
         (depth $depth)
         (width $width)
         (paths $paths)
         (noise-factor $noise-factor)
         (backward-ratio $backward-ratio)
         (backward-chain-len $backward-chain-len)
         (forward-chain-len $forward-chain-len))))

(= (BenchTargetProvedForward? $bench $path $steps)
   (let $_ (forward-chain $steps kb) (forward-has-derived? kb (BenchTarget $bench $path))))

(= (BenchTargetProvedBackward? $bench $path $steps)
   (not (== (collapse (query $steps kb (: $prf (BenchTarget $bench $path) $tv))) ())))

(= (BenchTimedTargetProvedForwardOnly $bench $path $steps)
   (let*
      (($t0 (current-time))
        ($ok (BenchTargetProvedForward? $bench $path $steps))
        ($t1 (current-time)))
      (forward $ok (seconds (- $t1 $t0)))))

(= (BenchTimedTargetProvedBackwardOnly $bench $path $steps)
   (let*
      (($t0 (current-time))
        ($ok (BenchTargetProvedBackward? $bench $path $steps))
        ($t1 (current-time)))
      (backward $ok (seconds (- $t1 $t0)))))

(= (BenchTimedTargetProvedForwardThenBackward $bench $path $forward-steps $backward-steps)
   (let*
      (($t0 (current-time))
        ($_fwd (forward-chain $forward-steps kb))
        ($ok (BenchTargetProvedBackward? $bench $path $backward-steps))
        ($t1 (current-time)))
      (forward_then_backward $ok (seconds (- $t1 $t0)))))

(= (BenchHalfSteps $steps) (max 1 (BenchIntDiv $steps 2)))

(=
   (BenchTimedForwardBackwardCompare $bench-forward
      $bench-forward-backward
      $bench-backward
      $path
      $depth
      $width
      $paths
      $noise-factor
      $backward-ratio
      $backward-chain-len
      $forward-chain-len
      $forward-steps
      $backward-steps)
   (let*
      (($_g1
           (BenchGenerateIsolated $bench-forward
              $depth
              $width
              $paths
              $noise-factor
              $backward-ratio
              $backward-chain-len
              $forward-chain-len))
        ($r1 (BenchTimedTargetProvedForwardOnly $bench-forward $path $forward-steps))
        ($_g2
           (BenchGenerateIsolated $bench-forward-backward
              $depth
              $width
              $paths
              $noise-factor
              $backward-ratio
              $backward-chain-len
              $forward-chain-len))
        ($forward-mix-steps (BenchHalfSteps $forward-steps))
        ($backward-mix-steps (BenchHalfSteps $backward-steps))
        ($r2
           (BenchTimedTargetProvedForwardThenBackward $bench-forward-backward
              $path
              $forward-mix-steps
              $backward-mix-steps))
        ($_g3
           (BenchGenerateIsolated $bench-backward
              $depth
              $width
              $paths
              $noise-factor
              $backward-ratio
              $backward-chain-len
              $forward-chain-len))
        ($r3 (BenchTimedTargetProvedBackwardOnly $bench-backward $path $backward-steps)))
      ($r1 $r2 $r3)))
