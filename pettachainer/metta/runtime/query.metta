;; Public query orchestration sits above the backward chainer. Keeping this
;; boundary out of knowledge_store lets compilation/storage remain a
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

;; One plan is one execution group. The root list preserves source identity,
;; compiler-alternative order, and duplicates; additions are already in their
;; final installation order for that group.
(: QueryExecutionPlan Type)
(: query-execution-plan
   (-[det]-> (List (Number CompiledQueryGoal))
       (List RuntimeAddition) QueryExecutionPlan))

(: append-runtime-additions
   (-[det]-> (List RuntimeAddition) (List RuntimeAddition)
       (List RuntimeAddition)))
(= (append-runtime-additions () $right) $right)
(= (append-runtime-additions (cons $head $tail) $right)
   (cons $head (append-runtime-additions $tail $right)))

(: append-query-plan-roots
   (-[det]-> (List (Number CompiledQueryGoal))
       (List (Number CompiledQueryGoal))
       (List (Number CompiledQueryGoal))))
(= (append-query-plan-roots () $right) $right)
(= (append-query-plan-roots (cons $head $tail) $right)
   (cons $head (append-query-plan-roots $tail $right)))

(: merge-query-execution-plans
   (-[det]-> QueryExecutionPlan QueryExecutionPlan QueryExecutionPlan))
(= (merge-query-execution-plans
      (query-execution-plan $left-roots $left-adds)
      (query-execution-plan $right-roots $right-adds))
   (query-execution-plan
      (append-query-plan-roots $left-roots $right-roots)
      (append-runtime-additions $left-adds $right-adds)))

(: compiled-query-execution-plan
   (-[nondet]-> Number CompiledQuery QueryExecutionPlan))
(= (compiled-query-execution-plan
      $key (compiled-query $goal $adds))
   (if (or (is-var $goal) (is-var $adds))
      (empty)
      (query-execution-plan (($key $goal)) $adds)))

;; Each source statement is copied before compilation so variables cannot
;; become shared between roots in a batch. Compiler alternatives remain in
;; compiler order and repeated roots remain represented separately.
(: prepare-query-many-plan
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryExecutionPlan))
(= (prepare-query-many-plan $_key $_kb ())
   (query-execution-plan () ()))
(= (prepare-query-many-plan $key $kb (cons $statement $rest))
   (let*
      (($statement-copy (copy_term $statement))
       ($materialized
          (the AnnotatedStatement
             (materialize-stmt-lambdas $statement-copy)))
       ($compiled (collapse (mm2compileQuery $kb $materialized)))
       ($statement-plan
          (foldr-flat merge-query-execution-plans
             (query-execution-plan () ())
             (map-flat
                (compiled-query-execution-plan $key)
                $compiled)))
       ($rest-plan
          (prepare-query-many-plan (+ $key 1) $kb $rest)))
      (merge-query-execution-plans $statement-plan $rest-plan)))

(: append-keyed-query-results
   (-[det]-> Number (List AnnotatedStatement)
       (List (Number AnnotatedStatement))
       (List (Number AnnotatedStatement))))
(= (append-keyed-query-results $_key () $right) $right)
(= (append-keyed-query-results
      $key (cons $answer $rest) $right)
   (cons ($key $answer)
      (append-keyed-query-results $key $rest $right)))

(: present-query-plan-results
   (-[nondet]-> (List (Number CompiledQueryGoal))
       (List (List RuntimeResult))
       (List (Number AnnotatedStatement))))
(= (present-query-plan-results () ()) ())
(= (present-query-plan-results
      (cons ($key $_goal) $roots)
      (cons $results $rest-results))
   (append-keyed-query-results
      $key
      (pretty-results (externalize-results $results))
      (present-query-plan-results $roots $rest-results)))

(: query-plan-runtime-goal
   (-[nondet]-> (Number CompiledQueryGoal)
       (| Goal (Statement KBContext Proof TV))))
(= (query-plan-runtime-goal ($_key $goal))
   (typed-runtime-premise $goal))

;; Temporary additions stay installed through proof externalization and pretty
;; printing. Direct chainer entrypoints intentionally do not own this bracket.
(: run-query-execution-plan
   (-[nondet]-> Number QueryExecutionPlan Bool
       (List (Number AnnotatedStatement))))
(= (run-query-execution-plan
      $steps (query-execution-plan $roots $adds) $materialize?)
   (let*
      (($_clear-temp-before (clear-temp-query-adds))
       ($_inject
          (collapse (once (inject-compiled-adds $adds))))
       ($goals
          (map-flat
             query-plan-runtime-goal
             $roots))
       ($runtime-results
          (if $materialize?
             (chainer-many-materialize $steps $goals)
             (chainer-many $steps $goals)))
       ($rows
          (present-query-plan-results $roots $runtime-results))
       ($_clear-temp-after (clear-temp-query-adds)))
      $rows))

(: keyed-query-answers
   (-[det]-> (List (Number AnnotatedStatement))
       (List AnnotatedStatement)))
(= (keyed-query-answers ()) ())
(= (keyed-query-answers (cons ($_key $answer) $rest))
   (cons $answer (keyed-query-answers $rest)))

(: keyed-query-batch-results
   (-[det]-> (List (Number AnnotatedStatement))
       (List QueryBatchResult)))
(= (keyed-query-batch-results ()) ())
(= (keyed-query-batch-results (cons ($key $answer) $rest))
   (cons (query-result $key $answer)
      (keyed-query-batch-results $rest)))

(: query-mode
   (-[nondet]-> Number KB AnnotatedStatement Bool AnnotatedStatement))
(= (query-mode $steps $kb $statement $materialize?)
   (let*
      (($materialized
          (the AnnotatedStatement
             (materialize-stmt-lambdas $statement)))
       ($compiled-queries
          (collapse (mm2compileQuery $kb $materialized)))
       ($answers
          (fold-flat append-annotated-statements ()
             (map-flat
                (|-> ($compiled-query)
                   (keyed-query-answers
                      (run-query-execution-plan
                         $steps
                         (compiled-query-execution-plan
                            0 $compiled-query)
                         $materialize?)))
                $compiled-queries))))
      (superpose $answers)))

(: query-many-mode
   (-[nondet]-> Number KB (List AnnotatedStatement) Bool
       QueryBatchResult))
(= (query-many-mode $steps $kb $statements $materialize?)
   (let*
      (($plan0 (prepare-query-many-plan 0 $kb $statements))
       ((query-execution-plan $roots $adds) $plan0)
       ($plan
          (query-execution-plan $roots (list_to_set $adds)))
       ($rows
          (keyed-query-batch-results
             (run-query-execution-plan
                $steps $plan $materialize?))))
      (superpose $rows)))

(: query
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(= (query $steps $kb $statement)
   (query-mode $steps $kb $statement false))

(: query-materialize
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(= (query-materialize $steps $kb $statement)
   (query-mode $steps $kb $statement true))

(: query-many
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many $steps $kb $statements)
   (query-many-mode $steps $kb $statements false))

(: query-many-materialize
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many-materialize $steps $kb $statements)
   (query-many-mode $steps $kb $statements true))
