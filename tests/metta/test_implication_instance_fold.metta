!(import! &self ../../pettachainer/metta/petta_chainer)

;; An implication query whose consequent variables occur in the antecedent is
;; also answered empirically: one sample per antecedent binding with a provable
;; consequent, folded with the weighted accumulator. Open world: c has no
;; provable consequent and is not a sample. Strength is the mass-weighted
;; consequent strength, confidence is count-based. Public implication queries
;; return that positive branch as an STV; `(Implication (Not A) B)` asks for
;; the negative one.

!(compileadd instanceFactsKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: a3 (A c) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: b2 (B b) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: c3 (C c) (STV 1.0 0.9)))

!(test
   (query 100 instanceFactsKb (: $prf (Implication (A $v) (B $v)) $tv))
   (: (implication-instance-fold cpu) (Implication (A $_v) (B $_v)) (STV 1.0 0.0020209076619844817)))

;; A ground implication is a one-sample fold.
!(test
   (query 100 instanceFactsKb (: $prf (Implication (A a) (B a)) $tv))
   (: (implication-instance-fold cpu) (Implication (A a) (B a)) (STV 1.0 0.001011475880670821)))

;; A consequent added later joins the fold on the next query. The ground
;; implication answered above is an instance of the open query and is
;; returned beside it.
!(compileadd instanceFactsKb (: b3 (B c) (STV 1.0 0.9)))

!(test
   (collapse
      (let (: $prf $type $tv) (query 100 instanceFactsKb (: $prf (Implication (A $v) (B $v)) $tv)) $tv))
   ((STV 1.0 0.0030283015340902015) (STV 1.0 0.001011475880670821)))

;; --- An explicit counterexample lowers the strength -------------------------
;; (Not (B b)) is stored as (B b) with inverted strength, so it is a sample
;; with consequent strength 0.

!(compileadd instanceNegKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceNegKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceNegKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd instanceNegKb (: nb2 (Not (B b)) (STV 1.0 0.9)))

!(test
   (query 100 instanceNegKb (: $prf (Implication (A $v) (B $v)) $tv))
   (:
      (implication-instance-fold cpu)
      (Implication (A $_v) (B $_v))
      (STV 0.4999627775704609 0.0020205545927834746)))

;; --- A rule for the same implication ---------------------------------------
;; The hypothetical proof through ab and the instance fold revise into one
;; answer. Samples whose consequent is derived by ab itself restate the rule
;; and are excluded, so only a (with its stored fact b1) is a sample; b and c
;; are provable only through ab.

