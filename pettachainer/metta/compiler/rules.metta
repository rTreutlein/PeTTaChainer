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

;; Only a rule certain in every branch is given. An uncertain CTV branch
;; still learns from its instances when the other branch is certain.
(: refined-rule? (-[det]-> KB Proof Statement Statement TV Bool))
(= (refined-rule? $kb $prf $a $b $tv)
   (if (== (collapse (once (match &rule_refinement ($kb true) true))) ()) false
      (let* (($name (rule-evidence-base-name $prf))
             ($c (case $tv (((STV $_s $c) $c)
                ((CTV (STV $_ps $pc) (STV $_ns $nc))
                   (if (is-var $pc) $pc (if (is-var $nc) $nc (min $pc $nc))))))))
         (if (is-expr $name) false
            (if (logic-rule? $name) false
               (if (is-var $c) false
                  (if (>= $c 1.0) false (implication-instance-supported? $a $b))))))))

;; Rule lowering and structural specialization form one recursive component:
;; derived views and specialization jobs compile new statements through
;; compile_, while compile_ dispatches back into both mechanisms.
;; Classify source computations rather than treating every CPU introduced by
;; lowering as a reason to suppress implication inversion: a connective or a
;; negation lowers through a TV-formula CPU, but an inverse rule can still
;; derive its canonical key. A statement computes when its canonical key does:
;; a connective when a child does, any other statement when its head is a
;; source computation (its arguments are terms, not statements). Actual source
;; computations remain restricted to the explicitly reversible subset; a
;; premise with an unsupported or nested one has no compute goals.
(: computing? (-[det]-> Bool Atom Bool))
(= (computing? $seen $statement)
   (if $seen true
      (let ($key $_odd) (canon (brand Statement $statement))
         (if (compound-source? $key)
            (let $children (the (List Atom) (cdr-atom $key)) (fold-flat computing? false $children))
            (if (is-expr $key) (let $head (car-atom $key) (if (is-var $head) false (source-computation-head? $head))) false)))))
(: source-compute-goals (-[semidet]-> (List Atom) (List Goal)))
(= (source-compute-goals ()) ())
(= (source-compute-goals (cons $premise $rest))
   (if (head-is? $premise Compute)
      (case $premise (
         ((Compute $function $args -> $result)
            (cons (CPU $function $args $result) (source-compute-goals $rest)))
         ((Compute $function $args $result)
            (source-compute-goals (cons (Compute $function $args -> $result) $rest)))))
      (if (computing? false $premise) (empty) (source-compute-goals $rest))))

(: direct-variable-index-or-negative (-[det]-> (List Atom) Variable Number Number))
(= (direct-variable-index-or-negative () $_variable $_index) -1)
(= (direct-variable-index-or-negative (cons $arg $rest) $variable $index)
   (if (if (is-var $arg) (== $arg $variable) false)
      $index
      (direct-variable-index-or-negative $rest $variable (+ $index 1))))

(: compute-args-known-except? (-[det]-> (List Atom) Number (List Variable) Bool))
(= (compute-args-known-except? () $_skip-index $_known) true)
(= (compute-args-known-except? (cons $arg $rest) $skip-index $known)
   (if (== $skip-index 0)
      (compute-args-known-except? $rest -1 $known)
      (if (vars-covered? $arg $known)
         (compute-args-known-except? $rest (- $skip-index 1) $known)
         false)))

;; Inverts compute goals from the conclusion backwards: each goal's one
;; unknown direct input is computed by the inverse operation, then the
;; original goal validates it.
(datatype ComputeInversePlan (inverse-compute-plan (List Goal) (List Variable)))

(: inverse-compute-goals (-[semidet]-> (List Goal) (List Variable) ComputeInversePlan))
(= (inverse-compute-goals () $known) (inverse-compute-plan () $known))
(= (inverse-compute-goals (cons (CPU $function $args $result) $rest) $known)
   (if (vars-covered? $result $known)
      (let* (((cons $unknown ()) (\== (list_to_set (extract-vars $args)) $known))
             ($arg-list (the (List Atom) $args))
             ($unknown-index (direct-variable-index-or-negative $arg-list $unknown 0)))
         (if (or (== $unknown-index -1)
                 (not (compute-args-known-except? $arg-list $unknown-index $known)))
            (empty)
            (let* (((inverse-compute-goal $inverse-goal)
                      (compute-inverse-goal-or-none $function $unknown-index $args $result))
                   ((inverse-compute-plan $rest-goals $final-known)
                      (inverse-compute-goals $rest (list_to_set (cons $unknown $known)))))
               (inverse-compute-plan
                  (cons $inverse-goal (cons (CPU $function $args $result) $rest-goals))
                  $final-known))))
      (empty)))

(: compile-reversible-compute-plan (-[semidet]-> Statement Statement ComputeInversePlan))
;; The plan inverting a rule onto its antecedent; an existential's is open.
(= (compile-reversible-compute-plan $antecedent $consequent)
   (let ($key $_odd) (canon $antecedent)
      (if (head-is-member? $key (Exists ExistentialClaim)) (empty)
         (inverse-compute-goals
            (reverse-onto (source-compute-goals (implication-side-conjuncts $antecedent)) ())
            (list_to_set (extract-vars $consequent))))))

;; Rules stored with an STV need a CTV derived from antecedent/consequent base
;; rates before modus ponens can use them. An explicit CTV already carries both
;; directions and therefore needs no runtime base-rate scans. `$value` is the
;; truth the rule applies with, of its stored truth's kind: the stored truth,
;; or a refined rule's resolved truth.
(: compile-implication-ctv-execs
   (-[semidet]-> KB (List Variable) Statement Statement TV Atom RateUse
       ((List Goal) CTVType LikelihoodRead)))
(= (compile-implication-ctv-execs $_kb $_params $_a $_b (CTV $original-pos $original-neg) $value $_use)
   (data () (the CTVType $value)
      (likelihood-read (the CTVType $value) (the CTVType $value) (stated (CTV $original-pos $original-neg)))))
(= (compile-implication-ctv-execs $kb $params $a $b (STV $_s $_c) $value $use)
   (implication-ctv-goals $kb $params $a $b $value $use))

;; The goals deriving a CTV from the positive branch `$value` and the base
;; rates of both sides; a rule's instance fold and its refined truth derive
;; theirs the same way.
(: implication-ctv-goals
   (-[det]-> KB (List Variable) Statement Statement Atom RateUse ((List Goal) CTVType LikelihoodRead)))
