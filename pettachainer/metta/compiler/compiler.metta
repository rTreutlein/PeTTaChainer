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
;; the temporary-rule route; implication-bearing Ands use child queries in the
;; canonical plan. An And root always asks for an STV, including stored answers.
(: mm2compileQuery (-[nondet]-> KB AnnotatedStatement  CompiledQuery))
(= (mm2compileQuery $kb (: $prf $type $requested-tv))
   (if (head-is? $requested-tv CTV) (empty)
      (let*
         (($tv (if (head-is? $type And)
                  (statement-query-tv $requested-tv) $requested-tv))
          ($stmt (: $prf $type $tv)))
         (if (if (head-is-member? $type (And Or LikelierThan))
                (if (if (head-is? $type And) (conjunction-query-needs-lowering? $type) false)
                   false
                   (compound-direct-query-bundle?
                      (statement-children (cdr-atom $type))))
                false)
            (compiled-query
               (brand CompiledQueryGoal
                  (internalize-proof-structure
                     (: (kbctx $kb) $prf $type $tv)))
               (collapse (mm2compile $kb (compound-query-temp-stmt $stmt))))
            (let (compilation-plan $goal $adds) (compileQuery $kb $stmt)
               (compiled-query
                  (brand CompiledQueryGoal
                     (if (head-is? $goal CPU)
                        (internalize-proof-structure-any $goal)
                        (internalize-proof-structure $goal)))
                  (map-flat mm2stmt $adds)))))))
