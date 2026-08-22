;; Internal compiler assembly. Each imported module owns one compilation phase;
;; only bootstrap imports this file.
!(import! &self ../../../third_party/metta_lowering/metta/source_lowering)
!(import! &self rules)
!(import! &self ../../../third_party/metta_lowering/metta/runtime_encoding)
!(import! &self query_lowering)

(: mm2compile
   (-[nondet]-> KB AnnotatedStatement  RuntimeAddition))
(= (mm2compile $kb $stmt)
   (let $compiled (compile_ $kb $stmt)
      (mm2stmt $compiled)))

;; MM2 query entry point. Compound queries with computed/nested children take
;; the temporary-rule route; all other statements translate the canonical plan.
(: mm2compileQuery (-[nondet]-> KB AnnotatedStatement  CompiledQuery))
(= (mm2compileQuery $kb $stmt)
         (if (and-then (= $stmt (: $prf $type $tv)) (query-needs-temp-rule? (the Statement $type)))
             (compiled-query
                (brand CompiledQueryGoal
                   (internalize-proof-structure
                      (: (kbctx $kb) $prf $type $tv)))
                (map-flat internalize-runtime-addition
                   (collapse (mm2compile $kb (compound-query-temp-stmt $stmt)))))
            (let (compilation-plan $goal $adds) (compileQuery $kb $stmt)
               (compiled-query
                  (brand CompiledQueryGoal
                     (internalize-proof-structure $goal))
                  (map-flat internalize-runtime-addition
                     (compiled-adds-mm2stmts $adds))))))
