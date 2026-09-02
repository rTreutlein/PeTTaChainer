;; Rule lowering and structural specialization form one recursive component:
;; derived views and specialization jobs compile new statements through
;; compile_, while compile_ dispatches back into both mechanisms.
(: disable-inversion-proof-id? (-[det]-> Proof Bool))
;; BiImplication lowering already emits both directions; inverting either one
;; again creates a redundant Bayesian version of its explicitly emitted peer.
(= (disable-inversion-proof-id? $prf)
   (if (= $prf (no_inverse $_)) true
      (if (= $prf (bi-forward $_)) true
         (= $prf (bi-backward $_)))))

;; Classify source computations rather than treating every CPU introduced by
;; lowering as a reason to suppress implication inversion. A pure top-level Or
;; lowers through a TV-formula CPU, but an inverse rule can still derive the
;; complete disjunction and let its ordinary projection adapters recover one
;; child. Actual source computations remain restricted to the explicitly
;; reversible subset. Pure And and Or antecedents can be inverted as complete
;; compounds. Child recovery for a pure And is only fused completion; Or still
;; projects from the inverted disjunction.
(: SourceComputeGoals Type)
(: source-computes
   (-[det]-> (List Goal) SourceComputeGoals))
(: unsupported-source-computes SourceComputeGoals)

(: source-compute-goals
   (-[det]-> (List Atom) SourceComputeGoals))

(: contains-source-computation? (-[det]-> Atom Bool))
(= (contains-source-computation? $term)
   (contains-head? source-computation-head? $term))

(= (source-compute-goals ()) (source-computes ()))
(= (source-compute-goals (cons $premise $rest))
   (case $premise (
      ((Compute $function $args -> $result)
         (case (source-compute-goals $rest) (
            ((source-computes $goals)
               (source-computes
                  (cons (CPU $function $args $result) $goals)))
            (unsupported-source-computes
               unsupported-source-computes))))
      ((Compute $function $args $result)
         (source-compute-goals
            (cons (Compute $function $args -> $result) $rest)))
      ($other
         (if (contains-source-computation? $other)
            unsupported-source-computes
            (source-compute-goals $rest))))))

(: direct-variable-index-or-negative
   (-[det]-> (List Atom) Variable Number Number))
(= (direct-variable-index-or-negative () $_variable $_index) -1)
(= (direct-variable-index-or-negative
      (cons $arg $rest) $variable $index)
   (if (if (is-var $arg) (== $arg $variable) false)
      $index
      (direct-variable-index-or-negative
         $rest $variable (+ $index 1))))

(: compute-args-known-except?
   (-[det]-> (List Atom) Number (List Variable) Bool))
(= (compute-args-known-except? () $_skip-index $_known) true)
(= (compute-args-known-except?
      (cons $arg $rest) $skip-index $known)
   (if (== $skip-index 0)
      (compute-args-known-except? $rest -1 $known)
      (if (==
             (\==
                (list_to_set (extract-vars $arg)) $known)
             ())
         (compute-args-known-except?
            $rest (- $skip-index 1) $known)
         false)))

(: ComputeInverseStep Type)
(: inverse-compute-step-result
   (-[det]-> Goal Goal (List Variable) ComputeInverseStep))
(: no-compute-inverse-step ComputeInverseStep)

(: inverse-compute-cpu-step
   (-[det]-> Atom Atom Atom (List Variable) ComputeInverseStep))
(= (inverse-compute-cpu-step $function $args $result $known)
   (let*
      (($result-unknown
          (\==
             (list_to_set (extract-vars $result)) $known))
       ($input-unknown
          (\==
             (list_to_set (extract-vars $args)) $known)))
      (if (not (== $result-unknown ()))
         no-compute-inverse-step
         (case $input-unknown (
            ((cons $unknown ())
               (let*
                  (($arg-list (the (List Atom) $args))
                   ($unknown-index
                      (direct-variable-index-or-negative
                         $arg-list $unknown 0)))
                  (if (or (== $unknown-index -1)
                          (not
                             (compute-args-known-except?
                                $arg-list $unknown-index $known)))
                     no-compute-inverse-step
                     (case
                        (compute-inverse-goal-or-none
                           $function $unknown-index $args $result)
                        (((inverse-compute-goal $inverse-goal)
                            (inverse-compute-step-result
                               $inverse-goal
                               (CPU $function $args $result)
                               (list_to_set (cons $unknown $known))))
                         (no-compute-inverse-goal
                            no-compute-inverse-step))))))
            ($_input-other no-compute-inverse-step))))))

(: inverse-compute-step
   (-[det]-> Goal (List Variable) ComputeInverseStep))
(= (inverse-compute-step $goal $known)
   (case $goal (
      ((CPU $function $args $result)
         (inverse-compute-cpu-step
            $function $args $result $known))
      ($_goal-other no-compute-inverse-step))))

(: ComputeInversePlan Type)
(: inverse-compute-plan
   (-[det]-> (List Goal) (List Variable) ComputeInversePlan))
(: no-compute-inverse ComputeInversePlan)

(: inverse-compute-goals
   (-[det]-> (List Goal) (List Variable) ComputeInversePlan))
(= (inverse-compute-goals () $known)
   (inverse-compute-plan () $known))
(= (inverse-compute-goals (cons $goal $rest) $known)
   (case (inverse-compute-step $goal $known) (
      ((inverse-compute-step-result
          $inverse-goal $validation-goal $next-known)
         (case (inverse-compute-goals $rest $next-known) (
            ((inverse-compute-plan $rest-goals $final-known)
               (inverse-compute-plan
                  (cons $inverse-goal
                     (cons $validation-goal $rest-goals))
                  $final-known))
            (no-compute-inverse no-compute-inverse))))
      (no-compute-inverse-step no-compute-inverse))))

