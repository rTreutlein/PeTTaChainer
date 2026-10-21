;; Rule lowering and structural specialization form one recursive component:
;; derived views and specialization jobs compile new statements through
;; compile_, while compile_ dispatches back into both mechanisms.
;; Classify source computations rather than treating every CPU introduced by
;; lowering as a reason to suppress implication inversion. A pure top-level Or
;; lowers through a TV-formula CPU, but an inverse rule can still derive the
;; complete disjunction and let its ordinary projection adapters recover one
;; child. Actual source computations remain restricted to the explicitly
;; reversible subset. Pure And and Or antecedents can be inverted as complete
;; compounds; a child of either is recovered only by completion. A premise
;; with an unsupported or nested source computation has no compute goals.
(: source-compute-goals (-[semidet]-> (List Atom) (List Goal)))
(= (source-compute-goals ()) ())
(= (source-compute-goals (cons $premise $rest))
   (if (head-is? $premise Compute)
      (case $premise (
         ((Compute $function $args -> $result)
            (cons (CPU $function $args $result) (source-compute-goals $rest)))
         ((Compute $function $args $result)
            (source-compute-goals (cons (Compute $function $args -> $result) $rest)))))
      (if (contains-head? source-computation-head? $premise) (empty) (source-compute-goals $rest))))

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
(: ComputeInversePlan Type)
(: inverse-compute-plan (-[det]-> (List Goal) (List Variable) ComputeInversePlan))

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
(= (compile-reversible-compute-plan $antecedent $consequent)
   (let* (($compute-goals (source-compute-goals (implication-side-conjuncts $antecedent)))
          ($known (list_to_set (extract-vars $consequent))))
      (if (== $compute-goals ())
         (if (head-is-member? $antecedent (And Or)) (inverse-compute-plan () $known) (empty))
         (inverse-compute-goals (prepend-reversed-goals $compute-goals ()) $known))))

;; The pattern a rule's base rate is taken over: a fresh copy of one of its
;; sides, except the variables a surrounding ForAll binds, which stay shared
;; with the rule application so the rate is taken per parameter value.
(: rule-base-rate-pattern (-[det]-> (List Variable) Statement Statement))
(= (rule-base-rate-pattern $params $side)
   (let ($params $pattern) (copy_term ($params (rule-query-pattern $side)))
      (brand Statement $pattern)))

(: RatePlan Type)
(: rate-plan (-[det]-> (List Goal) Atom RatePlan))
(: base-rate-read-plan (-[det]-> KB Statement RatePlan))
(= (base-rate-read-plan $kb $pattern)
   (let $goals (base-rate-premises $kb $pattern $result) (rate-plan $goals $result)))

;; Rules stored with an STV need a CTV derived from antecedent/consequent base
;; rates before modus ponens can use them. An explicit CTV already carries both
;; directions and therefore needs no runtime base-rate scans. `$value` is the
;; truth the rule applies with, of its stored truth's kind: the stored truth,
;; or a refined rule's resolved truth.
(: compile-implication-ctv-execs
   (-[semidet]-> KB (List Variable) Statement Statement TV Atom Bool
       ((List Goal) CTVType LikelihoodRead)))
(= (compile-implication-ctv-execs $_kb $_params $_a $_b (CTV $original-pos $original-neg) $value $_defer)
   (data () (the CTVType $value)
      (likelihood-read (the CTVType $value) (the CTVType $value) (stated (CTV $original-pos $original-neg)))))
(= (compile-implication-ctv-execs $kb $params $a $b (STV $_s $_c) $value $defer)
   (implication-ctv-goals $kb $params $a $b $value $defer))

;; The goals deriving a CTV from the positive branch `$value` and the base
;; rates of both sides; a rule's instance fold and its refined truth derive
;; theirs the same way.
(: implication-ctv-goals
   (-[det]-> KB (List Variable) Statement Statement Atom Bool ((List Goal) CTVType LikelihoodRead)))
(= (implication-ctv-goals $kb $params $a $b $value $defer)
   (let* (($a1 (rule-base-rate-pattern $params $a))
          ($b1 (rule-base-rate-pattern $params $b))
          ($rates (append-goals (antecedent-rate-premises $kb $a1 $rule-atv) (base-rate-premises $kb $b1 $rule-btv))))
         (if $defer
            (let* (($ctv (CTV (the STVType $value) (STV 0.5 0)))
                   ($a-plan (base-rate-read-plan $kb $a1))
                   ($b-plan (base-rate-read-plan $kb $b1)))
               (data (append-goals $rates
                        ((CPU ReadRate (quote ($kb $a1 $rule-atv $a-plan false)) (rate-read $admissible-a $_read-a))
                         (CPU ReadRate (quote ($kb $b1 $rule-btv $b-plan false)) (rate-read $admissible-b $_read-b))))
                  $ctv (likelihood-read $ctv $ctv
                     (negative-source (the OptionalSTV $admissible-a) (the OptionalSTV $admissible-b) (the STVType $value)))))
            (data
               (append-goals $rates
                  (cons (CPU ImplicationLikelihoodsFormula
                           (quote ($rule-atv $rule-btv $value)) $likelihoods)
                     ((CPU likelihood-read-tv (quote ($likelihoods)) $rule-ctv))))
               (the CTVType $rule-ctv) (the LikelihoodRead $likelihoods)))))

;; A negated conclusion is stored as positive evidence for its inner expression
;; with a negated proof and transformed TV. Keeping the runtime type positive
;; lets it share the ordinary fact indexes.
(: compile-implication-output
   (-[det]-> Proof Proof Statement STVType ((List Goal) Proof Statement STVType)))
(= (compile-implication-output $prf $proof-token $b $btv)
   (if (head-is? $b Not)
      (case $b (
         ((Not $inner)
            (data
               ((CPU NotFormula ($btv) $out-tv))
               (brand Proof (negated (quote (by $prf $proof-token))))
               (brand Statement $inner)
               (the STVType $out-tv)))
         ($_other (data () (brand Proof (quote (by $prf $proof-token))) $b $btv))))
      (data () (brand Proof (quote (by $prf $proof-token))) $b $btv)))

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
   (-[nondet]-> KB KBContext Proof TV (List Goal) Atom (List Variable)
       Statement Statement CompiledAddition))
