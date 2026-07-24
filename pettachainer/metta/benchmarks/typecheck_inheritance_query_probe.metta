; Measures a representative higher-order Inheritance query after compiling four
; source facts. This file deliberately uses syntax accepted by both runtimes.
!(import! &self petta_chainer)

(: current-time (-> Number))

!(compileadd typecheckPerfInheritanceKb
   (: typecheck-perf-i1 (Inheritance a Bird) (STV 1.0 0.9)))
!(compileadd typecheckPerfInheritanceKb
   (: typecheck-perf-i2 (Inheritance a Flier) (STV 1.0 0.9)))
!(compileadd typecheckPerfInheritanceKb
   (: typecheck-perf-i3 (Inheritance b Bird) (STV 1.0 0.9)))
!(compileadd typecheckPerfInheritanceKb
   (: typecheck-perf-i4 (Inheritance b Flier) (STV 1.0 0.9)))

!(let*
   (($start (current-time))
    ($results
       (collapse
          (query 80 typecheckPerfInheritanceKb
             (: $_proof (Inheritance Bird Flier) $_tv))))
    ($finish (current-time)))
   (println!
      (TYPECHECK_INHERITANCE_QUERY_RESULT
         (length $results)
         SECONDS
         (- $finish $start))))