(: compile-reversible-compute-plan
   (-[det]-> Statement Statement ComputeInversePlan))
(= (compile-reversible-compute-plan $antecedent $consequent)
   (case
      (source-compute-goals
         (implication-side-conjuncts $antecedent))
      (((source-computes $compute-goals)
          (if (== $compute-goals ())
             (if (head-is-member? $antecedent (And Or))
                (inverse-compute-plan
                   () (list_to_set (extract-vars $consequent)))
                no-compute-inverse)
             (inverse-compute-goals
                (prepend-reversed-goals $compute-goals ())
                (list_to_set (extract-vars $consequent)))))
       (unsupported-source-computes no-compute-inverse))))

(: implication-inverse-compute-plan
   (-[det]-> Statement Statement Bool ComputeInversePlan))
(= (implication-inverse-compute-plan
      $antecedent $consequent $has-cpu)
   (if $has-cpu
      (compile-reversible-compute-plan
         $antecedent $consequent)
      (inverse-compute-plan
         () (list_to_set (extract-vars $consequent)))))

;; Rules stored with an STV need a CTV derived from antecedent/consequent base
;; rates before modus ponens can use them. An explicit CTV already carries both
;; directions and therefore needs no runtime base-rate scans.
(: compile-implication-ctv-execs
   (-[semidet]-> KB Statement Statement TV
       ((List Goal) CTVType)))
(= (compile-implication-ctv-execs $_kb $_a $_b (CTV $pos $neg))
   (data () (CTV $pos $neg)))
(= (compile-implication-ctv-execs $kb $a $b (STV $s $c))
   (let*
      (($a1 (copy_term (rule-query-pattern $a)))
        ($b1 (copy_term (rule-query-pattern $b))))
      (data
         (the (List Goal)
            ((base-rate-premise $kb $a1 $rule-atv)
             (base-rate-premise $kb $b1 $rule-btv)
             (CPU ImplicationCTVFormula
                (quote ($rule-atv $rule-btv (STV $s $c)))
                $rule-ctv)))
         (the CTVType $rule-ctv))))

;; A negated conclusion is stored as positive evidence for its inner expression
;; with a negated proof and transformed TV. Keeping the runtime type positive
;; lets it share the ordinary fact indexes.
(: compile-implication-output
   (-[det]-> Proof Proof Statement STVType
       ((List Goal) Proof Statement STVType)))
(= (compile-implication-output $prf $proof-token $b $btv)
   (case $b (
      ((Not $inner)
         (data
            ((CPU NotFormula ($btv) $out-tv))
            (brand Proof (negated (quote (by $prf $proof-token))))
            (brand Statement $inner)
            (the STVType $out-tv)))
      ($other
         (data
            ()
            (brand Proof (quote (by $prf $proof-token)))
            $other
            $btv)))))

;; Emit the forward rule plus the adapters needed on both sides. The shape KB is
;; context-sensitive for assumption queries, while adapter-kb controls where
;; reusable source-shape adapters are indexed.
(: compile-implication-forward-rules
   (-[nondet]-> KB KBContext KBContext Proof TV Statement Statement
       (List Variable) (List Goal)
       (List Proof) TV  CompiledAddition))
(= (compile-implication-forward-rules $kb $shape-kb $adapter-kb $prf $tv
      $a $b $antecedent-vars $execs $proofs $atv)
   (superpose (
      (once
         (let*
            (($out-b
                 (skolemize-conclusion-vars $prf $antecedent-vars $b))
              ($proof-token (implication-proof-token $proofs))
              (($ctv-execs $rule-ctv)
                 (compile-implication-ctv-execs $kb $a $b $tv))
              (($out-execs $out-prf $out-type $out-tv)
                 (compile-implication-output
                    $prf $proof-token $out-b (the STVType $btv)))
              ($allargs
                 (append-goals
                    $execs
                    (append-goals
                       $ctv-execs
                       (append-goals
                          ((CPU CTVModusPonensFormula ($atv $rule-ctv) $btv))
                          $out-execs)))))
            (brand CompiledAddition
               ($allargs |-
                  (: $shape-kb $out-prf $out-type $out-tv)))))
      (let $out-b
         (skolemize-conclusion-vars $prf $antecedent-vars $b)
         (if (is-var $out-b)
            (empty)
            (compile-outputs
               (: $adapter-kb (by $prf $prfb) $out-b $btv2))))
      (if (is-var $a) (empty)
         (compile-adapter-chain plain
            (: $adapter-kb $prfa $a $atv))))))

(: rule-evidence-base-name (-[det]-> Proof Proof))
(= (rule-evidence-base-name $prf)
   (if (= $prf (bi-forward $fwd)) (brand Proof $fwd)
      (if (= $prf (bi-backward $bwd)) (brand Proof $bwd)
         (if (= $prf (no_inverse $inner)) (brand Proof $inner)
            $prf))))

(: rule-evidence-registered? (-[det]-> KB Proof Bool))
(= (rule-evidence-registered? $kbid $name)
   (if
      (== (collapse
             (once
                (match &rule_evidence_names
                   ($name $kbid) true)))
          ())
      false
      true))

(: register-rule-evidence!
   (-[det]-> KB Proof (List $no-result)))
