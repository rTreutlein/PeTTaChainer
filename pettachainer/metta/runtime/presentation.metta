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
   (-[semidet]-> (Number Statement AnnotatedStatement CompiledQueryGoal) ExecutionGoal))
(= (query-plan-runtime-goal ($_key $_written $_canonical $goal))
   (if (head-is? $goal query-scope)
      (let (query-scope $scope $facts $inner $proof $tv) $goal
         (query-scope (the KBContext $scope) (the Statement $facts) $inner (the Proof $proof) (the TV $tv)))
      (typed-runtime-premise $goal)))
