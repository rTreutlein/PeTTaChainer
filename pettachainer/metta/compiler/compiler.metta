;; Internal compiler assembly. Each imported module owns one compilation phase;
;; only bootstrap imports this file.
!(import! &self source_lowering)
!(import! &self rules)
!(import! &self runtime_encoding)
!(import! &self query_lowering)

(: mm2compile
   (-[nondet]-> KB AnnotatedStatement  RuntimeAddition))
(= (mm2compile $kb $stmt)
   (let $compiled (compile_ $kb $stmt)
      (mm2stmt $compiled)))

;; MM2 query entry point. Compound queries with computed/nested children take
;; the temporary-rule route; all other statements use compileQuery and the
;; structural normalization above.
(: mm2compileQuery (-[nondet]-> KB AnnotatedStatement  CompiledQuery))
(= (mm2compileQuery $kb $stmt)
         (if (and-then (= $stmt (: $prf $type $tv)) (query-needs-temp-rule? (the Statement $type)))
             (compiled-query
                (brand CompiledQueryGoal
                   (internalize-proof-structure
                      (: (kbctx $kb) $prf $type $tv)))
                (map-flat compile-internalize-runtime-addition
                   (collapse (mm2compile $kb (compound-query-temp-stmt $stmt)))))
            (mm2compileQuery-from-compiled $kb $stmt (compileQuery $kb $stmt))))
