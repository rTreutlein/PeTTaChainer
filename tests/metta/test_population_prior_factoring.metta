!(import! &self ../../pettachainer/metta/petta_chainer)

;; Plain implications are inverted with the antecedent's base rate as the
;; prior, so inversions of several observations of one hidden cause combine by
;; Bayes' rule, as WithPrior inversions do (docs/metta/prior_factored_merge.md).
;; P(Storm) = 0.3; a storm blocks each route with 0.8, a clear day with 0.03,
;; so P(Blocked) = 0.3 * 0.8 + 0.7 * 0.03 = 0.261. The rules state both
;; branches, so an inversion reads only its antecedent's base rate.

!(compileadd oneKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(set-base-rate oneKb (Storm $reg) (STV 0.3 0.9))
!(compileadd oneKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(test (case (query 100 oneKb (: $p (Storm north) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.9195391900632319 0.9402956587726978))

;; One route blocked and the other open: Bayes' rule gives 0.702, where
;; revising the two inversions gave 0.085, dominated by the open route's more
;; confident view.
!(compileadd mixedKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd mixedKb (: block2 (Implication (Storm $reg) (Blocked r2 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(set-base-rate mixedKb (Storm $reg) (STV 0.3 0.9))
!(compileadd mixedKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(compileadd mixedKb (: o2 (Blocked r2 north) (STV 0.0 1.0)))
!(test (query 100 mixedKb (: $p (Storm north) $tv)) (: (factored-revision cpu (prior (STV 0.30000555540123885 0.9)) (((inverted block1 with cpu (prior (STV 0.30000555540123885 0.9))) o1) ((inverted block2 with cpu (prior (STV 0.30000555540123885 0.9))) o2))) (Storm north) (STV 0.7020604165390665 0.8417105305268205)))

;; Both routes blocked: Bayes' rule gives 0.9967.
!(compileadd bothKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd bothKb (: block2 (Implication (Storm $reg) (Blocked r2 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(set-base-rate bothKb (Storm $reg) (STV 0.3 0.9))
!(compileadd bothKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(compileadd bothKb (: o2 (Blocked r2 north) (STV 1.0 1.0)))
!(test (case (query 100 bothKb (: $p (Storm north) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.9967293035199962 0.9961445162987431))

;; Gusts are as likely with a storm as without: observing one leaves the
;; blocked route's posterior as it is.
!(compileadd gustKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd gustKb (: gust (Implication (Storm $reg) (Gust $reg)) (CTV (STV 0.4 0.99) (STV 0.4 0.99))))
!(set-base-rate gustKb (Storm $reg) (STV 0.3 0.9))
!(compileadd gustKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(compileadd gustKb (: g1 (Gust north) (STV 1.0 1.0)))
!(test (case (query 100 gustKb (: $p (Storm north) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.9195391900632319 0.938317236276462))

;; Two levels: a blocked route delays its shipment with 0.9, an open one with
;; 0.05. Route r1 is
;; inspected blocked and r2's shipment is late. The forward view of r2 through
;; the storm r1 suggests is r2's prior given the other route; the shipment's
;; inversion updates r2's population base rate, and its likelihood ratio moves
;; the forward view instead (docs/metta/prior_factored_merge.md). By
;; enumeration P(Blocked r2 | r1 blocked, s2 late) = 0.980663 and
;; P(Storm | r1 blocked, s2 late) = 0.991032; revising the two views of r2 gave
;; 0.773.
!(compileadd routeKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd routeKb (: block2 (Implication (Storm $reg) (Blocked r2 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd routeKb (: late2 (Implication (Blocked r2 $reg) (Late s2 $reg)) (CTV (STV 0.9 0.99) (STV 0.05 0.99))))
!(set-base-rate routeKb (Storm $reg) (STV 0.3 0.9))
!(set-base-rate routeKb (Blocked r2 $reg) (STV 0.261 0.9))
!(compileadd routeKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(compileadd routeKb (: l2 (Late s2 north) (STV 1.0 1.0)))
!(test (query 100 routeKb (: $p (Blocked r2 north) $tv)) (: (factored-revision (by block2 ((inverted block1 with cpu (prior (STV 0.30000555540123885 0.9))) o1)) (prior (STV 0.7380438977920759 0.9789674868287385)) (((inverted late2 with cpu (prior (STV 0.26100663870448043 0.9))) l2))) (Blocked r2 north) (STV 0.9806623506588911 0.9942651005541906)))
!(test (case (query 100 routeKb (: $p (Storm north) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.9910311737109543 0.9924302864284203))

;; When the storm is also read off the late shipment, the forward view of r2
;; already holds that observation: it is not an independent prior for the
;; shipment's inversion. Both views observed l2, so they revise rather than
;; multiply its likelihood twice; no view is selected.
!(compileadd sharedKb (: block2 (Implication (Storm $reg) (Blocked r2 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd sharedKb (: late2 (Implication (Blocked r2 $reg) (Late s2 $reg)) (CTV (STV 0.9 0.99) (STV 0.05 0.99))))
!(compileadd sharedKb (: lateS (Implication (Storm $reg) (Late s2 $reg)) (CTV (STV 0.73 0.99) (STV 0.0755 0.99))))
!(set-base-rate sharedKb (Storm $reg) (STV 0.3 0.9))
!(set-base-rate sharedKb (Blocked r2 $reg) (STV 0.261 0.9))
!(compileadd sharedKb (: l2 (Late s2 north) (STV 1.0 1.0)))
!(test (query 100 sharedKb (: $p (Blocked r2 north) $tv)) (: (merge/revision (by block2 ((inverted lateS with cpu (prior (STV 0.30000555540123885 0.9))) l2)) ((inverted late2 with cpu (prior (STV 0.26100663870448043 0.9))) l2)) (Blocked r2 north) (STV 0.7231034858822245 0.9701587228190831)))
