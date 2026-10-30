;; Public query orchestration sits above the backward chainer. Keeping this
;; boundary out of knowledge_store lets compilation/storage remain a
;; foundational dependency of both chainers.

;; A function call gives each answer fresh destructuring variables; placing
;; this let inside a lambda would capture the fields across the whole batch.
(: retain-query-proof! (-[det]-> (Number AnnotatedStatement) Bool))
(= (retain-query-proof! ($_index (: $proof $_type $_tv))) (add-atom &query_proofs ($proof)))

;; pretty is semidet, so each collapse contains at most one value.
(: pretty-results (-[det]-> (List Atom) (List AnnotatedStatement)))
(= (pretty-results ()) ())
(= (pretty-results (cons $result $rest))
   (append-flat (collapse (pretty $result)) (pretty-results $rest)))

;; One plan is one execution group. The root list preserves source identity,
;; the written statement and its canonical form (`member-canon`),
;; compiler-alternative order, and duplicates; additions
;; are already in their final installation order for that group.
(datatype QueryExecutionPlan
   (query-execution-plan (List (Number Statement AnnotatedStatement CompiledQueryGoal)) (List RuntimeAddition)))

(: merge-query-execution-plans (-[det]-> QueryExecutionPlan QueryExecutionPlan QueryExecutionPlan))
(= (merge-query-execution-plans
      (query-execution-plan $left-roots $left-adds)
      (query-execution-plan $right-roots $right-adds))
   (query-execution-plan
      (append-flat $left-roots $right-roots)
      (append-flat $left-adds $right-adds)))

(: compiled-query-execution-plan (-[nondet]-> Number Statement AnnotatedStatement CompiledQuery QueryExecutionPlan))
(= (compiled-query-execution-plan $key $written $canonical (compiled-query $goal $adds))
   (if (or (is-var $goal) (is-var $adds)) (empty) (query-execution-plan (($key $written $canonical $goal)) $adds)))

