;; Shared PeTTaChainer wire and domain types.
;;
;; MeTTa signatures stay beside their implementations; native signatures live
;; in natives. These representations cross compiler/runtime module boundaries.

;; A value's evidence, an interned set of entries kept in the order they were
;; first added; (ev-set 0) is the empty set (runtime_helpers.pl,
;; docs/metta/evidence_sets.md). Equal sets have equal ids.
(datatype EvidenceSet (ev-set Number))

;; Truth values retain their existing tagged runtime representation, while
;; distinct result types let constructor patterns narrow a TV to the fields
;; that are actually present.  A CTV contains two STVs; absence of an entire
;; truth value is represented separately by no-evidence.
(datatype STVType (STV Number Number))
(datatype CTVType (CTV STVType STVType))
(datatype NoEvidenceType no-evidence)
(: TV (Alias (| STVType CTVType NoEvidenceType)))
(: OptionalSTV (Alias (| STVType NoEvidenceType)))

(datatype Distribution (PointMass $value) (ParticleDist Number Number))

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
(datatype CompiledQuery (compiled-query CompiledQueryGoal (List RuntimeAddition)))

;; Forward-runtime values shared with compiled rule insertion and backward
;; conclusion indexing.
(datatype ForwardDerived (forward-derived (Statement KBContext Proof TV) EvidenceSet))

(datatype ForwardTriggerKey (fwd_trigger KB Atom) (fwd_member KB Term) fwd_trigger_any)

;; Forward aggregate subscriptions share one maintenance kernel.  Identity,
;; descriptor, and observation roles stay distinct even though their branded
;; values erase to ordinary MeTTa terms at runtime.
(: ForwardAggregateIdentityKey Type)
(: ForwardAggregateDescriptor Type)
(: ForwardAggregateObservationKey (Newtype Atom))
(datatype ForwardAggregateMaintenance aggregate-update aggregate-remove)

;; Keys for the monotonic counters shared by the compiler and both runtimes.
;; Naming the role prevents an arbitrary atom from being accepted by the state
;; mutation helper while retaining the existing symbol representation.
(datatype CounterKey
   proof_id
   ruleid
   bwd_tmp_ruleid
   fwd_aggregate_id
   sk_budget
   sk_row_budget
   sk_eval_budget
   sk_branch_unpaid
   sk_branch_frame
   sk_branch_at
   sk_branch_budget
   sk_graph_budget
   sk_input_id
   sk_root_claim_budget
   sk_root_claim_cap
   sk_change_cause
   sk_need_budget
   sk_claim_state
   sk_claim_depth
   sk_claim_cut
   sk_deferred
   ;; computations near a root a query may make once its allowance is spent
   sk_near_reserve
   ;; 1 while a forward run grows the skeleton upward
   sk_forward_run
   ;; 1 while a query's evaluation holds the needed rows the stale cascade reaches
   sk_holding
   sk_walk_budget
   sk_epoch
   forgetting_horizon
   forgetting_decay
   sk_row_seq
   sk_push_seq
   sk_delivery_seq
   hm_name
   hm_seq)

;; The rule store: one row per rule, conclusion first, so a goal finds its
;; rules by the conclusion's head; a lookup by rule id uses the second column.
;; The premise list contains executable goals and internal runtime fact tuples.
(: ccls_index
   (SpaceOf
      ((Statement KBContext Proof TV)
       Number
       (List (| Goal (Statement KBContext Proof TV))))))
;; rule id -> the rule's expected premise confidence
(: rule_expected (SpaceOf (Number Number)))

;; Executable goals are either CPU computations or fact goals. Fact KB,
;; proof, and statement fields retain their original runtime shapes.
(: ExecutionGoal (Alias (| Goal QueryScope (Statement KBContext Proof TV))))
(datatype QueryScope (query-scope KBContext Statement $goal Proof TV))
(datatype Goal (CPU $formula $arguments $result) (: KBContext Proof Statement TV))

;; Public source statements and query answers omit the runtime KB/context.
(datatype AnnotatedStatement (: Proof Statement TV))

;; Batch query answers retain their input position and emit one row per
;; annotated answer. A root with no answer emits no row.
(datatype QueryBatchResult (query-result Number Atom))

(datatype AggregateTVMode result-tv unit-stv)

(datatype ExtractTV extract-tv)
(datatype ExtractValue (extract-value Statement $value) (extract-with-truth Statement Atom $value))

(datatype NilType Nil)

;; A stored proof: a reference in a proof term stands for the proof stored
;; under that id, with the evidence a walk of its leaves finds and whether it
;; contains a negation anywhere. Stored proofs refer only to earlier ids, so
;; they form a DAG, and a proof term stays as small as one rule application.
(: proof-ref (-[det]-> Number Proof))
(: fact-source (-[det]-> EvidenceSet Proof Proof))
(: zero-likelihood (-[det]-> Proof Proof))
;; Confidence annotation, not a new logical inference.
(: unsettled-summary (-[det]-> Number Proof Proof))
;; The metadata word packs the permanent owner rule id + 1 and negated bit:
;; ((owner-id + 1) << 1) | negated; owner code zero means no permanent owner.
(: &proof (SpaceOf (Number Proof EvidenceSet Number)))
;; the statement and truth value a stored fact proof proves
(: &proof_fact (SpaceOf (Number Statement TV)))

;; An installed application has explicit semantic inputs beside its explanation.
(datatype ProofApplicationTemplate
   (application-template Statement KBContext Proof Proof (List Atom)))
(datatype ProofApplicationValue
   (application-value Statement KBContext Proof Proof TV (List Atom)))

(: Evidence (Newtype Atom))
(: given-ev (-[det]-> KBContext Proof Statement Evidence))
(: fact-ev (-[det]-> KBContext Proof Statement Evidence))
(: not-fact-ev (-[det]-> KBContext Proof Statement Evidence))
(: rule-ev (-[det]-> KB Proof Evidence))
(: rule-excluded (-[det]-> KB Proof Evidence))
(: not-ev (-[det]-> Evidence Evidence))

(datatype BaseRateSource user computed)

(datatype BaseRateEntry (base-rate KB Statement TV BaseRateSource $mode))

(datatype IdentityFinish identity)
(datatype DistAverageFinish dist-average)
(datatype BaseRateFinish base-rate)
(datatype ImplicationInstanceFinish implication-instance-ctv)
(: AggregateFinish
   (Alias
      (| IdentityFinish
         DistAverageFinish
         BaseRateFinish
         ImplicationInstanceFinish)))

(datatype RetiredStore (retired-store Atom Number SkeletonKey))

(datatype QueryExecutionPlan
   (query-execution-plan (List (Number Statement AnnotatedStatement CompiledQueryGoal)) (List RuntimeAddition)))

;; A transported premise proof acquires its role while the row is read.
(datatype ApplicationEntanglement no-input-entanglement (result-input-entanglement Proof))