(= (register-rule-evidence! $kb $prf)
   (let $name (rule-evidence-base-name $prf)
      (if (is-expr $name) ()
         (if (logic-rule? $name) ()
            (if (rule-evidence-registered? $kb $name) ()
               (let $_added
                  (collapse
                     (once
                        (add-atom
                           &rule_evidence_names
                           ($name $kb))))
                  ()))))))

;; Estimate the base rate required to reinterpret an STV rule as a CTV. Open
;; inheritance antecedents use universe-aware weighted evidence; ordinary
;; patterns use the generic evidence accumulator.
(: base-rate-premise-default
   (-[det]-> KB Statement $truth-value Goal))
(= (base-rate-premise-default $kb $pattern $brtv)
   (let $generic
      (CPU FoldAllCompiled
         (quote
            ($kb $pattern extract-tv
               (BaseRateEvidence 0.0 0.0)
               BaseRateAcc base-rate result-tv))
         $brtv)
      (if (= $pattern (Inheritance $x $_concept))
         (if (is-var $x)
            (CPU FoldAllCompiled
               (quote
                  ($kb $pattern
                     (extract-inheritance-tv $kb $pattern)
                     (BaseRateEvidence 0.0 0.0)
                     WeightedBaseRateAcc
                     (weighted-base-rate-in-universe $kb)
                     result-tv))
               $brtv)
            $generic)
         $generic)))

;; A concrete inheritance target may have a configured/dynamic concept prior.
;; Seed its fold with that prior so sparse observations revise the prior instead
;; of silently behaving like an uninformative generic predicate.
(: base-rate-premise
   (-[det]-> KB Statement $truth-value Goal))
(= (base-rate-premise $kb $pattern $brtv)
   (if (= $pattern (Inheritance $x $subj))
      (if (is-var $x)
         (if (is-var $subj)
            (base-rate-premise-default
               $kb $pattern $brtv)
            (let*
               (($prior-runtime
                   (ConceptNodePriorRuntime $kb $subj))
                ($prior
                   (brand BaseRatePrior $prior-runtime)))
               (CPU FoldAllCompiled
                  (quote
                     ($kb $pattern
                        (extract-inheritance-tv $kb $pattern)
                        (BaseRateEvidenceWithPrior
                           $prior
                           (BaseRateEvidence 0.0 0.0))
                        WeightedBaseRateWithPriorAcc
                        (weighted-base-rate-with-prior-in-universe
                           $kb)
                        result-tv))
                  $brtv)))
         (base-rate-premise-default $kb $pattern $brtv))
      (base-rate-premise-default $kb $pattern $brtv)))

;; Compile the backward use of an implication by deriving its CTV, applying TV
;; inversion, and then using the observed consequent as modus-ponens evidence.
;; This is emitted only when the main compiler has proved the antecedent is
;; invertible. Reversible Compute goals bind antecedent variables first and
;; validate the generated binding with the original forward computation.
(: inverse-implication
   (-[det]-> KB Proof Statement Statement TV (List Goal)
       CompiledAddition))
(= (inverse-implication $kb $prf $a $b $itv $inverse-execs)
   (let*
      (($a1 (copy_term (rule-query-pattern $a)))
        ($b1 (copy_term (rule-query-pattern $b)))
        ($a-base-rate (base-rate-premise $kb $a1 $atv))
        ($b-base-rate (base-rate-premise $kb $b1 $btv))
        ($formula-goals
           (cons
              (CPU ImplicationCTVFormula
                 (quote ($atv $btv $itv)) $rule-ctv)
              (cons
                 (CPU CTVInversionFormula
                    (quote ($atv $btv $rule-ctv)) $iitv)
                 (cons
                    (CPU CTVModusPonensFormula
                       (quote ($btv_wit $iitv)) $mp-tv)
                    ()))))
        ($premises
           (append-goals
              (cons
                 (: (make-kb-context $kb $ctx $vars)
                    $prfb_wit $b $btv_wit)
                 ())
              (append-goals
                 $inverse-execs
                 (cons $a-base-rate
                    (cons $b-base-rate $formula-goals))))))
      ($premises |-
         (: (make-kb-context $kb $ctx $vars)
              ((inverted $prf with cpu cpu) $prfb_wit)
              $a $mp-tv))))

;; For every child M of a pure conjunction H, compile the direct probabilistic
;; completion (And O C) -> M, where O contains H's other children and C is the
;; original consequence. That is the only child-recovery operator for a pure
;; And: whole-H inversion still proves H itself, but does not also project to
;; each child.
(: pure-conjunction-antecedent? (-[det]-> Statement Bool))
(= (pure-conjunction-antecedent? $a)
   (if (head-is? $a And)
      (case (source-compute-goals (the (List Atom) (cdr-atom $a))) (
         ((source-computes ()) true)
         ($_other false)))
      false))
(: antecedent-completion-rule-info
   (-[det]-> KB Statement Statement TV
       ((List Goal) $base-truth-value CTVType)))
(= (antecedent-completion-rule-info
      $kb $full-pattern $_consequent-pattern (CTV $pos $neg))
   (let $full-base-rate
      (base-rate-premise
         $kb $full-pattern $full-base-tv)
      (data
         (cons $full-base-rate ())
         $full-base-tv
         (CTV $pos $neg))))
(= (antecedent-completion-rule-info
      $kb $full-pattern $consequent-pattern (STV $s $c))
   (data
      (the (List Goal)
         ((base-rate-premise
             $kb $full-pattern $full-base-tv)
          (base-rate-premise
             $kb $consequent-pattern $consequent-base-tv)
          (CPU ImplicationCTVFormula
             (quote
                ($full-base-tv $consequent-base-tv (STV $s $c)))
             $rule-ctv)))
      $full-base-tv
      (the CTVType $rule-ctv)))