(= (implication-ctv-goals $kb $params $a $b $value $use)
   (let* (($a1 (rule-base-rate-pattern $params $a))
          ($b1 (rule-base-rate-pattern $params $b))
          ($rates (append-flat (antecedent-rate-premises $kb $a1 $rule-atv) (base-rate-premises $kb $b1 $rule-btv)))
          ($centre (unknown-branch-centre $kb $b))
          ($formula (CPU ImplicationLikelihoodsFormula (quote ($rule-atv $rule-btv $value $centre)) $reconciled)))
      (case $use (
         (deferred-rates
            (let* (($ctv (CTV (the STVType $value) (STV $centre 0)))
                   ($a-plan (base-rate-read-plan $kb $a1))
                   ($b-plan (base-rate-read-plan $kb $b1)))
               (data (append-flat $rates
                        ((CPU ReadRate (quote ($kb $a1 $rule-atv $a-plan false)) (rate-read $admissible-a $_read-a))
                         (CPU ReadRate (quote ($kb $b1 $rule-btv $b-plan false)) (rate-read $admissible-b $_read-b))))
                  $ctv (likelihood-read $ctv $ctv
                     (negative-source (the OptionalSTV $admissible-a) (the OptionalSTV $admissible-b) (the STVType $value))))))
         (reconciled-rates
            (data
               (append-flat $rates
                  (cons $formula ((CPU likelihood-read-tv (quote ($reconciled)) $rule-ctv))))
               (the CTVType $rule-ctv) (the LikelihoodRead $reconciled)))
         (learned-rates
            (data
               (append-flat $rates
                  (cons $formula
                     ((CPU with-positive-branch (quote ($value $reconciled)) $likelihoods)
                      (CPU likelihood-read-tv (quote ($likelihoods)) $rule-ctv))))
               (the CTVType $rule-ctv) (the LikelihoodRead $likelihoods)))))))

;; A rule concluding an implication, a → (x → y), holds as its exported form
;; (a ∧ x) → y (docs/metta/derived_implications.md): the conjuncts of its
;; nested antecedents, outermost first, and its innermost consequent.
(: nested-implication-parts (-[semidet]-> Statement ((List Atom) Statement)))
(= (nested-implication-parts $b)
   (if (implication-type? $b)
      (let* (((Implication $x $y) $b)
             (($deeper $last) (nested-implication-parts (brand Statement $y)))
             ($inner (append (implication-side-conjuncts (brand Statement $x)) $deeper)))
         (data $inner $last))
      (data () $b)))

;; Project a rule's consequent before exporting a nested implication. These
;; are conditional projections, not observations of an implication statement.
;; Keep both CTV branches when the source already supplies them.
(: consequent-projection-tv (-[det]-> TV TV))
(= (consequent-projection-tv $tv)
   (case $tv (
      ((STV $s $c) (AndMarginalProjection (STV $s $c)))
      ((CTV $pos $neg) (CTV (AndMarginalProjection $pos) (AndMarginalProjection $neg))))))

(: compile-consequent-implications
   (-[nondet]-> KB KBContext Proof TV (List Goal) Atom RateUse (List Variable)
       Statement Statement CompiledAddition))
(= (compile-consequent-implications $kb $shape-kb $prf $tv $truth-premises $value $use $params $a $b)
   (if (head-is? $b And)
      (let* (($children (statement-children (cdr-atom $b)))
             ($child (superpose $children))
             ($projected-prf (brand Proof (consequent-projection $b $child $prf)))
             ($projected-premises
                (append-flat $truth-premises
                   ((CPU consequent-projection-tv ($value) $projected-tv)))))
         (compile-consequent-implications $kb $shape-kb $projected-prf $tv
            $projected-premises $projected-tv $use $params $a $child))
      (if (implication-type? $b)
         (let* ((($inner $last) (nested-implication-parts $b))
                ($exported-a (brand Statement
                   (seq2expr (append (implication-side-conjuncts $a) $inner)))))
            (superpose (
               ;; Export the projected conditional directly. A named source
               ;; owns this row, including after materialization/withdrawal.
               (if (head-is? $prf consequent-projection)
                  (superpose (
                     (compile-implication-forward-rules $kb $shape-kb $prf $tv
                        $truth-premises $value $use $params $exported-a $last
                        (implication-antecedent-free-vars $exported-a)
                        (antecedent-lowerings $shape-kb $exported-a))
                     (let $producers (producers $shape-kb $exported-a) (superpose $producers))))
                  (empty))
               ;; Another conjunction can hide a further conditional.
               (compile-consequent-implications $kb $shape-kb $prf $tv
                  $truth-premises $value $use $params $exported-a $last))))
         (empty))))

;; Emit the forward rules plus the conclusion's projections: one forward
;; rule per lowering of the antecedent, the complete one and those of its
;; settling parts (see settled-reading). A permanent caller adds the
;; producers of the compound keys the lowerings read. The rule and its adapters
;; (the projections of a compound conclusion, the compound antecedent's
;; connective) share the shape KB: they hold in whatever context the rule
;; applies in, the hypothetical contexts of an implication query included. A
;; conclusion that is an implication is a CTV: its rule's CTV is the exported
;; rule's, and the statement keeps that CTV's negative branch.
(: compile-implication-forward-rules
   (-[nondet]-> KB KBContext Proof TV (List Goal) Atom RateUse (List Variable)
       Statement Statement (List Variable) (List CompiledPremises)
       CompiledAddition))
(= (compile-implication-forward-rules $kb $shape-kb $prf $tv
      $truth-premises $value $use $params $a $b $antecedent-vars $antecedents)
   (let* ((($inner $last) (nested-implication-parts $b))
          ($rate-a (if (== $inner ()) $a (brand Statement (cons And (append (implication-side-conjuncts $a) $inner)))))
          ($mp (if (== $inner ()) CTVModusPonensFormula ImplicationModusPonensFormula))
          ($out-b (skolemize-conclusion-vars $prf (append $params $antecedent-vars) $b)))
     (superpose (
      (let ($execs $proofs $atv) (superpose $antecedents)
       (once
         (let*
            (($proof-token (implication-proof-token $proofs))
              (($ctv-execs $rule-ctv $rule-likelihoods)
                 (compile-implication-ctv-execs $kb $params $rate-a $last $tv $value $use))
              ($allargs
                 (append-flat
                    $truth-premises
                    (append-flat
                       $execs
                       (append-flat $ctv-execs ((CPU $mp ($atv $rule-ctv) $btv)))))))
            (let ($output-key $negative) (canon $out-b)
               (brand CompiledAddition
                  (source-application-plan
                     (forward-source $prf $a $value $negative
                        (if (if (== $inner ()) (is-var $atv) false) (not (computing? false $a)) false))
                     (case $tv (
                        ((STV $_s $_c)
                           (cons (data $kb (rule-base-rate-pattern $params $rate-a))
                              (cons (data $kb (rule-base-rate-pattern $params $last)) ())))
                        ($_ctv ())))
                     (canonical-addition $shape-kb $allargs
                        (brand Proof (quote (by $prf $proof-token))) $out-b $btv)))))))
      (if (is-var $out-b) (empty) (compile-outputs (: $shape-kb (by $prf $prfb) $out-b $btv2)))))))

