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
   (-[det]-> Atom (List AnnotatedStatement)))
(= (pretty-result-list $result)
   ;; pretty is semidet, so this list contains at most one value. Its declared
   ;; result now propagates through collapse without a boundary ascription.
   (let $raw-results
      (collapse (pretty $result))
      $raw-results))

(: pretty-results
   (-[det]-> (List Atom) (List AnnotatedStatement)))
(= (pretty-results ()) ())
(= (pretty-results (cons $result $rest))
   (let*
      (($head-results (pretty-result-list $result))
       ($rest-results (pretty-results $rest)))
      (append-annotated-statements
         $head-results $rest-results)))

(: externalize-results
   (-[nondet]-> (List RuntimeResult) (List Atom)))
(= (externalize-results ()) ())
(= (externalize-results (cons $result $rest))
   (cons
      (externalize-proof-structure $result)
      (externalize-results $rest)))

(: IndexedQuery Type)
(: indexed-query (-[det]-> Number AnnotatedStatement IndexedQuery))
(: IndexedCompiledQuery Type)
(: indexed-compiled-query
   (-[det]-> Number CompiledQuery IndexedCompiledQuery))
(: IndexedRuntimeResults Type)
(: indexed-runtime-results
   (-[det]-> Number (List RuntimeResult) IndexedRuntimeResults))

(: append-runtime-additions
   (-[det]-> (List RuntimeAddition) (List RuntimeAddition)
       (List RuntimeAddition)))
(= (append-runtime-additions () $right) $right)
(= (append-runtime-additions (cons $head $tail) $right)
   (cons $head (append-runtime-additions $tail $right)))

(: append-indexed-compiled-queries
   (-[det]-> (List IndexedCompiledQuery) (List IndexedCompiledQuery)
       (List IndexedCompiledQuery)))
(= (append-indexed-compiled-queries () $right) $right)
(= (append-indexed-compiled-queries (cons $head $tail) $right)
   (cons $head
      (append-indexed-compiled-queries $tail $right)))

(: append-query-batch-results
   (-[det]-> (List QueryBatchResult) (List QueryBatchResult)
       (List QueryBatchResult)))
(= (append-query-batch-results () $right) $right)
(= (append-query-batch-results (cons $head $tail) $right)
   (cons $head (append-query-batch-results $tail $right)))

(: index-queries-from
   (-[det]-> Number (List AnnotatedStatement) (List IndexedQuery)))
(= (index-queries-from $_index ()) ())
(= (index-queries-from $index (cons $statement $rest))
   (cons
      (indexed-query $index $statement)
      (index-queries-from (+ $index 1) $rest)))

(: compile-indexed-query
   (-[nondet]-> KB IndexedQuery (List IndexedCompiledQuery)))
(= (compile-indexed-query $kb (indexed-query $index $statement))
   (let*
      (($statement-copy (copy_term $statement))
       ($materialized
          (the AnnotatedStatement
             (materialize-stmt-lambdas $statement-copy)))
       ($compiled (collapse (mm2compileQuery $kb $materialized))))
      (map-flat
         (|-> ((compiled-query $goal $adds))
            (if (or (is-var $goal) (is-var $adds))
               (empty)
               (indexed-compiled-query $index
                  (compiled-query $goal $adds))))
         $compiled)))

(: attach-indexed-runtime-results
   (-[det]-> (List IndexedCompiledQuery)
       (List (List RuntimeResult))
       (List IndexedRuntimeResults)))
(= (attach-indexed-runtime-results () ()) ())
(= (attach-indexed-runtime-results
      (cons (indexed-compiled-query $index $_query) $queries)
      (cons $results $rest-results))
   (cons
      (indexed-runtime-results $index $results)
      (attach-indexed-runtime-results $queries $rest-results)))

(: indexed-query-result-rows
   (-[nondet]-> IndexedRuntimeResults (List QueryBatchResult)))
(= (indexed-query-result-rows
      (indexed-runtime-results $index $results))
   (map-flat
      (|-> ($answer) (query-result $index $answer))
      (pretty-results (externalize-results $results))))

(: run-compiled-query-many
   (-[nondet]-> Number (List IndexedCompiledQuery)
       Bool QueryBatchResult))
(= (run-compiled-query-many
      $steps $compiled-queries $materialize?)
   (let*
      (($_clear-temp-before (clear-temp-query-adds))
       ($adds
          (list_to_set
             (foldr-flat append-runtime-additions ()
                (map-flat
                   (|-> ((indexed-compiled-query $_index
                            (compiled-query $_goal $query-adds)))
                      $query-adds)
                   $compiled-queries))))
       ($_inject
          (collapse (once (inject-compiled-adds $adds))))
       ($goals
          (map-flat
             (|-> ((indexed-compiled-query $_index
                      (compiled-query $goal $_adds)))
                (typed-runtime-premise $goal))
             $compiled-queries))
       ($runtime-results
          (if $materialize?
             (chainer-many-materialize $steps $goals)
             (chainer-many $steps $goals)))
       ($indexed-results
          (attach-indexed-runtime-results
             $compiled-queries $runtime-results))
       ($rows
          (foldr-flat append-query-batch-results ()
             (map-flat
                indexed-query-result-rows
                $indexed-results)))
       ($_clear-temp-after (clear-temp-query-adds)))
      (superpose $rows)))

(: query-many-mode
   (-[nondet]-> Number KB (List AnnotatedStatement) Bool
       QueryBatchResult))
(= (query-many-mode $steps $kb $statements $materialize?)
   (let*
      (($indexed (index-queries-from 0 $statements))
       ($compiled
          (foldr-flat append-indexed-compiled-queries ()
             (map-flat
                (compile-indexed-query $kb)
                $indexed))))
      (run-compiled-query-many
         $steps $compiled $materialize?)))

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
          ($results
             (chainer $steps (typed-runtime-premise $goal)))
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
             (chainer-materialize
                $steps (typed-runtime-premise $goal)))
          ($externalized (externalize-results $results))
          ($pres (pretty-results $externalized))
          ($_clear-temp-after (clear-temp-query-adds)))
         $pres)))

(: query
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(= (query $steps $kb $stmt)
   (let*
      (($stmt1
          (the AnnotatedStatement
             (materialize-stmt-lambdas $stmt)))
       ($compiled-queries
          (collapse (mm2compileQuery $kb $stmt1)))
       ($pres
          (fold-flat append-annotated-statements ()
             (map-flat
                (run-compiled-query $steps)
                $compiled-queries))))
      (superpose $pres)))

(: query-materialize
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(= (query-materialize $steps $kb $stmt)
   (let*
      (($stmt1
          (the AnnotatedStatement
             (materialize-stmt-lambdas $stmt)))
       ($compiled-queries
          (collapse (mm2compileQuery $kb $stmt1)))
       ($pres
          (fold-flat append-annotated-statements ()
             (map-flat
                (run-compiled-query-materialize $steps)
                $compiled-queries))))
      (superpose $pres)))

(: query-many
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many $steps $kb $statements)
   (query-many-mode $steps $kb $statements false))

(: query-many-materialize
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many-materialize $steps $kb $statements)
   (query-many-mode $steps $kb $statements true))
