!(import! &self ../../pettachainer/metta/petta_chainer)

;; A ground statement stored with confidence 1 is its value: expansion applies
;; no rule to it, and the views its rows got before it was stored add nothing
;; to it, neither evidence nor dependencies. A rule stated with confidence 1 is
;; given, not estimated: proofs that both use it share no uncertain evidence.

;; Two sources raise one alarm through the same rule. Stated with confidence
;; 1, the rule is not shared evidence: the two proofs are independent and
;; revise. Stated with confidence 0.99, its truth is an estimate both proofs
;; read, and the more confident proof is kept.
!(compileadd givenKb (: alarm (Implication (And (Source $s) (Signal $s)) (Alarm)) (STV 0.9 1)))
!(compileadd givenKb (: src1 (Source s1) (STV 1 1)))
!(compileadd givenKb (: src2 (Source s2) (STV 1 1)))
!(compileadd givenKb (: sig1 (Signal s1) (STV 0.9 0.5)))
!(compileadd givenKb (: sig2 (Signal s2) (STV 0.6 0.4)))
!(test (query 100 givenKb (: $p (Alarm) $tv)) (: (merge/revision (by alarm (conjunction src1 sig1)) (by alarm (conjunction src2 sig2))) (Alarm) (STV 0.7324021821071247 0.7477210962591324)))
!(compileadd estimatedKb (: alarm (Implication (And (Source $s) (Signal $s)) (Alarm)) (STV 0.9 0.99)))
!(compileadd estimatedKb (: src1 (Source s1) (STV 1 1)))
!(compileadd estimatedKb (: src2 (Source s2) (STV 1 1)))
!(compileadd estimatedKb (: sig1 (Signal s1) (STV 0.9 0.5)))
!(compileadd estimatedKb (: sig2 (Signal s2) (STV 0.6 0.4)))
!(test (query 100 estimatedKb (: $p (Alarm) $tv)) (: (by alarm (conjunction src1 sig1)) (Alarm) (STV 0.81 0.6764909405625412)))

;; Two sources report one storm through the same rule, which states both
;; likelihoods with confidence 1. Given the storm the reports are independent,
;; so their inversions over the storm's base rate combine by Bayes' rule:
;; odds 0.3/0.7 * (0.8/0.1)^2 = 27.43, P(Storm) = 0.9648.
!(compileadd reportKb (: report (Implication (Storm $r) (Report $r $source)) (CTV (STV 0.8 1) (STV 0.1 1))))
!(set-base-rate reportKb (Storm $r) (STV 0.3 0.9))
!(compileadd reportKb (: ra (Report north a) (STV 1 1)))
!(compileadd reportKb (: rb (Report north b) (STV 1 1)))
!(test (query 100 reportKb (: $p (Storm north) $tv)) (: (factored-revision cpu (prior (STV 0.3 0.9)) (((inverted report with cpu (prior (STV 0.3 0.9))) ra) ((inverted report with cpu (prior (STV 0.3 0.9))) rb))) (Storm north) (STV 0.9648241206030151 0.9823012918395355)))