(: compile-antecedent-completion
   (-[nondet]-> KB $context $variables KBContext Proof TV
       Statement Statement (List Statement) Number (List Statement)
       CompiledAddition))
(= (compile-antecedent-completion
      $kb $ctx $vars $shape-kb $prf $tv
      $full $consequent $children $idx (cons $missing $rest))
   (superpose (
      (if (is-var $missing)
         (empty)
         (let $known
            (brand Statement
               (seq2expr
                  (append
                     (remove-index $idx $children)
                     (cons $consequent ()))))
            (if
               (==
                  (\==
                     (list_to_set (extract-vars $missing))
                     (list_to_set (extract-vars $known)))
                  ())
               (let*
                  ((($known-execs $known-proofs $known-witness-tv)
                      (once
                         (lower-implication-antecedent
                            $kb $ctx $vars $known)))
                   ($missing-pattern
                      (copy_term (rule-query-pattern $missing)))
                   ($full-pattern
                      (copy_term (rule-query-pattern $full)))
                   ($known-pattern
                      (copy_term (rule-query-pattern $known)))
                   ($consequent-pattern
                      (copy_term
                         (rule-query-pattern $consequent)))
                   ($missing-base-rate
                      (base-rate-premise
                         $kb $missing-pattern $missing-base-tv))
                   ($known-base-rate
                      (base-rate-premise
                         $kb $known-pattern $known-base-tv))
                   (($rule-base-execs $full-base-tv $rule-ctv)
                      (antecedent-completion-rule-info
                         $kb $full-pattern $consequent-pattern $tv))
                   ($proof-token
                      (implication-proof-token $known-proofs))
                   ($premises
                      (append-goals
                         $known-execs
                         (append-goals
                            $rule-base-execs
                            (cons $known-base-rate
                               (cons $missing-base-rate
                                  (the (List Goal)
                                     ((CPU CTVAntecedentCompletionFormula
                                         (quote
                                            ($missing-base-tv
                                             $full-base-tv
                                             $known-base-tv
                                             $rule-ctv))
                                         $completion-ctv)
                                      (CPU CTVModusPonensFormula
                                         (quote
                                            ($known-witness-tv
                                             $completion-ctv))
                                         $out-tv)))))))))
                  (brand CompiledAddition
                     ($premises |-
                        (: $shape-kb
                           ((antecedent-completion $prf $idx with cpu cpu)
                            $proof-token)
                           $missing $out-tv))))
               (empty))))
      (compile-antecedent-completion
         $kb $ctx $vars $shape-kb $prf $tv
         $full $consequent $children (+ $idx 1) $rest))))

(: compile-antecedent-completions
   (-[nondet]-> KB $context $variables KBContext Proof TV
       Statement Statement CompiledAddition))
(= (compile-antecedent-completions
      $kb $ctx $vars $shape-kb $prf $tv $a $b)
   (if (pure-conjunction-antecedent? $a)
      (let $children
         (statement-children (the (List Atom) (cdr-atom $a)))
         (compile-antecedent-completion
            $kb $ctx $vars $shape-kb $prf $tv
            $a $b $children 0 $children))
      (empty)))

;; Concrete Inheritance assertions also act as implication-like rules over
;; members. Materializing these views once at compile time lets ordinary rule
;; indexing and inference handle inheritance without a separate chainer path.
(: concrete-inheritance-link? (-[det]-> Atom Atom Bool))
(= (concrete-inheritance-link? $subj $concept)
   (if (is-var $subj)
      false
      (if (is-var $concept) false true)))

(: compile-derived-inheritance-views
   (-[nondet]-> KB Proof Term Term TV  CompiledAddition))
(= (compile-derived-inheritance-views $kb $prf $subj $concept $tv)
   (superpose
      ((compile_ $kb
          (: (inheritance-implication $prf)
             (Implication
                (Inheritance $x $subj)
                (Inheritance $x $concept))
             $tv))
       (let $ctv (inheritance-lift-ctv $tv)
          (compile_ $kb
             (: (no_inverse (member-inheritance-implication $prf))
                (Implication
                   (Member $x $subj)
                   (Member $x $concept))
                $ctv))))))

;; A total-implication context represents a hypothetical instance of the
;; queried subject. Top-level Inheritance premises about a rule's conclusion
;; subject transfer to that instance; every other premise is subject-specific
;; auxiliary evidence and must be specialized against MAIN. Examples:
;;
;;   friendSmokingRule: both premises are auxiliary to conclusion subject $y.
;;   lighterHeatsPlastic: `Inheritance $x madeOfPlastic` transfers, while
;;                        `Operation $x opLighter` is auxiliary.
(: inheritance-context-premise? (-[det]-> $premise $subject Bool))
(= (inheritance-context-premise? $premise $subj)
   (if (= $premise (Inheritance $premise-subj $_concept))
      (== $premise-subj $subj)
      false))

(: inheritance-lift-auxiliary-premises
   (-[det]-> (List Atom) $subject (List Atom)))
(= (inheritance-lift-auxiliary-premises () $_subj) ())
(= (inheritance-lift-auxiliary-premises (cons $premise $rest) $subj)
   (if (inheritance-context-premise? $premise $subj)
      (inheritance-lift-auxiliary-premises $rest $subj)
      (cons $premise (inheritance-lift-auxiliary-premises $rest $subj))))

