!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self ./posterior_assertions)

;; Facts stored after a search are read by the nodes it built
;; (docs/metta/fact_absorption.md). Budget zero does no work, so the joint
;; posterior they refresh is paid by a one-step query.

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
;; rule it is a premise of, so a one-step query takes it in.
!(compileadd absorbKb (: s1-t1 (Late s1 t1) (STV 1 1)))
!(test
   (let ((: (node (conjunction s1-t1 (by blocked-k1 cpu) (by delayed-d1 cpu) (by late-s1 cpu) (population-prior (Storm g1 $_0)))) (Blocked k1 t1) (STV $posterior-s $posterior-c))) (collapse (query 1 absorbKb (: $proof (Blocked k1 t1) $tv))) (posterior-tv-near? 0.8555844675740594 0.37282530478545584 (STV $posterior-s $posterior-c)))
   true)

;; So is the second, through its own rule.
!(compileadd absorbKb (: s2-t1 (Late s2 t1) (STV 1 1)))
!(test
   (let ((: (node (conjunction s1-t1 s2-t1 (by blocked-k1 cpu) (by delayed-d1 cpu) (by late-s1 cpu) (by late-s2 cpu) (population-prior (Storm g1 $_0)))) (Blocked k1 t1) (STV $posterior-s $posterior-c))) (collapse (query 1 absorbKb (: $proof (Blocked k1 t1) $tv))) (posterior-tv-near? 0.9193418069557667 0.350377682390757 (STV $posterior-s $posterior-c)))
   true)

;; An expanded node's join waiting on a ground premise reads the premise's
;; facts whenever they are stored, though the premise itself was never
;; expanded.
!(test
   (collapse (query 1 absorbKb (: $proof (Delayed d1 t2) $tv)))
   ((: (population-prior (Delayed d1 $_t)) (Delayed d1 t2) (STV 0.5 0.2857142857142857))))
!(compileadd absorbKb (: s1-t2 (Late s1 t2) (STV 0 1)))
!(test
   (let ((: (node (conjunction s1-t2 (by blocked-k1 cpu) (by delayed-d1 cpu) (by late-s1 cpu) (population-prior (Storm g1 $_0)))) (Delayed d1 t2) (STV $posterior-s $posterior-c))) (collapse (query 1 absorbKb (: $proof (Delayed d1 t2) $tv))) (posterior-tv-near? 0.06109067647529186 0.5898285722031854 (STV $posterior-s $posterior-c)))
   true)
