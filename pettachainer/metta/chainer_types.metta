;; Shared PeTTaChainer wire and domain types.
;;
;; Function signatures stay beside their implementations. This file contains
;; only representations shared across compiler/runtime module boundaries.

;; Executable goals are either CPU computations or fact goals. Fact KB,
;; proof, and statement fields remain parametric because they contain
;; user-defined atoms and open proof/source syntax.
(: Goal Type)
(: CPU (-> $formula $arguments $result Goal))
(: : (-> $kb $proof $statement TV Goal))

;; Public source statements and query answers omit the runtime KB/context.
(: AnnotatedStatement Type)
(: : (-> $proof $statement TV AnnotatedStatement))

(: AggregateTVMode Type)
(: result-tv AggregateTVMode)
(: unit-stv AggregateTVMode)

(: NilType Type)
(: Nil NilType)

(: NoCurrentScore Type)
(: no-current NoCurrentScore)

(: NoProjectionKey Type)
(: no-projection-key NoProjectionKey)

(: ProofRef Type)
(: proof-ref (-> Number ProofRef))

(: Evidence Type)
(: fact-ev (-> $kb $proof $type Evidence))
(: not-fact-ev (-> $kb $proof $type Evidence))
(: rule-ev (-> $kb $rule Evidence))
(: not-ev (-> Evidence Evidence))

(: BaseRateSource Type)
(: user BaseRateSource)
(: computed BaseRateSource)
(: forward-approx BaseRateSource)

(: BaseRateEntry Type)
(: base-rate
   (-> $kb $pattern TV BaseRateSource $mode BaseRateEntry))

(: UniverseSizeEntry Type)
(: universe-size (-> $kb Number UniverseSizeEntry))

(: UniverseSizeUnavailable Type)
(: no-universe-size UniverseSizeUnavailable)

(: IdentityFinish Type)
(: identity IdentityFinish)
(: DistAverageFinish Type)
(: dist-average DistAverageFinish)
(: BaseRateFinish Type)
(: base-rate BaseRateFinish)
(: WeightedBaseRateFinish Type)
(: weighted-base-rate WeightedBaseRateFinish)
(: WeightedBaseRateWithPriorFinish Type)
(: weighted-base-rate-with-prior WeightedBaseRateWithPriorFinish)
(: MemberInheritanceFinish Type)
(: member-inheritance (-> $kb MemberInheritanceFinish))
(: WeightedBaseRateInUniverseFinish Type)
(: weighted-base-rate-in-universe
   (-> $kb WeightedBaseRateInUniverseFinish))
(: WeightedBaseRateWithPriorInUniverseFinish Type)
(: weighted-base-rate-with-prior-in-universe
   (-> $kb WeightedBaseRateWithPriorInUniverseFinish))
(: UniformPriorFinish Type)
(: uniform-prior UniformPriorFinish)
(: UniformPriorKnownFinish Type)
(: uniform-prior-known UniformPriorKnownFinish)

(: ConceptPriorConfidence Type)
(: concept-prior-confidence
   (-> $kb Number ConceptPriorConfidence))
