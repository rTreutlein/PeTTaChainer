!(import! &self ../../pettachainer/metta/petta_chainer)

;; #49: certain shared B is already represented in each specific posterior.
;; Divide by live P(T|B), not by population P(T). Python covers every order,
;; general revision, variance, cyclic/mixed families and uncertain B (#68).
!(set-bayes-prior-count 0)
!(compileadd separatorKb (: ab (Implication (And (A $x) (B $x)) (T $x)) (CTV (STV 0.8 0.99) (STV 0.1 0.99))))
!(compileadd separatorKb (: bc (Implication (And (B $x) (C $x)) (T $x)) (CTV (STV 0.6 0.99) (STV 0.1 0.99))))
!(compileadd separatorKb (: b (Implication (B $x) (T $x)) (CTV (STV 0.5 0.99) (STV 0.1 0.99))))
!(compileadd separatorKb (: a-input (A fresh) (STV 1 1)))
!(compileadd separatorKb (: b-input (B fresh) (STV 1 1)))
!(compileadd separatorKb (: c-input (C fresh) (STV 1 1)))
!(add-space-atom! &combination_tally
   (make-space-row4 (index-hash (quote (separatorKb T))) separatorKb T (combination-tally 98 24 0 0 0)))

!(test (let (: $_proof (T fresh) (STV $s $_confidence))
            (query 1000 separatorKb (: $p (T fresh) $tv))
         (< (abs-math (- $s (/ 6.0 7.0))) 0.000000000001)) true)

;; #77: triangle correction envelope includes the three tree corrections,
;; population twice and inclusion-exclusion. Its width is ln(27), not a
;; confidence/size choice of one separator; missing estimates get width >=1.
!(test (let $range (sk-overlap-range 2 (sk-link odds 0.25)
                          (cons (sk-link odds 0.4) (cons (sk-link odds 0.5) (cons (sk-link odds 0.6) ()))))
         (< (abs-math (- $range (log-math 2.718281828459045 27))) 0.000000000001)) true)
!(test (sk-overlap-range 1 0.0 ()) 1.0)
!(set-bayes-prior-count 0.2)
