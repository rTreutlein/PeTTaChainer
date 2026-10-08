!(import! &self ../../pettachainer/metta/petta_chainer)

;; A completion inverts the rule onto one conjunct M given the others O and
;; the consequent C, by Bayes' rule over M's base rate: given O,
;; P(M|O,C) = u P(M) / (u P(M) + v (1 - P(M))) and P(M|O,not C) the same with
;; 1 - u, 1 - v, u = P(C|O,M) and v = P(C|not(O,M)) the rule's branches (v
;; recovered from P(C) and P(O,M) for a rule stated with an STV). C's value
;; weighs the two by modus ponens, and O's value weighs that against P(M),
;; since without O the rule says nothing about M:
;;   P(M) given the witnesses = s_O (s_C P(M|O,C) + (1 - s_C) P(M|O,not C)) + (1 - s_O) P(M).
;; The proof names the base rate it updates, so it merges with other updates
;; of P(M) by Bayes' rule.

;; P(C|A,B) = 1 stated with an STV; P(C|not(A,B)) = (0.4 - 0.2) / 0.8 = 0.25
;; from P(C) and P(A,B); P(B|A,C) = 0.3 / (0.3 + 0.25 * 0.7) = 0.6316 (the
;; likelihood read at confidence 0.9 moves it by less than 1e-4).
!(compileadd completionKb (: a A (STV 1.0 0.9)))
!(compileadd completionKb (: c C (STV 1.0 0.9)))
!(compileadd completionKb
   (: ab_c
      (Implication (And A B) C)
      (STV 1.0 0.9)))

!(set-base-rate completionKb (And A B) (STV 0.2 0.9))
!(set-base-rate completionKb C (STV 0.4 0.9))
!(set-base-rate completionKb B (STV 0.3 0.9))

;; The completion is the only child-recovery operator: whole-compound
;; inversion still proves (And A B) itself and does not also project to B.
!(test
   (query 2000 completionKb (: $proof B $tv))
   (: ((antecedent-completion ab_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a c)) B (STV 0.6309975088832207 0.2841868101052977)))

;; A rule named no_inverse gets no completion either: B has no proof.
!(compileadd noInverseCompletionKb (: a A (STV 1.0 0.9)))
!(compileadd noInverseCompletionKb (: c C (STV 1.0 0.9)))
!(compileadd noInverseCompletionKb
   (: (no_inverse ab_c)
      (Implication (And A B) C)
      (STV 1.0 0.9)))
!(set-base-rate noInverseCompletionKb (And A B) (STV 0.2 0.9))
!(set-base-rate noInverseCompletionKb C (STV 0.4 0.9))
!(set-base-rate noInverseCompletionKb B (STV 0.3 0.9))

!(test (query 2000 noInverseCompletionKb (: $proof B $tv)) ())

;; Pure conjunction antecedents retain whole-compound Bayesian inversion.
!(compileadd conjunctionInversionKb (: c C (STV 1.0 0.9)))
!(compileadd conjunctionInversionKb
   (: ab_c
      (Implication (And A B) C)
      (STV 1.0 0.9)))
!(set-base-rate conjunctionInversionKb
   (And A B) (STV 0.2 0.9))
!(set-base-rate conjunctionInversionKb C (STV 0.4 0.9))

!(test
   (query 2000 conjunctionInversionKb
      (: $proof (And A B) $tv))
   (: ((inverted ab_c with cpu (prior (STV 0.2 0.9))) c)
      (And A B)
      (STV 0.49999166689814173 0.6205495495952107)))

;; A completion is not generated when the missing premise contains a variable
;; which neither the remaining antecedents nor the consequence can bind.
!(compileadd unboundCompletionKb
   (: unsafe
      (Implication
         (And (A2 $x $y) (B2 $x))
         (C2 $x))
      (CTV (STV 1.0 0.9) (STV 0.0 0.9))))
!(compileadd unboundCompletionKb (: b2 (B2 current) (STV 1.0 0.9)))
!(compileadd unboundCompletionKb (: c2 (C2 current) (STV 1.0 0.9)))
!(set-base-rate unboundCompletionKb
   (And (A2 $x $y) (B2 $x)) (STV 0.2 0.9))
