!(import! &self benchgen_metta)

!(git-import! "https://github.com/trueagi-io/PLN.git")

!(import! &self (library PLN lib_pln))

(= (BenchTargetProvedPLN? $bench $path $steps)
   (not (== (PLN.Query (BenchPLNKB $bench) (BenchTarget $bench $path) $steps) ())))

(= (BenchTargetProvedCompare $bench $path $steps)
   (let*
      (($ours (BenchTargetProved? $bench $path $steps))
        ($lib (BenchTargetProvedPLN? $bench $path $steps)))
      ((ours $ours) (lib_pln $lib))))

(= (BenchTimedTargetProvedCompare $bench $path $steps)
   (let*
      (($t0 (current-time))
        ($ours (BenchTargetProved? $bench $path $steps))
        ($t1 (current-time))
        ($lib (BenchTargetProvedPLN? $bench $path $steps))
        ($t2 (current-time)))
      ((ours $ours (seconds (- $t1 $t0))) (lib_pln $lib (seconds (- $t2 $t1)))
         (total (seconds (- $t2 $t0))))))
