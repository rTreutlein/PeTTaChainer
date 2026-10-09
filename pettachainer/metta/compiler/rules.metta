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
         (if (contains-head? source-computation-head? $other)
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
      (if (vars-covered? $arg $known)
         (compute-args-known-except?
            $rest (- $skip-index 1) $known)
         false)))

(: ComputeInverseStep Type)
(: inverse-compute-step-result
   (-[det]-> Goal Goal (List Variable) ComputeInverseStep))
(: no-compute-inverse-step ComputeInverseStep)

(: inverse-compute-step
   (-[det]-> Goal (List Variable) ComputeInverseStep))
(= (inverse-compute-step $goal $known)
   (case $goal (
      ((CPU $function $args $result)
         (if (not (vars-covered? $result $known))
            no-compute-inverse-step
            (case (\== (list_to_set (extract-vars $args)) $known) (
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
                  ($_input-other no-compute-inverse-step)))))
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

;; The pattern a rule's base rate is taken over: a fresh copy of one of its
;; sides, except the variables a surrounding ForAll binds, which stay shared
;; with the rule application so the rate is taken per parameter value.
(: rule-base-rate-pattern (-[semidet]-> (List Variable) Statement Statement))
(= (rule-base-rate-pattern $params $side)
   (case (copy_term ($params (rule-query-pattern $side))) (
      (($params $pattern) (brand Statement $pattern)))))

;; Rules stored with an STV need a CTV derived from antecedent/consequent base
;; rates before modus ponens can use them. An explicit CTV already carries both
;; directions and therefore needs no runtime base-rate scans. `$value` is the
;; truth the rule applies with, of its stored truth's kind: the stored truth,
;; or a refined rule's resolved truth.
(: compile-implication-ctv-execs
   (-[semidet]-> KB (List Variable) Statement Statement TV Atom
       ((List Goal) CTVType)))
(= (compile-implication-ctv-execs $_kb $_params $_a $_b (CTV $_pos $_neg) $value)
   (data () (the CTVType $value)))
(= (compile-implication-ctv-execs $kb $params $a $b (STV $_s $_c) $value)
   (let*
      (($a1 (rule-base-rate-pattern $params $a))
        ($b1 (rule-base-rate-pattern $params $b)))
      (data
         (append-goals (base-rate-premises $kb $a1 $rule-atv)
            (append-goals (base-rate-premises $kb $b1 $rule-btv)
               (cons (CPU ImplicationCTVFormula
                        (quote ($rule-atv $rule-btv $value))
                        $rule-ctv)
                  ())))
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

;; Emit the forward rules plus the adapters needed on both sides: one forward
;; rule per lowering of the antecedent, the complete one and those of its
;; settling parts (see settled-premise-bundle). The shape KB is
;; context-sensitive for assumption queries, while adapter-kb controls where
;; reusable source-shape adapters are indexed.
(: compile-implication-forward-rules
   (-[nondet]-> KB KBContext KBContext Proof TV (List Goal) Atom (List Variable)
       Statement Statement (List Variable) (List CompiledPremises)
       CompiledAddition))
(= (compile-implication-forward-rules $kb $shape-kb $adapter-kb $prf $tv
      $truth-premises $value $params $a $b $antecedent-vars $antecedents)
   (let $out-b
      (skolemize-conclusion-vars $prf $antecedent-vars $b)
     (superpose (
      (let ($execs $proofs $atv) (superpose $antecedents)
       (once
         (let*
            (($proof-token (implication-proof-token $proofs))
              (($ctv-execs $rule-ctv)
                 (compile-implication-ctv-execs $kb $params $a $b $tv $value))
              (($out-execs $out-prf $out-type $out-tv)
                 (compile-implication-output
                    $prf $proof-token $out-b (the STVType $btv)))
              ($allargs
                 (append-goals
                    $truth-premises
                    (append-goals
                       $execs
                       (append-goals
                          $ctv-execs
                          (append-goals
                             ((CPU CTVModusPonensFormula ($atv $rule-ctv) $btv))
                             $out-execs))))))
            (brand CompiledAddition
               ($allargs |-
                  (: $shape-kb $out-prf $out-type $out-tv))))))
      (if (is-var $out-b)
         (empty)
         (compile-outputs
            (: $adapter-kb (by $prf $prfb) $out-b $btv2)))
      (if (is-var $a) (empty)
         (compile-adapter-chain plain
            (: $adapter-kb $prfa $a $adapter-atv)))))))

(: rule-evidence-base-name (-[det]-> Proof Proof))
(= (rule-evidence-base-name $prf)
   (if (= $prf (bi-forward $fwd)) (brand Proof $fwd)
      (if (= $prf (bi-backward $bwd)) (brand Proof $bwd)
         (if (= $prf (no_inverse $inner)) (brand Proof $inner)
            $prf))))

(: rule-evidence-registered? (-[det]-> KB Proof Bool))
(= (rule-evidence-registered? $kbid $name)
   (not
      (==
         (collapse
            (once
               (match &rule_evidence_names ($name $kbid) true)))
         ())))

;; A rule's applications carry its evidence when its truth is an estimate,
;; so two proofs through it are not independent. A rule stated with confidence
;; 1 in every branch is not refined (`refined-rule?`): its truth is given, not
;; estimated, and proofs that both use it share no uncertain evidence.
(: register-rule-evidence!
   (-[det]-> KB Proof TV (List $no-result)))
(= (register-rule-evidence! $kb $prf $tv)
   (let $name (rule-evidence-base-name $prf)
      (if (is-expr $name) ()
         (if (logic-rule? $name) ()
            (if (rule-evidence-registered? $kb $name) ()
               (if (case $tv (
                      ((STV $_s $c) (if (is-var $c) false (>= $c 1.0)))
                      ((CTV (STV $_ps $pc) (STV $_ns $nc))
                         (if (is-var $pc) false (if (is-var $nc) false (if (>= $pc 1.0) (>= $nc 1.0) false))))
                      ($_other false)))
                  ()
                  (let $_added
                     (collapse
                        (once
                           (add-atom
                              &rule_evidence_names
                              ($name $kb))))
                     ())))))))

;; Estimate the base rate required to reinterpret an STV rule as a CTV. Open
;; inheritance antecedents use universe-aware weighted evidence; a concrete
;; inheritance target may have a configured/dynamic concept prior, so its fold
;; is seeded with that prior and sparse observations revise the prior instead
;; of silently behaving like an uninformative generic predicate. Ordinary
;; patterns use the generic evidence accumulator.
(: base-rate-fold
   (-[det]-> KB Statement $truth-value Goal))
(= (base-rate-fold $kb $pattern $brtv)
   (let $generic
      (CPU FoldAllCompiled
         (quote
            ($kb $pattern extract-tv
               (BaseRateEvidence 0.0 0.0)
               BaseRateAcc base-rate result-tv))
         $brtv)
      (if (= $pattern (Inheritance $x $subj))
         (if (is-var $x)
            (if (is-var $subj)
               (CPU FoldAllCompiled
                  (quote
                     ($kb $pattern
                        (extract-inheritance-tv $kb $pattern)
                        (BaseRateEvidence 0.0 0.0)
                        WeightedBaseRateAcc
                        (weighted-base-rate-in-universe $kb)
                        result-tv))
                  $brtv)
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
            $generic)
         $generic)))

;; A conjunction's conjuncts grouped into parts that share no variables;
;; ground conjuncts join the first part that has variables, since a single
;; instance multiplies nothing.
(: ConjunctSplit Type)
(: conjunct-split (-[det]-> (List Atom) (List Atom) ConjunctSplit))
(: split-by-variables (-[det]-> (List Variable) (List Atom) ConjunctSplit ConjunctSplit))
(= (split-by-variables $vars $part (conjunct-split $touching $apart))
   (if (== (/==\ $vars (extract-vars $part)) ())
      (conjunct-split $touching (cons $part $apart))
      (conjunct-split (append $part $touching) $apart)))
(: add-to-parts (-[det]-> (List Atom) Atom (List Atom)))
(= (add-to-parts $parts $conjunct)
   (if (== (extract-vars $conjunct) ()) $parts
      (case (foldr-flat (split-by-variables (extract-vars $conjunct)) (conjunct-split () ()) $parts) (
         ((conjunct-split $touching $apart) (cons (cons $conjunct $touching) $apart))))))
(: add-ground-to-parts (-[det]-> (List Atom) Atom (List Atom)))
(= (add-ground-to-parts $parts $conjunct)
   (if (== (extract-vars $conjunct) ())
      (case $parts (
         (() (cons (cons $conjunct ()) ()))
         ((cons $first $rest) (cons (cons $conjunct $first) $rest))))
      $parts))
(: conjunct-parts (-[det]-> (List Atom) (List Atom)))
(= (conjunct-parts $conjuncts)
   (fold-flat add-ground-to-parts (fold-flat add-to-parts () $conjuncts) $conjuncts))

;; The premises estimating a pattern's base rate as `$brtv`. A conjunction
;; whose conjuncts fall into parts sharing no variables ranges over the cross
;; product of the parts' instances, so its rate is exactly the product of
;; theirs: each part is folded alone and AndFormula combines them, instead of
;; folding over every combination.
(: BaseRateParts Type)
(: base-rate-parts (-[det]-> (List Goal) (List Atom) BaseRateParts))
(: base-rate-part (-[det]-> KB Atom BaseRateParts BaseRateParts))
(= (base-rate-part $kb $part (base-rate-parts $goals $tvs))
   (base-rate-parts
      (cons (base-rate-fold $kb
               (brand Statement (if (== (cdr-atom $part) ()) (car-atom $part) (cons-atom And $part)))
               $tv)
         $goals)
      (cons $tv $tvs)))
(: base-rate-premises (-[det]-> KB Statement $truth-value (List Goal)))
(= (base-rate-premises $kb $pattern $brtv)
   (base-rate-part-premises $kb $pattern $brtv
      (conjunct-parts (implication-side-conjuncts $pattern))))
;; The parts arrive as a parameter: the determinism checker proves the fold
;; over a parameter list, not over a function result.
(: base-rate-part-premises (-[det]-> KB Statement $truth-value (List Atom) (List Goal)))
(= (base-rate-part-premises $kb $pattern $brtv $parts)
   (if (== (cdr-atom $parts) ())
      (cons (base-rate-fold $kb $pattern $brtv) ())
      (case (foldr-flat (base-rate-part $kb) (base-rate-parts () ()) $parts) (
         ((base-rate-parts $goals $tvs)
            (append-goals $goals (cons (CPU AndFormula $tvs $brtv) ())))))))

;; The premises reading a pattern's base rate as the prior an inversion or an
;; antecedent completion updates. A rate of 0 or 1 gives no prior: the
;; posterior would be the rate itself restated as the instance's value, and a
;; knowledge base storing only true instances (logic KBs of Provable or Path
;; facts) has rate 1, so every antecedent of every stored conclusion would be
;; asserted.
(: prior-base-rate-premises (-[det]-> KB Statement $truth-value (List Goal)))
(= (prior-base-rate-premises $kb $pattern $brtv)
   (append-goals (base-rate-premises $kb $pattern $brtv)
      (cons (CPU uncertain-rate? ($brtv) true) ())))
(: uncertain-rate? (-[semidet]-> TV Bool))
(= (uncertain-rate? (STV $s $_c)) (and (> $s 0.0) (< $s 1.0)))

;; An implication is also estimated from its instances: one sample per
;; antecedent binding whose consequent is provable, both sides resolved through
;; the backward chainer so derived instances count. Open world: an antecedent
;; instance without a provable consequent is not a sample. A sample never uses
;; a rule that restates the implication (see `sk-sample-exclusions`). The fold's
;; strength is the mass-weighted consequent strength and its confidence
;; count-based. Sampling needs plain predicate conjuncts whose consequent
;; variables the antecedent binds.
(: unsampled-conjunct? (-[det]-> Bool Atom Bool))
(= (unsampled-conjunct? $seen $conjunct)
   (if $seen true
      (if (is-var $conjunct) true
         (head-is-member? $conjunct
            (And Or Not Implication BiImplication Exists Compute
               KnownExistential ExistentialResidual)))))

(: implication-instance-supported? (-[det]-> Statement Statement Bool))
(= (implication-instance-supported? $antecedent $consequent)
   (if (is-var $antecedent) false
      (if (is-expr $consequent)
         (if (fold-flat unsampled-conjunct? false
                (cons $consequent (implication-side-conjuncts $antecedent)))
            false
            (vars-covered? $consequent (list_to_set (extract-vars $antecedent))))
         false)))

;; A sample rule's premises and its proof's arguments, built conjunct by
;; conjunct, and the antecedent truth values.
(: InstanceSampleParts Type)
(: instance-sample-parts
   (-[det]-> (List Goal) (List Atom) (List Atom) InstanceSampleParts))
(: implication-instance-premise
   (-[det]-> KB Atom InstanceSampleParts InstanceSampleParts))
(= (implication-instance-premise $kb $conjunct (instance-sample-parts $premises $proofs $tvs))
   (instance-sample-parts
      (cons (: (kbctx $kb) $prf $conjunct $tv) $premises)
      (cons $prf $proofs)
      (cons $tv $tvs)))

;; The sample rule and the fold rule concluding `$Type`. With `$ctv?` the fold
;; derives the negative branch from both sides' base rates, as a stored STV
;; rule does; otherwise it concludes the positive branch as an STV.
(: compile-implication-instance-adds
   (-[det]-> Bool KB Statement Statement Statement (List CompiledAddition)))
(= (compile-implication-instance-adds $ctv? $kb $Type $antecedent $consequent)
   (if (implication-instance-supported? $antecedent $consequent)
      (let*
         (($conjuncts (implication-side-conjuncts $antecedent))
          ($single (== (cdr-atom $conjuncts) ()))
          ;; The antecedent premises come first, then the conjunction of
          ;; their truth values (`$tvs`, bound by the fold below), then the
          ;; consequent; the sample proof lists their proofs in that order.
          ($consequent-goals
             (if $single (cons (: (kbctx $kb) $bprf $consequent $btv) ())
                (cons (CPU AndFormula $tvs $and-tv)
                   (cons (: (kbctx $kb) $bprf $consequent $btv) ()))))
          ($parts
             (foldr-flat (implication-instance-premise $kb)
                (instance-sample-parts $consequent-goals (cons $bprf ()) ())
                $conjuncts)))
         (case $parts (
            ((instance-sample-parts $premises $proofs $tvs)
               (let*
                  (($atv (if $single (car-atom $tvs) $and-tv))
                   ($sample-pattern
                      (ImplicationInstanceSample $antecedent $consequent $atv $btv))
                   ($fold
                      (CPU FoldAllCompiled
                         (quote
                            ($kb $sample-pattern
                               (extract-value $sample-pattern (WeightedTv $atv $btv))
                               (BaseRateEvidence 0.0 0.0)
                               WeightedBaseRateAcc implication-instance result-tv))
                         $fold-tv))
                   ($positive (CPU MemberInheritanceEvidenceFormula ($fold-tv) $instance-tv))
                   ($fold-premises
                      (cons $fold
                         (cons $positive
                            (if $ctv?
                               (append-goals
                                  (base-rate-premises $kb (copy_term (rule-query-pattern $antecedent)) $rule-atv)
                                  (append-goals
                                     (base-rate-premises $kb (copy_term (rule-query-pattern $consequent)) $rule-btv)
                                     (cons (CPU ImplicationCTVFormula
                                              (quote ($rule-atv $rule-btv $instance-tv)) $instance-ctv)
                                        ())))
                               ()))))
                   ($fold-result (if $ctv? $instance-ctv $instance-tv)))
                  (cons
                     (brand CompiledAddition
                        (cons $premises
                           (cons |-
                              (cons (: (kbctx $kb) (cons implication-instance-sample $proofs)
                                       $sample-pattern (STV 1.0 1.0))
                                 ()))))
                     (cons
                        (brand CompiledAddition
                           (cons $fold-premises
                              (cons |-
                                 (cons (: (kbctx $kb) (implication-instance-fold cpu) $Type $fold-result)
                                    ()))))
                        ())))))))
      ()))

;; Compile the backward use of an implication stated with an STV: derive its
;; negative branch from the base rates of both sides, invert by the ratio
;; P(A|B) = P(B|A) P(A) / P(B) over the reconciled base rates, and then use the
;; observed consequent as modus-ponens evidence, a soft value entering as its
;; likelihood ratio over the prior it was formed under (ObservationRatioFormula,
;; sk-observation-prior). A rule stated with a CTV gives
;; both likelihoods and is inverted by Bayes' rule over the antecedent's base
;; rate instead (`prior-inverse-implication` with `population`), which needs no
;; P(B): an empirical P(B) inconsistent with P(A) and the stated likelihoods
;; would otherwise decide the inversion. This is emitted only when the main
;; compiler has proved the antecedent is invertible. Reversible Compute goals
;; bind antecedent variables first and validate the generated binding with the
;; original forward computation.
(: inverse-implication
   (-[semidet]-> KB Proof (List Variable) Statement Statement Atom (List Goal) (List Goal)
       CompiledAddition))
(= (inverse-implication $kb $prf $params $a $b $itv $truth-premises $inverse-execs)
   (let*
      (($a1 (rule-base-rate-pattern $params $a))
        ($b1 (rule-base-rate-pattern $params $b))
        ($a-base-rates (prior-base-rate-premises $kb $a1 $atv))
        ($b-base-rates (base-rate-premises $kb $b1 $btv))
        ($formula-goals
           (the (List Goal)
              ((CPU ImplicationCTVFormula (quote ($atv $btv $itv)) $rule-ctv)
               (CPU CTVInversionFormula (quote ($atv $btv $rule-ctv)) $iitv)
               (CPU sk-observation-prior (quote ($prfb_wit $btv_wit)) $obs-prior)
               (CPU ObservationRatioFormula (quote ($btv_wit $obs-prior $atv $iitv)) $obs-tv)
               (CPU CTVModusPonensFormula (quote ($obs-tv $iitv)) $mp-tv))))
        ($premises
           (append-goals
              (append-goals $truth-premises
                 (cons
                    (: (make-kb-context $kb $ctx $vars)
                       $prfb_wit $b $btv_wit)
                    ()))
              (append-goals
                 $inverse-execs
                 (append-goals $a-base-rates
                    (append-goals $b-base-rates $formula-goals))))))
      ($premises |-
         (: (make-kb-context $kb $ctx $vars)
              ((inverted $prf with cpu (prior $atv)) $prfb_wit)
              $a $mp-tv))))

;; A rule declared `(WithPrior p (Implication a b))` is inverted per
;; instance by Bayes' rule: P(a) is the instance's prior and P(b) follows from
;; it and the rule by total probability, so an observation of b updates what is
;; believed about this instance, never contradicting the rule. The prior is the truth of `p`
;; for the observed instance, or, with `population`, a's base rate for an
;; instance without one; the first's evidence contains the second's, so it
;; replaces that answer wherever `p` is provable. A plain rule stated with a CTV
;; is inverted with `population` alone. The observation of b enters as its
;; likelihood ratio, as for an STV rule. The proof carries the prior's truth
;; value, so inversions of several observations over one prior merge by
;; Bayes' rule (sk-factored-merge).
(: prior-inverse-implication
   (-[semidet]-> KB Proof (List Variable) Atom Statement Statement TV Atom
       (List Goal) (List Goal) CompiledAddition))
(= (prior-inverse-implication $kb $prf $params $prior $a $b $tv $value
      $truth-premises $inverse-execs)
   (let*
      (($population (== $prior population))
       ($prior-goals
          (if $population
             (prior-base-rate-premises $kb (rule-base-rate-pattern $params $a) $atv)
             (cons (: (make-kb-context $kb $ctx $vars) $prior-prf (brand Statement $prior) $atv) ())))
       ($prior-token (if $population cpu $prior-prf))
       (($ctv-execs $rule-ctv)
          (compile-implication-ctv-execs $kb $params $a $b $tv $value))
       ($premises
          (append-goals $truth-premises
             (cons (: (make-kb-context $kb $ctx $vars) $prfb_wit $b $btv_wit)
                (append-goals $inverse-execs
                   (append-goals $prior-goals
                      (append-goals $ctv-execs
                         (the (List Goal)
                            ((CPU CTVBayesFormula (quote ($atv $rule-ctv)) $iitv)
                             (CPU sk-observation-prior (quote ($prfb_wit $btv_wit)) $obs-prior)
                             (CPU ObservationRatioFormula (quote ($btv_wit $obs-prior $atv $iitv)) $obs-tv)
                             (CPU CTVModusPonensFormula (quote ($obs-tv $iitv)) $mp-tv))))))))))
      ($premises |-
         (: (make-kb-context $kb $ctx $vars)
            ((inverted $prf with $prior-token (prior $atv)) $prfb_wit)
            $a $mp-tv))))

;; For every child M of a pure conjunction H, compile the completion
;; (And O C) -> M, where O contains H's other children and C is the original
;; consequence. That is the only child-recovery operator for a pure And:
;; whole-H inversion still proves H itself, but does not also project to each
;; child. The completion inverts the rule onto M over M's base rate, as a
;; plain inversion inverts onto its antecedent, with C's likelihoods given M
;; and not M at O's value (ConjunctLikelihoodFormula), so it is the joint
;; posterior over O and M; C's value enters as its likelihood ratio
;; (ObservationRatioFormula). A negated child (Not I) completes I, the
;; statement its observations and base rate are about. The proof carries the
;; base rate, so the completion merges with other updates of it by Bayes'
;; rule (sk-factored-merge).
(: pure-conjunction-antecedent? (-[det]-> Statement Bool))
;; A conjunction is pure when no child computes, a negated child counting by
;; the statement it negates.
(: computing-child? (-[det]-> Bool Atom Bool))
(= (computing-child? $seen $child)
   (if $seen true
      (let $statement (if (head-is? $child Not) (car-atom (cdr-atom $child)) $child)
         (contains-head? source-computation-head? $statement))))
(= (pure-conjunction-antecedent? $a)
   (if (head-is? $a And)
      (if (fold-flat computing-child? false (implication-side-conjuncts $a)) false true)
      false))
(: compile-antecedent-completion
   (-[nondet]-> KB $context $variables KBContext Proof TV (List Variable)
       Statement Statement (List Statement) Number (List Statement)
       CompiledAddition))
(= (compile-antecedent-completion
      $kb $ctx $vars $shape-kb $prf $tv $params
      $full $consequent $children $idx (cons $missing $rest))
   (superpose (
      (if (is-var $missing)
         (empty)
         (let* (($others (remove-index $idx $children))
                ($known (brand Statement (seq2expr (append $others (cons $consequent ()))))))
            ;; A missing conjunct that alone links the others' variables would be
            ;; inferred for every combination of unrelated instances; only a
            ;; conjunct whose variables the rest already connects is completed.
            (if (if (vars-covered? $missing (list_to_set (extract-vars $known)))
                   (== (cdr-atom (conjunct-parts (implication-side-conjuncts $known))) ())
                   false)
               (let*
                  ((($others-execs $others-proofs $others-tv)
                      (once
                         (lower-implication-antecedent
                            $kb $ctx $vars (brand Statement (seq2expr $others)))))
                   (($consequent-execs $consequent-proofs $consequent-tv)
                      (once
                         (lower-implication-antecedent
                            $kb $ctx $vars $consequent)))
                   (($rule-execs $rule-ctv)
                      (compile-implication-ctv-execs $kb $params $full $consequent $tv $tv))
                   ($proof-token
                      (implication-proof-token (append $others-proofs $consequent-proofs)))
                   ($consequent-proof (implication-proof-token $consequent-proofs))
                   ($negated (head-is? $missing Not))
                   ($target (if $negated (brand Statement (car-atom (cdr-atom $missing))) $missing))
                   ($consequent-head (if (is-expr $consequent) (car-atom $consequent) $consequent))
                   ($consequent-arity (if (is-expr $consequent) (- (length $consequent) 1) -1))
                   ($observed (CPU observed-predicate? ($kb $consequent-head $consequent-arity) true))
                   ($premises
                      (cons $observed
                      (append-goals $others-execs
                         (append-goals $consequent-execs
                            (append-goals $rule-execs
                               (append-goals
                                  (prior-base-rate-premises $kb
                                     (rule-base-rate-pattern $params $target) $target-base-tv)
                                  (the (List Goal)
                                     ((CPU ConjunctLikelihoodFormula
                                         (quote ($negated $others-tv $rule-ctv))
                                         $likelihood-ctv)
                                      (CPU CTVBayesFormula
                                         (quote ($target-base-tv $likelihood-ctv))
                                         $completion-ctv)
                                      (CPU sk-observation-prior
                                         (quote ($consequent-proof $consequent-tv))
                                         $consequent-prior)
                                      (CPU ObservationRatioFormula
                                         (quote ($consequent-tv $consequent-prior $target-base-tv $completion-ctv))
                                         $consequent-obs-tv)
                                      (CPU CTVModusPonensFormula
                                         (quote ($consequent-obs-tv $completion-ctv))
                                         $out-tv))))))))))
                  (brand CompiledAddition
                     ($premises |-
                        (: $shape-kb
                           ((antecedent-completion $prf $idx with cpu (prior $target-base-tv))
                            $proof-token)
                           $target $out-tv))))
               (empty))))
      (compile-antecedent-completion
         $kb $ctx $vars $shape-kb $prf $tv $params
         $full $consequent $children (+ $idx 1) $rest))))

(: concrete-inheritance-link? (-[det]-> Atom Atom Bool))
(= (concrete-inheritance-link? $subj $concept)
   (not (or (is-var $subj) (is-var $concept))))

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
   (let*
      ((($kbid $ctx $vars) $lift-kb)
       ($ground-premises
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
             (quote ($all-atv $rule-ctv)) $out-tv)))
      ((append-goals $main-execs
          (append-goals $context-execs
             (quote ($all-evidence $modus-ponens))))
        |- (: $lift-kb
              ((inheritance-rule-lift $prf) $source-proof $context-proof)
              (Inheritance $instance $ground-concept) $out-tv))))

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
      (let $_instance
         (if (== $stored ())
            (let $source-copy (copy_term $source-stmt)
               (add-atom &inheritance_lift_instance
                  ($hash
                     (inheritance-lift-instance-row
                        $kb $stmt-copy $source-copy))))
            ())
         (empty))))

(: collect-inheritance-lifts-for-context
   (-[det]-> KB KBContext (List CompiledAddition)))
(= (collect-inheritance-lifts-for-context $kb $lift-kb)
   (collapse
      (match &inheritance_lift_instance
         ($_hash
            (inheritance-lift-instance-row
               $kb $ground-stmt $source-stmt))
         (compile-inheritance-lift-instance
            $kb $lift-kb
            (the AnnotatedStatement (copy_term $ground-stmt))
            (the AnnotatedStatement (copy_term $source-stmt))))))

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

(: fact-head (-[det]-> Statement Atom))
(= (fact-head $type) (if (is-expr $type) (car-atom $type) $type))

;; Both structural rules and Inheritance lifts use the same indexed template
;; store. A job carries the emitter to run after its trigger list is grounded.
;; Keeping the triggers with the job lets a newly added fact use this one path
;; regardless of which compiler feature requested specialization.
(: register-specialization-templates!
   (-[det]-> KB (List Atom) (List Atom) SpecializationJob
       (| Bool (List $no-result))))
(= (register-specialization-templates! $_kb () $_triggers $_job) ())
(= (register-specialization-templates! $kb (cons $trigger $rest) $triggers $job)
   (let*
      (($head (fact-head (brand Statement $trigger)))
       ($hash (term_hash (quote ($kb $head))))
       ($registered
          (collapse
             (once
                (match &spec_template
                   ($hash
                      (specialization-template-row
                         $kb $head $_triggers $stored-job))
                   (if (=alpha $stored-job $job) true (empty))))))
       ($_register
          (if (not (== $registered ())) ()
             (let ($triggers-copy $job-copy)
                (copy_term (quote ($triggers $job)))
                (once
                   (add-atom &spec_template
                      ($hash
                         (specialization-template-row
                            $kb $head $triggers-copy $job-copy))))))))
      (register-specialization-templates! $kb $rest $triggers $job)))

;; Bind the trigger variables by matching each remaining trigger against the
;; stored facts; $body shares those variables, so it comes out ground.
(: ground-triggers
   (-[nondet]-> KB (List Atom) SpecializationJob
       SpecializationJob))
(= (ground-triggers $_kb () $body) $body)
(= (ground-triggers $kb (cons $trigger $rest) $body)
   (let $candidate
      (match &kb ($trigger ($kb $_ctx $_vars) $_prf $_tv) $trigger)
      (let $trigger $candidate
         (ground-triggers $kb $rest $body))))

;; Idempotency is per grounded statement, not merely per rule type: distinct
;; proof ids or TVs are independent evidence even when their types coincide.
;; The rule-add and fact-add paths may discover the same statement, so retain
;; the full statement as the stable deduplication key.
(= (emit-specialization $kb
      (compile-specialization (: $gprf $gtype $gtv)))
   (let*
      (($gstmt (: $gprf $gtype $gtv))
       ($copy (copy_term $gstmt))
       ($hash (term_hash $copy))
       ($done
          (collapse
             (once
                (match &spec_done
                   ($hash (specialization-done-row $kb $stored))
                   (if (=alpha $stored $copy) true (empty)))))))
      (if (not (== $done ())) (empty)
         (let $_
            (once
               (add-atom &spec_done
                  ($hash (specialization-done-row $kb $copy))))
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
(: remove-specialization-state! (-[det]-> Proof (List $none)))
(= (remove-specialization-state! $name)
   (let*
      (($_rule-templates
          (collapse
             (remove-atom &spec_template
                ($_rule-hash
                   (specialization-template-row
                      $_rule-kb $_rule-head $_rule-triggers
                      (compile-specialization (: $name $_rule-type $_rule-tv)))))))
       ($_lift-templates
          (collapse
             (remove-atom &spec_template
                ($_lift-hash
                   (specialization-template-row
                      $_lift-kb $_lift-head $_lift-triggers
                      (inheritance-lift-specialization
                         $_lift-ground (: $name $_lift-type $_lift-tv)))))))
       ($_done
          (collapse
             (remove-atom &spec_done
                ($_done-hash
                   (specialization-done-row
                      $_done-kb (: $name $_done-type $_done-tv))))))
       ($_lifts
          (collapse
             (remove-atom &inheritance_lift_instance
                ($_instance-hash
                   (inheritance-lift-instance-row
                      $_instance-kb $_instance-stmt
                      (: $name $_source-type $_source-tv)))))))
      ()))

;; Store a non-rule fact and emit its ordinary derived views. Keeping this
;; separate lets the main compiler normalize supported source syntax before
;; entering the single canonical fact path.
(: compile-ordinary-fact
   (-[nondet]-> KB Proof Statement TV CompiledAddition))
(= (compile-ordinary-fact $kb $prf $Type $tv)
   (let $fact-kb
      (if (context-polymorphic-facts? $kb)
         (make-kb-context $kb $ctx $vars)
         (kbctx $kb))
      (superpose (
         (brand CompiledAddition
            (() |- (: $fact-kb $prf $Type $tv)))
         ;; Concrete Inheritance assertions also act as implication-like
         ;; rules over members. Materializing these views once at compile
         ;; time lets ordinary rule indexing and inference handle inheritance
         ;; without a separate chainer path.
         (if (= $Type (Inheritance $subj $concept))
            (if (concrete-inheritance-link? $subj $concept)
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
                            $ctv)))))
               (empty))
            (empty))
         (compile-specialization-fact-triggers $kb $Type)
         (if (= $Type (Member $_obj $_class))
            (empty)
            (compile-outputs (: $fact-kb $prf $Type $tv)))))))

;; Rule refinement is opt-in per KB and set before its rules are added. A
;; refined rule's truth is the goal (RuleTruth (Implication a b)): the stored
;; truth is its axiom, the rule's instance fold a second proof, and the rule
;; applies, forward, backward and inverted, with their revision. Only named
;; user rules whose sides the instance producer samples are refined.
(: set-rule-refinement (-[det]-> KB Bool Bool))
(= (set-rule-refinement $kb $enabled)
   (let* (($_old
             (collapse (match &rule_refinement ($kb $stored)
                (remove-atom &rule_refinement ($kb $stored)))))
          ($_new (add-atom &rule_refinement ($kb $enabled))))
      $enabled))

;; A refined rule reads its truth `$truth-tv` from the goal first, over a copy
;; of the implication so all its applications share the one general goal.
(: rule-truth-premises (-[det]-> Bool KB Atom Atom (List Goal)))
(= (rule-truth-premises $refine? $kb $truth-type $truth-tv)
   (if $refine?
      (cons (: (kbctx $kb) $truth-prf (copy_term $truth-type) $truth-tv) ())
      ()))

;; A rule stated with confidence 1 (the positive branch of a CTV) is certain:
;; revision leaves it unchanged, so its instances are not folded.
(: refined-rule? (-[det]-> KB Proof Statement Statement TV Bool))
(= (refined-rule? $kb $prf $a $b $tv)
   (if (== (collapse (once (match &rule_refinement ($kb true) true))) ()) false
      (let* (($name (rule-evidence-base-name $prf))
             ($c (case $tv (((STV $_s $c) $c) ((CTV (STV $_s $c) $_neg) $c)))))
         (if (is-expr $name) false
            (if (logic-rule? $name) false
               (if (is-var $c) false
                  (if (>= $c 1.0) false
                     (implication-instance-supported? $a $b))))))))

;; collapse copies what it collects: unifying a copy's antecedent, context and
;; variables with the rule's own relinks the copied lowering to the rule.
(: relinked-lowering
   (-[det]-> Atom Atom Atom (Atom Atom Atom CompiledPremises) CompiledPremises))
(= (relinked-lowering $antecedent $ctx $vars ($antecedent $ctx $vars $lowered)) $lowered)

;; A rule `(Implication a b)`. `$params` are the variables a surrounding
;; `(ForAll $params ...)` binds: the rule holds for each of their values with
;; the same truth, so its instances pool across them, while its base rates are
;; taken per value (see `rule-base-rate-pattern`). `$prior` is the proposition
;; a surrounding `(WithPrior $prior ...)` names as the instance prior of `a`,
;; or `no-prior` (see `prior-inverse-implication`).
(: compile-rule
   (-[nondet]-> KB (List Variable) Atom Proof Statement Statement TV CompiledAddition))
(= (compile-rule $kb $params $prior $prf $antecedent $consequent $tv)
   (let $Type (brand Statement (Implication $antecedent $consequent))
      (let* (($_exists-valid
                  (validate-explicit-exists-rule
                     $antecedent $consequent))
               ($triggers
                  (the (List Atom)
                     (filter-atom
                        (implication-side-conjuncts (brand Statement $antecedent))
                        $premise (specialization-trigger? (brand Statement $premise))))))
        (if (not (== $triggers ()))
         (specialize-rule-add $kb $triggers
            (compile-specialization (: $prf $Type $tv)))
         (let*
            (($_evidence-reg (register-rule-evidence! $kb $prf $tv))
             ;; An explicit existential's lowerings are alternative complete
             ;; antecedents, each a rule of its own; otherwise the complete
             ;; lowering comes first and its settling parts follow.
             ($antecedents
                (if (explicit-exists-term? $antecedent)
                   (cons
                      (lower-implication-antecedent
                         $kb $ctx $vars
                         (brand Statement $antecedent))
                      ())
                   (map-flat (relinked-lowering $antecedent $ctx $vars)
                      (the (List (Atom Atom Atom CompiledPremises))
                         (collapse
                            (let $lowered
                               (lower-implication-antecedent
                                  $kb $ctx $vars
                                  (brand Statement $antecedent))
                               (data $antecedent $ctx $vars $lowered)))))))
             ((cons ($execs $_proofs $_atv) $_settled) $antecedents)
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
             ($pure-conjunction? (pure-conjunction-antecedent? $a))
             ($inverse-plan
                (if (contains-cpu? (execs-goal-type $execs))
                   (compile-reversible-compute-plan $a $b)
                   (inverse-compute-plan
                      () (list_to_set (extract-vars $b)))))
             ($ctv? (if (= $tv (CTV $_pos $_neg)) true false))
             ($refine? (refined-rule? $kb $prf $a $b $tv))
             ($truth-type (RuleTruth (Implication $a $b)))
             ($truth-premises (rule-truth-premises $refine? $kb $truth-type $truth-tv))
             ($_truth-shape
                (if $refine?
                   (collapse (once (add-atom &rule_truth_shapes ($kb $truth-type))))
                   ()))
             ($value (if $refine? $truth-tv $tv)))
            (superpose (
               (compile-implication-forward-rules
                  $kb $shape-kb $adapter-kb $prf $tv $truth-premises $value $params
                  $a $b $antecedent-vars $antecedents)
               ;; The stored truth is the goal's axiom, and the rule's
               ;; instances are folded into a second proof of it.
               (if $refine?
                  (let $refinement
                     (cons (brand CompiledAddition
                              (() |- (: (kbctx $kb) (rule-axiom $prf) $truth-type $tv)))
                        (compile-implication-instance-adds $ctv?
                           $kb (brand Statement $truth-type) $a $b))
                     (superpose $refinement))
                  (empty))
               (case $inverse-plan (
                  ((inverse-compute-plan $inverse-execs $inverse-known)
                     (if (disable-inversion-proof-id? $prf)
                        (empty)
                        (let $na
                           (skolemize-conclusion-vars
                              $prf $inverse-known $a)
                           (superpose (
                              (if (== $prior no-prior) (empty)
                                 (let $instance-prior
                                    (skolemize-conclusion-vars $prf $inverse-known (brand Statement $prior))
                                    (prior-inverse-implication $kb $prf $params $instance-prior
                                       $na $b $tv $value $truth-premises $inverse-execs)))
                              (if (if $ctv? true (not (== $prior no-prior)))
                                 (prior-inverse-implication $kb $prf $params population
                                    $na $b $tv $value $truth-premises $inverse-execs)
                                 (inverse-implication
                                    $kb $prf $params $na $b $value $truth-premises $inverse-execs))
                              (if (is-var $na) (empty)
                                 (if $pure-conjunction?
                                    (empty)
                                    (compile-outputs
                                       (: $adapter-kb
                                          ((inverted $prf $w $pa1 $pa2) $pb2)
                                          $na $natv))))
                              (if (is-var $b) (empty)
                                 (compile-adapter-chain plain
                                    (: $adapter-kb $pb2 $b $btv2))))))))
                  (no-compute-inverse (empty))))
               ;; No inverse rule of any kind for a rule named no_inverse:
               ;; completion recovers an antecedent conjunct from the
               ;; conclusion as inversion recovers the whole antecedent.
               (if (if $pure-conjunction? (not (= $prf (no_inverse $_))) false)
                  (let $children
                     (statement-children (the (List Atom) (cdr-atom $a)))
                     (compile-antecedent-completion
                        $kb $ctx $vars $shape-kb $prf $tv $params
                        $a $b $children 0 $children))
                  (empty))
               (compile-inheritance-rule-lifts $kb (: $prf $Type $tv)
                  (brand Statement $antecedent)
                  (brand Statement $consequent)))))))))

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
       (compile-rule $kb () no-prior $prf (brand Statement $antecedent) (brand Statement $consequent) $tv)
      (if (= $Type (ForAll $params (Implication $antecedent $consequent)))
       (compile-rule $kb (extract-vars $params) no-prior $prf
          (brand Statement $antecedent) (brand Statement $consequent) $tv)
      (if (= $Type (WithPrior $prior (Implication $antecedent $consequent)))
       (compile-rule $kb () $prior $prf
          (brand Statement $antecedent) (brand Statement $consequent) $tv)
      (if (= $Type (ForAll $params (WithPrior $prior (Implication $antecedent $consequent))))
       (compile-rule $kb (extract-vars $params) $prior $prf
          (brand Statement $antecedent) (brand Statement $consequent) $tv)
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
               (compile-ordinary-fact $kb $prf $Type $tv)))))))))))