;; A sample rule's premises and its proof's arguments, built conjunct by
;; conjunct, and the antecedent truth values.
(datatype InstanceSampleParts (instance-sample-parts (List Goal) (List Atom) (List Atom)))
(: implication-instance-premise (-[det]-> KB Atom InstanceSampleParts InstanceSampleParts))
(= (implication-instance-premise $kb $conjunct (instance-sample-parts $premises $proofs $tvs))
   (instance-sample-parts
      (cons (: (kbctx $kb) $prf $conjunct $tv) $premises)
      (cons $prf $proofs)
      (cons $tv $tvs)))

;; The sample rule and the fold rule concluding `$Type`. With `$ctv?` the fold
;; concludes a CTV: P(B | A) from the instances where the antecedent holds and
;; P(B | not A) from those where it fails, or, while no antecedent-false
;; instance was seen, from both sides' base rates, as a stored STV rule does;
;; otherwise it concludes the positive branch as an STV. A negated antecedent
;; (Not A) has A's samples and fold, the same rows as A's: its instances are
;; A's antecedent-false ones, so it concludes A's fold with the branches
;; swapped, once such an instance was seen.
(: compile-implication-instance-adds
   (-[det]-> Bool KB Statement Statement Statement (List CompiledAddition)))
(= (compile-implication-instance-adds $ctv? $kb $Type $stated $consequent)
   (let ($antecedent $negated) (canon $stated)
      (if (implication-instance-supported? $antecedent $consequent)
         (let*
            (($conjuncts (implication-side-conjuncts $antecedent))
             ($single (== (cdr-atom $conjuncts) ()))
             ;; The antecedent premises come first, then the conjunction of
             ;; their truth values (`$tvs`, bound by the fold below), then the
             ;; consequent; the sample proof lists their proofs in that order.
             ($parts
                (foldr-flat (implication-instance-premise $kb)
                   (instance-sample-parts $consequent-goals (cons $bprf ()) ())
                   $conjuncts)))
            (case $parts (
               ((instance-sample-parts $premises $proofs $tvs)
                  (let*
                     (($consequent-goals
                         (case $tvs (
                            ((cons $first $more)
                               (if $single (cons (: (kbctx $kb) $bprf $consequent $btv) ())
                                  (and-tv-goals AndFormula $first $more $and-tv (cons (: (kbctx $kb) $bprf $consequent $btv) ())))))))
                      ($atv (if $single (car-atom $tvs) $and-tv))
                      ($sample-pattern (ImplicationInstanceSample $antecedent $consequent $atv $btv))
                      ($fold
                         (CPU FoldAllCompiled
                            (quote
                               ($kb $sample-pattern
                                  (extract-value $sample-pattern (WeightedTv $atv $btv))
                                  (InstanceEvidence (BaseRateEvidence 0.0 0.0) (BaseRateEvidence 0.0 0.0))
                                  ImplicationInstanceAcc implication-instance-ctv result-tv))
                            $fold-tv))
                      ($positive (CPU InstanceEvidenceFormula ($ctv? $fold-tv) $instance-tv))
                      (($ctv-goals $instance-ctv $_instance-likelihoods)
                         (implication-ctv-goals $kb () $antecedent $consequent $instance-tv learned-rates))
                      ($fold-premises
                         (cons $fold
                            (if $negated (cons (CPU opposite-instance-tv ($fold-tv) $opposite-tv) ())
                               (cons $positive (if $ctv? $ctv-goals ())))))
                      ($fold-result (if $negated $opposite-tv (if $ctv? $instance-ctv $instance-tv))))
                     ;; Built with cons: the determinism checker reads a tuple
                     ;; headed by a variable, ($premises |- ...), as a call.
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
         ())))
(: opposite-instance-tv (-[semidet]-> TV CTVType))
(= (opposite-instance-tv $tv) (case $tv (((CTV $pos $neg) (CTV $neg $pos)))))

;; Compile the backward use of an implication stated with an STV: derive its
;; negative branch from the base rates of both sides and invert by the ratio
;; P(A|B) = P(B|A) P(A) / P(B) over the reconciled base rates. A rule stated
;; with a CTV gives both likelihoods and is inverted by Bayes' rule over the
;; antecedent's base rate instead (`prior-inverse-implication` with
;; `population`), which needs no P(B): an empirical P(B) inconsistent with
;; P(A) and the stated likelihoods would otherwise decide the inversion. This
;; is emitted only when the main compiler has proved the antecedent is
;; invertible. Reversible Compute goals bind antecedent variables first and
;; validate the generated binding with the original forward computation.
(: inverse-implication
   (-[semidet]-> KB Proof (List Variable) Statement Statement Atom (List Goal) (List Goal)
       CompiledAddition))
(= (inverse-implication $kb $prf $params $a $b $itv $truth-premises $inverse-execs)
   (let*
      (($a1 (rule-base-rate-pattern $params $a))
        ($b1 (rule-base-rate-pattern $params $b))
        ($b-plan (base-rate-read-plan $kb $b1))
        ($ctv (CTV (the STVType $itv) (STV (unknown-branch-centre $kb $b) 0)))
        ($rule-likelihoods (likelihood-read $ctv $ctv (negative-source (the OptionalSTV $raw-atv) (the OptionalSTV $btv) (the STVType $itv)))))
      (brand CompiledAddition
       (source-application-plan (reverse-source $prf population)
        (cons (data $kb $a1) (cons (data $kb $b1) ()))
        (inversion-addition (make-kb-context $kb $ctx $vars) $prf cpu $truth-premises $a $b $inverse-execs
         (append-flat (prior-base-rate-premises $kb $a1 $raw-atv $atv)
            (append-flat (base-rate-premises $kb $b1 $raw-btv)
               (the (List Goal)
                  ((CPU ReadRate (quote ($kb $b1 $raw-btv $b-plan false)) (rate-read $btv $_read-btv))
                   (CPU ReadLikelihoodContext () $read-context)
                   (CPU rule-likelihood-read (quote ($kb $prf $a1 $b1 $rule-likelihoods $read-context)) $read-likelihoods)
                   (CPU CTVInversionFormula (quote ($atv $btv $read-likelihoods)) $iitv)))))
         $atv $iitv)))))

;; Whether an inversion or completion target is a stage (prolog/sorts.pl):
;; one the rule's own sorts make a stage is one in every instance, so `$stage`
;; is `true` at compile time; otherwise its instance is checked when read.
(: stage-goals (-[det]-> KB Atom Atom Atom (List Goal)))
(= (stage-goals $kb $target $sides $stage)
   (if (stage-statement? $kb $target $sides)
      (let $stage true (the (List Goal) ()))
      (the (List Goal) ((CPU stage-statement? (quote ($kb $target ())) $stage)))))

;; An inversion: the observation of b read through `lower`, the inverse
;; computations, the goals `$estimate` binding the inversion `$iitv` over a's
;; prior `$atv`, and b's value as its likelihood ratio over the prior it was
;; formed under (ObservationRatioFormula). It concludes a's canonical key, so
;; a rule on (Not s) concludes s with value and prior complemented: the rule on
;; s with its branches swapped. The proof carries the prior, so updates of one
;; prior merge by Bayes' rule (sk-factored-merge).
(: inversion-addition
   (-[semidet]-> KBContext Proof Atom (List Goal) Statement Statement (List Goal) (List Goal) Atom Atom
       CompiledAddition))
(= (inversion-addition $kc $prf $token $truth-premises $a $b $inverse-execs $estimate $atv $iitv)
   (let* (((premise-bundle $b-goals $btv_wit $prfb_wit) (lower $kc $b))
          (($kb $_ctx $_vars) $kc)
          (($key $odd) (canon $a))
          ($premises
             (append-flat $truth-premises
                (append-flat $b-goals
                   (append-flat $inverse-execs
                      (append-flat $estimate
                         (append-flat (stage-goals $kb $key ($a $b) $stage)
                            (the (List Goal)
                               ((CPU sk-observation-prior (quote ($kb $prfb_wit $btv_wit $stage)) $obs-prior)
                                (CPU ObservationRatioFormula (quote ($btv_wit $obs-prior $atv $iitv)) $obs-tv)
                                (CPU CTVModusPonensFormula (quote ($obs-tv $iitv)) $mp-tv)))))))))
          (($polarity $key-tv $key-prior)
             (if $odd (data ((CPU NotFormula ($mp-tv) $not-tv) (CPU NotFormula ($atv) $not-prior)) $not-tv $not-prior)
                (data () $mp-tv $atv))))
      (brand CompiledAddition
         ((append-flat $premises (the (List Goal) $polarity))
            |- (: $kc ((inverted $prf with $token (prior $key-prior)) $prfb_wit) $key $key-tv)))))

;; Resolve a finite likelihood once after reading its observation. Certain
;; CTVs are already resolved: no contextual CPU goals or centre dependency.
;; STV lowering already watches both marginals, so it needs no second watch.
(: likelihood-read-premises
   (-[semidet]-> KB Proof Statement Statement TV LikelihoodRead ((List Goal) Atom)))
(= (likelihood-read-premises $kb $rule $antecedent $consequent $tv $initial)
   (let $goals (the (List Goal)
          ((CPU ReadLikelihoodContext () $context)
           (CPU rule-likelihood-read
              (quote ($kb $rule $antecedent $consequent $initial $context)) $read)))
      (case $tv (
         ((CTV (STV $_u $cu) (STV $_v $cv))
            (if (if (>= $cu 1.0) (>= $cv 1.0) false)
               (data () $initial)
               (data (append-flat (base-rate-premises $kb $consequent $_centre) $goals) $read)))
         ($_stv (data $goals $read))))))

;; Ordered population cohorts read while resolving source likelihoods. This
;; accompanies application plans; consumers never infer cohorts from CPU code.
(: source-likelihood-cohorts (-[det]-> KB Statement Statement TV (List (KB Statement))))
(= (source-likelihood-cohorts $kb $a $b $tv)
   (case $tv (
      ((STV $_s $_c) (cons (data $kb $a) (cons (data $kb $b) ())))
      ((CTV (STV $_p $cp) (STV $_n $cn))
         (if (if (>= $cp 1.0) (>= $cn 1.0) false) () (cons (data $kb $b) ()))))))

;; A rule declared `(WithPrior p (Implication a b))` is inverted per
;; instance by Bayes' rule: P(a) is the instance's prior and P(b) follows from
;; it and the rule by total probability, so an observation of b updates what is
;; believed about this instance, never contradicting the rule. The prior is the truth of `p`
;; for the observed instance, or, with `population`, a's base rate for an
;; instance without one; the first's evidence contains the second's, so it
;; replaces that answer wherever `p` is provable. A plain rule stated with a CTV
;; is inverted with `population` alone.
(: prior-inverse-implication
   (-[semidet]-> KB Proof (List Variable) Atom Statement Statement TV Atom
       (List Goal) (List Goal) CompiledAddition))
(= (prior-inverse-implication $kb $prf $params $prior $a $b $tv $value
      $truth-premises $inverse-execs)
   (let*
      (($kc (make-kb-context $kb $ctx $vars))
       ($a-rate-pattern (rule-base-rate-pattern $params $a))
       ($b-rate-pattern (rule-base-rate-pattern $params $b))
       ($population (== $prior population))
       ($prior-goals
          (if $population
             (prior-base-rate-premises $kb $a-rate-pattern $_raw-prior $atv)
             (cons (: $kc $prior-prf (brand Statement $prior) $raw-atv)
                ((CPU instance-prior-tv (quote ($kb $prior-prf $raw-atv)) $atv)))))
       (($ctv-execs $rule-ctv $rule-likelihoods)
          (compile-implication-ctv-execs $kb $params $a $b $tv $value deferred-rates))
       (($read-goals $read-likelihoods)
          (likelihood-read-premises $kb $prf $a-rate-pattern $b-rate-pattern $tv $rule-likelihoods))
       ($cohorts (source-likelihood-cohorts $kb $a-rate-pattern $b-rate-pattern $tv))
       ($prior-token (if $population cpu $prior-prf)))
      (brand CompiledAddition
       (source-application-plan (reverse-source $prf $prior)
        (if $population (cons (data $kb $a-rate-pattern) $cohorts) $cohorts)
        (inversion-addition $kc $prf $prior-token $truth-premises $a $b $inverse-execs
         (append-flat $prior-goals
            (append-flat (append-flat $ctv-execs $read-goals)
               ((CPU CTVBayesFormula (quote ($atv $read-likelihoods)) $iitv))))
         $atv $iitv)))))

;; Complete each child M of a pure And/Or H from its siblings O and original
;; consequence C; whole-H inversion proves H without projecting its children.
;; Negated H uses its De Morgan dual, and a negated child completes its key.
;; The recipe records the opening polarity and statement-input positions.
;; C updates M's prior through the likelihood marginalised over O. H's own
;; independent evidence conditions that prior and O (CompoundEvidence), and
;; supplies the proof's first `cpu` token, so completions combine over the
;; same prior. Formula details and limitations: prior_factored_merge.md.
;; The connective over a compound's children, or its one child.
(: connective-statement (-[det]-> Atom (List Statement) Statement))
(= (connective-statement $connective (cons $head $tail))
   (if (== $tail ()) $head (brand Statement (cons $connective (cons $head $tail)))))
(: compile-antecedent-completion
   (-[nondet]-> KB KBContext Proof TV (List Goal) Atom (List Variable)
       Statement Statement (List Statement) Number (List Statement)
       CompiledAddition))
(= (compile-antecedent-completion
      $kb $shape-kb $prf $tv $truth-premises $value $params
      $full $consequent $children $idx (cons $missing $rest))
   (superpose (
      (if (is-var $missing)
         (empty)
         (let* (($others (remove-index $idx $children))
                (($key $odd) (canon $full))
                ($connective (if $odd (if (head-is? $key And) Or And) (car-atom $key)))
                ($known (brand Statement (seq2expr (append $others (cons $consequent ()))))))
            ;; A missing conjunct that alone links the others' variables would be
            ;; inferred for every combination of unrelated instances; only a
            ;; conjunct whose variables the rest already connects is completed.
            (if (if (vars-covered? $missing (list_to_set (extract-vars $known)))
                   (== (cdr-atom (conjunct-parts (implication-side-conjuncts $known))) ())
                   false)
               (let*
                  ((($others-execs $others-proofs $others-tv)
                      (complete-lowering $shape-kb (connective-statement $connective $others)))
                   (($consequent-execs $consequent-proofs $consequent-tv)
                      (complete-lowering $shape-kb $consequent))
                   (($target $negated) (canon $missing))
                   ($inputs (append-flat $truth-premises (append-flat $others-execs $consequent-execs)))
                   ($recipe (completion-recipe
                      (- (length (filter-atom $inputs $input (not (head-is? $input CPU)))) 1) 0
                      (if (== $connective And) (not $negated) $negated)))
                   ($antecedent-rate-pattern (rule-base-rate-pattern $params $full))
                   ($consequence-rate-pattern (rule-base-rate-pattern $params $consequent))
                   (($rule-execs $rule-ctv $rule-likelihoods)
                      (compile-implication-ctv-execs $kb $params $full $consequent $tv $value deferred-rates))
                   (($read-goals $read-rule-likelihoods)
                      (likelihood-read-premises $kb $prf $antecedent-rate-pattern $consequence-rate-pattern
                         $tv $rule-likelihoods))
                   ($cohorts (source-likelihood-cohorts $kb $antecedent-rate-pattern $consequence-rate-pattern $tv))
                   ($target-cohort (data $kb (rule-base-rate-pattern $params $target)))
                   ($all-cohorts (append-flat $cohorts (cons $target-cohort ())))
                   ($proof-token
                      (implication-proof-token (append $others-proofs $consequent-proofs)))
                   ($consequent-proof (implication-proof-token $consequent-proofs))
                   ($premises
                      (append-flat $truth-premises
                         (append-flat $others-execs
                            (append-flat $consequent-execs
                            (cons (CPU CompoundEvidence (quote ($kb $key $consequent $shape-kb)) (key-evidence $key-tv $key-formed $_key-proof))
                            (append-flat (append-flat $rule-execs $read-goals)
                               (append-flat
                                  (prior-base-rate-premises $kb
                                     (rule-base-rate-pattern $params $target) $_raw-target $target-base-tv)
                                  (append-flat (stage-goals $kb $target ($full $consequent) $stage)
                                  (the (List Goal)
                                     ((CPU CompletionEvidenceFormula
                                         (quote ($connective $negated $odd $target-base-tv $others-tv $key-tv $key-formed))
                                         (completion-given $target-prior $others-given $conditioned))
                                      (CPU CompletionLikelihoodsFormula
                                         (quote ($connective $negated $conditioned $others-given $read-rule-likelihoods))
                                         $likelihood-read)
                                      (CPU CTVBayesFormula
                                         (quote ($target-prior $likelihood-read)) $completion-ctv)
                                      (CPU sk-observation-prior
                                         (quote ($kb $consequent-proof $consequent-tv $stage))
                                         $consequent-prior)
                                      (CPU ObservationRatioFormula
                                         (quote ($consequent-tv $consequent-prior $target-prior $completion-ctv))
                                         $consequent-obs-tv)
                                      (CPU CTVModusPonensFormula
                                         (quote ($consequent-obs-tv $completion-ctv))
                                         $out-tv))))))))))))
                  (brand CompiledAddition
                   (source-application-plan structural-source
                    $all-cohorts
                     ((cons (CPU ReadLikelihoodContext $recipe $_recipe-context) $premises) |-
                        (: $shape-kb
                           ((antecedent-completion $prf $idx with cpu (prior $target-prior))
                            $proof-token)
                           $target $out-tv)))))
               (empty))))
      (compile-antecedent-completion
         $kb $shape-kb $prf $tv $truth-premises $value $params
         $full $consequent $children (+ $idx 1) $rest))))

;; A grounded rule is one specialization job. The specialization engine below
;; handles template indexing and late facts.
(datatype SpecializationJob (compile-specialization (List Variable) Atom AnnotatedStatement))

;; These rows cross atom-space storage boundaries, so their tags are stable
;; schemas rather than local multiple-return wrappers.

(datatype SpecializationTemplateRow (specialization-template-row KB Atom (List Atom) SpecializationJob))

(datatype SpecializationDoneRow (specialization-done-row KB SpecializationJob))

(: emit-specialization (-[nondet]-> KB SpecializationJob CompiledAddition))
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
            (if (not (== (collapse (match &logic_config (specializing-predicate $head) true)) ())) (not (== (extract-vars $premise) ())) false)))
      false))