(= (compile-consequent-implications $kb $shape-kb $prf $tv $truth-premises $value $params $a $b)
   (if (head-is? $b And)
      (let* (($children (statement-children (cdr-atom $b)))
             ($child (superpose $children))
             ($projected-prf (brand Proof (consequent-projection $b $child $prf)))
             ($projected-premises
                (append-goals $truth-premises
                   ((CPU consequent-projection-tv ($value) $projected-tv)))))
         (compile-consequent-implications $kb $shape-kb $projected-prf $tv
            $projected-premises $projected-tv $params $a $child))
      (if (implication-type? $b)
         (let* ((($_kbid $ctx $vars) $shape-kb)
                (($inner $last) (nested-implication-parts $b))
                ($exported-a (brand Statement
                   (seq2expr (append (implication-side-conjuncts $a) $inner)))))
            (superpose (
               ;; Export the projected conditional directly. A named source
               ;; owns this row, including after materialization/withdrawal.
               (if (head-is? $prf consequent-projection)
                  (compile-implication-forward-rules $kb $shape-kb $prf $tv
                     $truth-premises $value $params $exported-a $last
                     (implication-antecedent-free-vars $exported-a)
                     (antecedent-lowerings $kb $ctx $vars $exported-a))
                  (empty))
               ;; Another conjunction can hide a further conditional.
               (compile-consequent-implications $kb $shape-kb $prf $tv
                  $truth-premises $value $params $exported-a $last))))
         (empty))))

;; Emit the forward rules plus the adapters needed on both sides: one forward
;; rule per lowering of the antecedent, the complete one and those of its
;; settling parts (see settled-premise-bundle). The rule and its adapters
;; (the projections of a compound conclusion, the compound antecedent's
;; connective) share the shape KB: they hold in whatever context the rule
;; applies in, the hypothetical contexts of an implication query included. A
;; conclusion that is an implication is a CTV: its rule's CTV is the exported
;; rule's, and the statement keeps that CTV's negative branch.
(: compile-implication-forward-rules
   (-[nondet]-> KB KBContext Proof TV (List Goal) Atom (List Variable)
       Statement Statement (List Variable) (List CompiledPremises)
       CompiledAddition))
(= (compile-implication-forward-rules $kb $shape-kb $prf $tv
      $truth-premises $value $params $a $b $antecedent-vars $antecedents)
   (let* ((($inner $last) (nested-implication-parts $b))
          ($rate-a (if (== $inner ()) $a (brand Statement (cons And (append (implication-side-conjuncts $a) $inner)))))
          ($mp (if (== $inner ()) CTVModusPonensFormula ImplicationModusPonensFormula))
          ($out-b (skolemize-conclusion-vars $prf (append $antecedent-vars (extract-vars $inner)) $b)))
     (superpose (
      (let ($execs $proofs $atv) (superpose $antecedents)
       (once
         (let*
            (($proof-token (implication-proof-token $proofs))
              (($ctv-execs $rule-ctv $rule-likelihoods)
                 (compile-implication-ctv-execs $kb $params $rate-a $last $tv $value false))
              (($out-execs $out-prf $out-type $out-tv)
                 (compile-implication-output $prf $proof-token $out-b (the STVType $btv)))
              ($allargs
                 (append-goals
                    $truth-premises
                    (append-goals
                       $execs
                       (append-goals
                          $ctv-execs
                          (append-goals ((CPU $mp ($atv $rule-ctv) $btv)) $out-execs))))))
            (brand CompiledAddition ($allargs |- (: $shape-kb $out-prf $out-type $out-tv))))))
      (if (is-var $out-b) (empty) (compile-outputs (: $shape-kb (by $prf $prfb) $out-b $btv2)))
      (if (is-var $a) (empty) (compile-adapter-chain plain (: $shape-kb $prfa $a $adapter-atv)))))))

(: rule-evidence-base-name (-[det]-> Proof Proof))
(= (rule-evidence-base-name $prf)
   (if (= $prf (bi-forward $fwd)) (brand Proof $fwd)
      (if (= $prf (bi-backward $bwd)) (brand Proof $bwd)
         (if (= $prf (no_inverse $inner)) (brand Proof $inner) $prf))))

(: rule-evidence-registered? (-[det]-> KB Proof Bool))
(= (rule-evidence-registered? $kbid $name)
   (not (== (collapse (once (match &rule_evidence_names ($name $kbid) true))) ())))

;; Ground given rules, by name and KB. A ground implication is knowledge about
;; its particular instances, as a fact is: its applications carry a certain
;; rule-ev entry, so a view that never applied it cannot stand for one that
;; did. A general given rule stays a parameter and carries no entry.
(: &given_rules (SpaceOf (Proof KB)))
!(bind! &given_rules (new-space))

(: given-rule? (-[det]-> KB Proof Bool))
(= (given-rule? $kbid $name) (not (== (collapse (once (match &given_rules ($name $kbid) true))) ())))

;; A rule's applications carry its evidence when its truth is an estimate, so
;; a proof of the rule (its axiom) and a proof through it are not independent;
;; two applications to different premises are, given the rule's truth (see
;; sk-merge-facts). A rule stated with confidence 1 in every branch is not
;; refined (`refined-rule?`): its truth is given, and carries no evidence. A
;; given rule whose every branch has strength 0 or 1 is deterministic: applied
;; to certain premises it determines its conclusion (sk-determined-row?).
(: register-rule-evidence! (-[det]-> KB Proof TV Bool (List $no-result)))
(= (register-rule-evidence! $kb $prf $tv $ground)
   (let $name (rule-evidence-base-name $prf)
      (if (is-expr $name) ()
         (if (logic-rule? $name) ()
            (if (rule-evidence-registered? $kb $name) ()
               (case $tv (
                  ((STV $s $c) (register-given-branches! $kb $name $ground (cons (STV $s $c) ())))
                  ((CTV $pos $neg) (register-given-branches! $kb $name $ground (cons $pos (cons $neg ()))))
                  ($_other (register-rule-evidence-name! $kb $name)))))))))