!(compileadd instanceRuleKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceRuleKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceRuleKb (: a3 (A c) (STV 1.0 0.9)))
!(compileadd instanceRuleKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd instanceRuleKb
   (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

;; The axiom and its conditional proof tie in confidence. Canonical fallback
;; order can select the conditional proof (confidence differs by 3.3e-10);
;; either still revises the supplied rate with the empirical instance fold.
!(test
   (let (: (merge/revision $_prior (implication-instance-fold cpu)) $type (STV $s $c))
        (query 200 instanceRuleKb (: $prf (Implication (A $v) (B $v)) $value))
      (if (< (abs-math (- $s 0.8000224974690348)) 0.00000001)
         (< (abs-math (- $c 0.9000101239749476)) 0.00000001) false)) true)

;; A rule-only KB keeps the plain hypothetical answer: nothing to sample.
!(compileadd instanceRuleOnlyKb
   (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

!(test
   (let
      (: ab $type $tv)
      (query 100 instanceRuleOnlyKb (: $prf (Implication (A $v) (B $v)) $tv))
      $tv)
   (STV 0.8 0.9))

;; --- A different rule producing the consequent is independent evidence ------

!(compileadd instanceOtherRuleKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceOtherRuleKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceOtherRuleKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd instanceOtherRuleKb (: c2 (C b) (STV 1.0 0.9)))
!(compileadd instanceOtherRuleKb
   (: cb (Implication (C $x) (B $x)) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(test
   (query 200 instanceOtherRuleKb (: $prf (Implication (A $v) (B $v)) $tv))
   (:
      (implication-instance-fold cpu)
      (Implication (A $_v) (B $_v))
      (STV 0.7500000125034592 0.0020209075611154013)))

;; --- Conjunctive antecedent and a variable only the antecedent uses ---------

!(compileadd instanceConjKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceConjKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceConjKb (: c1 (C a) (STV 1.0 0.9)))
!(compileadd instanceConjKb (: c2 (C b) (STV 1.0 0.9)))
!(compileadd instanceConjKb (: b1 (B a) (STV 1.0 0.9)))

!(test
   (query 200 instanceConjKb (: $prf (Implication (And (A $v) (C $v)) (B $v)) $tv))
   (:
      (implication-instance-fold cpu)
      (Implication (And (A $_v) (C $_v)) (B $_v))
      (STV 1.0 0.0009195848842900393)))

!(compileadd instanceTwoVarKb (: p1 (P a x) (STV 1.0 0.9)))
!(compileadd instanceTwoVarKb (: p2 (P b y) (STV 1.0 0.9)))
!(compileadd instanceTwoVarKb (: q1 (Q a) (STV 1.0 0.9)))

!(test
   (query 200 instanceTwoVarKb (: $prf (Implication (P $v $w) (Q $v)) $tv))
   (: (implication-instance-fold cpu) (Implication (P $_v $_w) (Q $_v)) (STV 1.0 0.001011475880670821)))

;; --- A consequent derivable only through the implication itself ------------
;; The sample would depend on the goal being estimated; the dependency checks
;; reject it before it reaches the fold.

!(compileadd instanceCycleKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceCycleKb
   (: viaImpl
      (Implication
         (And (A $x) (Implication (A $z) (B $z)))
         (B $x))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 200 instanceCycleKb (: $prf (Implication (A $v) (B $v)) $tv))
   ())

;; --- Antecedent-false samples leave the positive query unchanged ------------
;; A binding whose antecedent is known false is a sample of P(B | not A), with
;; its own count: 1 of 4 here, so (0.25, 4/804), however the base rates of A
;; and B would put it. P(B | A) is 2 of 2.
!(compileadd negKb (: n1 (A p) (STV 1 1)))
!(compileadd negKb (: n2 (A q) (STV 1 1)))
!(compileadd negKb (: n3 (A r) (STV 0 1)))
!(compileadd negKb (: n4 (A s) (STV 0 1)))
!(compileadd negKb (: n5 (A t) (STV 0 1)))
!(compileadd negKb (: n6 (A u) (STV 0 1)))
!(compileadd negKb (: m1 (B p) (STV 1 1)))
!(compileadd negKb (: m2 (B q) (STV 1 1)))
!(compileadd negKb (: m3 (B r) (STV 1 1)))
!(compileadd negKb (: m4 (B s) (STV 0 1)))
!(compileadd negKb (: m5 (B t) (STV 0 1)))
!(compileadd negKb (: m6 (B u) (STV 0 1)))
;; The negated antecedent's instances are A's antecedent-false samples, read
;; from A's own fold (#108): 1 of 4 at their count, alike cold and after the
;; positive query.
!(test
   (let (: $prf $type $tv) (query 100 negKb (: $prf (Implication (Not (A $v)) (B $v)) $tv)) $tv)
   (STV 0.24990002999100272 0.004974629489078395))
!(test
   (let (: $prf $type $tv) (query 100 negKb (: $prf (Implication (A $v) (B $v)) $tv)) $tv)
   (STV 1.0 0.0024937655860349127))
!(test
   (let (: $prf $type $tv) (query 100 negKb (: $prf (Implication (Not (A $v)) (B $v)) $tv)) $tv)
   (STV 0.24990002999100272 0.004974629489078395))
;; Without an antecedent-false instance the negated antecedent has no sample,
;; and the instances give it no answer (every A of instanceFactsKb is true).
!(test (query 100 instanceFactsKb (: $prf (Implication (Not (A $v)) (B $v)) $tv)) ())

;; Uncertain samples weigh each branch by the antecedent's mass on its side,
;; the claim's confidence times the consequent's (0.81), times the claim's
;; strength for the positive branch and its complement for the negative one:
;; P(Up | Claims) = (0.81 + 0.2025 * 0.6) / (0.81 + 0.2025) and
;; P(Up | not Claims) = (0.81 + 0.6075 * 0.6) / (0.81 * 2 + 0.6075), at the
;; count of their masses. One regime keeps the plain counts.
!(set-rule-change-hazard softKb 0)
!(compileadd softKb (: c1 (Claims a) (STV 1 0.9)))
!(compileadd softKb (: c2 (Claims b) (STV 0 0.9)))
!(compileadd softKb (: c3 (Claims c) (STV 0 0.9)))
!(compileadd softKb (: c4 (Claims d) (STV 0.25 0.9)))
!(compileadd softKb (: u1 (Up a) (STV 1 0.9)))
!(compileadd softKb (: u2 (Up b) (STV 1 0.9)))
!(compileadd softKb (: u3 (Up c) (STV 0 0.9)))
!(compileadd softKb (: u4 (Up d) (STV 0.6 0.9)))
!(test
   (collapse (let (query-result $i (: $prf $type (STV $s $c)))
         (query-many 100 softKb
            ((: $p (Implication (Claims $n) (Up $n)) $tv)
             (: $q (Implication (Not (Claims $m)) (Up $m)) $tv2)))
      (let ($ws $ms) (if (== $i 0) (0.9315 1.0125) (1.1745 2.2275))
         (and (< (abs-math (- $s (/ $ws $ms))) 1e-12)
            (< (abs-math (- $c (count-confidence $ms))) 1e-12)))))
   (true true))

;; --- Three conjuncts --------------------------------------------------------
;; The conjunction of the antecedent's truth values is multiplied pairwise, as
;; a lowered antecedent multiplies it (AndFormula is binary): before, three
;; conjuncts gave no sample and no answer (ChainerGame
;; benchmarks/ona/repros/three_conjuncts.py).
!(set-evidence-confidence-k 1)
!(compileadd threeKb (: p1 (P t1) (STV 1 1)))
!(compileadd threeKb (: q1 (Q t1) (STV 1 1)))
!(compileadd threeKb (: r1 (R t1) (STV 1 1)))
!(compileadd threeKb (: g1 (G t1) (STV 1 1)))
!(compileadd threeKb (: p2 (P t2) (STV 1 1)))
!(compileadd threeKb (: q2 (Q t2) (STV 1 1)))
!(compileadd threeKb (: r2 (R t2) (STV 1 1)))
!(compileadd threeKb (: g2 (G t2) (STV 1 1)))
!(test
   (let
      (: $prf $type $tv)
      (query 200 threeKb (: $prf (Implication (And (P $t) (Q $t) (R $t)) (G $t)) $tv))
      $tv)
   (STV 1.0 0.66659999333266))
!(set-rule-refinement threeRuleKb true)
;; A refined three-part rule learns from its instances (t2's third conjunct
;; at 0.9 weighs its negative sample 0.9), instead of keeping its axiom.
!(compileadd threeRuleKb (: h3 (Implication (And (P $t) (Q $t) (R $t)) (G $t)) (STV 0.5 0.01)))
!(compileadd threeRuleKb (: p1 (P t1) (STV 1 1)))
!(compileadd threeRuleKb (: q1 (Q t1) (STV 1 1)))
!(compileadd threeRuleKb (: r1 (R t1) (STV 1 1)))
!(compileadd threeRuleKb (: g1 (G t1) (STV 1 1)))
!(compileadd threeRuleKb (: p2 (P t2) (STV 1 1)))
!(compileadd threeRuleKb (: q2 (Q t2) (STV 1 1)))
!(compileadd threeRuleKb (: r2 (R t2) (STV 1 0.9)))
!(compileadd threeRuleKb (: g2 (G t2) (STV 0 1)))
!(test
   (let (: $prf $type $tv) (query 200 threeRuleKb (: $prf (RuleTruth (Implication (And (P $t) (Q $t) (R $t)) (G $t))) $tv)) $tv)
   (STV 0.5260578505053451 0.6562878403845945))

;; A query's rules leave with it, deferred joins included: a later query's
;; rule may take the same id, and resuming the old join with it failed the
;; whole walk, so a larger budget after a zero-budget read answered nothing.
!(set-rule-change-hazard laterBudgetKb 0)
!(compileadd laterBudgetKb (: la (Human a) (STV 1.0 1.0)))
!(compileadd laterBudgetKb (: lam (Mortal a) (STV 0.8 1.0)))
!(compileadd laterBudgetKb (: lb (Human b) (STV 0.5 1.0)))
!(compileadd laterBudgetKb (: lbm (Mortal b) (STV 0.4 1.0)))
!(query 5 laterBudgetKb (: $prf (Implication (Human $x) (Mortal $x)) $tv))
!(query 0 laterBudgetKb (: $prf (Implication (Human $x) (Mortal $x)) $tv))
!(test
   (let (: $prf $type $tv) (query 1000 laterBudgetKb (: $prf (Implication (Human $x) (Mortal $x)) $tv)) $tv)
   (STV 0.6666666666666666 0.6))
