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
(datatype ComputeInversePlan
   (inverse-compute-plan (List Goal) (List Variable)))

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

;; The pattern a rule's base rate is taken over: a fresh copy of one of its
;; sides, except the variables a surrounding ForAll binds, which stay shared
;; with the rule application so the rate is taken per parameter value.
(: rule-base-rate-pattern (-[det]-> (List Variable) Statement Statement))
(= (rule-base-rate-pattern $params $side)
   (let ($params $pattern) (copy_term ($params (rule-query-pattern $side)))
      (brand Statement $pattern)))

(datatype RatePlan
   (rate-plan (List Goal) Atom))
(: base-rate-read-plan (-[det]-> KB Statement RatePlan))
(= (base-rate-read-plan $kb $pattern)
   (let $goals (base-rate-premises $kb $pattern $result) (rate-plan $goals $result)))

;; How the base rates of a rule's sides derive its CTV from its positive
;; branch. `reconciled-rates`: the branch and the rates are reconciled within
;; the Fréchet bounds (ConsistentTriple), the rule applying with what remains.
;; `learned-rates`: the branch is a truth learned from the rule's instances,
;; which are the members the rates count, so they already moved it by their
;; evidence; reconciling would count them again, so only the negative branch
;; is reconciled. `deferred-rates`: the application resolves the likelihoods
;; itself (rule-likelihood-read).
(datatype RateUse
   reconciled-rates
   learned-rates
   deferred-rates)

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
            (canonical-addition $shape-kb $allargs
               (brand Proof (quote (by $prf $proof-token))) $out-b $btv))))
      (if (is-var $out-b) (empty) (compile-outputs (: $shape-kb (by $prf $prfb) $out-b $btv2)))))))

(: rule-evidence-base-name (-[det]-> Proof Proof))
(= (rule-evidence-base-name $prf)
   (if (= $prf (bi-forward $fwd)) (brand Proof $fwd)
      (if (= $prf (bi-backward $bwd)) (brand Proof $bwd)
         (if (= $prf (no_inverse $inner)) (brand Proof $inner) $prf))))

;; A rule's evidence name is a symbol, or the context token of an implication
;; assumed in an Assuming query, which names that query-local rule as a
;; symbol names a stored one. Other proof expressions are not rule names.
(: rule-name? (-[det]-> Proof Bool))
(= (rule-name? $name) (if (is-expr $name) (head-is? $name ctx) true))

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

;; Whether a rule's applications carry an entry naming it: an estimated rule's
;; or a ground given rule's.
(: named-rule? (-[det]-> KB Proof Bool))
(= (named-rule? $kbid $name) (if (rule-evidence-registered? $kbid $name) true (given-rule? $kbid $name)))

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
      (if (not (rule-name? $name)) ()
         (if (logic-rule? $name) ()
            (if (rule-evidence-registered? $kb $name) ()
               (case $tv (
                  ((STV $s $c)
                     (let $_named (register-given-name! $kb $name $ground (cons (STV $s $c) ()))
                        (register-given-branches! $kb $name (cons (STV $s $c) ()))))
                  ((CTV $pos $neg)
                     (let $_named (register-given-name! $kb $name $ground (cons $pos (cons $neg ())))
                        (register-given-branches! $kb $name (cons $pos (cons $neg ())))))
                  ($_other (register-rule-evidence-name! $kb $name)))))))))

(: register-given-branches! (-[det]-> KB Proof (List TV) (List $no-result)))
(= (register-given-branches! $kb $name $branches)
   (if (fold-flat given-branch-step true $branches)
      (if (fold-flat deterministic-branch-step true $branches)
         (if (deterministic-rule? $kb $name) ()
            (let $_added (add-atom &deterministic_rules ($name $kb)) ()))
         ())
      (register-rule-evidence-name! $kb $name)))

;; Named apart from the deterministic check, so a rule seen before, or first
;; stated generally, is still named once a ground statement of it is given.
(: register-given-name! (-[det]-> KB Proof Bool (List TV) (List $no-result)))
(= (register-given-name! $kb $name $ground $branches)
   (if (if $ground (fold-flat given-branch-step true $branches) false)
      (if (given-rule? $kb $name) () (let $_added (add-atom &given_rules ($name $kb)) ()))
      ()))

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