(: register-given-branches! (-[det]-> KB Proof Bool (List TV) (List $no-result)))
(= (register-given-branches! $kb $name $ground $branches)
   (if (fold-flat given-branch-step true $branches)
      (if (fold-flat deterministic-branch-step true $branches)
         (if (deterministic-rule? $kb $name) ()
            (let $_added (add-atom &deterministic_rules ($name $kb)) (if $ground (register-given-rule! $kb $name) ())))
         (if $ground (register-given-rule! $kb $name) ()))
      (register-rule-evidence-name! $kb $name)))

(: register-given-rule! (-[det]-> KB Proof (List $no-result)))
(= (register-given-rule! $kb $name)
   (if (given-rule? $kb $name) () (let $_added (add-atom &given_rules ($name $kb)) ())))

(: given-branch-step (-[det]-> Bool TV Bool))
(= (given-branch-step $given $branch)
   (if $given (case $branch (((STV $_s $c) (if (is-var $c) false (>= $c 1.0))) ($_other false))) false))

(: deterministic-branch-step (-[det]-> Bool TV Bool))
(= (deterministic-branch-step $deterministic $branch)
   (if $deterministic
      (case $branch (((STV $s $_c) (if (is-var $s) false (if (<= $s 0.0) true (>= $s 1.0)))) ($_other false)))
      false))

(: register-rule-evidence-name! (-[det]-> KB Proof (List $no-result)))
(= (register-rule-evidence-name! $kb $name)
   (let $_added (collapse (once (add-atom &rule_evidence_names ($name $kb)))) ()))

;; given rules whose every branch has strength 0 or 1, by name and KB
(: &deterministic_rules (SpaceOf (Proof KB)))
!(bind! &deterministic_rules (new-space))

(: deterministic-rule? (-[det]-> KB Proof Bool))
(= (deterministic-rule? $kbid $name) (not (== (collapse (once (match &deterministic_rules ($name $kbid) true))) ())))

;; Estimate the base rate required to reinterpret an STV rule as a CTV. Open
;; inheritance antecedents use universe-aware weighted evidence; a concrete
;; inheritance target may have a configured/dynamic concept prior, so its fold
;; is seeded with that prior and sparse observations revise the prior instead
;; of silently behaving like an uninformative generic predicate. Ordinary
;; patterns use the generic evidence accumulator.
(: base-rate-fold (-[det]-> KB Statement $truth-value Goal))
(= (base-rate-fold $kb $pattern $brtv)
   (let ($extractor $initial $accumulator $finish)
      (if (if (head-is? $pattern Inheritance)
              (if (= $pattern (Inheritance $x $subj)) (is-var $x) false) false)
         (if (is-var $subj)
            (data (extract-inheritance-tv $kb $pattern) (BaseRateEvidence 0.0 0.0)
               WeightedBaseRateAcc (weighted-base-rate-in-universe $kb))
            (data (extract-inheritance-tv $kb $pattern)
               (BaseRateEvidenceWithPrior (brand BaseRatePrior (ConceptNodePriorRuntime $kb $subj))
                  (BaseRateEvidence 0.0 0.0))
               WeightedBaseRateWithPriorAcc (weighted-base-rate-with-prior-in-universe $kb)))
         (data extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate))
      (CPU FoldAllCompiled
         (quote ($kb $pattern $extractor $initial $accumulator $finish result-tv))
         $brtv)))

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
      (cons (base-rate-fold $kb (brand Statement (seq2expr (the (List Atom) $part))) $tv) $goals)
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
            (case $tvs (((cons $first $more) (append-goals $goals (and-tv-goals BaseRateProductFormula $first $more $brtv ()))))))))))

;; The conjunction of truth values, multiplied left to right by the binary
;; `$formula` (AndFormula, as a lowered antecedent multiplies them, or
;; BaseRateProductFormula for base rates). Followed by the goals `$tail`.
(: and-tv-goals (-[det]-> Atom Atom (List Atom) Atom (List Goal) (List Goal)))
(= (and-tv-goals $formula $acc (cons $tv $rest) $result $tail)
   (if (== $rest ())
      (cons (CPU $formula (quote ($acc $tv)) $result) $tail)
      (cons (CPU $formula (quote ($acc $tv)) $partial) (and-tv-goals $formula $partial $rest $result $tail))))

;; The premises reading the base rate of an STV rule's antecedent, from which
;; its negative branch is derived. A positive-only predicate's stored
;; instances are no sample of its population and their rate (1) estimates
;; nothing: reconciled with it, P(B | A) would be pulled to P(B). Such an
;; antecedent reads as no evidence.
(: antecedent-rate-premises (-[det]-> KB Statement $truth-value (List Goal)))
(= (antecedent-rate-premises $kb $pattern $atv)
   (if (positive-only-pattern? $kb $pattern)
      (append-goals (base-rate-premises $kb $pattern $rate)
         (cons (CPU explicit-antecedent-rate-tv (quote ($kb $pattern $rate)) $atv) ()))
      (base-rate-premises $kb $pattern $atv)))

;; The declaration describes biased samples, never an explicit user estimate.
;; Read the setting at evaluation so setting or clearing a rate also updates
;; rows compiled before it. Keep the fold as a premise to track those changes.
(: user-base-rate? (-[det]-> KB Statement Bool))
(= (user-base-rate? $kb $pattern)
   (let $hash (index-hash (quote ($kb $pattern)))
      (not (== (collapse (once (match &ctx_base_rate_cache
         ($hash (base-rate $kb $stored $_tv user any))
         (if (=alpha $stored $pattern) true (empty))))) ()))))
