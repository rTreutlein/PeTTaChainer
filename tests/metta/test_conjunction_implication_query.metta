!(import! &self ../../pettachainer/metta/petta_chainer)

;; The implication query always supplies its positive STV. Certain report
;; metadata and a certain gated rule therefore give strength 1. Confidence
;; 0.9995002493256119 propagates through nested MP and ordinary STV And;
;; unsupported negative rule storage does not participate in this query.
!(compileadd compoundKb (: metadata (SourceDocument Report Study) (STV 1 1)))
!(compileadd compoundKb (: rule (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x))) (STV 1 1)))
!(compileadd groundCompoundKb (: metadata (SourceDocument Report Study) (STV 1 1)))
!(compileadd groundCompoundKb (: rule (Implication (AcceptSource Report) (Implication (And (Member Supplier1 Supplier) (ExposedTo Supplier1 ClimateRisk)) (ChargesLowerPrices Supplier1))) (STV 1 1)))

;; Cold general query: full positive provenance.
!(test (collapse (let (: (conjunction metadata (conditional-implication (by (by rule (ctx proof $ctx)) (conjunction (ctx proof $ctx 1) (ctx proof $ctx 2))))) (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $result-tv)
   (query 300 compoundKb (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $tv)) $result-tv))
   ((STV 1.0 0.9995002493256119)))

;; Reversed order.
!(test (collapse (let (: (conjunction (conditional-implication (by (by rule (ctx proof $ctx)) (conjunction (ctx proof $ctx 1) (ctx proof $ctx 2)))) metadata) (And (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x))) (SourceDocument Report Study)) $result-tv)
   (query 300 compoundKb (: $p (And (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x))) (SourceDocument Report Study)) $tv)) $result-tv))
   ((STV 1.0 0.9995002493256119)))

;; An open scaffold cannot replace this bound instance.
!(test (collapse (let (: (conjunction metadata (conditional-implication (by (by rule (ctx proof $ctx)) (conjunction (ctx proof $ctx 1) (ctx proof $ctx 2))))) (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member Supplier1 Supplier) (ExposedTo Supplier1 ClimateRisk)) (ChargesLowerPrices Supplier1)))) $result-tv)
   (query 300 compoundKb (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member Supplier1 Supplier) (ExposedTo Supplier1 ClimateRisk)) (ChargesLowerPrices Supplier1)))) $tv)) $result-tv))
   ((STV 1.0 0.9995002493256119)))

;; Back to general after a bound query.
!(test (collapse (let (: (conjunction metadata (conditional-implication (by (by rule (ctx proof $ctx)) (conjunction (ctx proof $ctx 1) (ctx proof $ctx 2))))) (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $result-tv)
   (query 300 compoundKb (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $tv)) $result-tv))
   ((STV 1.0 0.9995002493256119)))

;; Warm query has the same value and proof shape.
!(test (collapse (let (: (conjunction metadata (conditional-implication (by (by rule (ctx proof $ctx)) (conjunction (ctx proof $ctx 1) (ctx proof $ctx 2))))) (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $result-tv)
   (query 300 compoundKb (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $tv)) $result-tv))
   ((STV 1.0 0.9995002493256119)))

;; Assertion and query both use a constant.
!(test (collapse (let (: (conjunction metadata (conditional-implication (by (by rule (ctx proof $ctx)) (conjunction (ctx proof $ctx 1) (ctx proof $ctx 2))))) (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member Supplier1 Supplier) (ExposedTo Supplier1 ClimateRisk)) (ChargesLowerPrices Supplier1)))) $result-tv)
   (query 300 groundCompoundKb (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member Supplier1 Supplier) (ExposedTo Supplier1 ClimateRisk)) (ChargesLowerPrices Supplier1)))) $tv)) $result-tv))
   ((STV 1.0 0.9995002493256119)))

;; Missing either assertion is unknown.
!(compileadd metadataOnlyKb (: metadata (SourceDocument Report Study) (STV 1 1)))
!(compileadd ruleOnlyKb (: rule (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x))) (STV 1 1)))
!(test (collapse (query 300 metadataOnlyKb (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $tv))) ())
!(test (collapse (query 300 ruleOnlyKb (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $tv))) ())

;; The source gate is never accepted outside the query.
!(test (collapse (query 300 compoundKb (: $p (AcceptSource Report) $tv))) ())
!(test (collapse (query 300 compoundKb (: $p (ChargesLowerPrices Supplier1) $tv))) ())
!(test (collapse (query 300 compoundKb (: $p (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)) $tv))) ())

;; A ground rule must not answer as a general rule.
!(test (collapse (let (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $tv)
   (query 300 groundCompoundKb (: $q (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $value))
   (if (is-var $x) $tv (empty)))) ())

;; Unrelated instance facts cannot accept the source gate.
!(compileadd instanceOnlyKb (: metadata (SourceDocument Report Study) (STV 1 1)))
!(compileadd instanceOnlyKb (: member (Member Supplier1 Supplier) (STV 1 1)))
!(compileadd instanceOnlyKb (: exposed (ExposedTo Supplier1 ClimateRisk) (STV 1 1)))
!(compileadd instanceOnlyKb (: price (ChargesLowerPrices Supplier1) (STV 1 1)))
!(test (collapse (query 300 instanceOnlyKb (: $p (And (SourceDocument Report Study) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $tv))) ())

;; All conjuncts remain in the answer, in the caller's order.
!(compileadd compoundKb (: tag (Reviewed Report) (STV 1 1)))
!(test (collapse (let (: (conjunction metadata tag (conditional-implication (by (by rule (ctx proof $ctx)) (conjunction (ctx proof $ctx 1) (ctx proof $ctx 2))))) (And (SourceDocument Report Study) (Reviewed Report) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $result-tv)
   (query 300 compoundKb (: $p (And (SourceDocument Report Study) (Reviewed Report) (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x)))) $tv)) $result-tv))
   ((STV 1.0 0.9994003591099384)))

;; Old CTV answer selectors and nested annotated conjuncts are unsupported.
!(test (collapse (query 300 compoundKb (: $p (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x))) (CTV $pos $neg)))) ())
!(test (collapse (query 300 compoundKb (: $p (And (SourceDocument Report Study) (: $q (Implication (AcceptSource Report) (Implication (And (Member $x Supplier) (ExposedTo $x ClimateRisk)) (ChargesLowerPrices $x))) (STV $s $c))) $tv))) ())

;; Proof comparison must not bind an open proof head.
!(test (let $same (same-proof? (brand Proof (quote ($head $payload))) (brand Proof (proof-ref 1))) ($same (is-var $head) (is-var $payload))) (false true true))
