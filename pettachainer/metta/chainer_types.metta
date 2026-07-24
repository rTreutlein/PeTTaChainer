;; Shared PeTTaChainer wire and domain types.
;;
;; Function signatures stay beside their implementations. This file contains
;; only representations shared across compiler/runtime module boundaries.

;; These semantic roles share PeTTaChainer's existing open MeTTa wire
;; representation. Newtype brands distinguish them statically and are erased
;; completely by the compiler.
;; KB names identify a knowledge base. KBContext is the full runtime
;; (name context variables) tuple carried by compiled facts and goals.
(: KB (Newtype Expression))
(: KBContext (Newtype Expression))
(: Proof (Newtype Expression))
(: Statement (Newtype Expression))
(: Term (Newtype Expression))
(: Variable (Newtype Expression))
(: CompiledAddition (Newtype Expression))
(: RuntimeAddition (Newtype Expression))
;; Proof-store results are either CPU goals or internal runtime fact tuples.
;; Their nested role brands are erased while stored, so the boundary itself is
;; branded rather than attempting to rediscover those roles at runtime.
(: RuntimeResult (Newtype Expression))

;; Stored rule rows retain the existing conclusion/premise wire format. The
;; outer constructor gives both chainers typed fields after a space lookup.
(: RuntimeRuleRow Type)
(: runtime-rule-row
   (-> Number
       (Statement KBContext Proof TV)
       (List Expression)
       RuntimeRuleRow))

(: StoredGoalRow Type)
(: stored-goal-row
   (-> Number Number
       (| Goal (Statement KBContext Proof TV))
       Bool Number StoredGoalRow))

(: StoredAggregateRow Type)
(: stored-aggregate-row
   (-> Number Number Expression Number Number
       (| Number (List Number))
       StoredAggregateRow))

;; Executable goals are either CPU computations or fact goals. Fact KB,
;; proof, and statement fields retain their original runtime shapes.
(: Goal Type)
(: CPU (-> $formula $arguments $result Goal))
(: : (-> KBContext Proof Statement TV Goal))

;; Public source statements and query answers omit the runtime KB/context.
(: AnnotatedStatement Type)
(: : (-> Proof Statement TV AnnotatedStatement))

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
(: fact-ev (-> KBContext Proof Statement Evidence))
(: not-fact-ev (-> KBContext Proof Statement Evidence))
(: rule-ev (-> KB Proof Evidence))
(: not-ev (-> Evidence Evidence))

(: MergedProofGroup Type)
(: merged-proof-group (-> Number MergedProofGroup))

(: ProofKind Type)
(: leaf
   (-> (| Goal (Statement KBContext Proof TV)) ProofKind))
(: rule
   (-> (| Goal (Statement KBContext Proof TV)) ProofKind))
(: aggregate
   (-> (| Goal (Statement KBContext Proof TV)) ProofKind))
(: merged
   (-> (| Goal (Statement KBContext Proof TV)) ProofKind))

(: StoredProofRow Type)
(: stored-proof-row
   (-> Number (| Number MergedProofGroup)
       (| Goal (Statement KBContext Proof TV))
       ProofKind Number (List Evidence) (List Number)
       StoredProofRow))

(: BaseRateSource Type)
(: user BaseRateSource)
(: computed BaseRateSource)
(: forward-approx BaseRateSource)

(: BaseRatePrior (Newtype Expression))

(: BaseRateEntry Type)
(: base-rate
   (-> KB Statement TV BaseRateSource $mode BaseRateEntry))

(: UniverseSizeEntry Type)
(: universe-size (-> KB Number UniverseSizeEntry))

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
(: member-inheritance (-> KB MemberInheritanceFinish))
(: WeightedBaseRateInUniverseFinish Type)
(: weighted-base-rate-in-universe
   (-> KB WeightedBaseRateInUniverseFinish))
(: WeightedBaseRateWithPriorInUniverseFinish Type)
(: weighted-base-rate-with-prior-in-universe
   (-> KB WeightedBaseRateWithPriorInUniverseFinish))
(: UniformPriorFinish Type)
(: uniform-prior UniformPriorFinish)
(: UniformPriorKnownFinish Type)
(: uniform-prior-known UniformPriorKnownFinish)

(: ConceptPriorConfidence Type)
(: concept-prior-confidence
   (-> KB Number ConceptPriorConfidence))

(: ConceptNodePriorRuntime Type)
(: ConceptNodePriorRuntime
   (-> KB Statement ConceptNodePriorRuntime))
