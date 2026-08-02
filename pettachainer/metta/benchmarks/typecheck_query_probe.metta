; Bypasses compileadd by inserting one canonical fact directly, isolating query
; execution from source compilation. This file deliberately avoids the
; typecheck-v2-only determinism syntax so the same source runs on master.
; External /usr/bin/time measures the complete process separately.
!(import! &self ../petta_chainer)

(: current-time (-[det]-> Number))

!(chainer-add-atom &kb
   ((TypecheckPerfFact value)
      (typecheckPerfQueryKb MAIN Nil)
      typecheck-perf-proof
      (STV 1.0 1.0)))

!(let*
   (($start (current-time))
    ($results
       (collapse
          (query 20 typecheckPerfQueryKb
             (: $_proof (TypecheckPerfFact value) $_tv))))
    ($finish (current-time)))
   (println!
      (TYPECHECK_QUERY_RESULT
         (length $results)
         SECONDS
         (- $finish $start))))
