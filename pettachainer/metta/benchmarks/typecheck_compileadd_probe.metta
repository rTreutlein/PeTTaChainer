; Measures one compileadd after petta_chainer has loaded. External /usr/bin/time
; measures the complete process separately.
!(import! &self ../petta_chainer)

(: current-time (-[det]-> Number))

!(let*
   (($start (current-time))
    ($_result
       (collapse
          (compileadd typecheckPerfCompileKb
             (: typecheck-perf-fact
                (Inheritance typecheck-perf-a typecheck-perf-b)
                (STV 1.0 0.9)))))
    ($finish (current-time)))
   (println! (TYPECHECK_COMPILEADD_SECONDS (- $finish $start))))