(: fact-head (-[det]-> Statement Atom))
(= (fact-head $type) (if (is-expr $type) (car-atom $type) $type))

;; Structural rules use an indexed template store. A job carries the emitter
;; to run after its trigger list is grounded, so a newly added fact grounds it
;; through this one path.
(: register-specialization-templates!
   (-[det]-> KB (List Atom) (List Atom) SpecializationJob (| Bool (List $no-result))))
(= (register-specialization-templates! $_kb () $_triggers $_job) ())
(= (register-specialization-templates! $kb (cons $trigger $rest) $triggers $job)
   (let*
      (($head (fact-head (brand Statement $trigger)))
       ($hash (term_hash (quote ($kb $head))))
       ($registered
          (collapse
             (once
                (match &spec_template
                   ($hash (specialization-template-row $kb $head $_triggers $stored-job))
                   (if (=alpha $stored-job $job) true (empty))))))
       ($_register
          (if (== $registered ())
             (let ($triggers-copy $job-copy)
                (copy_term (quote ($triggers $job)))
                (once
                   (add-atom &spec_template
                      ($hash (specialization-template-row $kb $head $triggers-copy $job-copy)))))
             ())))
      (register-specialization-templates! $kb $rest $triggers $job)))

;; Bind the trigger variables by matching each remaining trigger against the
;; stored facts; $body shares those variables, so it comes out ground.
(: ground-triggers (-[nondet]-> KB (List Atom) SpecializationJob SpecializationJob))
(= (ground-triggers $_kb () $body) $body)
(= (ground-triggers $kb (cons $trigger $rest) $body)
   (let* (($candidate (match &kb ($trigger ($kb $_ctx $_vars) $_prf $_tv) $trigger))
          ($trigger $candidate))
      (ground-triggers $kb $rest $body)))