(: explicit-antecedent-rate-tv (-[det]-> KB Statement TV TV))
(= (explicit-antecedent-rate-tv $kb $pattern $rate)
   (if (user-base-rate? $kb $pattern) $rate no-evidence))

;; The premises reading a pattern's base rate as the prior an inversion or an
;; antecedent completion updates. A rate is the share of true members among
;; those counted; the prior of one more member is its mean under the Bayes
;; prior, as Bayes' rule reads a likelihood (bayes-shrink, centred on 0.5).
;; A rate of 0 or 1 from finitely many members then leaves an instance
;; either way possible, and its updates keep their likelihood ratios for a
;; view in the base rate's place. A predicate declared positive-only has no
;; such empirical prior; an explicit user rate still permits an update, and
;; the row is a rule only while one is set (kb-add-gated-rule!).
;; Functional inputs remain non-derivable regardless of population settings.
(: prior-base-rate-premises (-[semidet]-> KB Statement $raw-value $truth-value (List Goal)))
(= (prior-base-rate-premises $kb $pattern $raw $brtv)
   (if (functional-pattern? $kb $pattern) (empty)
      (let $plan (base-rate-read-plan $kb $pattern)
         (append-goals (base-rate-premises $kb $pattern $rate)
            (cons (CPU ReadRate (quote ($kb $pattern $rate $plan true)) (rate-read $raw $brtv)) ())))))
(: configured-population-prior-tv (-[semidet]-> KB Statement TV TV))
(= (configured-population-prior-tv $kb $pattern $rate)
   (if (if (positive-only-pattern? $kb $pattern) (user-base-rate? $kb $pattern) true)
      (population-prior-tv $rate) (empty)))
(: population-prior-tv (-[det]-> TV TV))
(= (population-prior-tv (STV $s $c)) (STV (bayes-shrink $s $c 0.5 1.0) $c))
(= (population-prior-tv (CTV $pos $neg)) (CTV $pos $neg))
;; A supported inversion may need a neutral bridge when excluding the target
;; drains its population. This carries no observation or prior evidence.
(= (population-prior-tv no-evidence) (STV 0.5 0.0))

;; A KB may declare that it stores only the true instances of a predicate
;; (logic KBs of Provable, Path or Ancestor facts): its stored instances are
;; then no sample of the predicate's population, their rate (1) estimates
;; nothing, and an inversion over it would assert every antecedent of every
;; stored conclusion. Declared before the rules that would be inverted onto
;; it are added.
(: &positive_only_predicates (SpaceOf (KB Atom)))
!(bind! &positive_only_predicates (new-space))

(: set-positive-only-predicate (-[det]-> KB Atom Bool))
(= (set-positive-only-predicate $kb $head)
   (if (== (collapse (once (match &positive_only_predicates ($kb $head) true))) ())
      (let $_row (add-atom &positive_only_predicates ($kb $head)) true)
      true))

;; A pattern one of whose conjuncts (or a negated conjunct's statement) has a
;; positive-only predicate.
(: positive-only-pattern? (-[det]-> KB Statement Bool))
(= (positive-only-pattern? $kb $pattern)
   (fold-flat (positive-only-conjunct? $kb) false (implication-side-conjuncts $pattern)))
(: positive-only-conjunct? (-[det]-> KB Bool Atom Bool))
(= (positive-only-conjunct? $kb $seen $conjunct)
   (if $seen true
      (let* (($statement (if (head-is? $conjunct Not) (car-atom (cdr-atom $conjunct)) $conjunct))
             ($head (if (is-expr $statement) (car-atom $statement) $statement)))
         (not (== (collapse (once (match &positive_only_predicates ($kb $head) true))) ())))))

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
(: instance-sample-parts (-[det]-> (List Goal) (List Atom) (List Atom) InstanceSampleParts))
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
   (let* (($negated (head-is? $stated Not))
          ($antecedent (if $negated (brand Statement (car-atom (cdr-atom $stated))) $stated)))
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
                      ($finish (if (if $negated true $ctv?) implication-instance-ctv implication-instance))
                      ($sample-pattern (ImplicationInstanceSample $antecedent $consequent $atv $btv))
                      ($fold
                         (CPU FoldAllCompiled
                            (quote
                               ($kb $sample-pattern
                                  (extract-value $sample-pattern (WeightedTv $atv $btv))
                                  (InstanceEvidence (BaseRateEvidence 0.0 0.0) (BaseRateEvidence 0.0 0.0))
                                  ImplicationInstanceAcc $finish result-tv))
                            $fold-tv))
                      ($positive (CPU MemberInheritanceEvidenceFormula ($fold-tv) $instance-tv))
                      (($ctv-goals $instance-ctv $_instance-likelihoods)
                         (implication-ctv-goals $kb () $antecedent $consequent $instance-tv false))
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
        ($a-base-rates (prior-base-rate-premises $kb $a1 $raw-atv $atv))
        ($b-plan (base-rate-read-plan $kb $b1))
        ($b-base-rates (append-goals (base-rate-premises $kb $b1 $raw-btv)
                          ((CPU ReadRate (quote ($kb $b1 $raw-btv $b-plan false)) (rate-read $btv $_read-btv)))))
        ($ctv (CTV (the STVType $itv) (STV 0.5 0)))
        ($rule-likelihoods (likelihood-read $ctv $ctv (negative-source (the OptionalSTV $raw-atv) (the OptionalSTV $btv) (the STVType $itv))))
        ($formula-goals
           (the (List Goal)
              ((CPU ReadLikelihoodContext () $read-context)
               (CPU rule-likelihood-read (quote ($kb $prf $a1 $b1 $rule-likelihoods $read-context)) $read-likelihoods)
               (CPU CTVInversionFormula (quote ($atv $btv $read-likelihoods)) $iitv)
               (CPU sk-observation-prior (quote ($prfb_wit $btv_wit)) $obs-prior)
               (CPU ObservationRatioFormula (quote ($btv_wit $obs-prior $atv $iitv)) $obs-tv)
               (CPU CTVModusPonensFormula (quote ($obs-tv $iitv)) $mp-tv))))
        ($premises
           (append-goals
              (append-goals $truth-premises
                 (cons (: (make-kb-context $kb $ctx $vars) $prfb_wit $b $btv_wit) ()))
              (append-goals
                 $inverse-execs
                 (append-goals $a-base-rates (append-goals $b-base-rates $formula-goals))))))
      ($premises |-
         (: (make-kb-context $kb $ctx $vars)
              ((inverted $prf with cpu (prior $atv)) $prfb_wit)
              $a $mp-tv))))

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
               (data (append-goals (base-rate-premises $kb $consequent $_centre) $goals) $read)))
         ($_stv (data $goals $read))))))

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
      (($a-rate-pattern (rule-base-rate-pattern $params $a))
       ($b-rate-pattern (rule-base-rate-pattern $params $b))
       ($population (== $prior population))
       ($prior-goals
          (if $population
             (prior-base-rate-premises $kb (rule-base-rate-pattern $params $a) $_raw-prior $atv)
             (cons (: (make-kb-context $kb $ctx $vars) $prior-prf (brand Statement $prior) $raw-atv)
                ((CPU instance-prior-tv (quote ($prior-prf $raw-atv)) $atv)))))
       ($prior-token (if $population cpu $prior-prf))
       (($ctv-execs $rule-ctv $rule-likelihoods)
          (compile-implication-ctv-execs $kb $params $a $b $tv $value true))
       (($read-goals $read-likelihoods)
          (likelihood-read-premises $kb $prf $a-rate-pattern $b-rate-pattern $tv $rule-likelihoods))
       ($premises
          (append-goals $truth-premises
             (cons (: (make-kb-context $kb $ctx $vars) $prfb_wit $b $btv_wit)
                (append-goals $inverse-execs
                   (append-goals $prior-goals
                      (append-goals (append-goals $ctv-execs $read-goals)
                         (the (List Goal)
                            ((CPU CTVBayesFormula (quote ($atv $read-likelihoods)) $iitv)
                             (CPU sk-observation-prior (quote ($prfb_wit $btv_wit)) $obs-prior)
                             (CPU ObservationRatioFormula (quote ($btv_wit $obs-prior $atv $iitv)) $obs-tv)
                             (CPU CTVModusPonensFormula (quote ($obs-tv $iitv)) $mp-tv))))))))))
      ($premises |-
         (: (make-kb-context $kb $ctx $vars)
            ((inverted $prf with $prior-token (prior $atv)) $prfb_wit)
            $a $mp-tv))))

