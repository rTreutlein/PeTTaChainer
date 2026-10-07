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