;; Deduplicate complete rule specifications: parameters and prior as well as
;; source proof, sides and TV. Rule-add and fact-add can discover the same job.
(= (emit-specialization $kb $job)
   (let*
      (((compile-specialization $params $prior (: $gprf (Implication $a $b) $gtv)) $job)
       ($copy (copy_term $job))
       ($hash (term_hash $copy))
       ($done
          (collapse
             (once
                (match &spec_done
                   ($hash (specialization-done-row $kb $stored))
                   (if (=alpha $stored $copy) true (empty)))))))
      (if (== $done ())
         (let $_
            (once (add-atom &spec_done ($hash (specialization-done-row $kb $copy))))
            (compile-rule $kb $params $prior $gprf
               (brand Statement $a) (brand Statement $b) $gtv))
         (empty))))

;; Rule-add: retain the job for later facts and also ground it against facts
;; already in the KB.
(: specialize-rule-add (-[nondet]-> KB (List Atom) SpecializationJob CompiledAddition))
(= (specialize-rule-add $kb $triggers $job)
   (let $_register
      (register-specialization-templates! $kb $triggers $triggers $job)
      (emit-specialization $kb (ground-triggers $kb $triggers $job))))

;; Fact-add: the new fact is not in &kb yet, so pin the trigger it satisfies
;; directly in each compatible position, then resolve the remaining triggers
;; against the store.
(: ground-specialization-with-fact
   (-[nondet]-> KB Statement (List Atom) (List Atom) SpecializationJob SpecializationJob))
