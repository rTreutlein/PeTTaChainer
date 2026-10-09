!(import! &self ../../pettachainer/metta/petta_chainer)

;; A completion inverts the rule onto one conjunct M given the others O and
;; the consequent C, by Bayes' rule over M's base rate and the joint of O and
;; M. With u = P(C|O,M) and v = P(C|not(O,M)) the rule's branches (v
;; recovered from P(C) and P(O,M) for a rule stated with an STV), C's
;; likelihoods given M are u' = s_O u + (1 - s_O) v and v, so
;;   P(M|C) = u' P(M) / (u' P(M) + v (1 - P(M)))
;; and P(M|not C) the same with 1 - u', 1 - v; C's value weighs the two as its
;; likelihood ratio. A negated conjunct (Not I) completes I, with the two
;; likelihoods swapped. The proof names the base rate it updates, so it merges
;; with other updates of P(M) by Bayes' rule.

;; P(C|A,B) = 1 stated with an STV; P(C|not(A,B)) = (0.4 - 0.2) / 0.8 = 0.25
;; from P(C) and P(A,B); P(B|A,C) = 0.3 / (0.3 + 0.25 * 0.7) = 0.6316 (the
;; likelihoods, read at their confidence and A's 0.9, move it by less than
;; 1e-3).
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
   (: ((antecedent-completion ab_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a c)) B (STV 0.6310073449451215 0.2841778944410888)))

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
   (: ((antecedent-completion ab_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a c)) B (STV 0.5624999979355387 0.8847429872624439)))

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

;; An uncertain other conjunct enters C's likelihood given B: P(C|B) =
;; 0.5 * 0.9 + 0.5 * 0.3 = 0.6 and P(C|not B) = 0.3, so C doubles B's odds:
;; 0.6 * 0.3 / (0.6 * 0.3 + 0.3 * 0.7) = 0.4615. Weighing P(B|A,C) = 0.5625
;; by A's value, 0.5 * 0.5625 + 0.5 * 0.3 = 0.43125, ignored that C also
;; makes A likelier.
!(compileadd uncertainOtherKb (: a A (STV 0.5 0.9)))
!(compileadd uncertainOtherKb (: c C (STV 1.0 0.9)))
!(compileadd uncertainOtherKb
   (: ab_c
      (Implication (And A B) C)
      (CTV (STV 0.9 1) (STV 0.3 1))))
!(set-base-rate uncertainOtherKb B (STV 0.3 0.9))

!(test
   (query 2000 uncertainOtherKb (: $proof B $tv))
   (: ((antecedent-completion ab_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a c)) B (STV 0.4615371694105368 0.8783766592806719)))

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
   (: ((antecedent-completion abd_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a d c)) Mid (STV 0.46153845998002846 0.8837518482808618)))

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
!(test (query 2000 rainKb (: $proof (Rain d) $tv)) (: (factored-revision cpu (prior (STV 0.3 0.9)) (((antecedent-completion wet 1 with cpu (prior (STV 0.3 0.9))) (conjunction outdoor-d wet-d)) ((inverted clouds with cpu (prior (STV 0.3 0.9))) clouds-d))) (Rain d) (STV 0.8605577689243028 0.9402246334533977)))

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
!(test (query 2000 sharedKb (: $proof (Rain d) $tv)) (: ((antecedent-completion wet 1 with cpu (prior (STV 0.3 0.9))) (conjunction outdoor-d wet-d)) (Rain d) (STV 0.6585365853658537 0.8935987963764114)))