;; Pair a grounded rule instance with its original template. Contextual
;; Inheritance premises keep their grounded concept but replace the concrete
;; subject with the query's hypothetical instance; auxiliary premises remain
;; grounded MAIN facts.
(: inheritance-lift-parts
   (-[semidet]-> (List Atom) (List Atom) $subject $instance
       ((List Atom) (List Atom))))
(= (inheritance-lift-parts () () $_source-subj $_instance)
   (data () ()))
(= (inheritance-lift-parts
      (cons $ground-premise $ground-rest)
      (cons $source-premise $source-rest)
      $source-subj $instance)
   (let ($contextual $auxiliary)
      (inheritance-lift-parts $ground-rest $source-rest $source-subj $instance)
      (if (inheritance-context-premise? $source-premise $source-subj)
         (let (Inheritance $_ground-subj $ground-concept) $ground-premise
            (data
               (cons (Inheritance $instance $ground-concept) $contextual)
               $auxiliary))
         (data $contextual (cons $ground-premise $auxiliary)))))

;; Compile a specialized relational rule into one fixed query context. The
;; rule's positive STV is already its conditional estimate; unlike an observed
;; Inheritance link it does not need to be inferred again from population base
;; rates. Explicit CTV rules retain both branches.
(: inheritance-lift-ctv (-[semidet]-> TV CTVType))
(= (inheritance-lift-ctv (CTV $pos $neg)) (CTV $pos $neg))
(= (inheritance-lift-ctv (STV $s $c))
   (CTV (STV $s $c) (STV 0.0 1.0)))

(: compile-inheritance-lift-instance
   (-[semidet]-> KB KBContext AnnotatedStatement AnnotatedStatement
       CompiledAddition))
(= (compile-inheritance-lift-instance $kb $lift-kb
      (: $prf
         (Implication $ground-antecedent
            (Inheritance $ground-subj $ground-concept))
         $tv)
      (: $_source-prf
         (Implication $source-antecedent
            (Inheritance $source-subj $_source-concept))
         $_source-tv))
   (let ($kbid $ctx $vars) $lift-kb
      (let*
         (($ground-premises
             (implication-side-conjuncts
                (brand Statement $ground-antecedent)))
          ($source-premises
             (implication-side-conjuncts
                (brand Statement $source-antecedent)))
          (($contextual-premises $auxiliary-premises)
             (inheritance-lift-parts
                (the (List Atom) $ground-premises)
                (the (List Atom) $source-premises)
                $source-subj $instance))
          ($lift-premises
             (if (== $contextual-premises ())
                (the (List Atom)
                   ((Inheritance $instance $ground-subj)))
                $contextual-premises))
          (($main-execs $main-proofs $main-atv)
             (once (lower-implication-antecedent $kbid MAIN Nil
                (brand Statement
                   (seq2expr
                      (the (List Atom) $auxiliary-premises))))))
          (($context-execs $context-proofs $context-atv)
             (once (lower-implication-antecedent $kbid $ctx $vars
                (brand Statement
                   (seq2expr (the (List Atom) $lift-premises))))))
          ($source-proof (implication-proof-token $main-proofs))
          ($context-proof (implication-proof-token $context-proofs))
          ($all-evidence
             (CPU AndFormula (quote ($main-atv $context-atv)) $all-atv))
          ($rule-ctv (inheritance-lift-ctv $tv))
          ($modus-ponens
             (CPU CTVModusPonensFormula
                (quote ($all-atv $rule-ctv)) $out-tv))
          ($out
             (: $lift-kb
                ((inheritance-rule-lift $prf) $source-proof $context-proof)
                (Inheritance $instance $ground-concept) $out-tv)))
         ((append-goals $main-execs
             (append-goals $context-execs
                (quote ($all-evidence $modus-ponens))))
           |- $out))))

;; A grounded lift is one specialization job. The common specialization engine
;; below handles template indexing and late facts for both ordinary compiler
;; specialization and these Inheritance views.
(: SpecializationJob Type)
(: compile-specialization (-[det]-> AnnotatedStatement SpecializationJob))
(: inheritance-lift-specialization
   (-[det]-> AnnotatedStatement AnnotatedStatement SpecializationJob))

;; These rows cross atom-space storage boundaries, so their tags are stable
;; schemas rather than local multiple-return wrappers.
(: InheritanceLiftInstanceRow Type)
(: inheritance-lift-instance-row
   (-[det]-> KB AnnotatedStatement AnnotatedStatement
       InheritanceLiftInstanceRow))

(: SpecializationTemplateRow Type)
(: specialization-template-row
   (-[det]-> KB Atom (List Atom) SpecializationJob
       SpecializationTemplateRow))

(: SpecializationDoneRow Type)
(: specialization-done-row
   (-[det]-> KB AnnotatedStatement SpecializationDoneRow))

(: emit-specialization
   (-[nondet]-> KB SpecializationJob  CompiledAddition))
(= (emit-specialization $kb
      (inheritance-lift-specialization $stmt $source-stmt))
   (let*
      (($stmt-copy (copy_term $stmt))
       ($hash (term_hash $stmt-copy))
       ($stored
          (collapse
             (once
                (match &inheritance_lift_instance
                   ($hash
                      (inheritance-lift-instance-row
                         $kb $candidate $_source))
                   (if (=alpha $candidate $stmt-copy) true (empty)))))))
      (if (not (== $stored ())) (empty)
         (let*
            (($source-copy (copy_term $source-stmt))
             ($_instance
                (add-atom &inheritance_lift_instance
                   ($hash
                      (inheritance-lift-instance-row
                         $kb $stmt-copy $source-copy)))))
            (empty)))))

(: compile-inheritance-lifts-for-context
   (-[nondet]-> KB KBContext  CompiledAddition))