;; Storms persist (SupplyNet stage 2): a storm continues with 0.7 and starts
;; with 0.3; it blocks route r1 with 0.8 (0.03 without), and a blocked route
;; delays each of its shipments s1, s2, s3 with 0.9 (0.05 when open). Period
;; h3 is asked about while open, then resolved: no storm, so the storm in w1
;; has prior 0.3. All three shipments of w1 are late, none of w2. Exact
;; filtering (Bayes' rule over the stated rates):
;;   P(L | storm) = 0.8 * 0.9^3 + 0.2 * 0.05^3 = 0.583225,
;;   P(L | no storm) = 0.03 * 0.9^3 + 0.97 * 0.05^3 = 0.02199125,
;;   P(Storm w1) = 0.3 * 0.583225 / (0.3 * 0.583225 + 0.7 * 0.02199125) = 0.919133;
;;   prior of w2 = 0.7 * 0.919133 + 0.3 * 0.080867 = 0.667653, and with no
;;   shipment late P(Storm w2) = 0.293848.
;; The persistence prediction takes the base rate's place under the period's
;; block and shipment inversions. Before, the resolved storm of h3 was revised
;; with its rows' inversions, the persistence view carried their block rule as
;; evidence, and the window's own evidence was dropped: 0.3 for w1.
!(set-evidence-confidence-k 5.0)
!(compileadd k (: persist-north (Implication (And (NextPeriod $p $t) (Storm north $p)) (Storm north $t)) (CTV (STV 0.7 1) (STV 0.3 1))))
!(compileadd k (: block-r1 (Implication (Storm north $p) (Blocked r1 $p)) (CTV (STV 0.8 1) (STV 0.03 1))))
!(compileadd k (: late-s1 (Implication (Blocked r1 $p) (Late s1 $p)) (CTV (STV 0.9 1) (STV 0.05 1))))
!(compileadd k (: late-s2 (Implication (Blocked r1 $p) (Late s2 $p)) (CTV (STV 0.9 1) (STV 0.05 1))))
!(compileadd k (: late-s3 (Implication (Blocked r1 $p) (Late s3 $p)) (CTV (STV 0.9 1) (STV 0.05 1))))
!(compileadd k (: storm-h1 (Storm north h1) (STV 1 1)))
!(compileadd k (: blocked-h1 (Blocked r1 h1) (STV 1 1)))
!(compileadd k (: late-s1-h1 (Late s1 h1) (STV 1 1)))
!(compileadd k (: late-s2-h1 (Late s2 h1) (STV 1 1)))
!(compileadd k (: late-s3-h1 (Late s3 h1) (STV 0 1)))
!(compileadd k (: next-h2 (NextPeriod h1 h2) (STV 1 1)))
!(compileadd k (: storm-h2 (Storm north h2) (STV 0 1)))
!(compileadd k (: blocked-h2 (Blocked r1 h2) (STV 0 1)))
!(compileadd k (: late-s1-h2 (Late s1 h2) (STV 0 1)))
!(compileadd k (: late-s2-h2 (Late s2 h2) (STV 0 1)))
!(compileadd k (: late-s3-h2 (Late s3 h2) (STV 0 1)))
!(compileadd k (: next-h3 (NextPeriod h2 h3) (STV 1 1)))
!(compileadd k (: late-s1-h3 (Late s1 h3) (STV 0 1)))
!(compileadd k (: late-s2-h3 (Late s2 h3) (STV 1 1)))
!(compileadd k (: late-s3-h3 (Late s3 h3) (STV 0 1)))
!(test (case (query 100 k (: $p (Storm north h3) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.14997149309284746 0.572822474573108))
!(compileadd k (: storm-h3 (Storm north h3) (STV 0 1)))
!(compileadd k (: blocked-h3 (Blocked r1 h3) (STV 0 1)))
!(compileadd k (: next-w1 (NextPeriod h3 w1) (STV 1 1)))
!(compileadd k (: late-s1-w1 (Late s1 w1) (STV 1 1)))
!(compileadd k (: late-s2-w1 (Late s2 w1) (STV 1 1)))
!(compileadd k (: late-s3-w1 (Late s3 w1) (STV 1 1)))
!(test (query 100 k (: $p (Storm north h3) $tv)) (: storm-h3 (Storm north h3) (STV 0 1)))
!(test (query 100 k (: $p (Storm north w1) $tv)) (: (factored-revision (by persist-north (conjunction next-w1 storm-h3)) (prior (STV 0.3 0.9999000099228118)) (((inverted block-r1 with cpu (prior (STV 0.3250006249536047 0.44443827214888326))) (factored-revision cpu (prior (STV 0.3152510770422629 0.4444395424457702)) (((inverted late-s1 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s1-w1) ((inverted late-s2 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s2-w1) ((inverted late-s3 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s3-w1)))))) (Storm north w1) (STV 0.9191961391612157 0.7335827638932074)))
!(compileadd k (: next-w2 (NextPeriod w1 w2) (STV 1 1)))
!(compileadd k (: late-s1-w2 (Late s1 w2) (STV 0 1)))
!(compileadd k (: late-s2-w2 (Late s2 w2) (STV 0 1)))
!(compileadd k (: late-s3-w2 (Late s3 w2) (STV 0 1)))
!(test (case (query 100 k (: $p (Storm north w2) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.29404545256813475 0.46143541390156206))

;; Smoothing: w2's observations bear on the storm of w1 through the
;; persistence rule's completion, which inverts the rule onto Storm w1 over
;; its base rate, and so merges with the filter view by Bayes' rule (the two
;; share no observation, and the rules are given). Exact:
;;   P(none late | storm w2) = 0.8 * 0.1^3 + 0.2 * 0.95^3 = 0.172275,
;;   P(none late | no storm w2) = 0.03 * 0.1^3 + 0.97 * 0.95^3 = 0.831684,
;;   likelihood ratio for Storm w1 = (0.7 * 0.172275 + 0.3 * 0.831684)
;;     / (0.3 * 0.172275 + 0.7 * 0.831684) = 0.58388,
;;   odds 0.919133/0.080867 * 0.58388 = 6.636, P(Storm w1) = 0.86905.
;; The completion reads Storm w2 from w2's block inversion, 0.0908 over its
;; base rate 0.325, and gives (P(M) = 0.325, u = 0.7, v = 0.3)
;;   0.0908 * 0.52907 + 0.9092 * 0.17105 = 0.20355,
;; a likelihood ratio of odds(0.20355)/odds(0.325) = 0.531, and
;; logit 0.91920 + logit 0.20355 - logit 0.325 = 1.7986, P = 0.8579. The ratio
;; falls short of 0.584 because modus ponens reads 0.0908 as a posterior under
;; the prior the rule implies for Storm w2 (0.43), while it was formed under
;; the base rate 0.325. Revising the two views gave 0.7445.
!(test (query 100 k (: $p (Storm north w1) $tv)) (: (factored-revision (by persist-north (conjunction next-w1 storm-h3)) (prior (STV 0.3 0.9999000099228118)) (((inverted block-r1 with cpu (prior (STV 0.3250006249536047 0.44443827214888326))) (factored-revision cpu (prior (STV 0.3152510770422629 0.4444395424457702)) (((inverted late-s1 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s1-w1) ((inverted late-s2 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s2-w1) ((inverted late-s3 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s3-w1)))) ((antecedent-completion persist-north 1 with cpu (prior (STV 0.3250006249536047 0.44443827214888326))) (conjunction next-w2 ((inverted block-r1 with cpu (prior (STV 0.3250006249536047 0.44443827214888326))) (factored-revision cpu (prior (STV 0.3152510770422629 0.4444395424457702)) (((inverted late-s1 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s1-w2) ((inverted late-s2 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s2-w2) ((inverted late-s3 with cpu (prior (STV 0.3152510770422629 0.4444395424457702))) late-s3-w2)))))))) (Storm north w1) (STV 0.85791551316166 0.6153326167632389)))