;; Rules stated as a certain equivalence, ((1, 1), (0, 1)), over one
;; statement with the conclusion's variables, by their proof name as their
;; applications carry it, such as (bi-backward name): the conclusion is the
;; premise, so an application of one update is that update
;; (sk-prior-update-of). A premise with a variable the conclusion lacks, as in
;; (P $x $y) -> (Q $x), is one of many instances, whose population prior is
;; not the conclusion's: carrying its update put Q's own inversion under P's
;; prior. A rule named no_inverse
;; declares its conclusion no observation of its premise, and a refined rule
;; holds by its learned truth: neither is one (the conflict benchmark's claims
;; run from a source-wide reliability to each claimed node, no_inverse).
(: &equivalence_rules (SpaceOf (Proof KB)))
!(bind! &equivalence_rules (new-space))

(: equivalence-rule? (-[det]-> KB Proof Bool))
(= (equivalence-rule? $kb $prf) (not (== (collapse (once (match &equivalence_rules ($prf $kb) true))) ())))

(: register-equivalence-rule! (-[det]-> KB Proof TV Statement Statement Atom))
(= (register-equivalence-rule! $kb $prf $tv $antecedent $consequent)
   (if (head-is? $prf no_inverse) ()
      (if (if (== (extract-vars $tv) ())
             (if (== (cdr-atom (implication-side-conjuncts $antecedent)) ())
                (if (vars-covered? $antecedent (extract-vars $consequent)) (vars-covered? $consequent (extract-vars $antecedent)) false)
                false)
             false)
         (case $tv (
            ((CTV (STV $ps $pc) (STV $ns $nc))
               (if (if (>= $ps 1.0) (if (>= $pc 1.0) (if (<= $ns 0.0) (>= $nc 1.0) false) false) false)
                  (if (equivalence-rule? $kb $prf) () (let $_added (add-atom &equivalence_rules ($prf $kb)) ()))
                  ()))
            ($_other ())))
         ())))

(: deterministic-rule? (-[det]-> KB Proof Bool))
(= (deterministic-rule? $kbid $name) (not (== (collapse (once (match &deterministic_rules ($name $kbid) true))) ())))

;; The base rate required to reinterpret an STV rule as a CTV.
(: base-rate-fold (-[det]-> KB Statement $truth-value Goal))
(= (base-rate-fold $kb $pattern $brtv)
   (CPU FoldAllCompiled
      (quote ($kb $pattern extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv))
      $brtv))

;; A conjunction's conjuncts grouped into parts that share no variables;
;; ground conjuncts join the first part that has variables, since a single
;; instance multiplies nothing.
(datatype ConjunctSplit
   (conjunct-split (List Atom) (List Atom)))
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

;; A connective's children whose parts its base rate splits by: an And's
;; conjuncts, through nested conjunctions, or an Or's children.
(: rate-children (-[det]-> Statement (List Atom)))
(= (rate-children $key)
   (if (head-is? $key Or) (the (List Atom) (cdr-atom $key)) (implication-side-conjuncts $key)))

;; The premises estimating a pattern's base rate as `$brtv`, its prior: a
;; compound's is one aggregate key per pattern (CompoundRate, #142), any other
;; statement is folded.
(datatype BaseRateParts
   (base-rate-parts (List Goal) (List Atom)))
(: base-rate-premises (-[det]-> KB Statement $truth-value (List Goal)))
(= (base-rate-premises $kb $pattern $brtv)
   (if (head-is-member? $pattern (Not And Or))
      (cons (CPU CompoundRate (quote ($kb $pattern)) $brtv) ())
      (cons (base-rate-fold $kb $pattern $brtv) ())))

;; The goals computing a compound's prior, recursively over its structure. A
;; negation's is the complement of its canonical key's, as a rate set on
;; (Not X) is stored on X. A connective whose children fall into parts sharing
;; no variables ranges over the cross product of the parts' instances, so its
;; rate is exactly the product (And) or the independent disjunction (Or) of
;; theirs. A connective whose children share variables takes its joint rate,
;; the fold over the compound itself, when that has evidence or a user pin,
;; and otherwise the rate composed from its children's priors as if
;; independent (CompoundRateFormula). A connective of one child, as an (And X)
;; a nested conjunction leaves, is that child. A search (`$searched`) reads
;; only the joint, which is the prior once it has evidence.
(: compound-rate-goals (-[det]-> $spec Bool $truth-value (List Goal)))
(= (compound-rate-goals ($kbid $pattern) $searched $brtv)
   (let* (($kb (brand KB $kbid)) (($key $odd) (canon (brand Statement $pattern))))
      (if $odd
         (append-flat (base-rate-premises $kb $key $rate) ((CPU BaseRateNotFormula (quote ($rate)) $brtv)))
         (let $children (rate-children $key)
            (connective-rate-goals $kb $key $searched $brtv $children (conjunct-parts $children))))))