(= (ground-specialization-with-fact $kb $fact (cons $trigger $rest) $before $job)
   (superpose
      ((let $_ (let $trigger $fact ok) (ground-triggers $kb (append $before $rest) $job))
       (ground-specialization-with-fact $kb $fact $rest (append $before ($trigger)) $job))))

(: compile-specialization-fact-triggers (-[nondet]-> KB Statement CompiledAddition))
(= (compile-specialization-fact-triggers $kb $type)
   (let*
      (($head (fact-head $type)) ($hash (term_hash (quote ($kb $head)))))
      (match &spec_template
         ($hash (specialization-template-row $kb $head $stored-triggers $stored-job))
         (let
            ($triggers $job)
            (copy_term (quote ($stored-triggers $stored-job)))
            (emit-specialization $kb
               (ground-specialization-with-fact
                  $kb $type
                  (the (List Atom) $triggers) ()
                  (the SpecializationJob $job)))))))

;; Store a non-rule fact and emit its ordinary derived views. Keeping this
;; separate lets the main compiler normalize supported source syntax before
;; entering the single canonical fact path.
(: compile-ordinary-fact (-[nondet]-> KB Proof Statement TV CompiledAddition))
(= (compile-ordinary-fact $kb $prf $Type $tv)
   (let $fact-kb
      (if (space-row-present? &context_polymorphic_facts (quote ($kb true))) (make-kb-context $kb $ctx $vars) (kbctx $kb))
      (superpose (
         (brand CompiledAddition (() |- (: $fact-kb $prf $Type $tv)))
         (compile-specialization-fact-triggers $kb $Type)
         ;; Stored compounds use the ordinary source merge. Supply its partial
         ;; part proof without making the report itself an input of that proof.
         (if (head-is-member? $Type (And Or))
            (let* (($parts (compound-parts $Type (statement-children (list_to_set (cdr-atom $Type)))))
                   (($goals $tvs $proofs $_tokens $_keys)
                      (lower-node-siblings $fact-kb $Type (node-joint-part) $parts true)))
               (reading-addition $fact-kb $Type
                  (premise-bundle
                     (append-flat (the (List Goal) $goals)
                        ((CPU compound-bounds (quote ($Type $parts $tvs $proofs)) (bound-result $bound-tv $bound-proof))))
                     $bound-tv (brand Proof $bound-proof))))
            (empty))
         (if (if (head-is? $Type And)
                (case $tv (((STV $s $c) (if (>= $s 1.0) (>= $c 1.0) false)) ($_other false)))
                false)
            ;; One hard observation entails every conjunct with its original
            ;; identity. Materialize these views without constructing a node.
            (let* (($children (conjunct-leaves (the (List Atom) (cdr-atom $Type)) ()))
                   ($child (superpose $children)))
               (compile_ $kb (: (joint-source $prf $Type) (brand Statement $child) $tv)))
            (compile-outputs (: $fact-kb $prf $Type $tv)))))))

;; A refined rule reads its truth `$truth-tv` from the goal first, over a copy
;; of the implication so all its applications share the one general goal. The
;; typed result keeps the premise list a (List Goal) for strict mode.
(: rule-truth-premises (-[det]-> Bool KB Atom Atom (List Goal)))
(= (rule-truth-premises $refine? $kb $truth-type $truth-tv)
   (if $refine? (cons (: (kbctx $kb) $truth-prf (copy_term $truth-type) $truth-tv) ()) ()))

