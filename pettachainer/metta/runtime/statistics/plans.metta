;; Base-rate read plans shared by lowering and runtime fold evaluation.
;; These construct goals without installing rules or performing inference.

;; The pattern a rule's base rate is taken over: a fresh copy of one of its
;; sides, except the variables a surrounding ForAll binds, which stay shared
;; with the rule application so the rate is taken per parameter value.
(: rule-base-rate-pattern (-[det]-> (List Variable) Statement Statement))
(= (rule-base-rate-pattern $params $side)
   (let ($params $pattern) (copy_term ($params (rule-query-pattern $side)))
      (brand Statement $pattern)))

(datatype RatePlan (rate-plan (List Goal) Atom))
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
(datatype RateUse reconciled-rates learned-rates deferred-rates)

;; The base rate required to reinterpret an STV rule as a CTV.
(: base-rate-fold (-[det]-> KB Statement $truth-value Goal))
(= (base-rate-fold $kb $pattern $brtv)
   (CPU FoldAllCompiled
      (quote ($kb $pattern extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv))
      $brtv))

;; A conjunction's conjuncts grouped into parts that share no variables;
;; ground conjuncts join the first part that has variables, since a single
;; instance multiplies nothing.
(datatype ConjunctSplit (conjunct-split (List Atom) (List Atom)))
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
(datatype BaseRateParts (base-rate-parts (List Goal) (List Atom)))
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
