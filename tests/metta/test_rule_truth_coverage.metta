!(import! &self ../../pettachainer/metta/petta_chainer)

;; A ground rule does not cover an open population query. Its shape lookup
;; must neither specialize that query nor replace the independent blue sample.
!(set-rule-refinement coverageKb true)
!(set-rule-change-hazard coverageKb 0)
!(compileadd coverageKb (: local (Implication (A red) (B red))
   (CTV (STV 0.2 0.1) (STV 0.2 0.1))))
!(compileadd coverageKb (: a (A blue) (STV 1 1)))
!(compileadd coverageKb (: b (B blue) (STV 1 1)))
!(test (rule-truth-installed? coverageKb (Implication (A $x) (B $x))) false)
!(test (rule-truth-installed? coverageKb (Implication (A red) (B red))) true)
!(test (rule-truth-installed? coverageKb (Implication (A blue) (B blue))) false)
!(test (collapse (let (: $p $type (STV 1.0 $c))
   (query 1000 coverageKb (: $q (Implication (A $x) (B $x)) $tv))
   (<= (abs-math (- $c (/ 1 801))) 1e-12))) (true))

;; General coverage works for variants and specializations, preserving the
;; query's variables. Shared variables in the producer are constraints.
!(compileadd coverageKb (: general (Implication (C $x) (D $x)) (STV 0.8 0.5)))
!(test (let* (($type (Implication (C $y) (D $y)))
              ($_found (rule-truth-installed? coverageKb $type)))
   (=alpha $type (Implication (C $z) (D $z)))) true)
!(test (rule-truth-installed? coverageKb (Implication (C blue) (D blue))) true)
!(test (rule-truth-installed? coverageKb (Implication (C $y) (D $z))) false)