(= (compile-inheritance-lifts-for-context $kb $lift-kb)
   (match &inheritance_lift_instance
      ($_hash
         (inheritance-lift-instance-row
            $kb $ground-stmt $source-stmt))
      (let* (($ground-copy
                (the AnnotatedStatement
                   (copy_term $ground-stmt)))
             ($source-copy
                (the AnnotatedStatement
                   (copy_term $source-stmt))))
         (compile-inheritance-lift-instance
            $kb $lift-kb $ground-copy $source-copy))))

(: collect-inheritance-lifts-for-context
   (-[det]-> KB KBContext (List CompiledAddition)))
(= (collect-inheritance-lifts-for-context $kb $lift-kb)
   (collapse
      (compile-inheritance-lifts-for-context $kb $lift-kb)))

;; On rule addition, emit every instance already supported by stored facts and
;; retain the template for facts added later. No open lifted rule enters the KB.
(: compile-inheritance-rule-lifts
   (-[nondet]-> KB AnnotatedStatement Statement Statement
       CompiledAddition))
(= (compile-inheritance-rule-lifts $kb $stmt $antecedent $consequent)
   (if (= $consequent (Inheritance $subj $_concept))
      (let*
         (($ground-copy (copy_term $stmt))
          ($source-copy (copy_term $stmt))
          ((: $_prf
              (Implication $ground-antecedent
                 (Inheritance $ground-subj $_ground-concept))
              $_tv)
             $ground-copy)
          ($ground-premises
             (implication-side-conjuncts
                (brand Statement $ground-antecedent)))
          ($ground-auxiliary
             (inheritance-lift-auxiliary-premises
                $ground-premises $ground-subj))
          ($job
             (inheritance-lift-specialization
                $ground-copy $source-copy)))
         (if (== $ground-auxiliary ()) (empty)
            (specialize-rule-add $kb $ground-auxiliary $job)))
      (empty)))

;; --- Rule specialization against structural facts -------------------------
;;
;; A premise is a specialization *trigger* when its head is a registered
;; specializing predicate and it still contains variables to ground (so a
;; ground (Symmetric Friend) premise is never re-triggered). When a rule has
;; trigger premises we do not emit the generic variable-headed rule; instead we
;; store the rule as a template and emit one ground instance per matching fact.
;; The instance keeps the trigger premise (now ground), so its truth value is
;; threaded exactly as the uncompiled rule would, and its conclusion head is
;; concrete -- giving precise indexing instead of the `any` wildcard.

(: specialization-trigger? (-[det]-> Statement Bool))
(= (specialization-trigger? $premise)
   (if (is-expr $premise)
      (let $head (car-atom $premise)
         (if (is-var $head) false
            (if (specializing-predicate? $head)
               (if (== (extract-vars $premise) ())
                  false
                  true)
               false)))
      false))

(: rule-trigger-premises (-[det]-> (List Atom) (List Atom)))
(= (rule-trigger-premises ()) ())
(= (rule-trigger-premises (cons $prem $rest))
   (if (specialization-trigger? (brand Statement $prem))
      (cons $prem (rule-trigger-premises $rest))
      (rule-trigger-premises $rest)))

(: fact-head (-[det]-> Statement Atom))
(= (fact-head $type) (if (is-expr $type) (car-atom $type) $type))

;; Both structural rules and Inheritance lifts use the same indexed template
;; store. A job carries the emitter to run after its trigger list is grounded.
;; Keeping the triggers with the job lets a newly added fact use this one path
;; regardless of which compiler feature requested specialization.
(: specialization-template-registered?
   (-[det]-> KB Atom SpecializationJob Bool))
(= (specialization-template-registered? $kb $head $job)
   (let $hash (term_hash (quote ($kb $head)))
      (not
         (==
            (collapse
               (once
                  (match &spec_template
                     ($hash
                        (specialization-template-row
                           $kb $head $_triggers $stored-job))
                     (if (=alpha $stored-job $job) true (empty)))))
            ()))))

(: register-specialization-templates!
   (-[det]-> KB (List Atom) (List Atom) SpecializationJob
       (| Bool (List $no-result))))
(= (register-specialization-templates! $_kb () $_triggers $_job) ())
(= (register-specialization-templates! $kb (cons $trigger $rest) $triggers $job)
   (let $head (fact-head (brand Statement $trigger))
      (let $_register
         (if (specialization-template-registered? $kb $head $job) ()
            (let*
               (($hash (term_hash (quote ($kb $head))))
                (($triggers-copy $job-copy)
                   (copy_term (quote ($triggers $job)))))
               (once
                  (add-atom &spec_template
                     ($hash
                        (specialization-template-row
                           $kb $head $triggers-copy $job-copy))))))
         (register-specialization-templates! $kb $rest $triggers $job))))

;; Idempotency is per grounded statement, not merely per rule type: distinct
;; proof ids or TVs are independent evidence even when their types coincide.
;; The rule-add and fact-add paths may discover the same statement, so retain
;; the full statement as the stable deduplication key.
(: spec-done? (-[det]-> KB AnnotatedStatement Bool))
(= (spec-done? $kb $gstmt)
   (let*
      (($candidate (copy_term $gstmt))
       ($hash (term_hash $candidate)))
      (not
         (== (collapse
                (once
                   (match &spec_done
                      ($hash
                         (specialization-done-row $kb $stored))
                      (if (=alpha $stored $candidate) true (empty)))))
             ()))))