;; The parts arrive as a parameter: the determinism checker proves the fold
;; over a parameter list, not over a function result.
(: connective-rate-goals (-[det]-> KB Statement Bool $truth-value (List Atom) (List Atom) (List Goal)))
(= (connective-rate-goals $kb $key $searched $brtv $children $parts)
   (if (== (cdr-atom $parts) ())
      (if (== (cdr-atom $children) ())
         (base-rate-premises $kb (brand Statement (car-atom $children)) $brtv)
         (if $searched (cons (base-rate-fold $kb $key $brtv) ())
            (cons (base-rate-fold $kb $key $joint)
               (composed-rate-premises $kb $key (map-flat (|-> ($child) (the (List Atom) (cons $child ()))) $children) $composed
                  ((CPU CompoundRateFormula (quote ($joint $composed)) $brtv))))))
      (composed-rate-premises $kb $key $parts $brtv ())))

;; The rate the connective `$key` composes from its parts' priors, left to
;; right, as a product (And) or an independent disjunction (Or), followed by
;; the goals `$tail`.
(: composed-rate-part (-[det]-> KB Statement (List Atom) BaseRateParts BaseRateParts))
(= (composed-rate-part $kb $key $part (base-rate-parts $goals $tvs))
   (let $statement (brand Statement (if (== (cdr-atom $part) ()) (car-atom $part) (cons (car-atom $key) $part)))
      (base-rate-parts (append-flat (base-rate-premises $kb $statement $tv) $goals) (cons $tv $tvs))))