;; A derived implication is applied by modus ponens like a rule
;; (docs/metta/derived_implications.md): one statement rule per implication
;; shape a rule concludes reads the statement's rule-derived value, a CTV,
;; and its antecedent; its proof applies the statement's proof. A nested
;; consequent gets its own statement rule.
(: compile-implication-statement-rules (-[nondet]-> KB Statement CompiledAddition))
(= (compile-implication-statement-rules $kb $statement)
   (if (implication-type? $statement)
      (let* (($shape (quote ($kb $statement))) ($hash (index-hash $shape)))
         (if (== (collapse (once (match &implication_statement_rules ($hash $stored)
                   (if (=alpha $stored $shape) true (empty))))) ())
            (let* (($_row (add-atom &implication_statement_rules ($hash $shape)))
                   ((Implication $x $y) (copy_term $statement))
                   ($shape-kb (make-kb-context $kb $ctx $vars))
                   ($source-prf (brand Proof (derived-implication $statement-prf)))
                   ($ctv (the TV (CTV $pos $neg))))
               (superpose (
                  (compile-implication-forward-rules $kb $shape-kb (brand Proof $statement-prf) $ctv
                     (cons (: $shape-kb $source-prf (Implication $x $y) $ctv) ()) $ctv reconciled-rates ()
                     (brand Statement $x) (brand Statement $y)
                     (list_to_set (extract-vars (Implication $x $y)))
                     (antecedent-lowerings $shape-kb (brand Statement $x)))
                  (let $producers (producers $shape-kb (brand Statement $x)) (superpose $producers))
                  (compile-implication-statement-rules $kb (brand Statement $y)))))
            (empty)))
      (empty)))