(: mark-spec-done! (-[det]-> KB AnnotatedStatement Bool))
(= (mark-spec-done! $kb $gstmt)
   (let*
      (($copy (copy_term $gstmt))
       ($hash (term_hash $copy)))
      (once
         (add-atom &spec_done
            ($hash (specialization-done-row $kb $copy))))))

;; Compiler backends may contribute additional fact providers for structural
;; specialization. PeTTaChainer's default provider reads its native KB; MM2
;; adds a provider that reads compiler metadata directly from MORK.
(: compiler-specialization-fact
   (-[nondet]-> KB Statement  Statement))
(= (compiler-specialization-fact $kb $trigger)
   (match &kb ($trigger ($kb $_ctx $_vars) $_prf $_tv)
      $trigger))

;; Bind the trigger variables by matching each remaining trigger against the
;; compiler-visible fact providers; $body shares those variables, so it comes
;; out ground.
(: ground-triggers
   (-[nondet]-> KB (List Atom) SpecializationJob
       SpecializationJob))
(= (ground-triggers $_kb () $body) $body)
(= (ground-triggers $kb (cons $trigger $rest) $body)
   (let $candidate
      (compiler-specialization-fact $kb (brand Statement $trigger))
      (let $trigger $candidate
         (ground-triggers $kb $rest $body))))

(= (emit-specialization $kb
      (compile-specialization (: $gprf $gtype $gtv)))
   (let $gstmt (: $gprf $gtype $gtv)
      (if (spec-done? $kb $gstmt) (empty)
         (let $_ (mark-spec-done! $kb $gstmt)
            (compile_ $kb $gstmt)))))

;; Rule-add: retain the job for later facts and also ground it against facts
;; already in the KB.
(: specialize-rule-add
   (-[nondet]-> KB (List Atom) SpecializationJob
       CompiledAddition))
(= (specialize-rule-add $kb $triggers $job)
   (let $_register
      (register-specialization-templates! $kb $triggers $triggers $job)
      (emit-specialization $kb (ground-triggers $kb $triggers $job))))

;; Fact-add: the new fact is not in &kb yet, so pin the trigger it satisfies
;; directly in each compatible position, then resolve the remaining triggers
;; against the store.
(: ground-specialization-with-fact
   (-[nondet]-> KB Statement (List Atom) (List Atom) SpecializationJob
       SpecializationJob))
(= (ground-specialization-with-fact $kb $fact
      (cons $trigger $rest) $before $job)
   (superpose
      ((let $_ (let $trigger $fact ok)
          (ground-triggers $kb (append $before $rest) $job))
       (ground-specialization-with-fact $kb $fact $rest
          (append $before ($trigger)) $job))))

(: compile-specialization-fact-triggers
   (-[nondet]-> KB Statement  CompiledAddition))
(= (compile-specialization-fact-triggers $kb $type)
   (let*
      (($head (fact-head $type))
       ($hash (term_hash (quote ($kb $head)))))
      (match &spec_template
         ($hash
            (specialization-template-row
               $kb $head $stored-triggers $stored-job))
         (let
            ($triggers $job)
            (copy_term
               (quote ($stored-triggers $stored-job)))
            (emit-specialization $kb
               (ground-specialization-with-fact
                  $kb $type
                  (the (List Atom) $triggers) ()
                  (the SpecializationJob $job)))))))

;; Retraction support for the unified specialization store. Templates and
;; grounded completion markers must disappear with their source statement;
;; otherwise a later fact can resurrect a removed rule, and a clean re-add can
;; be suppressed by stale idempotency state.
(: NoSpecializationName Type)
(: no-specialization-name NoSpecializationName)

(: NoSpecializationStatement Type)
(: no-specialization-statement NoSpecializationStatement)

(: NoSpecializationJob Type)
(: no-specialization-job NoSpecializationJob)

(: specialization-statement-name
   (-[det]-> (| AnnotatedStatement NoSpecializationStatement)
       (| Proof NoSpecializationName)))
(= (specialization-statement-name $stmt)
   (case $stmt (((: $name $_type $_tv) $name) ($_other no-specialization-name))))

(: specialization-job-name
   (-[det]-> (| SpecializationJob NoSpecializationJob)
       (| Proof NoSpecializationName)))
(= (specialization-job-name $job)
   (case $job (
      ((compile-specialization $stmt) (specialization-statement-name $stmt))
      ((inheritance-lift-specialization $_ground $source) (specialization-statement-name $source))
      ($_other no-specialization-name))))

(: remove-specialization-state! (-[det]-> Proof (List $none)))
(= (remove-specialization-state! $name)
   (let*
      (($_templates
          (collapse
             (match &spec_template
                ($hash
                   (specialization-template-row
                      $kb $head $triggers $job))
                (if (== (specialization-job-name
                           (the SpecializationJob $job))
                        $name)
                   (remove-atom &spec_template
                      ($hash
                         (specialization-template-row
                            $kb $head $triggers $job)))
                   (empty)))))
       ($_done
          (collapse
             (match &spec_done
                ($hash (specialization-done-row $kb $stmt))
                (if (== (specialization-statement-name
                           (the AnnotatedStatement $stmt))
                        $name)
                   (remove-atom &spec_done
                      ($hash (specialization-done-row $kb $stmt)))
                   (empty)))))
       ($_lifts
          (collapse
             (match &inheritance_lift_instance
                ($hash
                   (inheritance-lift-instance-row
                      $kb $stmt $source))
                (if (== (specialization-statement-name
                           (the AnnotatedStatement $source))
                        $name)
                   (remove-atom &inheritance_lift_instance
                      ($hash
                         (inheritance-lift-instance-row
                            $kb $stmt $source)))
                   (empty))))))
      ()))

