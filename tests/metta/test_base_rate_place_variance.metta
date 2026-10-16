!(import! &self ../../pettachainer/metta/petta_chainer)

;; A view in the base rate's place keeps its own variance (SupplyNet stage
;; scale in small). A front persists with 0.9 and starts with 0.05, brings a
;; storm with 0.7 (0.05 without), and each of two sensors alarms with 0.6 in a
;; storm (0.25 without); all rules are given. The front is labelled off in
;; h1..h3, and both alarms ring in t1..t4. Exact (forward-backward
;; over the front, the storm summed out):
;;   P(alarms | front) = 0.7 * 0.36 + 0.3 * 0.0625 = 0.27075,
;;   P(alarms | no front) = 0.05 * 0.36 + 0.95 * 0.0625 = 0.077375,
;;   P(Front t1..t4) = 0.641822, 0.831254, 0.880809, 0.872239.
;; Each front is its persistence prediction in the base rate's place under
;; the storm's inversion, and the storm's own value read through the inversion
;; is its alarms' likelihood ratio over the storm's base rate. Every rule and
;; the label of h3 are given, so the posteriors are nearly certain. Before,
;; the merge gave the persistence prediction the front rate's log-odds
;; variance (a rate of 0.0125 over four periods, uncertain by a factor of
;; several), and the storm's ratio carried the storm rate's variance: every
;; front came out at confidence 10^-6.
!(set-evidence-confidence-k 5.0)
!(compileadd k (: persist (Implication (And (NextPeriod $p $t) (Front $p)) (Front $t)) (CTV (STV 0.9 1) (STV 0.05 1))))
!(compileadd k (: storm (Implication (Front $t) (Storm $t)) (CTV (STV 0.7 1) (STV 0.05 1))))
!(compileadd k (: alarm1 (Implication (Storm $t) (Alarm a1 $t)) (CTV (STV 0.6 1) (STV 0.25 1))))
!(compileadd k (: alarm2 (Implication (Storm $t) (Alarm a2 $t)) (CTV (STV 0.6 1) (STV 0.25 1))))
!(compileadd k (: front-h1 (Front h1) (STV 0 1)))
!(compileadd k (: storm-h1 (Storm h1) (STV 1 1)))
!(compileadd k (: next-h2 (NextPeriod h1 h2) (STV 1 1)))
!(compileadd k (: front-h2 (Front h2) (STV 0 1)))
!(compileadd k (: storm-h2 (Storm h2) (STV 0 1)))
!(compileadd k (: next-h3 (NextPeriod h2 h3) (STV 1 1)))
!(compileadd k (: front-h3 (Front h3) (STV 0 1)))
!(compileadd k (: storm-h3 (Storm h3) (STV 0 1)))
!(compileadd k (: next-t1 (NextPeriod h3 t1) (STV 1 1)))
!(compileadd k (: a1-t1 (Alarm a1 t1) (STV 1 1)))
!(compileadd k (: a2-t1 (Alarm a2 t1) (STV 1 1)))
!(compileadd k (: next-t2 (NextPeriod t1 t2) (STV 1 1)))
!(compileadd k (: a1-t2 (Alarm a1 t2) (STV 1 1)))
!(compileadd k (: a2-t2 (Alarm a2 t2) (STV 1 1)))
!(compileadd k (: next-t3 (NextPeriod t2 t3) (STV 1 1)))
!(compileadd k (: a1-t3 (Alarm a1 t3) (STV 1 1)))
!(compileadd k (: a2-t3 (Alarm a2 t3) (STV 1 1)))
!(compileadd k (: next-t4 (NextPeriod t3 t4) (STV 1 1)))
!(compileadd k (: a1-t4 (Alarm a1 t4) (STV 1 1)))
!(compileadd k (: a2-t4 (Alarm a2 t4) (STV 1 1)))
;; Independent addition order can differ in the last floating point bit.
(: front-tv-close? (-[det]-> Atom TV Bool))
(= (front-tv-close? (: $_proof $_statement (STV $s $c)) (STV $expected-s $expected-c))
   (and (<= (abs-math (- $s $expected-s)) 1e-12)
        (<= (abs-math (- $c $expected-c)) 1e-12)))
!(test (let $answer (query 400 k (: $p (Front t1) $tv)) (front-tv-close? $answer (STV 0.6418215221402455 0.9995162177195637))) true)
!(test (let $answer (query 400 k (: $p (Front t2) $tv)) (front-tv-close? $answer (STV 0.8312542646557476 0.9998114806859971))) true)
!(test (let $answer (query 400 k (: $p (Front t3) $tv)) (front-tv-close? $answer (STV 0.8808092974576823 0.999890519622883))) true)
!(test (let $answer (query 400 k (: $p (Front t4) $tv)) (front-tv-close? $answer (STV 0.872238571738694 0.9999205471487975))) true)
