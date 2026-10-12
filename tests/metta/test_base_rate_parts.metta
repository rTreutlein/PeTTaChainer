!(import! &self ../../pettachainer/metta/petta_chainer)

;; An STV rule's antecedent whose conjuncts fall into parts sharing no
;; variables takes its base rate as the product of the parts' rates
;; (docs/metta/runtime_design_assumptions.md). A part with no counted member
;; has no evidence, and neither has the product: the rule still applies. Here
;; the part (And (AcceptSource R) (Member $f Firm)) counts no member; without
;; the ground conjunct, or with other predicates than Member, both parts count
;; theirs.
!(compileadd partsKb (: r (Implication (And (AcceptSource R) (Member $an EA) (Member $f Firm)) (P $an)) (STV 1.0 1.0)))
!(compileadd partsKb (: f1 (AcceptSource R) (STV 1.0 1.0)))
!(compileadd partsKb (: f2 (Member a EA) (STV 1.0 1.0)))
!(compileadd partsKb (: f3 (Member g Firm) (STV 1.0 1.0)))
!(test (query 100 partsKb (: $p (P a) $tv))
   (: (by r (conjunction f1 f2 f3)) (P a) (STV 1.0 0.9996001594863853)))