;; Store a non-rule fact and emit its ordinary derived views. Keeping this
;; separate lets the main compiler normalize supported source syntax before
;; entering the single canonical fact path.
(: compile-ordinary-fact
   (-[nondet]-> KB Proof Statement TV CompiledAddition))
(= (compile-ordinary-fact $kb $prf $Type $tv)
   (let $fact-kb
      (if (is-expr $kb)
         (existing-kb-context $kb)
         (let $kbid (brand KB $kb)
            (if (context-polymorphic-facts? $kbid)
               (make-kb-context $kbid $ctx $vars)
               (make-kb-context $kbid MAIN Nil))))
      (superpose (
         (brand CompiledAddition
            (() |- (: $fact-kb $prf $Type $tv)))
         (if (= $Type (Inheritance $subj $concept))
            (if (concrete-inheritance-link? $subj $concept)
               (compile-derived-inheritance-views
                  $kb $prf
                  (brand Term $subj) (brand Term $concept)
                  $tv)
               (empty))
            (empty))
         (compile-specialization-fact-triggers $kb $Type)
         (if (= $Type (Member $_obj $_class))
            (empty)
            (compile-outputs (: $fact-kb $prf $Type $tv)))))))

;; Main statement compiler.
;;
;; Implications become forward rules, optional inverse rules, and adapters.
;; Bidirectional forms are split into two ordinary implications. Facts are
;; stored directly, with extra derived views for concrete Inheritance links and
;; projections for configured compound outputs. Structural specialization is
;; checked before generic implication compilation so variable-headed templates
;; never leak into the broad `any` index.
(: compile_ (-[nondet]-> KB AnnotatedStatement  CompiledAddition))
(= (compile_ $kb (: $prf $Type $tv))
   (if (is-var $Type) (empty)
      (if (= $Type (Implication $antecedent $consequent))
       (let* (($_exists-valid
                  (validate-explicit-exists-rule
                     $antecedent $consequent))
               ($triggers
                  (rule-trigger-premises
                     (implication-side-conjuncts
                        (brand Statement $antecedent)))))
        (if (not (== $triggers ()))
         (specialize-rule-add $kb $triggers
            (compile-specialization (: $prf $Type $tv)))
         (let*
            (($_evidence-reg (register-rule-evidence! $kb $prf))
             (($execs $proofs $atv)
                (if (explicit-exists-term? $antecedent)
                   (lower-implication-antecedent
                      $kb $ctx $vars
                      (brand Statement $antecedent))
                   (once
                      (lower-implication-antecedent
                         $kb $ctx $vars
                         (brand Statement $antecedent)))))
             ($shape-kb (make-kb-context $kb $ctx $vars))
             ($adapter-kb (kbctx $kb))
             ($a
                (brand Statement
                   (implication-source-term $antecedent)))
             ($b
                (brand Statement
                   (implication-source-term $consequent)))
             ($antecedent-vars
                (implication-antecedent-free-vars $antecedent))
             ($has-cpu (contains-cpu? (execs-goal-type $execs)))
             ($inverse-plan
                (implication-inverse-compute-plan
                   $a $b $has-cpu)))
            (superpose (
               (compile-implication-forward-rules
                  $kb $shape-kb $adapter-kb $prf $tv
                  $a $b $antecedent-vars $execs $proofs $atv)
               (case $inverse-plan (
                  ((inverse-compute-plan $inverse-execs $inverse-known)
                     (if (disable-inversion-proof-id? $prf)
                        (empty)
                        (let $na
                           (skolemize-conclusion-vars
                              $prf $inverse-known $a)
                           (superpose (
                              (inverse-implication
                                 $kb $prf $na $b $tv $inverse-execs)
                              (if (is-var $na) (empty)
                                 (if (pure-conjunction-antecedent? $a)
                                    (empty)
                                    (compile-outputs
                                       (: $adapter-kb
                                          ((inverted $prf $w $pa1 $pa2) $pb2)
                                          $na $natv))))
                              (if (is-var $b) (empty)
                                 (compile-adapter-chain plain
                                    (: $adapter-kb $pb2 $b $btv2))))))))
                  (no-compute-inverse (empty))))
               (compile-antecedent-completions
                  $kb $ctx $vars $shape-kb $prf $tv $a $b)
               (compile-inheritance-rule-lifts $kb (: $prf $Type $tv)
                  (brand Statement $antecedent)
                  (brand Statement $consequent)))))))
         (if (implication-type? $Type)
            (empty)
         (if (bidirectional-implication-type? $Type)
            (if (contains-explicit-exists? $Type)
               (empty)
               (let ($_head $left $right) $Type
                  (superpose (
                     (compile_ $kb (: (bi-forward $prf)
                        (Implication $left $right)
                        $tv))
                     (compile_ $kb (: (bi-backward $prf)
                        (Implication $right $left)
                        $tv))))))
            (if (contains-explicit-exists? $Type)
               (empty)
            ;; Canonicalize asserted negation into the inner fact's strength.
            ;; Keeping the original proof name makes removal and provenance
            ;; behave exactly like an ordinary fact; query adapters reconstruct
            ;; `(Not ...)` and its negated proof token when requested.
            (if (= $Type (Not $inner))
               (case $tv (
                  ((STV $s $c)
                     (compile_ $kb
                        (: $prf $inner (STV (- 1.0 $s) $c))))
                  ($_unsupported-tv
                     (compile-ordinary-fact $kb $prf $Type $tv))))
               (compile-ordinary-fact $kb $prf $Type $tv))))))))
