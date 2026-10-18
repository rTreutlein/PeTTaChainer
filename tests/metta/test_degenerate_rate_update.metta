!(import! &self ../../pettachainer/metta/petta_chainer)

;; A front never seen in the history (SupplyNet stage scale in small): it
;; persists with 0.9 and starts with 0.05, brings a storm with 0.7 (0.05
;; without), and each of two sensors alarms with 0.6 in a storm (0.25
;; without); all rules are given. The front was off in h1..h3, and both
;; alarms ring in t1. Exact:
;;   P(alarms | storm) = 0.6^2 = 0.36, P(alarms | no storm) = 0.25^2 = 0.0625,
;;   P(alarms | front) = 0.7 * 0.36 + 0.3 * 0.0625 = 0.27075,
;;   P(alarms | no front) = 0.05 * 0.36 + 0.95 * 0.0625 = 0.077375,
;;   P(Front t1) = 0.05 * 0.27075 / (0.05 * 0.27075 + 0.95 * 0.077375) = 0.155525.
;; The front's base rate is 0 (three stored periods, none on; the budget does
;; not reach the fold's derived members). The storm's inversion onto the
;; front reads it as the prior of one more period under the Bayes prior,
;; 0.1 / 3.2 = 0.03125, so the update keeps its likelihood ratio, and the
;; persistence prediction takes the rate's place under it. The rules and the
;; labelled h3 are given, so the answer is nearly certain. Before, a rate of
;; 0 gave the inversion no prior, and the front stayed at the persistence
;; prediction, 0.05.
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
!(test
   (query 4 k (: $p (Front t1) $tv))
   (: (factored-revision (by persist (conjunction next-t1 front-h3)) (prior (STV 0.050001800020179385 0.9999000084782169)) (((inverted storm with cpu (prior (STV 0.03125 0.375))) (factored-revision cpu (prior (STV 0.34375 0.375)) (((inverted alarm1 with cpu (prior (STV 0.34375 0.375))) a1-t1) ((inverted alarm2 with cpu (prior (STV 0.34375 0.375))) a2-t1)))))) (Front t1) (STV 0.155530215767092 0.9997235654422796)))

;; The mirror case: a front on throughout its history (rate 1), and neither
;; alarm rings in t1. Exact:
;;   P(no alarms | storm) = 0.4^2 = 0.16, P(no alarms | no storm) = 0.75^2 = 0.5625,
;;   P(no alarms | front) = 0.7 * 0.16 + 0.3 * 0.5625 = 0.28075,
;;   P(no alarms | no front) = 0.05 * 0.16 + 0.95 * 0.5625 = 0.542375,
;;   P(Front t1) = 0.9 * 0.28075 / (0.9 * 0.28075 + 0.1 * 0.542375) = 0.823280.
;; The rate of 1 is read as 3.1 / 3.2, and the persistence prediction 0.9
;; takes its place under the storm's inversion. Before, a rate of 1 gave no
;; prior, and the front stayed at 0.9.
!(compileadd on (: persist (Implication (And (NextPeriod $p $t) (Front $p)) (Front $t)) (CTV (STV 0.9 1) (STV 0.05 1))))
!(compileadd on (: storm (Implication (Front $t) (Storm $t)) (CTV (STV 0.7 1) (STV 0.05 1))))
!(compileadd on (: alarm1 (Implication (Storm $t) (Alarm a1 $t)) (CTV (STV 0.6 1) (STV 0.25 1))))
!(compileadd on (: alarm2 (Implication (Storm $t) (Alarm a2 $t)) (CTV (STV 0.6 1) (STV 0.25 1))))
!(compileadd on (: front-h1 (Front h1) (STV 1 1)))
!(compileadd on (: storm-h1 (Storm h1) (STV 1 1)))
!(compileadd on (: next-h2 (NextPeriod h1 h2) (STV 1 1)))
!(compileadd on (: front-h2 (Front h2) (STV 1 1)))
!(compileadd on (: storm-h2 (Storm h2) (STV 1 1)))
!(compileadd on (: next-h3 (NextPeriod h2 h3) (STV 1 1)))
!(compileadd on (: front-h3 (Front h3) (STV 1 1)))
!(compileadd on (: storm-h3 (Storm h3) (STV 0 1)))
!(compileadd on (: next-t1 (NextPeriod h3 t1) (STV 1 1)))
!(compileadd on (: a1-t1 (Alarm a1 t1) (STV 0 1)))
!(compileadd on (: a2-t1 (Alarm a2 t1) (STV 0 1)))
!(test
   (query 4 on (: $p (Front t1) $tv))
   (: (factored-revision (by persist (conjunction next-t1 front-h3)) (prior (STV 0.8999983999807107 0.9999000083937291)) (((inverted storm with cpu (prior (STV 0.96875 0.375))) (factored-revision cpu (prior (STV 0.65625 0.375)) (((inverted alarm1 with cpu (prior (STV 0.65625 0.375))) a1-t1) ((inverted alarm2 with cpu (prior (STV 0.65625 0.375))) a2-t1)))))) (Front t1) (STV 0.8232776643714399 0.9998383665600461)))