;; A query of (Not s) is a query of s, answered complemented once per written
;; negation: its root reads s's canonical key, so it answers wherever s does,
;; at budget zero from a stored or materialized value too. A query of
;; (ForAll params rule) is the judgment of its rule (#142). The root is of
;; the canonical statement, a written (Member x P) read as (P x) (#96).
(: query-root (-[det]-> AnnotatedStatement AnnotatedStatement))
(= (query-root (: $prf $type $tv))
   (if (head-is? $type Not)
      (let ($key $_odd) (canon $type) (: $key-proof $key $key-tv))
      (if (head-is? $type ForAll)
         (: $prf (brand Statement (car-atom (cdr-atom (cdr-atom $type)))) $tv)
         (: $prf $type $tv))))

;; A ForAll answer is its rule's answer under the written binder.
(: forall-result (-[semidet]-> Statement RuntimeResult RuntimeResult))
(= (forall-result $written ($type $kbctx $proof $tv))
   (let (ForAll $params $rule) (copy_term $written)
      (let $rule $type (brand RuntimeResult (data (ForAll $params $rule) $kbctx $proof $tv)))))

;; An answer of a written Member statement, in the written form; an open
;; class bound to an internal key answers nothing (member-shape).
(: member-step (-[det]-> Statement RuntimeResult (List RuntimeResult) (List RuntimeResult)))
(= (member-step $written $result $kept)
   (case $result (
      ((CPU $_fun $_args $_res) (cons $result $kept))
      (($type $kbctx $proof $tv)
         (case (collapse (member-shape $written $type)) (
            (() $kept)
            ((cons $shape $_none) (cons (brand RuntimeResult (data $shape $kbctx $proof $tv)) $kept))))))))

;; The public answers of a canonical root from those of its query root: each
;; negation complements the answer, negates its proof and wraps its public
;; statement, and the written truth-value pattern constrains the complemented
;; value; a ForAll answer is its rule's answer under the written binder. A
;; computation row answers no statement.
(: canonical-results (-[semidet]-> AnnotatedStatement (List RuntimeResult) (List RuntimeResult)))
(= (canonical-results (: $_prf $type $tv) $results)
   (if (head-is? $type Not)
      (negated-results $tv
         (canonical-results (: $_inner-proof (car-atom (cdr-atom $type)) $_inner-tv) $results))
      (if (head-is? $type ForAll) (map-semidet (forall-result $type) $results) $results)))

;; A written Member answers in its written form.
(: written-results (-[semidet]-> Statement AnnotatedStatement (List RuntimeResult) (List RuntimeResult)))
(= (written-results $written (: $prf $type $tv) $results)
   (let $answers (canonical-results (: $prf $type $tv) $results)
      (if (== $type $written) $answers (foldr-flat (member-step $written) () $answers))))

(: negated-step (-[det]-> Atom RuntimeResult (List RuntimeResult) (List RuntimeResult)))
(= (negated-step $tv $result $kept)
   (case $result (
      ((CPU $_fun $_args $_res) $kept)
      (($type $kbctx $proof $result-tv)
         (let $not-tv (NotFormula (the STVType $result-tv))
            (if (= (copy_term $tv) $not-tv)
               (cons (brand RuntimeResult (data (Not $type) $kbctx (negated $proof) $not-tv)) $kept)
               $kept))))))

;; The results arrive as a parameter: the determinism checker proves a fold
;; over a parameter list, not over a function result.
(: negated-results (-[det]-> Atom (List RuntimeResult) (List RuntimeResult)))
(= (negated-results $tv $results) (foldr-flat (negated-step $tv) () $results))

;; Each source statement is copied before compilation so variables cannot
;; become shared between roots in a batch. Compiler alternatives remain in
;; compiler order and repeated roots remain represented separately.
(: prepare-query-many-plan (-[nondet]-> Number KB (List AnnotatedStatement) QueryExecutionPlan))
(= (prepare-query-many-plan $_key $_kb ()) (query-execution-plan () ()))
(= (prepare-query-many-plan $key $kb (cons $statement $rest))
   (let*
      (($statement-copy (copy_term $statement))
       ($materialized (the AnnotatedStatement (materialize-stmt-lambdas $statement-copy)))
       ($_annotations (check-query-annotations! $materialized))
       ((: $root-proof $written $root-tv) $materialized)
       ($canonical-type (member-canon $written))
       ($canonical (: $root-proof $canonical-type $root-tv))
       ($compiled (collapse (mm2compileQuery $kb (query-root $canonical))))
       ($statement-plan
          (foldr-flat merge-query-execution-plans
             (query-execution-plan () ())
             (map-flat (compiled-query-execution-plan $key $written $canonical) $compiled)))
       ($rest-plan (prepare-query-many-plan (+ $key 1) $kb $rest)))
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
(= (expand-proof $proof) (externalize-query-proof (sk-full-proof $proof)))

;; The public answer boundary never exposes packed rule storage, including
;; wildcard and RuleTruth reads. The skeleton and materialization keep the CTV.
(: public-query-type (-[det]-> Atom Atom))
(= (public-query-type $type)
   (if (head-is-member? $type (QuantifiedRule ExistsJudgment Assuming))
      (case $type (
         ((QuantifiedRule $_hash $canonical) (existential-source $canonical))
         ((ExistsJudgment $claim) (existential-source $claim))
         ((Assuming $facts $goal) (Assuming $facts (public-query-type $goal)))
         ($_ordinary $type)))
      $type))

;; Fact provenance is internal. Reference answers keep their DAG references,
;; while inline sources retain the same public proof names as expanded answers.
(: public-query-proof (-[det]-> Proof Proof))
(= (public-query-proof $proof)
   (if (is-var $proof) $proof
      (case $proof (
         ((fact-source $_ev $source) (public-query-proof $source))
         ((zero-likelihood $source) (public-query-proof $source))
         ((proof-ref $_id) $proof)
         ($_other
            (if (is-expr $proof)
               (brand Proof (cons (car-atom $proof)
                  (map-flat public-query-proof (proof-children (cdr-atom $proof)))))
               $proof))))))

(: public-query-result (-[det]-> RuntimeResult RuntimeResult))
(= (public-query-result $result)
   (case $result (
      ((CPU $_fun $_args $_res) $result)
      (($type $kbctx $proof $tv)
         (let $answer-tv
            (if (head-is? $tv CTV) (case (the TV $tv) (((CTV $pos $_neg) $pos) ($_other $tv))) $tv)
            (brand RuntimeResult
               (data (public-query-type $type)
                  $kbctx (public-query-proof (brand Proof $proof)) $answer-tv)))))))

(: present-query-plan-results
   (-[nondet]-> Bool (List (Number Statement AnnotatedStatement CompiledQueryGoal))
       (List (List RuntimeResult))
       (List (Number AnnotatedStatement))))
(= (present-query-plan-results $_expand? () ()) ())
(= (present-query-plan-results $expand? (cons ($key $written $canonical $_goal) $roots) (cons $results $rest-results))
   (append-flat
      (map-flat (|-> ($answer) (data $key $answer))
         (pretty-results
            (map-flat externalize-proof-structure
               (written-results $written $canonical
                  (map-flat public-query-result
                     (if $expand? (map-flat expand-result $results) $results))))))
      (present-query-plan-results $expand? $roots $rest-results)))

(: query-plan-runtime-goal
   (-[nondet]-> (Number Statement AnnotatedStatement CompiledQueryGoal) (| Goal (Statement KBContext Proof TV))))
(= (query-plan-runtime-goal ($_key $_written $_canonical $goal)) (typed-runtime-premise $goal))

;; Temporary additions and Assuming contexts stay installed through proof
;; externalization and pretty printing. Direct chainer entrypoints
;; intentionally do not own this bracket.
(: run-query-execution-plan
   (-[nondet]-> Number QueryExecutionPlan Bool Bool (List (Number AnnotatedStatement))))
(= (run-query-execution-plan $steps (query-execution-plan $roots $adds) $materialize? $expand?)
   (let*
      (($_clear-temp-before (clear-temp-query-adds))
       ($_inject (collapse (once (inject-compiled-adds (map-flat context-addition $adds)))))
       ($goals (map-flat query-plan-runtime-goal $roots))
       ($runtime-results
          (if $materialize? (chainer-many-materialize $steps $goals) (chainer-many $steps $goals)))
       ($rows (present-query-plan-results $expand? $roots $runtime-results))
       ($_old-proofs (remove-data-rows! &query_proofs (quote ($_proof))))
       ($_answer-proofs (if $expand? () (map-flat retain-query-proof! $rows)))
       ($_clear-overlay (context-clear!))
       ($_clear-temp-after (clear-temp-query-adds))
       ($_retired (sk-retire-searches!))
       ;; What the contexts' rows interned and stored is reached by nothing now.
       ($_collected (if (deps-gc-due?) (deps-gc! (sk-deps-roots)) true))
       ($_refs (stored-refs-gc-step!)))
      $rows))

(: query-mode (-[nondet]-> Number KB AnnotatedStatement Bool AnnotatedStatement))
(= (query-mode $steps $kb $statement $materialize?)
   (let*
      (($materialized (the AnnotatedStatement (materialize-stmt-lambdas $statement)))
       ($_annotations (check-query-annotations! $materialized))
       ((: $root-proof $written $root-tv) $materialized)
       ($canonical-type (member-canon $written))
       ($canonical (: $root-proof $canonical-type $root-tv))
       ($compiled-queries (collapse (mm2compileQuery $kb (query-root $canonical))))
       ($answers
          (fold-flat append-flat ()
             (map-flat
                (|-> ($compiled-query)
                   (map-flat snd
                      (run-query-execution-plan
                         $steps
                         (compiled-query-execution-plan 0 $written $canonical $compiled-query)
                         $materialize? true)))
                $compiled-queries))))
      (superpose $answers)))

(: query-many-mode (-[nondet]-> Number KB (List AnnotatedStatement) Bool Bool QueryBatchResult))
(= (query-many-mode $steps $kb $statements $materialize? $expand?)
   (let*
      (((query-execution-plan $roots $adds) (prepare-query-many-plan 0 $kb $statements))
       ($rows
          (map-flat
             (|-> ($row) (query-result (fst $row) (snd $row)))
             (run-query-execution-plan
                $steps
                (query-execution-plan $roots (alpha_unique_keys $adds))
                $materialize? $expand?))))
      (superpose $rows)))

(: query (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(= (query $steps $kb $statement) (query-mode $steps $kb $statement false))

(: query-materialize (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(= (query-materialize $steps $kb $statement) (query-mode $steps $kb $statement true))

(: query-many (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many $steps $kb $statements) (query-many-mode $steps $kb $statements false true))

;; As query-many, with each answer's proof left as references into the proof
;; store (expand-proof prints it in full).
(: query-many-refs (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many-refs $steps $kb $statements) (query-many-mode $steps $kb $statements false false))

(: query-many-materialize (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(= (query-many-materialize $steps $kb $statements)
   (query-many-mode $steps $kb $statements true true))
