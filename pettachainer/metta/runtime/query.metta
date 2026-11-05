

;; One plan is one execution group. The root list preserves source identity,
;; the written statement and its canonical form (`member-canon`),
;; compiler-alternative order, and duplicates; additions
;; are already in their final installation order for that group.


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
;; the canonical statement, a written (Member x P) read as (P x) (#96). The
;; written truth-value pattern selects the root's values, except that a
;; written confidence .9999, which a computed point (confidence 1) is
;; published at, is left open: the public answer is matched against the
;; written pattern (canonical-results).
(: root-read-tv (-[det]-> Atom Atom))
(= (root-read-tv $tv)
   (if (is-var $tv) $tv
      (case $tv (((STV $s $c) (if (== $c 0.9999) (STV $s $_point) $tv)) ($_other $tv)))))

(: query-root (-[det]-> AnnotatedStatement AnnotatedStatement))
(= (query-root (: $prf $type $tv))
   (if (head-is? $type Not)
      (let ($key $_odd) (canon $type) (: $key-proof $key $key-tv))
      (if (head-is? $type ForAll)
         (: $prf (brand Statement (car-atom (cdr-atom (cdr-atom $type)))) (root-read-tv $tv))
         (: $prf $type (root-read-tv $tv)))))

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
