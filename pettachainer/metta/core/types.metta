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
(: heap-empty? (-[det]-> (Heap $item) Bool))

;; A 60-bit digest of a link term (runtime_helpers.pl).
(: link-digest (-[det]-> Atom Number))

;; Sets of key hashes, kept as SWI ordered sets (runtime_helpers.pl).
(: hash-set (-[det]-> (List Number) (List Number)))
(: hash-union (-[det]-> (List Number) (List Number) (List Number)))

;; A value's dependency set, an interned node id; 0 is the empty set
;; (runtime_helpers.pl).
(: deps-key (-[det]-> Number Number))
(: deps-union (-[det]-> Number Number Number))
(: deps-join (-[det]-> (List Number) Number))
(: deps-has? (-[det]-> Number Number Bool))
(: deps-meet? (-[det]-> (List Number) Number Bool))
(: deps-within? (-[det]-> Number Number Bool))
(: deps-mask-within? (-[det]-> Number Number Bool))
(: deps-size (-[det]-> Number Number))
(: deps-shared (-[det]-> Number Number (List Number)))
(: deps-entangled (-[det]-> (List Number) (List Number)))
(: deps-cut! (-[det]-> (List Number) Number Bool))
(: deps-gc! (-[det]-> (List Number) Bool))
(: deps-gc-due? (-[det]-> Bool))
(: stored-refs-gc! (-[det]-> Bool))
(: stored-refs-gc-step! (-[det]-> Bool))
(: set-functional-predicate (-[det]-> KB Atom Number (List Number) Bool))
(: functional-check-additions! (-[det]-> KB $adds Bool))
(: functional-fact! (-[det]-> $fact Bool))
(: functional-rule! (-[det]-> $conclusion Bool))
(: sk-functional-conflict? (-[det]-> $premise Bool))
(: sk-functional-exhausted? (-[det]-> $premise Bool))
(: sk-functional-subscription (-[det]-> $waiter Atom))
(: sk-functional-delivered! (-[det]-> Atom Bool))
(: sk-known-conclusion? (-[det]-> $fact Bool))
(: sk-store-join! (-[det]-> Number Number $conclusion Bool))
(: sk-keep-child! (-[det]-> Number $conclusion Bool))
(: sk-store-wait! (-[det]-> Number Number $premise $waiter Bool))
(: sk-store-child! (-[det]-> Number Number $owner $child Number Bool))
(: sk-retire-known! (-[det]-> Statement KBContext Bool))
(: sk-retire-wait! (-[det]-> Number $premise $waiter Bool))
(: sk-retire-searches! (-[det]-> Bool))

;; Rules whose premise only their own conclusion supports (runtime_helpers.pl).
(: rule-dormant? (-[det]-> Number Bool))
(: rule-dormancy-wake! (-[det]-> Atom (List Number)))
(: rule-dormancy-reset! (-[det]-> (List Number)))
(: rule-dormancy-forget-temp! (-[det]-> Bool))

;; Contexts of Assuming queries, which see the world, and whether their
;; assumptions can change a statement (runtime_helpers.pl).
(: context-world! (-[det]-> KBContext Statement Bool))
(: context-world? (-[det]-> Atom Bool))
(: context-affected? (-[det]-> Atom Atom Bool))
(: context-pattern-affected? (-[det]-> Atom Atom Bool))
(: context-affected-reset! (-[det]-> Bool))
(: context-forget! (-[det]-> Atom Bool))
(: remove-hash-rows! (-[det]-> Atom Number Bool))
(: existential-outer-values? (-[det]-> Atom Bool))
(: existential-source (-[det]-> Atom Statement))
(: pattern-shape (-[det]-> Atom Atom))
(: rule-truth-factor (-[det]-> Atom Number))
;; Hypothesis mining's term helpers (runtime/hypothesis_mining.metta).
(: hypothesis-candidates (-[det]-> Atom Atom Atom (List (Atom Atom Atom))))
(: hypothesis-failure-candidates (-[det]-> Atom Atom Atom Atom (List (Atom Atom Atom))))
(: hypothesis-exception-pairs (-[det]-> Atom Atom Atom Atom (List (Atom Atom Atom))))
(: hypothesis-place (-[det]-> Atom Atom Atom))
;; Observed predicates' term helper (runtime/observed_predicates.metta).
(: closed-world-gaps (-[det]-> KB Atom Number Atom (List AnnotatedStatement)))
(: hypothesis-constants (-[det]-> Atom (List Atom)))
(: hypothesis-patterns (-[det]-> Atom (List Atom)))
(: hypothesis-generalizes? (-[det]-> Atom Atom Bool))
(: hypothesis-name (-[det]-> Number Atom))
(: hypothesis-features (-[det]-> Atom Atom Atom Atom Number Atom))
(: hypothesis-truths (-[det]-> Atom Atom Atom))
(: hypothesis-read! (-[det]-> KB Atom Number))
(: hypothesis-layers (-[det]-> KB Atom Atom))
(: node-context (-[det]-> Atom Atom))
(: key-context (-[det]-> Atom Atom))
(: scope-context (-[det]-> Atom Atom))
;; A value's evidence, an interned set of entries kept in the order they were
;; first added; (ev-set 0) is the empty set (runtime_helpers.pl,
;; docs/metta/evidence_sets.md). Equal sets have equal ids.
(: EvidenceSet Type)
(: ev-set (-[det]-> Number EvidenceSet))
(: evidence-set (-[det]-> (List Evidence) EvidenceSet))
(: evidence-entries (-[det]-> EvidenceSet (List Evidence)))
(: evidence-union (-[det]-> EvidenceSet EvidenceSet EvidenceSet))
(: evidence-join (-[det]-> (List EvidenceSet) EvidenceSet))
(: evidence-overlap? (-[det]-> EvidenceSet EvidenceSet Bool))
(: evidence-subset? (-[det]-> EvidenceSet EvidenceSet Bool))
(: evidence-subtraction (-[det]-> EvidenceSet EvidenceSet EvidenceSet))
(: evidence-negated (-[det]-> EvidenceSet EvidenceSet))
(: evidence-shared-facts (-[det]-> EvidenceSet EvidenceSet (List Evidence)))
(: evidence-common-facts (-[det]-> (List EvidenceSet) (List Evidence)))
(: evidence-excludes? (-[det]-> EvidenceSet EvidenceSet Bool))

