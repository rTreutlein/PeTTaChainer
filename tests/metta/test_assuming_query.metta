!(import! &self ../../pettachainer/metta/petta_chainer)

;; An Assuming query proves its goal as if its facts were stored, together
;; with everything the knowledge base holds (docs/metta/assumption_queries.md).
!(compileadd decideKb (: l1 (LeakBelief u1) (STV 0.3 0.8)))
!(compileadd decideKb
   (: (no_inverse protects)
      (Implication (And (Candidate $s $u) (LeakBelief $u)) (Outcome $s $u protected))
      (CTV (STV 1 1) (STV 0 1))))

;; The assumed candidate combines with the stored belief, read in the main
;; context since the assumption cannot change it.
!(test
   (query 60 decideKb (: $prf (Assuming (Candidate s1 u1) (Outcome s1 u1 $o)) $tv))
   (: (assuming (by (no_inverse protects) (conjunction (ctx proof 0) l1)))
      (Assuming (Candidate s1 u1) (Outcome s1 u1 protected))
      (STV 0.3 0.7999999997956221)))

;; Nothing assumed is stored.
!(test (query 60 decideKb (: $prf (Outcome s1 u1 $o) $tv)) ())

;; An assumed implication is a rule within the query: it links a stored
;; statement to the one the decision reads, without adding a rule to the
;; knowledge base.
!(compileadd linkKb (: leak2 (SealLeak u2) (STV 0.6 0.9)))
!(compileadd linkKb
   (: (no_inverse protects)
      (Implication (And (Candidate $s $u) (LeakBelief $u)) (Outcome $s $u protected))
      (CTV (STV 1 1) (STV 0 1))))
!(test
   (let (: $_prf $_type (STV $s $_c))
      (car-atom (collapse (query 60 linkKb
         (: $prf
            (Assuming (And (Candidate s2 u2) (Implication (SealLeak u2) (LeakBelief u2)))
               (Outcome s2 u2 $o))
            $tv))))
      (and (> $s 0.5999) (< $s 0.6001)))
   true)

;; A fold over statements the assumptions affect folds them in the context:
;; the expected value of a repair weights each outcome's amount by its truth.
!(compileadd valueKb (: l1 (LeakBelief x) (STV 0.3 0.8)))
!(compileadd valueKb
   (: (no_inverse protects)
      (Implication (And (Candidate $s $u) (LeakBelief $u) (OutcomeValue $s (Repair $u) protected $v))
         (Outcome $s (Repair $u) protected $v))
      (CTV (STV 1 1) (STV 0 1))))
!(compileadd valueKb
   (: (no_inverse expected)
      (Implication
         (And (Candidate $s $u)
              (FoldAllTruth (Outcome $s (Repair $u) $o $v) (STV $p $_c) (Weighted $p $v) 0.0
                 (|-> ($acc (Weighted $w $x)) (+ $acc (* $w $x))) -> $g))
         (ExpectedValue $s (Repair $u) $g))
      (CTV (STV 1 1) (STV 0 1))))
!(test
   (let (: $_prf (Assuming $_facts (ExpectedValue $_s $_a $g)) $_tv)
      (car-atom (collapse (query 200 valueKb
         (: $prf (Assuming (And (Candidate s1 x) (OutcomeValue s1 (Repair x) protected 120))
                    (ExpectedValue s1 (Repair x) $g)) $tv))))
      $g)
   36.0)

;; The world's rules hold in the context, connective adapters included, and a
;; rule dormant in the main context runs there: here the leak belief exists
;; only through the assumed link, and an expected value folds a conjunction.
!(compileadd worldKb (: s1 (SealLeak x) (STV 0.3 0.8)))
!(compileadd worldKb
   (: (no_inverse protects)
      (Implication (And (Candidate $s $u) (LeakBelief $u)) (Outcome $s (Repair $u) protected))
      (CTV (STV 1 1) (STV 0 1))))
!(compileadd worldKb
   (: (no_inverse unneeded)
      (Implication (And (Candidate $s $u) (Not (LeakBelief $u))) (Outcome $s (Repair $u) unnecessary))
      (CTV (STV 1 1) (STV 0 1))))
!(compileadd worldKb
   (: (no_inverse expected)
      (Implication
         (And (Candidate $s $u)
              (FoldAllTruth (And (Outcome $s (Repair $u) $o) (Amount $s (Repair $u) $o $v)) (STV $p $_c)
                 (Weighted $p $v) 0.0 (|-> ($acc (Weighted $w $x)) (+ $acc (* $w $x))) -> $g))
         (ExpectedValue $s (Repair $u) $g))
      (CTV (STV 1 1) (STV 0 1))))
!(test
   (let (: $_prf (Assuming $_facts (ExpectedValue $_s $_a $g)) $_tv)
      (car-atom (collapse (query 200 worldKb
         (: $prf (Assuming (And (Candidate s1 x) (Implication (SealLeak x) (LeakBelief x))
                                (Amount s1 (Repair x) protected 120) (Amount s1 (Repair x) unnecessary -30))
                    (ExpectedValue s1 (Repair x) $g)) $tv))))
      $g)
   15.0)