(: composed-rate-premises (-[det]-> KB Statement (List Atom) $truth-value (List Goal) (List Goal)))
(= (composed-rate-premises $kb $key $parts $rate $tail)
   (case (foldr-flat (composed-rate-part $kb $key) (base-rate-parts () ()) $parts) (
      ((base-rate-parts $goals $tvs)
         (case $tvs (((cons $first $more)
            (let $formula (if (head-is? $key And) BaseRateProductFormula BaseRateOrFormula)
               (append-flat $goals (and-tv-goals $formula $first $more $rate $tail))))))))))

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
      (append-flat (base-rate-premises $kb $pattern $rate)
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
         (append-flat (base-rate-premises $kb $pattern $rate)
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
   (let $_declared (declared-head! $head)
      (if (== (collapse (once (match &positive_only_predicates ($kb $head) true))) ())
         (let $_row (add-atom &positive_only_predicates ($kb $head)) true)
         true)))

;; A pattern one of whose conjuncts (or a negated conjunct's statement) has a
;; positive-only predicate.
;; A KB may declare that a predicate's rules and facts are the only ways one of
;; its statements becomes true (docs/metta/complete_predicates.md). Declared
;; before knowledge is added.
(: &complete_predicates (SpaceOf (KB Atom)))
!(bind! &complete_predicates (new-space))

(: complete-predicate? (-[det]-> KB Atom Bool))
(= (complete-predicate? $kb $head)
   (not (== (collapse (once (match &complete_predicates ($kb $head) true))) ())))
(: set-complete-predicate (-[det]-> KB Atom Bool))
(= (set-complete-predicate $kb $head)
   (let $_declared (declared-head! $head)
      (if (complete-predicate? $kb $head) true
         (let $_row (add-atom &complete_predicates ($kb $head)) true))))

;; The strength of a rule's negative branch that no rate determines: even odds,
;; but false for a complete conclusion, which only rule applications make true.
(: unknown-branch-centre (-[det]-> KB Statement Number))
(= (unknown-branch-centre $kb $b)
   (let $head (if (is-expr $b) (car-atom $b) $b)
      (if (complete-predicate? $kb $head) 0.0 0.5)))

(: positive-only-pattern? (-[det]-> KB Statement Bool))
(= (positive-only-pattern? $kb $pattern)
   (fold-flat (positive-only-conjunct? $kb) false (implication-side-conjuncts $pattern)))
(: positive-only-conjunct? (-[det]-> KB Bool Atom Bool))
(= (positive-only-conjunct? $kb $seen $conjunct)
   (if $seen true
      (let* ((($statement $_odd) (canon (brand Statement $conjunct)))
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
(datatype InstanceSampleParts
   (instance-sample-parts (List Goal) (List Atom) (List Atom)))
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
      (inversion-addition (make-kb-context $kb $ctx $vars) $prf cpu $truth-premises $a $b $inverse-execs
         (append-flat (prior-base-rate-premises $kb $a1 $raw-atv $atv)
            (append-flat (base-rate-premises $kb $b1 $raw-btv)
               (the (List Goal)
                  ((CPU ReadRate (quote ($kb $b1 $raw-btv $b-plan false)) (rate-read $btv $_read-btv))
                   (CPU ReadLikelihoodContext () $read-context)
                   (CPU rule-likelihood-read (quote ($kb $prf $a1 $b1 $rule-likelihoods $read-context)) $read-likelihoods)
                   (CPU CTVInversionFormula (quote ($atv $btv $read-likelihoods)) $iitv)))))
         $atv $iitv)))

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
       ($prior-token (if $population cpu $prior-prf)))
      (inversion-addition $kc $prf $prior-token $truth-premises $a $b $inverse-execs
         (append-flat $prior-goals
            (append-flat (append-flat $ctv-execs $read-goals)
               ((CPU CTVBayesFormula (quote ($atv $read-likelihoods)) $iitv))))
         $atv $iitv)))

;; For every child M of a pure conjunction or disjunction H, compile the
;; completion (And O C) -> M, where O is the connective over H's other
;; children and C is the original consequence. A negated connective H is
;; completed as its De Morgan dual over the negated children. That is the only
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
;; Bayes' rule (sk-factored-merge). H's key K can have evidence of its own (a
;; stored compound), which screens C off from M: the completion reads it
;; apart from K's parts and C (CompoundEvidence, sk-evidence-view) and is
;; conditioned on it (CompletionEvidenceFormula), its prior then P(M | e_K)
;; and its proof's base e_K's proof instead of the population's `cpu`: the
;; first goal read, its proof takes the first `cpu` token (replace-token). So
;; completions conditioned on one e_K combine over that prior, and the
;; completion holds e_K's evidence.
;; A conjunction or disjunction is pure when no child computes (`computing?`).
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
                   ($antecedent-rate-pattern (rule-base-rate-pattern $params $full))
                   ($consequence-rate-pattern (rule-base-rate-pattern $params $consequent))
                   (($rule-execs $rule-ctv $rule-likelihoods)
                      (compile-implication-ctv-execs $kb $params $full $consequent $tv $value deferred-rates))
                   (($read-goals $read-rule-likelihoods)
                      (likelihood-read-premises $kb $prf $antecedent-rate-pattern $consequence-rate-pattern
                         $tv $rule-likelihoods))
                   ($proof-token
                      (implication-proof-token (append $others-proofs $consequent-proofs)))
                   ($consequent-proof (implication-proof-token $consequent-proofs))
                   (($target $negated) (canon $missing))
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
                     ($premises |-
                        (: $shape-kb
                           ((antecedent-completion $prf $idx with cpu (prior $target-prior))
                            $proof-token)
                           $target $out-tv))))
               (empty))))
      (compile-antecedent-completion
         $kb $shape-kb $prf $tv $truth-premises $value $params
         $full $consequent $children (+ $idx 1) $rest))))

;; A grounded rule is one specialization job. The specialization engine below
;; handles template indexing and late facts.
(datatype SpecializationJob
   (compile-specialization (List Variable) Atom AnnotatedStatement))

;; These rows cross atom-space storage boundaries, so their tags are stable
;; schemas rather than local multiple-return wrappers.

(datatype SpecializationTemplateRow
   (specialization-template-row KB Atom (List Atom) SpecializationJob))

(datatype SpecializationDoneRow
   (specialization-done-row KB SpecializationJob))

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
            (if (specializing-predicate? $head) (not (== (extract-vars $premise) ())) false)))
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
      (if (context-polymorphic-facts? $kb) (make-kb-context $kb $ctx $vars) (kbctx $kb))
      (superpose (
         (brand CompiledAddition (() |- (: $fact-kb $prf $Type $tv)))
         (compile-specialization-fact-triggers $kb $Type)
         (compile-outputs (: $fact-kb $prf $Type $tv))))))

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
            (superpose (
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
               (compile-implication-statement-rules $kb $b)))))))

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