;; KL divergence of Beta(a1, b1) from Beta(a2, b2) (runtime_helpers.pl).
(: beta_kl (-[det]-> Number Number Number Number Number))

;; A stored proof expanded with each shared subproof printed once (runtime_helpers.pl).
(: proof_dag_expand (-[det]-> Atom Atom))

;; The first of each group of variant terms, in order (runtime_helpers.pl).
(: alpha_unique_keys (-[det]-> (List $item) (List $item)))

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
(: PointMass (-[det]-> $value Distribution))
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
;; Explicit existential conclusions are propositions about a canonical body
;; shape, not assertions about one syntactically distinct Skolem object.
;; `exists-slot` marks each bound position without exposing a witness identity.
(: exists-slot (-[det]-> Number Term))
(: ExistentialClaim (-[det]-> Statement Statement))
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
   (-[det]-> (Statement KBContext Proof TV) EvidenceSet ForwardDerived))

(: ForwardTriggerKey Type)
(: fwd_trigger (-[det]-> KB Atom ForwardTriggerKey))
(: fwd_member (-[det]-> KB Term ForwardTriggerKey))
(: fwd_trigger_any ForwardTriggerKey)

;; Forward aggregate subscriptions share one maintenance kernel.  Identity,
;; descriptor, and observation roles stay distinct even though their branded
;; values erase to ordinary MeTTa terms at runtime.
(: ForwardAggregateIdentityKey Type)
(: ForwardAggregateDescriptor Type)
(: ForwardAggregateObservationKey (Newtype Atom))
(: ForwardAggregateMaintenance Type)
(: aggregate-update ForwardAggregateMaintenance)
(: aggregate-remove ForwardAggregateMaintenance)

;; Keys for the monotonic counters shared by the compiler and both runtimes.
;; Naming the role prevents an arbitrary atom from being accepted by the state
;; mutation helper while retaining the existing symbol representation.
(: CounterKey Type)
(: proof_id CounterKey)
(: ruleid CounterKey)
(: bwd_tmp_ruleid CounterKey)
(: fwd_aggregate_id CounterKey)
(: sk_budget CounterKey)
(: sk_row_budget CounterKey)
(: sk_eval_budget CounterKey)
(: sk_need_budget CounterKey)
(: sk_claim_left CounterKey)
(: sk_claim_depth CounterKey)
(: sk_claim_cut CounterKey)
;; computations near a root a query may make once its allowance is spent
(: sk_near_reserve CounterKey)
;; 1 while a forward run grows the skeleton upward
(: sk_forward_run CounterKey)
;; 1 while a query's evaluation holds the needed rows the stale cascade reaches
(: sk_holding CounterKey)
(: sk_walk_budget CounterKey)
(: sk_epoch CounterKey)
(: forgetting_horizon CounterKey)
(: forgetting_decay CounterKey)
(: sk_row_seq CounterKey)
(: sk_push_seq CounterKey)
(: sk_delivery_seq CounterKey)
(: hm_name CounterKey)
(: hm_seq CounterKey)

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
;; rule id -> the rule's expected premise confidence
(: rule_expected (SpaceOf (Number Number)))

