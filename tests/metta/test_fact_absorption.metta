!(import! &self ../../pettachainer/metta/petta_chainer)

;; Facts stored after a search are read by the nodes it built, at no step
;; (docs/metta/fact_absorption.md).

!(set-evidence-confidence-k 5)
!(compileadd absorbKb (: blocked-k1 (Implication (Storm g1 $t) (Blocked k1 $t)) (CTV (STV 0.8 1) (STV 0.03 1))))
!(compileadd absorbKb (: delayed-d1 (Implication (Blocked k1 $t) (Delayed d1 $t)) (CTV (STV 0.85 1) (STV 0.05 1))))
!(compileadd absorbKb (: late-s1 (Implication (Delayed d1 $t) (Late s1 $t)) (CTV (STV 0.9 1) (STV 0.05 1))))
!(compileadd absorbKb (: late-s2 (Implication (Delayed d1 $t) (Late s2 $t)) (CTV (STV 0.9 1) (STV 0.05 1))))
!(compileadd absorbKb (: g-h1 (Storm g1 h1) (STV 1 1)))
!(compileadd absorbKb (: g-h2 (Storm g1 h2) (STV 0 1)))
!(compileadd absorbKb (: k-h1 (Blocked k1 h1) (STV 1 1)))
!(compileadd absorbKb (: k-h2 (Blocked k1 h2) (STV 0 1)))
!(compileadd absorbKb (: d-h1 (Delayed d1 h1) (STV 1 1)))
!(compileadd absorbKb (: d-h2 (Delayed d1 h2) (STV 0 1)))
!(compileadd absorbKb (: s1-h1 (Late s1 h1) (STV 1 1)))
!(compileadd absorbKb (: s1-h2 (Late s1 h2) (STV 0 1)))
!(compileadd absorbKb (: s2-h1 (Late s2 h1) (STV 1 1)))
!(compileadd absorbKb (: s2-h2 (Late s2 h2) (STV 0 1)))

;; One step expands the root: (Blocked k1 t1) joins its search unexpanded and
;; (Delayed d1 t1) is not reached. Nothing is known about t1 yet.
!(test
   (collapse (query 1 absorbKb (: $proof (Blocked k1 t1) $tv)))
   ((: (population-prior (Blocked k1 $_t)) (Blocked k1 t1) (STV 0.5 0.2857142857142857))))

;; A late shipment of t1 is read by the unexpanded (Delayed d1 t1) through the
;; rule it is a premise of, so a query without steps takes it in.
!(compileadd absorbKb (: s1-t1 (Late s1 t1) (STV 1 1)))
!(test
   (collapse (query 0 absorbKb (: $proof (Blocked k1 t1) $tv)))
   ((: ((inverted delayed-d1 with cpu (prior (STV 0.5 0.2857142857142857)))
         ((inverted late-s1 with cpu (prior (STV 0.5 0.2857142857142857))) s1-t1))
       (Blocked k1 t1) (STV 0.8930635838150288 0.732942705403439))))

;; So is the second, through its own rule.
!(compileadd absorbKb (: s2-t1 (Late s2 t1) (STV 1 1)))
!(test
   (collapse (query 0 absorbKb (: $proof (Blocked k1 t1) $tv)))
   ((: ((inverted delayed-d1 with cpu (prior (STV 0.5 0.2857142857142857)))
         (factored-revision cpu (prior (STV 0.5 0.2857142857142857))
            (((inverted late-s1 with cpu (prior (STV 0.5 0.2857142857142857))) s1-t1)
             ((inverted late-s2 with cpu (prior (STV 0.5 0.2857142857142857))) s2-t1))))
       (Blocked k1 t1) (STV 0.9414075845575675 0.7379853529326867))))

;; An expanded node's join waiting on a ground premise reads the premise's
;; facts whenever they are stored, though the premise itself was never
;; expanded.
!(test
   (collapse (query 1 absorbKb (: $proof (Delayed d1 t2) $tv)))
   ((: (population-prior (Delayed d1 $_t)) (Delayed d1 t2) (STV 0.5 0.2857142857142857))))
!(compileadd absorbKb (: s1-t2 (Late s1 t2) (STV 0 1)))
!(test
   (collapse (query 0 absorbKb (: $proof (Delayed d1 t2) $tv)))
   ((: ((inverted late-s1 with cpu (prior (STV 0.5 0.2857142857142857))) s1-t2)
       (Delayed d1 t2) (STV 0.09523809523809523 0.6063849287916186))))
