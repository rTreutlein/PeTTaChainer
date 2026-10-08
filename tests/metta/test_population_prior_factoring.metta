!(import! &self ../../pettachainer/metta/petta_chainer)

;; Plain implications are inverted with the antecedent's base rate as the
;; prior, so inversions of several observations of one hidden cause combine by
;; Bayes' rule, as WithPrior inversions do (docs/metta/prior_factored_merge.md).
;; P(Storm) = 0.3; a storm blocks each route with 0.8, a clear day with 0.03,
;; so P(Blocked) = 0.3 * 0.8 + 0.7 * 0.03 = 0.261.

!(compileadd oneKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(set-base-rate oneKb (Storm $reg) (STV 0.3 0.9))
!(set-base-rate oneKb (Blocked r1 $reg) (STV 0.261 0.9))
!(compileadd oneKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(test (case (query 100 oneKb (: $p (Storm north) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.9195386653934782 0.1308746894638477))

;; One route blocked and the other open: Bayes' rule gives 0.702, where
;; revising the two inversions gave 0.085, dominated by the open route's more
;; confident view.
!(compileadd mixedKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd mixedKb (: block2 (Implication (Storm $reg) (Blocked r2 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(set-base-rate mixedKb (Storm $reg) (STV 0.3 0.9))
!(set-base-rate mixedKb (Blocked r1 $reg) (STV 0.261 0.9))
!(set-base-rate mixedKb (Blocked r2 $reg) (STV 0.261 0.9))
!(compileadd mixedKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(compileadd mixedKb (: o2 (Blocked r2 north) (STV 0.0 1.0)))
!(test (query 100 mixedKb (: $p (Storm north) $tv)) (: (factored-revision cpu (prior (STV 0.3 0.9)) (((inverted block1 with cpu (prior (STV 0.3 0.9))) o1) ((inverted block2 with cpu (prior (STV 0.3 0.9))) o2))) (Storm north) (STV 0.7020594342858494 0.049840890458653433)))

;; Both routes blocked: Bayes' rule gives 0.9967.
!(compileadd bothKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd bothKb (: block2 (Implication (Storm $reg) (Blocked r2 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(set-base-rate bothKb (Storm $reg) (STV 0.3 0.9))
!(set-base-rate bothKb (Blocked r1 $reg) (STV 0.261 0.9))
!(set-base-rate bothKb (Blocked r2 $reg) (STV 0.261 0.9))
!(compileadd bothKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(compileadd bothKb (: o2 (Blocked r2 north) (STV 1.0 1.0)))
!(test (case (query 100 bothKb (: $p (Storm north) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.9967293435245479 0.6332776196133625))

;; Gusts are as likely with a storm as without: observing one leaves the
;; blocked route's posterior as it is.
!(compileadd gustKb (: block1 (Implication (Storm $reg) (Blocked r1 $reg)) (CTV (STV 0.8 0.99) (STV 0.03 0.99))))
!(compileadd gustKb (: gust (Implication (Storm $reg) (Gust $reg)) (CTV (STV 0.4 0.99) (STV 0.4 0.99))))
!(set-base-rate gustKb (Storm $reg) (STV 0.3 0.9))
!(set-base-rate gustKb (Blocked r1 $reg) (STV 0.261 0.9))
!(set-base-rate gustKb (Gust $reg) (STV 0.4 0.9))
!(compileadd gustKb (: o1 (Blocked r1 north) (STV 1.0 1.0)))
!(compileadd gustKb (: g1 (Gust north) (STV 1.0 1.0)))
!(test (case (query 100 gustKb (: $p (Storm north) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.9195386653934781 0.1303984052547716))