;; Executable goals are either CPU computations or fact goals. Fact KB,
;; proof, and statement fields retain their original runtime shapes.
(: Goal Type)
(: CPU (-[det]-> $formula $arguments $result Goal))
(: : (-[det]-> KBContext Proof Statement TV Goal))

;; Public source statements and query answers omit the runtime KB/context.
(: AnnotatedStatement Type)
(: : (-[det]-> Proof Statement TV AnnotatedStatement))

;; Batch query answers retain their input position and emit one row per
;; annotated answer. A root with no answer emits no row.
(: QueryBatchResult Type)
(: query-result (-[det]-> Number Atom QueryBatchResult))

(: AggregateTVMode Type)
(: result-tv AggregateTVMode)
(: unit-stv AggregateTVMode)

(: ExtractTV Type)
(: extract-tv ExtractTV)
(: ExtractValue Type)
(: extract-value (-[det]-> Statement $value ExtractValue))
(: extract-with-truth (-[det]-> Statement Atom $value ExtractValue))
(: ExtractInheritanceTV Type)
(: extract-inheritance-tv
   (-[det]-> KB Statement ExtractInheritanceTV))

(: NilType Type)
(: Nil NilType)

;; A stored proof: a reference in a proof term stands for the proof stored
;; under that id, with the evidence a walk of its leaves finds and whether it
;; contains a negation anywhere. Stored proofs refer only to earlier ids, so
;; they form a DAG, and a proof term stays as small as one rule application.
(: proof-ref (-[det]-> Number Proof))
;; The metadata word packs the permanent owner rule id + 1 and negated bit:
;; ((owner-id + 1) << 1) | negated; owner code zero means no permanent owner.
(: &proof (SpaceOf (Number Proof EvidenceSet Number)))
;; the statement and truth value a stored fact proof proves
(: &proof_fact (SpaceOf (Number Statement TV)))

(: Evidence (Newtype Atom))
(: fact-ev (-[det]-> KBContext Proof Statement Evidence))
(: not-fact-ev (-[det]-> KBContext Proof Statement Evidence))
(: rule-ev (-[det]-> KB Proof Evidence))
(: rule-excluded (-[det]-> KB Proof Evidence))
(: not-ev (-[det]-> Evidence Evidence))

(: BaseRateSource Type)
(: user BaseRateSource)
(: computed BaseRateSource)

(: BaseRatePrior (Newtype Atom))

(: BaseRateEntry Type)
(: base-rate
   (-[det]-> KB Statement TV BaseRateSource $mode BaseRateEntry))
;; entries by a hash of their knowledge base and pattern
(: &base_rate_cache (SpaceOf (Number BaseRateEntry)))

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
(: ImplicationInstanceFinish Type)
(: implication-instance ImplicationInstanceFinish)
(: implication-instance-ctv ImplicationInstanceFinish)
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
(: AggregateFinish
   (Alias
      (| IdentityFinish
         DistAverageFinish
         BaseRateFinish
         WeightedBaseRateFinish
         WeightedBaseRateWithPriorFinish
         MemberInheritanceFinish
         ImplicationInstanceFinish
         WeightedBaseRateInUniverseFinish
         WeightedBaseRateWithPriorInUniverseFinish
         UniformPriorFinish
         UniformPriorKnownFinish)))

(: ConceptPriorConfidence Type)
(: concept-prior-confidence
   (-[det]-> KB Number ConceptPriorConfidence))

(: ConceptNodePriorRuntime Type)
(: ConceptNodePriorRuntime
   (-[det]-> KB Statement ConceptNodePriorRuntime))

;; Withdrawal provenance is independent of truth-value evidence.
(: withdraw-rule! (-[det]-> Number Bool))
(: rule-live? (-[det]-> Number Bool))
(: proof-live? (-[det]-> Proof Bool))
(: record-summary-rules! (-[det]-> Number Number Proof Bool))

;; Rule retirement and the physical stores exposing derived facts in &kb.
(: record-view-rule! (-[det]-> Number Number Proof Number))
(: record-stored-rules! (-[det]-> Atom Number SkeletonKey Proof Bool))
(: forget-stored-rules! (-[det]-> Atom Number SkeletonKey Bool))
(: RetiredStore Type)
(: retired-store (-[det]-> Atom Number SkeletonKey RetiredStore))
(: withdrawn-stores! (-[det]-> (List Number) (List RetiredStore)))

(: sk-retire-store! (-[det]-> RetiredStore Atom))

(: existential-key-before? (-[det]-> Atom Atom Bool))
