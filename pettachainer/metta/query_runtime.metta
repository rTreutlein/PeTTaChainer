;; Public query orchestration sits above the backward chainer. Keeping these
;; wrappers out of compiled_query_runtime lets compilation/storage remain a
;; foundational dependency of both chainers.

(: append-annotated-statements
   (-[det]-> (List AnnotatedStatement) (List AnnotatedStatement)
       (List AnnotatedStatement)))
(= (append-annotated-statements () $right) $right)
(= (append-annotated-statements
      (cons $statement $rest) $right)
   (cons $statement
      (append-annotated-statements $rest $right)))

(: pretty-result-list
   (-[det]-> Expression (List AnnotatedStatement)))
(= (pretty-result-list $result)
   ;; pretty is semidet, so this list contains at most one value. Keep the
   ;; explicit boundary check local and constant-sized.
   (let $raw-results
      (collapse (pretty $result))
      (the (List AnnotatedStatement) $raw-results)))

(: pretty-results
   (-[det]-> (List Expression) (List AnnotatedStatement)))
(= (pretty-results ()) ())
(= (pretty-results (cons $result $rest))
   (let*
      (($head-results (pretty-result-list $result))
       ($rest-results (pretty-results $rest)))
      (append-annotated-statements
         $head-results $rest-results)))

(: externalize-results
   (-[nondet]-> (List RuntimeResult) (List Expression)))
(= (externalize-results ()) ())
(= (externalize-results (cons $result $rest))
   (cons
      (externalize-proof-structure $result)
      (externalize-results $rest)))

(: run-compiled-query
   (-[nondet]-> Number CompiledQuery (List AnnotatedStatement)))
(= (run-compiled-query $steps (compiled-query $goal $adds))
   (if (or (is-var $goal) (is-var $adds))
      (empty)
      (let*
         (($_clear-temp-before (clear-temp-query-adds))
          ($_
             (collapse
                (once (inject-compiled-adds $adds))))
          ($results (chainer $steps $goal))
          ($externalized (externalize-results $results))
          ($pres (pretty-results $externalized))
          ($_clear-temp-after (clear-temp-query-adds)))
         $pres)))

(: run-compiled-query-materialize
   (-[nondet]-> Number CompiledQuery (List AnnotatedStatement)))
(= (run-compiled-query-materialize $steps (compiled-query $goal $adds))
   (if (or (is-var $goal) (is-var $adds))
      (empty)
      (let*
         (($_clear-temp-before (clear-temp-query-adds))
          ($_
             (collapse
                (once (inject-compiled-adds $adds))))
          ($results
             (chainer-materialize $steps $goal))
          ($externalized (externalize-results $results))
          ($pres (pretty-results $externalized))
          ($_clear-temp-after (clear-temp-query-adds)))
         $pres)))

(: query
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(= (query $steps $kb $stmt)
   (let*
      (($compiled-queries
          (collapse (mm2compileQuery $kb $stmt)))
       ($pres
          (fold-flat append-annotated-statements ()
             (map-flat-nondet
                (run-compiled-query $steps)
                $compiled-queries))))
      (superpose $pres)))

(: query-materialize
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(= (query-materialize $steps $kb $stmt)
   (let*
      (($compiled-queries
          (collapse (mm2compileQuery $kb $stmt)))
       ($pres
          (fold-flat append-annotated-statements ()
             (map-flat-nondet
                (run-compiled-query-materialize $steps)
                $compiled-queries))))
      (superpose $pres)))