!(set-base-rate unboundCompletionKb
   (A2 $x $y) (STV 0.3 0.9))

!(test
   (query 2000 unboundCompletionKb
      (: ((antecedent-completion unsafe 0 with cpu $prior)
          $witness)
         (A2 current arbitrary)
         $tv))
   ())

;; A rule stating both likelihoods reads only P(B):
;; P(B|A,C) = 0.9 * 0.3 / (0.9 * 0.3 + 0.3 * 0.7) = 0.5625.
!(compileadd ctvCompletionKb (: a A (STV 1.0 0.9)))
!(compileadd ctvCompletionKb (: c C (STV 1.0 0.9)))
!(compileadd ctvCompletionKb
   (: ab_c
      (Implication (And A B) C)
      (CTV (STV 0.9 1) (STV 0.3 1))))
!(set-base-rate ctvCompletionKb B (STV 0.3 0.9))

!(test
   (query 2000 ctvCompletionKb (: $proof B $tv))
   (: ((antecedent-completion ab_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a c)) B (STV 0.5625000000000001 0.8847429725023245)))

;; A base rate of 1 leaves no room for evidence about one instance, so there
;; is no completion: it would restate the rate as B's value.
!(compileadd saturatedKb (: a A (STV 1.0 0.9)))
!(compileadd saturatedKb (: c C (STV 1.0 0.9)))
!(compileadd saturatedKb
   (: ab_c
      (Implication (And A B) C)
      (CTV (STV 0.9 1) (STV 0.3 1))))
!(set-base-rate saturatedKb B (STV 1.0 0.9))

!(test (query 2000 saturatedKb (: $proof B $tv)) ())

;; An uncertain other conjunct weighs the completion against P(B): without A
;; the rule says nothing about B. 0.5 * 0.5625 + 0.5 * 0.3 = 0.43125.
!(compileadd uncertainOtherKb (: a A (STV 0.5 0.9)))
!(compileadd uncertainOtherKb (: c C (STV 1.0 0.9)))
!(compileadd uncertainOtherKb
   (: ab_c
      (Implication (And A B) C)
      (CTV (STV 0.9 1) (STV 0.3 1))))
!(set-base-rate uncertainOtherKb B (STV 0.3 0.9))

!(test
   (query 2000 uncertainOtherKb (: $proof B $tv))
   (: ((antecedent-completion ab_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a c)) B (STV 0.43125 0.9396139065481569)))

;; A three-child conjunction completes the middle child from the other
;; children plus the original consequence: (And A D C) -> Mid.
;; P(Mid|A,D,C) = 0.8 * 0.3 / (0.8 * 0.3 + 0.4 * 0.7) = 0.4615.
!(compileadd ternaryCompletionKb (: a A (STV 1.0 0.9)))
!(compileadd ternaryCompletionKb (: d D (STV 1.0 0.9)))
!(compileadd ternaryCompletionKb (: c C (STV 1.0 0.9)))
!(compileadd ternaryCompletionKb
   (: abd_c
      (Implication (And A Mid D) C)
      (CTV (STV 0.8 1) (STV 0.4 1))))
!(set-base-rate ternaryCompletionKb Mid (STV 0.3 0.9))

!(test
   (query 2000 ternaryCompletionKb (: $proof Mid $tv))
   (: ((antecedent-completion abd_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a d c)) Mid (STV 0.4615384615384615 0.8837518407406776)))