;; A rule `(Implication a b)`. `$params` are the variables a surrounding
;; `(ForAll $params ...)` binds: the rule holds for each of their values with
;; the same truth, so its instances pool across them, while its base rates are
;; taken per value (see `rule-base-rate-pattern`). `$prior` is the proposition
;; a surrounding `(WithPrior $prior ...)` names as the instance prior of `a`,
;; or `no-prior` (see `prior-inverse-implication`).
(: compile-rule (-[nondet]-> KB (List Variable) Atom Proof Statement Statement TV CompiledAddition))
(= (compile-rule $kb $params $prior $prf $antecedent $consequent $tv)
   (let* (($Type (brand Statement (Implication $antecedent $consequent)))
          ($_exists-valid (validate-explicit-exists-rule $antecedent $consequent))
          ($triggers
             (the (List Atom)
                (filter-atom
                   (implication-side-conjuncts (brand Statement $antecedent))
                   $premise (specialization-trigger? (brand Statement $premise))))))
      (if (not (== $triggers ()))
         (specialize-rule-add $kb $triggers (compile-specialization $params $prior (: $prf $Type $tv)))
         (let*
            (($_evidence-reg (register-rule-evidence! $kb $prf $tv (== (extract-vars $Type) ())))
             ($shape-kb (make-kb-context $kb $ctx $vars))
             ($antecedents (antecedent-lowerings $shape-kb (brand Statement $antecedent)))
             ;; A nested conjunction is read as the flat one (#142).
             ($flat-antecedent (if (head-is? $antecedent And)
                (cons And (implication-side-conjuncts (brand Statement $antecedent)))
                $antecedent))
             ($a (brand Statement (implication-source-term $flat-antecedent)))
             ($b
                (if (explicit-exists-term? $consequent)
                   (canonical-existential-side (brand Statement $consequent))
                   (brand Statement (implication-source-term $consequent))))
             ($antecedent-vars (implication-antecedent-free-vars $antecedent))
             (($a-key $a-odd) (canon $a))
             ($pure-connective? (if (head-is-member? $a-key (And Or)) (not (computing? false $a-key)) false))
             ($ctv? (if (= $tv (CTV $_pos $_neg)) true false))
             ($refine? (refined-rule? $kb $prf $a $b $tv))
             ($truth-type (RuleTruth (Implication $a $b)))
             ($a-opposite (if $a-odd $a-key (brand Statement (Not $a-key))))
             ($truth-premises (rule-truth-premises $refine? $kb $truth-type $truth-tv))
             ($_truth-shape
                (if $refine?
                   (let* (($_positive (add-atom &rule_truth_shapes ($kb $truth-type)))
                          ($_negative (if $ctv? (add-atom &rule_truth_shapes ($kb (RuleTruth (Implication $a-opposite $b)))) ())))
                      ())
                   ()))
             ($value (if $refine? $truth-tv $tv))
             ($use (if $refine? learned-rates reconciled-rates))
             ($_equivalence (if $refine? () (register-equivalence-rule! $kb $prf $tv $a $b))))
            (let $application (superpose (
               ;; Source truth lives at its ordinary statement key. The
               ;; executable CTV uses the immutable stated value directly,
               ;; with the ordinary base rates supplied by its permanent row.
               (let* ((($inner $last) (nested-implication-parts $b))
                      ($source-b (skolemize-conclusion-vars $prf (append $params $antecedent-vars) $b))
                      ($source-type (brand Statement (Implication $antecedent $source-b)))
                      ($query-type
                         (if (contains-explicit-exists? $Type)
                            (let $canonical (Implication
                                   (canonical-existential-side (brand Statement $antecedent))
                                   (canonical-existential-side (brand Statement $consequent)))
                               (brand Statement (QuantifiedRule (index-hash $canonical) $canonical)))
                            $source-type)))
                  (superpose (
                     (case $tv (
                        ((CTV $source-pos $source-neg)
                           (superpose (
                              (brand CompiledAddition
                                 (() |- (: (kbctx $kb) $prf $source-type $tv)))
                              (brand CompiledAddition
                                 (() |- (: (kbctx $kb) $prf (Implication $a-opposite $source-b)
                                    (CTV $source-neg $source-pos))))
                              (if (=alpha $source-type $query-type) (empty)
                                 (brand CompiledAddition
                                    (() |- (: (kbctx $kb) $prf $query-type $tv)))))))
                        ((STV $s $c)
                           (let* (($rate-a (if (== $inner ()) $a
                                     (brand Statement (cons And (append (implication-side-conjuncts $a) $inner)))))
                                  (($ctv-execs $source-ctv $_source-likelihoods)
                                     (compile-implication-ctv-execs $kb $params $rate-a $last $tv $tv reconciled-rates)))
                              (superpose (
                                 (brand CompiledAddition
                                    (() |- (: (kbctx $kb) $prf $source-type $tv)))
                                 (if (=alpha $source-type $query-type) (empty)
                                    (brand CompiledAddition (() |- (: (kbctx $kb) $prf $query-type $tv))))
                                 (brand CompiledAddition
                                    ($ctv-execs |- (: (kbctx $kb) $prf $source-type $source-ctv)))))))))
                     ;; The variables a nested implication of the source binds
                     ;; are its own: a projection reads the source apart from them.
                     (let* (($bound (\== (list_to_set (extract-vars $source-b)) (append $params $antecedent-vars)))
                            ($source (sealed $bound (: (kbctx $kb) $prf $source-type $tv))))
                        (compile-consequent-implications $kb $shape-kb $prf $tv
                           (cons $source $truth-premises) $value $use $params $a $b)))))
               (compile-implication-forward-rules
                  $kb $shape-kb $prf $tv $truth-premises $value $use $params
                  $a $b $antecedent-vars $antecedents)
               (if (is-var $a) (empty) (let $producers (producers $shape-kb $a) (superpose $producers)))
               ;; The stored truth is the goal's axiom, and the rule's
               ;; instances are folded into a second proof of it.
               (if $refine?
                  (let $refinement
                     (cons (brand CompiledAddition
                              (() |- (: (kbctx $kb) (rule-axiom $prf) $truth-type $tv)))
                        (compile-implication-instance-adds $ctv?
                           $kb (brand Statement $truth-type) $a $b))
                     (superpose (
                        (superpose $refinement)
                        (if $ctv?
                           (brand CompiledAddition
                              (((: (kbctx $kb) $refined-proof $truth-type (CTV $refined-pos $refined-neg)))
                                 |- (: (kbctx $kb) (rule-opposite $refined-proof)
                                    (RuleTruth (Implication $a-opposite $b))
                                    (CTV $refined-neg $refined-pos))))
                           (empty)))))
                  (empty))
               ;; An antecedent whose computations cannot be inverted has no
               ;; inverse rule. BiImplication lowering already emits both
               ;; directions; inverting either again would add a redundant
               ;; Bayesian version of its explicitly emitted peer.
               (if (if (head-is-member? $prf (no_inverse bi-forward bi-backward)) true (implication-type? $b))
                  (empty)
                  (let* (((inverse-compute-plan $inverse-execs $inverse-known)
                            (compile-reversible-compute-plan $a $b))
                         ($na (skolemize-conclusion-vars $prf (append $params $inverse-known) $a)))
                     (superpose (
                        (if (== $prior no-prior) (empty)
                           (let $instance-prior
                              (skolemize-conclusion-vars $prf (append $params $inverse-known) (brand Statement $prior))
                              (prior-inverse-implication $kb $prf $params $instance-prior
                                 $na $b $tv $value $truth-premises $inverse-execs)))
                        (if (if $ctv? true (not (== $prior no-prior)))
                           (prior-inverse-implication $kb $prf $params population
                              $na $b $tv $value $truth-premises $inverse-execs)
                           (inverse-implication
                              $kb $prf $params $na $b $value $truth-premises $inverse-execs))
                        (if (is-var $na) (empty)
                           (if $pure-connective?
                              (empty)
                              (let ($na-key $_na-odd) (canon $na)
                                 (compile-outputs
                                    (: $shape-kb ((inverted $prf $w $pa1 $pa2) $pb2) $na-key $natv)))))
                        (if (is-var $b) (empty)
                           (let $producers (producers $shape-kb $b) (superpose $producers)))))))
               ;; No inverse rule of any kind for a rule named no_inverse:
               ;; completion recovers an antecedent conjunct from the
               ;; conclusion as inversion recovers the whole antecedent. Both
               ;; read the conclusion as an observation, and a derived
               ;; implication is not one.
               (if (if $pure-connective? (if (= $prf (no_inverse $_)) false (not (implication-type? $b))) false)
                  (let* (($key-children (statement-children (the (List Atom) (cdr-atom $a-key))))
                         ($children (if $a-odd (map-flat (|-> ($child) (brand Statement (Not $child))) $key-children) $key-children))
                         ($full (if $a-odd (brand Statement (Not $a-key)) $a-key)))
                     (compile-antecedent-completion
                        $kb $shape-kb $prf $tv $truth-premises $value $params
                        $full $b $children 0 $children))
                  (empty))
               (compile-implication-statement-rules $kb $b)))
               (brand CompiledAddition
                  (source-rule-plan
                     (source-rule $prf $shape-kb $a $b $tv $params $prior
                        (collapse (compile-reversible-compute-plan $a $b)))
                     $application)))))))

;; Main statement compiler.
;;
;; Implications become forward rules, optional inverse rules, and adapters.
;; Bidirectional forms are split into two ordinary implications. Facts are
;; stored directly, with projections for configured compound outputs. Structural specialization is
;; checked before generic implication compilation so variable-headed templates
;; never leak into the broad `any` index.
(: compile_ (-[nondet]-> KB AnnotatedStatement  CompiledAddition))
(= (compile_ $kb (: $prf $Type $tv))
   (if (source-rule? $Type)
      (case $Type (
         ((Implication $antecedent $consequent)
            (compile-rule $kb () no-prior $prf
               (brand Statement $antecedent) (brand Statement $consequent) $tv))
         ((ForAll $params (Implication $antecedent $consequent))
            (compile-rule $kb (extract-vars $params) no-prior $prf
               (brand Statement $antecedent) (brand Statement $consequent) $tv))
         ((WithPrior $prior (Implication $antecedent $consequent))
            (compile-rule $kb () $prior $prf
               (brand Statement $antecedent) (brand Statement $consequent) $tv))
         ((ForAll $params (WithPrior $prior (Implication $antecedent $consequent)))
            (compile-rule $kb (extract-vars $params) $prior $prf
               (brand Statement $antecedent) (brand Statement $consequent) $tv))))
      (if (implication-type? $Type) (empty)
         ;; An asserted negation keeps the source name and is stored at its
         ;; canonical key, with complemented strength when the count is odd
         ;; (ingestion accepts only an STV on a negation).
         (if (head-is? $Type Not)
            (let ($key $odd) (canon $Type)
               (if $odd
                  (let (STV $s $c) $tv (compile_ $kb (: $prf $key (STV (- 1.0 $s) $c))))
                  (compile_ $kb (: $prf $key $tv))))
            ;; An existential fact is its claim; an existential nested in a
            ;; connective is no fact form yet.
            (if (explicit-exists-term? $Type)
               (compile-ordinary-fact $kb $prf (canonical-existential-side $Type) $tv)
               (if (source-exists? $Type) (empty)
                  (if (bidirectional-implication-type? $Type)
                     (let ($_head $left $right) $Type
                        (superpose (
                           (compile_ $kb (: (bi-forward $prf) (Implication $left $right) $tv))
                           (compile_ $kb (: (bi-backward $prf) (Implication $right $left) $tv)))))
                     (compile-ordinary-fact $kb $prf $Type $tv))))))))