;; For every child M of a pure conjunction or disjunction H, compile the
;; completion (And O C) -> M, where O is the connective over H's other
;; children and C is the original consequence. That is the only
;; child-recovery operator for a pure And or Or: whole-H inversion still
;; proves H itself, but does not also project to each child. The completion
;; inverts the rule onto M over M's base rate, as a plain inversion inverts
;; onto its antecedent, with C's likelihoods given M and not M at O's value
;; (ConjunctLikelihoodFormula, DisjunctLikelihoodFormula), so it is the joint
;; posterior over O and M; C's value enters as its likelihood ratio
;; (ObservationRatioFormula). Projecting the inverted disjunction instead
;; read O as known and the disjunction under its unconditioned prior, so a
;; known disjunct did not condition it. A negated child (Not I) completes I,
;; the statement its observations and base rate are about. The proof carries
;; the base rate, so the completion merges with other updates of it by
;; Bayes' rule (sk-factored-merge).
;; A conjunction or disjunction is pure when no child computes, a negated
;; child counting by the statement it negates.
(: computing-child? (-[det]-> Bool Atom Bool))
(= (computing-child? $seen $child)
   (if $seen true
      (let $statement (if (head-is? $child Not) (car-atom (cdr-atom $child)) $child)
         (contains-head? source-computation-head? $statement))))
;; The connective over a compound's children, or its one child.
(: connective-statement (-[det]-> Atom (List Statement) Statement))
(= (connective-statement $connective (cons $head $tail))
   (if (== $tail ()) $head (brand Statement (cons $connective (cons $head $tail)))))
(: compile-antecedent-completion
   (-[nondet]-> KB $context $variables KBContext Proof TV (List Goal) Atom (List Variable)
       Statement Statement (List Statement) Number (List Statement)
       CompiledAddition))
