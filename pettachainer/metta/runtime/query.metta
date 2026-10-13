;; Public query orchestration sits above the backward chainer. Keeping this
;; boundary out of knowledge_store lets compilation/storage remain a
;; foundational dependency of both chainers.

;; pretty is semidet, so each collapse contains at most one value.
(: pretty-results
   (-[det]-> (List Atom) (List AnnotatedStatement)))
(= (pretty-results ()) ())
(= (pretty-results (cons $result $rest))
   (append-flat (collapse (pretty $result)) (pretty-results $rest)))

;; One plan is one execution group. The root list preserves source identity,
;; compiler-alternative order, and duplicates; additions are already in their
;; final installation order for that group.
(: QueryExecutionPlan Type)
(: query-execution-plan
   (-[det]-> (List (Number CompiledQueryGoal))
       (List RuntimeAddition) QueryExecutionPlan))

(: merge-query-execution-plans
   (-[det]-> QueryExecutionPlan QueryExecutionPlan QueryExecutionPlan))
(= (merge-query-execution-plans
      (query-execution-plan $left-roots $left-adds)
      (query-execution-plan $right-roots $right-adds))
   (query-execution-plan
      (append-flat $left-roots $right-roots)
      (append-flat $left-adds $right-adds)))

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

;; A chainer result's proof refers to stored proofs (sk-root-results);
;; expanding it prints each shared subproof once.
(: expand-result (-[det]-> RuntimeResult RuntimeResult))
(= (expand-result $result)
   (case $result (
      ((CPU $_fun $_args $_res) $result)
      (($type $kbctx $proof $tv)
         (brand RuntimeResult (data $type $kbctx (sk-full-proof (brand Proof $proof)) $tv))))))

(: expand-proof (-[nondet]-> Proof Proof))
(= (expand-proof $proof)
   (externalize-query-proof (sk-full-proof $proof)))

;; The public answer boundary never exposes packed rule storage, including
;; wildcard and RuleTruth reads. The skeleton and materialization keep the CTV.
(: public-query-result (-[det]-> RuntimeResult RuntimeResult))
(= (public-query-result $result)
   (case $result (
      ((CPU $_fun $_args $_res) $result)
      (($type $kbctx $proof $tv)
         (let $answer-tv
            (if (head-is? $tv CTV)
               (case (the TV $tv) (((CTV $pos $_neg) $pos) ($_other $tv))) $tv)
            (brand RuntimeResult (data $type $kbctx $proof $answer-tv)))))))

(: present-query-plan-results
   (-[nondet]-> Bool (List (Number CompiledQueryGoal))
       (List (List RuntimeResult))
       (List (Number AnnotatedStatement))))
(= (present-query-plan-results $_expand? () ()) ())
(= (present-query-plan-results $expand?
      (cons ($key $_goal) $roots)
      (cons $results $rest-results))
   (append-flat
      (map-flat (|-> ($answer) (data $key $answer))
         (pretty-results
            (map-flat externalize-proof-structure
               (map-flat public-query-result
                  (if $expand? (map-flat expand-result $results) $results)))))
      (present-query-plan-results $expand? $roots $rest-results)))

(: query-plan-runtime-goal
   (-[nondet]-> (Number CompiledQueryGoal)
       (| Goal (Statement KBContext Proof TV))))
(= (query-plan-runtime-goal ($_key $goal))
   (typed-runtime-premise $goal))

;; Temporary additions and Assuming contexts stay installed through proof
;; externalization and pretty printing. Direct chainer entrypoints
;; intentionally do not own this bracket.
(: run-query-execution-plan
   (-[nondet]-> Number QueryExecutionPlan Bool Bool
       (List (Number AnnotatedStatement))))
(= (run-query-execution-plan
      $steps (query-execution-plan $roots $adds) $materialize? $expand?)
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
          (present-query-plan-results $expand? $roots $runtime-results))
       ($_clear-temp-after (clear-temp-query-adds))
       ($_contexts (sk-clear-contexts!))
       ($_retired (sk-retire-searches!))
       ;; What the contexts' rows interned and stored is reached by nothing now.
       ($_collected (if (deps-gc-due?) (deps-gc! (sk-deps-roots)) true))
       ($_refs (stored-refs-gc-step!)))
      $rows))

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
          (fold-flat append-flat ()
             (map-flat
                (|-> ($compiled-query)
                   (map-flat snd
                      (run-query-execution-plan
                         $steps
                         (compiled-query-execution-plan
                            0 $compiled-query)
                         $materialize? true)))
                $compiled-queries))))
      (superpose $answers)))

(: query-many-mode
   (-[nondet]-> Number KB (List AnnotatedStatement) Bool Bool
       QueryBatchResult))
(= (query-many-mode $steps $kb $statements $materialize? $expand?)
   (let*
      (((query-execution-plan $roots $adds)
          (prepare-query-many-plan 0 $kb $statements))
       ($rows
          (map-flat
             (|-> ($row) (query-result (fst $row) (snd $row)))
             (run-query-execution-plan
                $steps
                (query-execution-plan $roots (list_to_set $adds))
                $materialize? $expand?))))
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
   (query-many-mode $steps $kb $statements false true))

;; As query-many, with each answer's proof left as references into the proof
;; store (expand-proof prints it in full).
(: query-many-refs
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many-refs $steps $kb $statements)
   (query-many-mode $steps $kb $statements false false))

(: query-many-materialize
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many-materialize $steps $kb $statements)
   (query-many-mode $steps $kb $statements true true))