;; A completion reads its consequence as an observation. A predicate that only
;; forward rules conclude is predicted, here from the completed conjunct and
;; from servicing, never observed: the rule start prunes the completion, and
;; (Pred a) has no proof but its population prior, the base rate 0.3. Read as
;; an observation, the prediction 0.2 for (Pred2 b) would have pulled it down
;; to 0.172.
!(compileadd predictedKb (: persist (Implication (And (Next $p $t) (Pred $p)) (Pred2 $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd predictedKb (: fresh (Implication (Serv $t) (Pred2 $t)) (CTV (STV 0.2 1) (STV 0.2 1))))
!(compileadd predictedKb (: n1 (Next a b) (STV 1 1)))
!(compileadd predictedKb (: s1 (Serv b) (STV 1 1)))
!(set-base-rate predictedKb (Pred $p) (STV 0.3 0.9))
!(test (query 100 predictedKb (: $prf (Pred a) $tv)) (: (population-prior (Pred $p)) (Pred a) (STV 0.3 0.9)))

;; The mine runs exactly when the power plant runs and the mine is not
;; degraded. With the plant running and the mine off, the mine is degraded:
;; a negated conjunct completes the statement it negates, with the rule's
;; likelihoods swapped, P(Producing mine | Degraded) = v = 0 and
;; P(Producing mine | not Degraded) = u = 1 given the plant, so the mine off
;; gives 0.25 / (0.25 + 0) = 1.
!(compileadd degradedKb (: runs-mine (Implication (And (Producing plant $t) (Not (Degraded mine $t))) (Producing mine $t)) (CTV (STV 1 1) (STV 0 1))))
!(set-base-rate degradedKb (Degraded mine $t) (STV 0.25 0.9))
!(compileadd degradedKb (: plant-on (Producing plant t5) (STV 1 1)))
!(compileadd degradedKb (: mine-off (Producing mine t5) (STV 0 1)))
!(test (query 2000 degradedKb (: $prf (Degraded mine t5) $tv))
   (: ((antecedent-completion runs-mine 1 with cpu (prior (STV 0.25 0.9))) (conjunction plant-on mine-off)) (Degraded mine t5) (STV 1.0 0.9990009978782473)))
!(test (query 2000 degradedKb (: $prf (Not (Degraded mine t5)) $tv))
   (: (negated ((antecedent-completion runs-mine 1 with cpu (prior (STV 0.25 0.9))) (conjunction plant-on mine-off))) (Not (Degraded mine t5)) (STV 0.0 0.9990009978782473)))

;; The same with a positive conjunct: the mine is not healthy.
!(compileadd healthyKb (: runs-mine (Implication (And (Producing plant $t) (Healthy mine $t)) (Producing mine $t)) (CTV (STV 1 1) (STV 0 1))))
!(set-base-rate healthyKb (Healthy mine $t) (STV 0.75 0.9))
!(compileadd healthyKb (: plant-on (Producing plant t5) (STV 1 1)))
!(compileadd healthyKb (: mine-off (Producing mine t5) (STV 0 1)))
!(test (query 2000 healthyKb (: $prf (Healthy mine t5) $tv))
   (: ((antecedent-completion runs-mine 1 with cpu (prior (STV 0.75 0.9))) (conjunction plant-on mine-off)) (Healthy mine t5) (STV 0.0 0.9990009978782185)))

;; Both soft: the plant runs with 0.8, and a report that the mine runs
;; (P(report | runs) = 0.9, P(report | not) = 0.2) is a likelihood ratio of
;; 4.5 for the mine running. Given Degraded the mine is off whatever the
;; plant; given not Degraded it runs with 0.8. Bayes over the joint:
;; odds(Degraded) = 0.25 / 0.75 * 1 / (0.8 * 4.5 + 0.2) = 0.0877,
;; P = 2.5 / 31 = 0.0806452.
!(compileadd softKb (: runs-mine (Implication (And (Producing plant $t) (Not (Degraded mine $t))) (Producing mine $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd softKb (: report (Implication (Producing mine $t) (Reported mine $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(set-base-rate softKb (Degraded mine $t) (STV 0.25 0.9))
!(set-base-rate softKb (Producing mine $t) (STV 0.5 0.9))
!(compileadd softKb (: plant-maybe (Producing plant t5) (STV 0.8 1)))
!(compileadd softKb (: reported (Reported mine t5) (STV 1 1)))
!(test (query 2000 softKb (: $prf (Degraded mine t5) $tv))
   (: ((antecedent-completion runs-mine 1 with cpu (prior (STV 0.25 0.9))) (conjunction plant-maybe ((inverted report with cpu (prior (STV 0.5 0.9))) reported))) (Degraded mine t5) (STV 0.08064516197330747 0.9643979414693271)))

;; The degradation persists with 0.75 and starts with 0.1. Inspected sound in
;; t4, the mine is degraded in t5 with 0.1 by persistence alone; the plant
;; running and the mine off in t5 make it degraded, and the persistence chain
;; reads that: 0.75 in t6.
!(compileadd chainKb (: runs-mine (Implication (And (Producing plant $t) (Not (Degraded mine $t))) (Producing mine $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd chainKb (: persist (Implication (And (NextPeriod $p $t) (Degraded mine $p)) (Degraded mine $t)) (CTV (STV 0.75 1) (STV 0.1 1))))
!(set-base-rate chainKb (Degraded mine $t) (STV 0.25 0.9))
!(compileadd chainKb (: next-t5 (NextPeriod t4 t5) (STV 1 1)))
!(compileadd chainKb (: next-t6 (NextPeriod t5 t6) (STV 1 1)))
!(compileadd chainKb (: degraded-t4 (Degraded mine t4) (STV 0 1)))
!(compileadd chainKb (: plant-on (Producing plant t5) (STV 1 1)))
!(compileadd chainKb (: mine-off (Producing mine t5) (STV 0 1)))
!(test (query 2000 chainKb (: $prf (Degraded mine t6) $tv))
   (: (by persist (conjunction next-t6 (factored-revision (by persist (conjunction next-t5 degraded-t4)) (prior (STV 0.1 0.99990000952965)) (((antecedent-completion runs-mine 1 with cpu (prior (STV 0.25 0.9))) (conjunction plant-on mine-off)))))) (Degraded mine t6) (STV 0.7499980500039 0.9998999906178188)))
