!(import! &self ../../pettachainer/metta/petta_chainer)

;; A ground statement stored with confidence 1 is its value: expansion applies
;; no rule to it, and the views its rows got before it was stored add nothing
;; to it, neither evidence nor dependencies. A rule stated with confidence 1 is
;; given, not estimated: proofs that both use it share no uncertain evidence.

;; Two sources raise one alarm through the same rule. Given the rule's truth,
;; the two proofs are independent, so they revise whether that truth is
;; stated with confidence 1 or is an estimate (0.99): sharing a rule is not
;; sharing evidence of the alarm. The estimate's uncertainty lowers each
;; proof's confidence, and so the revision's.
!(compileadd givenKb (: alarm (Implication (And (Source $s) (Signal $s)) (Alarm)) (STV 0.9 1)))
!(compileadd givenKb (: src1 (Source s1) (STV 1 1)))
!(compileadd givenKb (: src2 (Source s2) (STV 1 1)))
!(compileadd givenKb (: sig1 (Signal s1) (STV 0.9 0.5)))
!(compileadd givenKb (: sig2 (Signal s2) (STV 0.6 0.4)))
!(test (query 100 givenKb (: $p (Alarm) $tv)) (: (merge/revision (by alarm (conjunction src1 sig1)) (by alarm (conjunction src2 sig2))) (Alarm) (STV 0.8509227749064925 0.058908118539918355)))
!(compileadd estimatedKb (: alarm (Implication (And (Source $s) (Signal $s)) (Alarm)) (STV 0.9 0.99)))
!(compileadd estimatedKb (: src1 (Source s1) (STV 1 1)))
!(compileadd estimatedKb (: src2 (Source s2) (STV 1 1)))
!(compileadd estimatedKb (: sig1 (Signal s1) (STV 0.9 0.5)))
!(compileadd estimatedKb (: sig2 (Signal s2) (STV 0.6 0.4)))
!(test (query 100 estimatedKb (: $p (Alarm) $tv)) (: (merge/revision (by alarm (conjunction src1 sig1)) (by alarm (conjunction src2 sig2))) (Alarm) (STV 0.850919813437148 0.05888933033515643)))

