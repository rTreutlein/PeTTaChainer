;; Internal compiler assembly. Each imported module owns one compilation phase;
;; only bootstrap imports this file.
!(import! &self source_lowering)
!(import! &self rules)
!(import! &self runtime_encoding)
!(import! &self query_lowering)

(: mm2compile (-[nondet]-> KB AnnotatedStatement RuntimeAddition))
(= (mm2compile $kb $stmt) (let $compiled (compile_ $kb $stmt) (mm2stmt $compiled)))

;; MM2 query entry point. A compound root reads its key, whose producers the
;; chainer installs. An And root always asks for an STV, including stored
;; answers.
(: mm2compileQuery (-[nondet]-> KB AnnotatedStatement  CompiledQuery))
(= (mm2compileQuery $kb (: $prf $type $requested-tv))
   (if (head-is? $requested-tv CTV) (empty)
      (let (compilation-plan $goal $adds)
           (compileQuery $kb (: $prf $type (if (head-is? $type And) (statement-query-tv $requested-tv) $requested-tv)))
         (compiled-query
            (brand CompiledQueryGoal
               (if (head-is? $goal CPU)
                  (internalize-proof-structure-any $goal)
                  (internalize-proof-structure $goal)))
            (map-flat mm2stmt $adds)))))