;; Source computations in the antecedent block every child completion.
!(compileadd computeSkipKb
   (: addOne
      (Implication
         (And
            (A $x)
            (Compute + ($x 1) -> $y))
         (B $y))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd computeSkipKb (: a-one (A 1) (STV 0.7 0.8)))
!(compileadd computeSkipKb (: b-two (B 2) (STV 0.9 0.8)))
!(set-base-rate computeSkipKb
   (And (A $x) (Compute + ($x 1) -> $y)) (STV 0.2 0.9))
!(set-base-rate computeSkipKb (B $y) (STV 0.4 0.9))
!(set-base-rate computeSkipKb (A $x) (STV 0.3 0.9))

!(test
   (query 300 computeSkipKb
      (: ((antecedent-completion addOne 0 with cpu $prior) $w)
         (A 1) $tv))
   ())

;; An existential And is compiled as an ExistentialClaim, not as a
;; conjunction that can complete a missing child.
!(compileadd existsSkipKb (: p (P a) (STV 1.0 1.0)))
!(compileadd existsSkipKb (: q Q (STV 1.0 0.9)))
!(compileadd existsSkipKb
   (: existsRule
      (Implication
         (Exists ($x) (And (P $x) Q))
         R)
      (CTV (STV 1.0 0.9) (STV 0.0 0.9))))
!(compileadd existsSkipKb (: r R (STV 1.0 0.9)))
!(set-base-rate existsSkipKb (And (P $x) Q) (STV 0.2 0.9))
!(set-base-rate existsSkipKb R (STV 0.4 0.9))
!(set-base-rate existsSkipKb (P $x) (STV 0.3 0.9))

!(test
   (query 300 existsSkipKb
      (: ((antecedent-completion existsRule 1 with cpu $prior) $w)
         Q $tv))
   ())

;; A completion is an update of its conjunct's base rate, so it merges with
;; a plain inversion over the same base rate by Bayes' rule when they share no
;; evidence. Rain wets an outdoor place with 0.9 (0.2 otherwise) and brings
;; clouds with 0.8 (0.25 otherwise); d is outdoor, wet and cloudy. Given
;; Outdoor d, the observations are independent given Rain d:
;;   odds = 0.3/0.7 * (0.9/0.2) * (0.8/0.25) = 6.1714, P(Rain d) = 0.86056.
;; Alone, the completion gives 0.6585 and the inversion 0.5783; revising them
;; would average the two and count the base rate twice.
!(compileadd rainKb (: wet (Implication (And (Outdoor $x) (Rain $x)) (Wet $x)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd rainKb (: clouds (Implication (Rain $x) (Clouds $x)) (CTV (STV 0.8 1) (STV 0.25 1))))
!(set-base-rate rainKb (Rain $x) (STV 0.3 0.9))
!(compileadd rainKb (: outdoor-d (Outdoor d) (STV 1 1)))
!(compileadd rainKb (: wet-d (Wet d) (STV 1 1)))
!(compileadd rainKb (: clouds-d (Clouds d) (STV 1 1)))
!(test (query 2000 rainKb (: $proof (Rain d) $tv)) (: (factored-revision cpu (prior (STV 0.3 0.9)) (((antecedent-completion wet 1 with cpu (prior (STV 0.3 0.9))) (conjunction outdoor-d wet-d)) ((inverted clouds with cpu (prior (STV 0.3 0.9))) clouds-d))) (Rain d) (STV 0.8605577689243028 0.9402246334264118)))

;; A rule reading rain off the wet ground directly inverts the same
;; observation the completion reads: the two share wet-d and are not
;; independent, so they are not factored. The completion's evidence (outdoor-d
;; and wet-d) contains the inversion's, so it is kept:
;; 0.9 * 0.3 / (0.9 * 0.3 + 0.2 * 0.7) = 0.6585, where factoring would have
;; counted wet-d twice (0.897).
!(compileadd sharedKb (: wet (Implication (And (Outdoor $x) (Rain $x)) (Wet $x)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd sharedKb (: wet-direct (Implication (Rain $x) (Wet $x)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(set-base-rate sharedKb (Rain $x) (STV 0.3 0.9))
!(compileadd sharedKb (: outdoor-d (Outdoor d) (STV 1 1)))
!(compileadd sharedKb (: wet-d (Wet d) (STV 1 1)))
!(test (query 2000 sharedKb (: $proof (Rain d) $tv)) (: ((antecedent-completion wet 1 with cpu (prior (STV 0.3 0.9))) (conjunction outdoor-d wet-d)) (Rain d) (STV 0.6585365853658537 0.8935987963307269)))