;; Two sources report one storm through the same rule, which states both
;; likelihoods with confidence 1. Given the storm the reports are independent,
;; so their inversions over the storm's base rate combine by Bayes' rule:
;; odds 0.3/0.7 * (0.8/0.1)^2 = 27.43, P(Storm) = 0.9648.
!(compileadd reportKb (: report (Implication (Storm $r) (Report $r $source)) (CTV (STV 0.8 1) (STV 0.1 1))))
!(set-base-rate reportKb (Storm $r) (STV 0.3 0.9))
!(compileadd reportKb (: ra (Report north a) (STV 1 1)))
!(compileadd reportKb (: rb (Report north b) (STV 1 1)))
!(test (query 100 reportKb (: $p (Storm north) $tv)) (: (factored-revision cpu (prior (STV 0.30000555540123885 0.9)) (((inverted report with cpu (prior (STV 0.30000555540123885 0.9))) ra) ((inverted report with cpu (prior (STV 0.30000555540123885 0.9))) rb))) (Storm north) (STV 0.9648250184071773 0.9823019027284696)))

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
;; evidence, and the window's own evidence was dropped: 0.3 for w1. The block
;; inversion reads the route's soft value as a likelihood ratio over the base
;; rate it was formed under, so the views are exact: while h3 is open, s2 late
;; alone gives P(L | storm) = 0.8 * 0.009 + 0.2 * 0.045125 = 0.016225 and
;; P(L | no storm) = 0.03 * 0.009 + 0.97 * 0.045125 = 0.04404, so 0.13636 for
;; h3 over the persistence prediction 0.3. Read as a posterior under the
;; prior the block rule implies for the route, it gave 0.1500 for h3, 0.91920
;; for w1 and 0.29405 for w2.
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
!(test (case (query 100 k (: $p (Storm north h3) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.13635883235598123 0.9999439250602885))
!(compileadd k (: storm-h3 (Storm north h3) (STV 0 1)))
!(compileadd k (: blocked-h3 (Blocked r1 h3) (STV 0 1)))
!(compileadd k (: next-w1 (NextPeriod h3 w1) (STV 1 1)))
!(compileadd k (: late-s1-w1 (Late s1 w1) (STV 1 1)))
!(compileadd k (: late-s2-w1 (Late s2 w1) (STV 1 1)))
!(compileadd k (: late-s3-w1 (Late s3 w1) (STV 1 1)))
!(test (query 100 k (: $p (Storm north h3) $tv)) (: storm-h3 (Storm north h3) (STV 0 1)))
!(test (query 100 k (: $p (Storm north w1) $tv)) (: (factored-revision (by persist-north (conjunction next-w1 storm-h3)) (prior (STV 0.3000007999974096 0.9999000099228195)) (((inverted block-r1 with cpu (prior (STV 0.3333341269242677 0.44443827214888376))) (factored-revision cpu (prior (STV 0.32404881104953287 0.4444395428411525)) (((inverted late-s1 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s1-w1) ((inverted late-s2 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s2-w1) ((inverted late-s3 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s3-w1)))))) (Storm north w1) (STV 0.9191336945362226 0.9999646079530727)))
!(compileadd k (: next-w2 (NextPeriod w1 w2) (STV 1 1)))
!(compileadd k (: late-s1-w2 (Late s1 w2) (STV 0 1)))
!(compileadd k (: late-s2-w2 (Late s2 w2) (STV 0 1)))
!(compileadd k (: late-s3-w2 (Late s3 w2) (STV 0 1)))
!(test (case (query 100 k (: $p (Storm north w2) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.29384723150275627 0.9999228861408821))

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
;; base rate 0.325, as the likelihood ratio odds(0.0908) / odds(0.325) =
;; 0.2071 = P(none late | storm w2) / P(none late | no storm w2), and its
;; message to Storm w1 is (0.7 * 0.2071 + 0.3) / (0.3 * 0.2071 + 0.7) = 0.5839:
;; the filter view 0.91913 and the completion factor to 0.86905. Read as a
;; posterior under the prior the rule implies for Storm w2 (0.43), the
;; completion's ratio was 0.531 and Storm w1 0.8579. Revising the two views
;; gave 0.7445.
!(test (query 100 k (: $p (Storm north w1) $tv)) (: (factored-revision (by persist-north (conjunction next-w1 storm-h3)) (prior (STV 0.3000007999974096 0.9999000099228195)) (((inverted block-r1 with cpu (prior (STV 0.3333341269242677 0.44443827214888376))) (factored-revision cpu (prior (STV 0.32404881104953287 0.4444395428411525)) (((inverted late-s1 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s1-w1) ((inverted late-s2 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s2-w1) ((inverted late-s3 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s3-w1)))) ((antecedent-completion persist-north 1 with cpu (prior (STV 0.3333341269242677 0.44443827214888376))) (conjunction next-w2 ((inverted block-r1 with cpu (prior (STV 0.3333341269242677 0.44443827214888376))) (factored-revision cpu (prior (STV 0.32404881104953287 0.4444395428411525)) (((inverted late-s1 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s1-w2) ((inverted late-s2 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s2-w2) ((inverted late-s3 with cpu (prior (STV 0.32404881104953287 0.4444395428411525))) late-s3-w2)))))))) (Storm north w1) (STV 0.8690484291015605 0.9999458114471936)))

;; A system w is up when both its parts are; each source has a trust rule
;; estimated at confidence 0.9 (ChainerGame's conflicting sources, in small).
;; s says c1 is up, r says c2 is up, and w's own claim says it is down. The
;; forward view through the system rule reads s's claim about c1 through
;; trust-s. When s also makes w's claim, its view of w shares trust-s with the
;; forward view but nothing else: given the rule the two are independent and
;; revise, exactly as when another source, q, with the same trust makes it.
;; Treated as overlapping evidence, s's claim was dropped (0.748).
!(compileadd sharedTrustKb (: sys (Implication (And (Up c1 $t) (Up c2 $t)) (Up w $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd sharedTrustKb (: trust-s (Implication (Claims s (Up $n $t)) (Up $n $t)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd sharedTrustKb (: trust-r (Implication (Claims r (Up $n $t)) (Up $n $t)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd sharedTrustKb (: trust-q (Implication (Claims q (Up $n $t)) (Up $n $t)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd sharedTrustKb (: l1-0 (Up c1 h0) (STV 1 1)))
!(compileadd sharedTrustKb (: l2-0 (Up c2 h0) (STV 1 1)))
!(compileadd sharedTrustKb (: lw-0 (Up w h0) (STV 1 1)))
!(compileadd sharedTrustKb (: l1-1 (Up c1 h1) (STV 1 1)))
!(compileadd sharedTrustKb (: l2-1 (Up c2 h1) (STV 1 1)))
!(compileadd sharedTrustKb (: lw-1 (Up w h1) (STV 1 1)))
!(compileadd sharedTrustKb (: l1-2 (Up c1 h2) (STV 1 1)))
!(compileadd sharedTrustKb (: l2-2 (Up c2 h2) (STV 0 1)))
!(compileadd sharedTrustKb (: lw-2 (Up w h2) (STV 0 1)))
!(compileadd sharedTrustKb (: l1-3 (Up c1 h3) (STV 0 1)))
!(compileadd sharedTrustKb (: l2-3 (Up c2 h3) (STV 1 1)))
!(compileadd sharedTrustKb (: lw-3 (Up w h3) (STV 0 1)))
!(compileadd sharedTrustKb (: l1-4 (Up c1 h4) (STV 1 1)))
!(compileadd sharedTrustKb (: l2-4 (Up c2 h4) (STV 1 1)))
!(compileadd sharedTrustKb (: lw-4 (Up w h4) (STV 0 1)))
!(compileadd sharedTrustKb (: l1-5 (Up c1 h5) (STV 0 1)))
!(compileadd sharedTrustKb (: l2-5 (Up c2 h5) (STV 0 1)))
!(compileadd sharedTrustKb (: lw-5 (Up w h5) (STV 0 1)))
!(compileadd sharedTrustKb (: l1-6 (Up c1 h6) (STV 1 1)))
!(compileadd sharedTrustKb (: l2-6 (Up c2 h6) (STV 1 1)))
!(compileadd sharedTrustKb (: lw-6 (Up w h6) (STV 1 1)))
!(compileadd sharedTrustKb (: l1-7 (Up c1 h7) (STV 1 1)))
!(compileadd sharedTrustKb (: l2-7 (Up c2 h7) (STV 0 1)))
!(compileadd sharedTrustKb (: lw-7 (Up w h7) (STV 1 1)))
!(compileadd sharedTrustKb (: k1 (Claims s (Up c1 n)) (STV 1 1)))
!(compileadd sharedTrustKb (: k2 (Claims r (Up c2 n)) (STV 1 1)))
!(compileadd sharedTrustKb (: kw (Claims s (Up w n)) (STV 0 1)))
!(test (query 200 sharedTrustKb (: $p (Up w n) $tv)) (: (merge/revision (by sys (conjunction (by trust-s k1) (by trust-r k2))) (by trust-s kw)) (Up w n) (STV 0.5676753183674934 0.9647274589607039)))
!(compileadd otherTrustKb (: sys (Implication (And (Up c1 $t) (Up c2 $t)) (Up w $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd otherTrustKb (: trust-s (Implication (Claims s (Up $n $t)) (Up $n $t)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd otherTrustKb (: trust-r (Implication (Claims r (Up $n $t)) (Up $n $t)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd otherTrustKb (: trust-q (Implication (Claims q (Up $n $t)) (Up $n $t)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd otherTrustKb (: l1-0 (Up c1 h0) (STV 1 1)))
!(compileadd otherTrustKb (: l2-0 (Up c2 h0) (STV 1 1)))
!(compileadd otherTrustKb (: lw-0 (Up w h0) (STV 1 1)))
!(compileadd otherTrustKb (: l1-1 (Up c1 h1) (STV 1 1)))
!(compileadd otherTrustKb (: l2-1 (Up c2 h1) (STV 1 1)))
!(compileadd otherTrustKb (: lw-1 (Up w h1) (STV 1 1)))
!(compileadd otherTrustKb (: l1-2 (Up c1 h2) (STV 1 1)))
!(compileadd otherTrustKb (: l2-2 (Up c2 h2) (STV 0 1)))
!(compileadd otherTrustKb (: lw-2 (Up w h2) (STV 0 1)))
!(compileadd otherTrustKb (: l1-3 (Up c1 h3) (STV 0 1)))
!(compileadd otherTrustKb (: l2-3 (Up c2 h3) (STV 1 1)))
!(compileadd otherTrustKb (: lw-3 (Up w h3) (STV 0 1)))
!(compileadd otherTrustKb (: l1-4 (Up c1 h4) (STV 1 1)))
!(compileadd otherTrustKb (: l2-4 (Up c2 h4) (STV 1 1)))
!(compileadd otherTrustKb (: lw-4 (Up w h4) (STV 0 1)))
!(compileadd otherTrustKb (: l1-5 (Up c1 h5) (STV 0 1)))
!(compileadd otherTrustKb (: l2-5 (Up c2 h5) (STV 0 1)))
!(compileadd otherTrustKb (: lw-5 (Up w h5) (STV 0 1)))
!(compileadd otherTrustKb (: l1-6 (Up c1 h6) (STV 1 1)))
!(compileadd otherTrustKb (: l2-6 (Up c2 h6) (STV 1 1)))
!(compileadd otherTrustKb (: lw-6 (Up w h6) (STV 1 1)))
!(compileadd otherTrustKb (: l1-7 (Up c1 h7) (STV 1 1)))
!(compileadd otherTrustKb (: l2-7 (Up c2 h7) (STV 0 1)))
!(compileadd otherTrustKb (: lw-7 (Up w h7) (STV 1 1)))
!(compileadd otherTrustKb (: k1 (Claims s (Up c1 n)) (STV 1 1)))
!(compileadd otherTrustKb (: k2 (Claims r (Up c2 n)) (STV 1 1)))
!(compileadd otherTrustKb (: kw (Claims q (Up w n)) (STV 0 1)))
!(test (query 200 otherTrustKb (: $p (Up w n) $tv)) (: (merge/revision (by sys (conjunction (by trust-s k1) (by trust-r k2))) (by trust-q kw)) (Up w n) (STV 0.5676753183674934 0.9647274589607039)))
