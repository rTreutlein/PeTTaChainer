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

;; Truth values retain their existing tagged runtime representation, while
;; distinct result types let constructor patterns narrow a TV to the fields
;; that are actually present.  A CTV contains two STVs; absence of an entire
;; truth value is represented separately by no-evidence.
(: STVType Type)
(: CTVType Type)
(: NoEvidenceType Type)
(: STV (-[det]-> Number Number STVType))
(: CTV (-[det]-> STVType STVType CTVType))
(: no-evidence NoEvidenceType)
(: TV (Alias (| STVType CTVType NoEvidenceType)))
(: OptionalSTV (Alias (| STVType NoEvidenceType)))

(: Distribution Type)
(: ParticleDist (-[det]-> Number Number Distribution))

;; These semantic roles share PeTTaChainer's existing open MeTTa wire
;; representation. Newtype brands distinguish them statically and are erased
;; completely by the compiler.
;; KB names identify a knowledge base. KBContext is the full runtime
;; (name context variables) tuple carried by compiled facts and goals.
(: KB (Newtype Atom))
(: KBContext (Newtype (KB Atom Atom)))
(: Proof (Newtype Atom))
(: Statement (Newtype Atom))
(: Term (Newtype Atom))
(: Variable (Newtype Atom))
(: CompiledAddition (Newtype Atom))
(: RuntimeAddition (Newtype Atom))
;; Any value with this role is known to be a nonempty expression that can be
;; inserted into an atom space.  The brand is erased at runtime.
(: SpaceAtom (Newtype Atom))
;; Proof-store results are either CPU goals or internal runtime fact tuples.
;; Their nested role brands are erased while stored, so the boundary itself is
;; branded rather than attempting to rediscover those roles at runtime.
(: RuntimeResult (Newtype Atom))

;; The canonical knowledge space stores internal runtime facts in
;; `(statement kb-context proof tv)` order.  Naming the schema keeps those
;; roles intact across reads, so consumers can bind and reuse the complete row
;; without rebuilding and rechecking it.
(: &kb
   (SpaceOf
      (Statement KBContext Proof TV)))

;; The compiler/runtime query handoff is shared by the compiler, backward
;; chainer, and public query runtime.
(: CompiledQueryGoal (Newtype Atom))
(: CompiledQuery Type)
(: compiled-query
   (-[det]-> CompiledQueryGoal
       (List RuntimeAddition) CompiledQuery))

;; Forward-runtime values shared with compiled rule insertion and backward
;; conclusion indexing.
(: ForwardDerived Type)
(: forward-derived
   (-[det]-> (Statement KBContext Proof TV) (List Evidence) ForwardDerived))

(: ForwardTriggerKey Type)
(: fwd_trigger (-[det]-> KB Atom ForwardTriggerKey))
(: fwd_member (-[det]-> KB Term ForwardTriggerKey))
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
   (-[det]-> Number
       (Statement KBContext Proof TV)
       (List (| Goal (Statement KBContext Proof TV)))
       RuntimeRuleRow))
(: rules
   (SpaceOf
      (runtime-rule-row
         Number
         (Statement KBContext Proof TV)
         (List (| Goal (Statement KBContext Proof TV))))))
(: ccls_index
   (SpaceOf
      ((Statement KBContext Proof TV)
       Number
       (List (| Goal (Statement KBContext Proof TV))))))

(: StoredGoalRow Type)
(: stored-goal-row
   (-[det]-> Number Number
       (| Goal (Statement KBContext Proof TV))
       Bool Number StoredGoalRow))

(: StoredAggregateRow Type)
(: stored-aggregate-row
   (-[det]-> Number Number Atom Number Number
       (| Number (List Number))
       StoredAggregateRow))

;; Executable goals are either CPU computations or fact goals. Fact KB,
;; proof, and statement fields retain their original runtime shapes.
(: Goal Type)
(: CPU (-[det]-> $formula $arguments $result Goal))
(: : (-[det]-> KBContext Proof Statement TV Goal))

;; Public source statements and query answers omit the runtime KB/context.
(: AnnotatedStatement Type)
(: : (-[det]-> Proof Statement TV AnnotatedStatement))

(: AggregateTVMode Type)
(: result-tv AggregateTVMode)
(: unit-stv AggregateTVMode)

(: ExtractTV Type)
(: extract-tv ExtractTV)
(: ExtractValue Type)
(: extract-value (-[det]-> Statement $value ExtractValue))
(: ExtractInheritanceTV Type)
(: extract-inheritance-tv
   (-[det]-> KB Statement ExtractInheritanceTV))

(: NilType Type)
(: Nil NilType)

(: NoCurrentScore Type)
(: no-current NoCurrentScore)

(: NoProjectionKey Type)
(: no-projection-key NoProjectionKey)
(: ProjectionKey Type)
(: projection-key (-[det]-> Atom Atom ProjectionKey))

(: ProofRef Type)
(: proof-ref (-[det]-> Number ProofRef))

(: Evidence (Newtype Atom))
(: fact-ev (-[det]-> KBContext Proof Statement Evidence))
(: not-fact-ev (-[det]-> KBContext Proof Statement Evidence))
(: rule-ev (-[det]-> KB Proof Evidence))
(: not-ev (-[det]-> Evidence Evidence))

(: MergedProofGroup Type)
(: merged-proof-group (-[det]-> Number MergedProofGroup))

(: ProofKind Type)
(: leaf
   (-[det]-> (| Goal (Statement KBContext Proof TV)) ProofKind))
(: rule
   (-[det]-> (| Goal (Statement KBContext Proof TV)) ProofKind))
(: aggregate
   (-[det]-> (| Goal (Statement KBContext Proof TV)) ProofKind))
(: merged
   (-[det]-> (| Goal (Statement KBContext Proof TV)) ProofKind))

(: StoredProofRow Type)
(: stored-proof-row
   (-[det]-> Number (| Number MergedProofGroup)
       (| Goal (Statement KBContext Proof TV))
       ProofKind Number (List Evidence) (List Number)
       StoredProofRow))

(: BaseRateSource Type)
(: user BaseRateSource)
(: computed BaseRateSource)
(: forward-approx BaseRateSource)

(: BaseRatePrior (Newtype Atom))

(: BaseRateEntry Type)
(: base-rate
   (-[det]-> KB Statement TV BaseRateSource $mode BaseRateEntry))

(: UniverseSizeEntry Type)
(: universe-size (-[det]-> KB Number UniverseSizeEntry))

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
(: member-inheritance (-[det]-> KB MemberInheritanceFinish))
(: WeightedBaseRateInUniverseFinish Type)
(: weighted-base-rate-in-universe
   (-[det]-> KB WeightedBaseRateInUniverseFinish))
(: WeightedBaseRateWithPriorInUniverseFinish Type)
(: weighted-base-rate-with-prior-in-universe
   (-[det]-> KB WeightedBaseRateWithPriorInUniverseFinish))
(: UniformPriorFinish Type)
(: uniform-prior UniformPriorFinish)
(: UniformPriorKnownFinish Type)
(: uniform-prior-known UniformPriorKnownFinish)

(: ConceptPriorConfidence Type)
(: concept-prior-confidence
   (-[det]-> KB Number ConceptPriorConfidence))

(: ConceptNodePriorRuntime Type)
(: ConceptNodePriorRuntime
   (-[det]-> KB Statement ConceptNodePriorRuntime))
