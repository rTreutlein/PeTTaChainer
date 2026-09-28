!(import! &self ../../pettachainer/metta/petta_chainer)

;; An implication query whose consequent variables occur in the antecedent is
;; also answered empirically: one sample per antecedent binding with a provable
;; consequent, folded with the weighted accumulator. Open world: c has no
;; provable consequent and is not a sample. Strength is the mass-weighted
;; consequent strength, confidence is count-based. The negative branch is the
;; heuristic one a stored STV rule gets, derived from the base rates of both
;; sides at a quarter of the smallest confidence.

!(compileadd instanceFactsKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: a3 (A c) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: b2 (B b) (STV 1.0 0.9)))
!(compileadd instanceFactsKb (: c3 (C c) (STV 1.0 0.9)))

!(test
   (query 100 instanceFactsKb (: $prf (Implication (A $v) (B $v)) $tv))
   (: (implication-instance-fold
         (foldall-proof
            (implication-instance-sample a1 b1)
            (implication-instance-sample a2 b2)))
      (Implication (A $_v) (B $_v))
      (CTV (STV 1.0 0.0020209076619844817) (STV 1.0 0.0005052269154961204))))

;; A ground implication is a one-sample fold.
!(test
   (query 100 instanceFactsKb (: $prf (Implication (A a) (B a)) $tv))
   (: (implication-instance-fold
         (foldall-proof (implication-instance-sample a1 b1)))
      (Implication (A a) (B a))
      (CTV (STV 1.0 0.001011475880670821) (STV 1.0 0.00025286897016770524))))

;; A consequent added later joins the fold on the next query. The ground
;; implication answered above is an instance of the open query and is
;; returned beside it.
!(compileadd instanceFactsKb (: b3 (B c) (STV 1.0 0.9)))

!(test
   (collapse
      (let (: $prf $type $tv)
         (query 100 instanceFactsKb (: $prf (Implication (A $v) (B $v)) $tv))
         $tv))
   ((CTV (STV 1.0 0.0030283015340902015) (STV 1.0 0.0007570753835225504))
    (CTV (STV 1.0 0.001011475880670821) (STV 1.0 0.00025286897016770524))))

;; --- An explicit counterexample lowers the strength -------------------------
;; (Not (B b)) is stored as (B b) with inverted strength, so it is a sample
;; with consequent strength 0.

!(compileadd instanceNegKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceNegKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceNegKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd instanceNegKb (: nb2 (Not (B b)) (STV 1.0 0.9)))

!(test
   (query 100 instanceNegKb (: $prf (Implication (A $v) (B $v)) $tv))
   (: (implication-instance-fold
         (foldall-proof
            (implication-instance-sample a1 b1)
            (implication-instance-sample a2 nb2)))
      (Implication (A $_v) (B $_v))
      (CTV (STV 0.5 0.0020209076619844817) (STV 0.5 0.0005052269154961204))))

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

!(test
   (let (: (merge/revision
              (total-implication (by ab $_pos) (by ab $_neg))
              (implication-instance-fold
                 (foldall-proof (implication-instance-sample a1 b1))))
           $type $tv)
      (query 200 instanceRuleKb (: $prf (Implication (A $v) (B $v)) $tv))
      $tv)
   (CTV (STV 0.8000224974691158 0.9000101236509124)
        (STV 3.4615653061434316e-08 0.9998360246640894)))

;; A rule-only KB keeps the plain hypothetical answer: nothing to sample.
!(compileadd instanceRuleOnlyKb
   (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

!(test
   (let (: (total-implication (by ab $_pos) (by ab $_neg)) $type $tv)
      (query 100 instanceRuleOnlyKb (: $prf (Implication (A $v) (B $v)) $tv))
      $tv)
   (CTV (STV 0.8 0.8999999996758992) (STV 0.0 0.9998360246572885)))

;; --- A different rule producing the consequent is independent evidence ------

!(compileadd instanceOtherRuleKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceOtherRuleKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceOtherRuleKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd instanceOtherRuleKb (: c2 (C b) (STV 1.0 0.9)))
!(compileadd instanceOtherRuleKb
   (: cb (Implication (C $x) (B $x)) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(test
   (query 200 instanceOtherRuleKb (: $prf (Implication (A $v) (B $v)) $tv))
   (: (implication-instance-fold
         (foldall-proof
            (implication-instance-sample a1 b1)
            (implication-instance-sample a2 (by cb c2))))
      (Implication (A $_v) (B $_v))
      (CTV (STV 0.7500000125034592 0.0020209075611154013)
           (STV 0.750000012503459 0.0005052268902788503))))

;; --- Conjunctive antecedent and a variable only the antecedent uses ---------

!(compileadd instanceConjKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd instanceConjKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd instanceConjKb (: c1 (C a) (STV 1.0 0.9)))
!(compileadd instanceConjKb (: c2 (C b) (STV 1.0 0.9)))
!(compileadd instanceConjKb (: b1 (B a) (STV 1.0 0.9)))

!(test
   (query 200 instanceConjKb
      (: $prf (Implication (And (A $v) (C $v)) (B $v)) $tv))
   (: (implication-instance-fold
         (foldall-proof (implication-instance-sample a1 c1 b1)))
      (Implication (And (A $_v) (C $_v)) (B $_v))
      (CTV (STV 1.0 0.0009195848842900393) (STV 1.0 0.00022989622107250982))))

!(compileadd instanceTwoVarKb (: p1 (P a x) (STV 1.0 0.9)))
!(compileadd instanceTwoVarKb (: p2 (P b y) (STV 1.0 0.9)))
!(compileadd instanceTwoVarKb (: q1 (Q a) (STV 1.0 0.9)))

!(test
   (query 200 instanceTwoVarKb (: $prf (Implication (P $v $w) (Q $v)) $tv))
   (: (implication-instance-fold
         (foldall-proof (implication-instance-sample p1 q1)))
      (Implication (P $_v $_w) (Q $_v))
      (CTV (STV 1.0 0.001011475880670821) (STV 1.0 0.00025286897016770524))))

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
