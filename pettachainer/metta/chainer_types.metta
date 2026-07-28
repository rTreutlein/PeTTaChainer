;; Shared PeTTaChainer wire and domain types.
;;
;; Function signatures stay beside their implementations. This file contains
;; only representations shared across compiler/runtime module boundaries.

;; SWI heap values are opaque Prolog terms. The parameter tracks their payload
;; type, while heap_pop adapts get_from_heap/4 to PeTTa's single output.
(: Heap (Foreign 1))
(: empty_heap (-[det]-> (Heap $item)))
(: add_to_heap
   (-[det]-> (Heap $item) Number $item (Heap $item)))
(: heap_pop
   (-[semidet]-> (Heap $item)
       (Number $item (Heap $item))))

(: TV Type)
(: STV (-> Number Number TV))
(: CTV (-> TV TV TV))
(: no-evidence TV)

(: Distribution Type)
(: ParticleDist (-> Number Number Distribution))

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
;; Any value with this role is known to be a nonempty expression that can be
;; inserted into an atom space.  The brand is erased at runtime.
(: SpaceAtom (Newtype Expression))
;; Proof-store results are either CPU goals or internal runtime fact tuples.
;; Their nested role brands are erased while stored, so the boundary itself is
;; branded rather than attempting to rediscover those roles at runtime.
(: RuntimeResult (Newtype Expression))

;; The compiler/runtime query handoff is shared by the compiler, backward
;; chainer, and public query runtime.
(: CompiledQuery Type)
(: compiled-query
   (-> (| Goal
          (Statement KBContext Proof TV))
       (List RuntimeAddition) CompiledQuery))

;; Forward-runtime values shared with compiled rule insertion and backward
;; conclusion indexing.
(: ForwardDerived Type)
(: forward-derived
   (-> (Statement KBContext Proof TV) (List Evidence) ForwardDerived))

(: ForwardTriggerKey Type)
(: fwd_trigger (-> KB Atom ForwardTriggerKey))
(: fwd_member (-> KB Term ForwardTriggerKey))
(: fwd_trigger_any ForwardTriggerKey)

;; Keys for the monotonic counters shared by the compiler and both runtimes.
;; Naming the role prevents an arbitrary atom from being accepted by the state
;; mutation helper while retaining the existing symbol representation.
(: CounterKey Type)
(: bwd_gid CounterKey)
(: bwd_pid CounterKey)
(: ruleid CounterKey)
(: bwd_tmp_ruleid CounterKey)
(: fwd_br_id CounterKey)
(: fwd_member_inheritance_id CounterKey)

;; Stored rule rows retain the existing conclusion/premise wire format. The
;; premise list contains executable goals and internal runtime fact tuples;
;; keeping that union here lets both chainers retain it after a space lookup.
(: RuntimeRuleRow Type)
(: runtime-rule-row
   (-> Number
       (Statement KBContext Proof TV)
       (List (| Goal (Statement KBContext Proof TV)))
       RuntimeRuleRow))
(: rules
   (SpaceOf
      (runtime-rule-row
         Number
         (Statement KBContext Proof TV)
         (List (| Goal (Statement KBContext Proof TV))))))

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

(: ExtractTV Type)
(: extract-tv ExtractTV)
(: ExtractValue Type)
(: extract-value (-> Statement $value ExtractValue))
(: ExtractInheritanceTV Type)
(: extract-inheritance-tv
   (-> KB Statement ExtractInheritanceTV))

(: NilType Type)
(: Nil NilType)

(: NoCurrentScore Type)
(: no-current NoCurrentScore)

(: NoProjectionKey Type)
(: no-projection-key NoProjectionKey)
(: ProjectionKey Type)
(: projection-key (-> Atom Atom ProjectionKey))

(: ProofRef Type)
(: proof-ref (-> Number ProofRef))

(: Evidence (Newtype Expression))
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