(= (compile-antecedent-completion
      $kb $ctx $vars $shape-kb $prf $tv $truth-premises $value $params
      $full $consequent $children $idx (cons $missing $rest))
   (superpose (
      (if (is-var $missing)
         (empty)
         (let* (($others (remove-index $idx $children))
                ($connective (car-atom $full))
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
                            $kb $ctx $vars (connective-statement $connective $others))))
                   (($consequent-execs $consequent-proofs $consequent-tv)
                      (once (lower-implication-antecedent $kb $ctx $vars $consequent)))
                   ($antecedent-rate-pattern (rule-base-rate-pattern $params $full))
                   ($consequence-rate-pattern (rule-base-rate-pattern $params $consequent))
                   (($rule-execs $rule-ctv $rule-likelihoods)
                      (compile-implication-ctv-execs $kb $params $full $consequent $tv $value true))
                   (($read-goals $read-rule-likelihoods)
                      (likelihood-read-premises $kb $prf $antecedent-rate-pattern $consequence-rate-pattern
                         $tv $rule-likelihoods))
                   ($proof-token
                      (implication-proof-token (append $others-proofs $consequent-proofs)))
                   ($consequent-proof (implication-proof-token $consequent-proofs))
                   ($negated (head-is? $missing Not))
                   ($target (if $negated (brand Statement (car-atom (cdr-atom $missing))) $missing))
                   ($premises
                      (append-goals $truth-premises
                         (append-goals $others-execs
                            (append-goals $consequent-execs
                            (append-goals (append-goals $rule-execs $read-goals)
                               (append-goals
                                  (prior-base-rate-premises $kb
                                     (rule-base-rate-pattern $params $target) $_raw-target $target-base-tv)
                                  (the (List Goal)
                                     ((CPU CompletionLikelihoodsFormula
                                         (quote ($connective $negated $others-tv $read-rule-likelihoods)) $likelihood-read)
                                      (CPU CTVBayesFormula
                                         (quote ($target-base-tv $likelihood-read)) $completion-ctv)
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
         $kb $ctx $vars $shape-kb $prf $tv $truth-premises $value $params
         $full $consequent $children (+ $idx 1) $rest))))

(: concrete-inheritance-link? (-[det]-> Atom Atom Bool))
(= (concrete-inheritance-link? $subj $concept) (not (or (is-var $subj) (is-var $concept))))

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
   (if (if (head-is? $premise Inheritance) (= $premise (Inheritance $premise-subj $_concept)) false)
      (== $premise-subj $subj)
      false))

(: inheritance-lift-auxiliary-premises (-[det]-> (List Atom) $subject (List Atom)))
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
   (-[semidet]-> (List Atom) (List Atom) $subject $instance ((List Atom) (List Atom))))
(= (inheritance-lift-parts () () $_source-subj $_instance) (data () ()))
(= (inheritance-lift-parts
      (cons $ground-premise $ground-rest)
      (cons $source-premise $source-rest)
      $source-subj $instance)
   (let ($contextual $auxiliary)
      (inheritance-lift-parts $ground-rest $source-rest $source-subj $instance)
      (if (inheritance-context-premise? $source-premise $source-subj)
         (let (Inheritance $_ground-subj $ground-concept) $ground-premise
            (data (cons (Inheritance $instance $ground-concept) $contextual) $auxiliary))
         (data $contextual (cons $ground-premise $auxiliary)))))

;; Compile a specialized relational rule into one fixed query context. The
;; rule's positive STV is already its conditional estimate; unlike an observed
;; Inheritance link it does not need to be inferred again from population base
;; rates. Explicit CTV rules retain both branches.
(: inheritance-lift-ctv (-[semidet]-> TV CTVType))
(= (inheritance-lift-ctv (CTV $pos $neg)) (CTV $pos $neg))
(= (inheritance-lift-ctv (STV $s $c)) (CTV (STV $s $c) (STV 0.0 1.0)))

(: compile-inheritance-lift-instance
   (-[semidet]-> KB KBContext AnnotatedStatement AnnotatedStatement CompiledAddition))
(= (compile-inheritance-lift-instance $kb $lift-kb
      (: $prf (Implication $ground-antecedent (Inheritance $ground-subj $ground-concept)) $tv)
      (: $_source-prf
         (Implication $source-antecedent (Inheritance $source-subj $_source-concept))
         $_source-tv))
   (let*
      ((($kbid $ctx $vars) $lift-kb)
       (($contextual-premises $auxiliary-premises)
          (inheritance-lift-parts
             (implication-side-conjuncts (brand Statement $ground-antecedent))
             (implication-side-conjuncts (brand Statement $source-antecedent))
             $source-subj $instance))
       ($lift-premises
          (if (== $contextual-premises ())
             (the (List Atom) ((Inheritance $instance $ground-subj)))
             $contextual-premises))
       (($main-execs $main-proofs $main-atv)
          (once (lower-implication-antecedent $kbid MAIN Nil
             (brand Statement (seq2expr (the (List Atom) $auxiliary-premises))))))
       (($context-execs $context-proofs $context-atv)
          (once (lower-implication-antecedent $kbid $ctx $vars
             (brand Statement (seq2expr (the (List Atom) $lift-premises))))))
       ($source-proof (implication-proof-token $main-proofs))
       ($context-proof (implication-proof-token $context-proofs))
       ($all-evidence (CPU AndFormula (quote ($main-atv $context-atv)) $all-atv))
       ($rule-ctv (inheritance-lift-ctv $tv))
       ($modus-ponens (CPU CTVModusPonensFormula (quote ($all-atv $rule-ctv)) $out-tv)))
      ((append-goals $main-execs
          (append-goals $context-execs (quote ($all-evidence $modus-ponens))))
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
   (-[det]-> KB AnnotatedStatement AnnotatedStatement InheritanceLiftInstanceRow))

(: SpecializationTemplateRow Type)
(: specialization-template-row
   (-[det]-> KB Atom (List Atom) SpecializationJob SpecializationTemplateRow))

(: SpecializationDoneRow Type)
(: specialization-done-row (-[det]-> KB AnnotatedStatement SpecializationDoneRow))

(: emit-specialization (-[nondet]-> KB SpecializationJob CompiledAddition))
(= (emit-specialization $kb (inheritance-lift-specialization $stmt $source-stmt))
   (let*
      (($stmt-copy (copy_term $stmt))
       ($hash (term_hash $stmt-copy))
       ($stored
          (collapse
             (once
                (match &inheritance_lift_instance
                   ($hash (inheritance-lift-instance-row $kb $candidate $_source))
                   (if (=alpha $candidate $stmt-copy) true (empty))))))
       ($_instance
          (if (== $stored ())
             (let $source-copy (copy_term $source-stmt)
                (add-atom &inheritance_lift_instance
                   ($hash (inheritance-lift-instance-row $kb $stmt-copy $source-copy))))
             ())))
      (empty)))

(: collect-inheritance-lifts-for-context (-[det]-> KB KBContext (List CompiledAddition)))
(= (collect-inheritance-lifts-for-context $kb $lift-kb)
   (collapse
      (match &inheritance_lift_instance
         ($_hash (inheritance-lift-instance-row $kb $ground-stmt $source-stmt))
         (compile-inheritance-lift-instance
            $kb $lift-kb
            (the AnnotatedStatement (copy_term $ground-stmt))
            (the AnnotatedStatement (copy_term $source-stmt))))))

;; On rule addition, emit every instance already supported by stored facts and
;; retain the template for facts added later. No open lifted rule enters the KB.
(: compile-inheritance-rule-lifts
   (-[nondet]-> KB AnnotatedStatement Statement Statement CompiledAddition))
(= (compile-inheritance-rule-lifts $kb $stmt $antecedent $consequent)
   (if (if (head-is? $consequent Inheritance) (= $consequent (Inheritance $subj $_concept)) false)
      (let*
         (($ground-copy (copy_term $stmt))
          ($source-copy (copy_term $stmt))
          ((: $_prf
              (Implication $ground-antecedent (Inheritance $ground-subj $_ground-concept))
              $_tv)
             $ground-copy)
          ($ground-auxiliary
             (inheritance-lift-auxiliary-premises
                (implication-side-conjuncts (brand Statement $ground-antecedent))
                $ground-subj))
          ($job (inheritance-lift-specialization $ground-copy $source-copy)))
         (if (== $ground-auxiliary ()) (empty) (specialize-rule-add $kb $ground-auxiliary $job)))
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
            (if (specializing-predicate? $head) (not (== (extract-vars $premise) ())) false)))
      false))

(: fact-head (-[det]-> Statement Atom))
(= (fact-head $type) (if (is-expr $type) (car-atom $type) $type))

;; Both structural rules and Inheritance lifts use the same indexed template
;; store. A job carries the emitter to run after its trigger list is grounded.
;; Keeping the triggers with the job lets a newly added fact use this one path
;; regardless of which compiler feature requested specialization.
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

;; Idempotency is per grounded statement, not merely per rule type: distinct
;; proof ids or TVs are independent evidence even when their types coincide.
;; The rule-add and fact-add paths may discover the same statement, so retain
;; the full statement as the stable deduplication key.
(= (emit-specialization $kb (compile-specialization (: $gprf $gtype $gtv)))
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
      (if (== $done ())
         (let $_
            (once (add-atom &spec_done ($hash (specialization-done-row $kb $copy))))
            (compile_ $kb $gstmt))
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
      (if (context-polymorphic-facts? $kb) (make-kb-context $kb $ctx $vars) (kbctx $kb))
      (superpose (
         (brand CompiledAddition (() |- (: $fact-kb $prf $Type $tv)))
         ;; Concrete Inheritance assertions also act as implication-like
         ;; rules over members. Materializing these views once at compile
         ;; time lets ordinary rule indexing and inference handle inheritance
         ;; without a separate chainer path.
         (if (= $Type (Inheritance $subj $concept))
            (if (concrete-inheritance-link? $subj $concept)
               (superpose
                  ((compile_ $kb
                      (: (inheritance-implication $prf)
                         (Implication (Inheritance $x $subj) (Inheritance $x $concept))
                         $tv))
                   (let $ctv (inheritance-lift-ctv $tv)
                      (compile_ $kb
                         (: (no_inverse (member-inheritance-implication $prf))
                            (Implication (Member $x $subj) (Member $x $concept))
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
;; applies, forward, backward, inverted and completed, with their revision.
;; Only named user rules whose sides the instance producer samples are refined.
(: set-rule-refinement (-[det]-> KB Bool Bool))
(= (set-rule-refinement $kb $enabled)
   (let* (($_old
             (collapse (match &rule_refinement ($kb $stored)
                (remove-atom &rule_refinement ($kb $stored)))))
          ($_new (add-atom &rule_refinement ($kb $enabled))))
      $enabled))

;; A refined rule reads its truth `$truth-tv` from the goal first, over a copy
;; of the implication so all its applications share the one general goal. The
;; typed result keeps the premise list a (List Goal) for strict mode.
(: rule-truth-premises (-[det]-> Bool KB Atom Atom (List Goal)))
(= (rule-truth-premises $refine? $kb $truth-type $truth-tv)
   (if $refine? (cons (: (kbctx $kb) $truth-prf (copy_term $truth-type) $truth-tv) ()) ()))

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

;; collapse copies what it collects: unifying a copy's antecedent, context and
;; variables with the rule's own relinks the copied lowering to the rule.
(: relinked-lowering (-[det]-> Atom Atom Atom (Atom Atom Atom CompiledPremises) CompiledPremises))
(= (relinked-lowering $antecedent $ctx $vars ($antecedent $ctx $vars $lowered)) $lowered)

;; Every lowering of a rule's antecedent, the complete one first, linked to
;; the rule's own antecedent, context and variables.
(: antecedent-lowerings (-[det]-> KB Atom Atom Statement (List CompiledPremises)))
(= (antecedent-lowerings $kb $ctx $vars $antecedent)
   (map-flat (relinked-lowering $antecedent $ctx $vars)
      (the (List (Atom Atom Atom CompiledPremises))
         (collapse
            (let $lowered (lower-implication-antecedent $kb $ctx $vars $antecedent)
               (data $antecedent $ctx $vars $lowered))))))

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
                     (cons (: $shape-kb $source-prf (Implication $x $y) $ctv) ()) $ctv ()
                     (brand Statement $x) (brand Statement $y)
                     (list_to_set (extract-vars (Implication $x $y)))
                     (antecedent-lowerings $kb $ctx $vars (brand Statement $x)))
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
         (specialize-rule-add $kb $triggers (compile-specialization (: $prf $Type $tv)))
         (let*
            (($_evidence-reg (register-rule-evidence! $kb $prf $tv (== (extract-vars $Type) ())))
             ($antecedents (antecedent-lowerings $kb $ctx $vars (brand Statement $antecedent)))
             ((cons ($execs $_proofs $_atv) $_settled) $antecedents)
             ($shape-kb (make-kb-context $kb $ctx $vars))
             ($a (brand Statement (implication-source-term $antecedent)))
             ($b
                (if (explicit-exists-term? $consequent)
                   (canonical-existential-side (brand Statement $consequent))
                   (brand Statement (implication-source-term $consequent))))
             ($antecedent-vars (implication-antecedent-free-vars $antecedent))
             ($pure-connective? (if (head-is-member? $a (And Or))
                (not (fold-flat computing-child? false (implication-side-conjuncts $a))) false))
             ($ctv? (if (= $tv (CTV $_pos $_neg)) true false))
             ($refine? (refined-rule? $kb $prf $a $b $tv))
             ($truth-type (RuleTruth (Implication $a $b)))
             ($a-opposite (if (head-is? $a Not) (car-atom (cdr-atom $a)) (Not $a)))
             ($truth-premises (rule-truth-premises $refine? $kb $truth-type $truth-tv))
             ($_truth-shape
                (if $refine?
                   (let* (($_positive (add-atom &rule_truth_shapes ($kb $truth-type)))
                          ($_negative (if $ctv? (add-atom &rule_truth_shapes ($kb (RuleTruth (Implication $a-opposite $b)))) ())))
                      ())
                   ()))
             ($value (if $refine? $truth-tv $tv)))
            (superpose (
               ;; Stated positive judgments stay private. A CTV is already
               ;; executable rule storage in MAIN; an STV's full CTV reads its
               ;; source and the ordinary base rates through a permanent row.
               (let* ((($inner $last) (nested-implication-parts $b))
                      ($source-b (skolemize-conclusion-vars $prf
                         (append $antecedent-vars (extract-vars $inner)) $b))
                      ($source-type (brand Statement (Implication $antecedent $source-b)))
                      ($query-type
                         (if (contains-explicit-exists? $Type)
                            (let $canonical (Implication
                                   (canonical-existential-side (brand Statement $antecedent))
                                   (canonical-existential-side (brand Statement $consequent)))
                               (brand Statement (QuantifiedRule (index-hash $canonical) $canonical)))
                            $source-type))
                      ($query-kb (make-kb-context (brand KB (implication-query $kb)) MAIN Nil))
                      ($source-kb
                         (if $ctv? (kbctx $kb)
                            (make-kb-context (brand KB (implication-stated $kb)) MAIN $params))))
                  (superpose (
                     (case $tv (
                        ((CTV $source-pos $source-neg)
                           (let $opposite (if (head-is? $antecedent Not)
                              (car-atom (cdr-atom $antecedent)) (Not $antecedent))
                              (superpose (
                                 (brand CompiledAddition
                                    (() |- (: (kbctx $kb) $prf $source-type $tv)))
                                 (brand CompiledAddition
                                    (() |- (: (kbctx $kb) $prf (Implication $opposite $source-b)
                                       (CTV $source-neg $source-pos))))
                                 (brand CompiledAddition
                                    (() |- (: $query-kb $prf $query-type $source-pos)))
                                 (brand CompiledAddition
                                    (() |- (: $query-kb $prf (Implication $opposite $source-b) $source-neg)))))))
                        ((STV $s $c)
                           (let* (($rate-a (if (== $inner ()) $a
                                     (brand Statement (cons And (append (implication-side-conjuncts $a) $inner)))))
                                  (($ctv-execs $source-ctv $_source-likelihoods)
                                     (compile-implication-ctv-execs $kb $params $rate-a $last $tv $tv false)))
                              (superpose (
                                 (brand CompiledAddition
                                    (() |- (: $source-kb $prf $source-type $tv)))
                                 (brand CompiledAddition (() |- (: $query-kb $prf $query-type $tv)))
                                 (brand CompiledAddition
                                    ((cons (: $source-kb $prf $source-type $tv) $ctv-execs)
                                       |- (: (kbctx $kb) $prf $source-type $source-ctv)))))))))
                     (compile-consequent-implications $kb $shape-kb $prf $tv
                        (cons (: $source-kb $prf $source-type $tv) $truth-premises)
                        $value $params $a $b))))
               (compile-implication-forward-rules
                  $kb $shape-kb $prf $tv $truth-premises $value $params
                  $a $b $antecedent-vars $antecedents)
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
                            (if (contains-cpu? (execs-goal-type $execs))
                               (compile-reversible-compute-plan $a $b)
                               (inverse-compute-plan () (list_to_set (extract-vars $b)))))
                         ($na (skolemize-conclusion-vars $prf $inverse-known $a)))
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
                           (if $pure-connective?
                              (empty)
                              (compile-outputs
                                 (: $shape-kb ((inverted $prf $w $pa1 $pa2) $pb2) $na $natv))))
                        (if (is-var $b) (empty)
                           (compile-adapter-chain plain (: $shape-kb $pb2 $b $btv2)))))))
               ;; No inverse rule of any kind for a rule named no_inverse:
               ;; completion recovers an antecedent conjunct from the
               ;; conclusion as inversion recovers the whole antecedent. Both
               ;; read the conclusion as an observation, and a derived
               ;; implication is not one.
               (if (if $pure-connective? (if (= $prf (no_inverse $_)) false (not (implication-type? $b))) false)
                  (let $children
                     (statement-children (the (List Atom) (cdr-atom $a)))
                     (compile-antecedent-completion
                        $kb $ctx $vars $shape-kb $prf $tv $truth-premises $value $params
                        $a $b $children 0 $children))
                  (empty))
               (compile-implication-statement-rules $kb $b)
               (compile-inheritance-rule-lifts $kb (: $prf $Type $tv)
                  (brand Statement $antecedent)
                  (brand Statement $consequent))))))))

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
         (if (source-exists? $Type) (empty)
            (if (bidirectional-implication-type? $Type)
               (let ($_head $left $right) $Type
                  (superpose (
                     (compile_ $kb (: (bi-forward $prf) (Implication $left $right) $tv))
                     (compile_ $kb (: (bi-backward $prf) (Implication $right $left) $tv)))))
            ;; Asserted negation keeps the source name and stores its
            ;; inner statement with complemented strength.
            (if (head-is? $Type Not)
               (let (Not $inner) $Type
                  (case $tv (
                     ((STV $s $c) (compile_ $kb (: $prf $inner (STV (- 1.0 $s) $c))))
                     ($_unsupported-tv (compile-ordinary-fact $kb $prf $Type $tv)))))
               (compile-ordinary-fact $kb $prf $Type $tv)))))))
