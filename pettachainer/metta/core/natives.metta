;; Native entry points: one name and signature drives registration and typing.
;; Groups share a determinism annotation; a bare name retains an intentionally
;; untyped Python/ingestion boundary.
;; The bootstrap loads their implementations before this declaration table.
!(declare-natives! -[det]-> (
   declare-stores!
   (sk-order-claims (List SkeletonClaim) (List SkeletonClaim))
   ;; A row is forced once per evaluation by each cause. Supported changes are
   ;; finite, and forced propagation never creates a new cause, even through a
   ;; fold, so feedback still ends. A row never computed is not forced: its first
   ;; view changes its key whatever caused it.
   (sk-force-causes! Number Number (List Number) Atom)
   (sk-force-reset! Atom)
   (source-list-union SourceList SourceList SourceList)
   (observation-keys SourceList (List Number))
   (observation-sources (| EvidenceSet Evidence) SourceList)
   (update-likelihood-support! Atom Atom SourceList Number Number Bool)
   (update-aggregate-sources! Number ForwardAggregateObservationKey SourceList Number SourceList Number Bool)
   (aggregate-readers Number (List Number) (List ForwardAggregateObservationKey))
   (likelihood-support-counts Atom SupportCounts)
   (likelihood-sources Atom Number SourceList)
   (likelihood-support-admissible? Atom SourceList Bool)
   ;; A disconnected conjunction has no independent joint population parameter,
   ;; and a negation's rate is an STV.
   (validate-base-rate! Statement (List Atom) TV Bool)
   ;; Immutable input relations cannot be targets of inversion or completion.
   (functional-pattern? KB Statement Bool)
   ;; Nonbinding syntactic coverage, including variable sharing.
   (term-covers? Atom Atom Bool)
   validate-ingestion!
   (proof-identities-free! $adds Bool)
   (member-canon $statement $statement)
   (reserved-head? Atom Bool)
   source-heads-free!
   record-source-heads!
   (declared-head! Atom Bool)
   set-argument-sorts
   set-constant-sort
   (set-predicate-time KB Atom Number Number Bool)
   record-source-sorts!
   (stage-statement? KB Atom Atom Bool)
   (stationary-rule? KB Atom Atom Bool)
   (class-link? Atom Atom Bool)
   (class-link-instance? Atom Atom Bool)
   (generalize-constants Atom Atom)
   (hazards-changed! Bool)
   (take-hazards-changed Bool)
   weighted-assumption
   check-query-annotations!
   source-exists?
   source-rule?
   set-max-term-bytes
   (source-tv-canon $statement $statement)
   (jeffrey-order Expression Expression)
   (node-joint-goals Atom Expression)
   (node-formula Atom Expression)
   (observed-rate-evidence (List SkFact) (List Number) EvidenceSet BaseRateEvidenceState)
   ;; MAIN identity and mutable evaluation scope are separate. These native
   ;; operations own Assuming's read-through value overlay.
   (source-plan-addition RuntimeAddition RuntimeAddition)
   (source-plan-parts CompiledAddition (Atom Atom Atom Atom Atom))
   (compile-source-plan Atom Atom Atom Atom RuntimeAddition)
   (prepare-source-addition RuntimeAddition (Atom RuntimeAddition))
   (source-catalog-rule! Atom Number Atom Atom Bool)
   (source-catalog-fact! Atom Atom Atom Bool)
   (source-catalog-unindex! Atom Bool)
   (source-catalog-remove! Number Bool)
   (source-catalog-clear-temp! Bool)
   (source-catalog-changed! KB Bool)
   (source-catalog-priors Statement KBContext Atom)
   (rule-forward-ids Number (List Number))
   (context-current Atom)
   (context-prepare! KBContext Statement Proof TV Bool)
   (context-seeds Atom (List SkFact))
   (context-rule-rows Atom (List (Atom Number SkFact (List SkPattern))))
   (context-answer-keys SkPattern (List SkeletonKey))
   (context-key-local? Atom Number SkeletonKey Bool)
   (context-reuse-threshold Number)
   (context-propagated SkeletonKey ContextSnapshot)
   (context-store-propagated! SkeletonKey SkeletonValue (List (Number SkeletonValue)) Bool)
   (context-views SkeletonKey (List (Number SkeletonValue)))
   (context-view-changes (List (Number SkeletonValue)) (List (Number SkeletonValue)) (List (SkeletonValue SkeletonValue)))
   (context-add! Atom $row Bool)
   (context-remove! Atom $row Bool)
   (set-context-reuse-threshold Number Bool)
   (context-searching? Atom Bool)
   (context-rule-visible? Number Bool)
   (context-rule-enabled? Atom Bool)
   (context-seeded? Statement KBContext Bool)
   (context-addition RuntimeAddition RuntimeAddition)
   (context-note-rule! Number SkFact Bool)
   (context-rule-premises SkFact (List SkPattern) (List SkPattern))
   (context-leaves SkeletonKey (List SkFact))
   (context-clear! Bool)
   (set-functional-predicate KB Atom Number (List Number) Bool)
   (functional-check-additions! KB $adds Bool)
   (functional-fact! $fact Bool)
   (functional-rule! $conclusion Bool)
   (sk-functional-conflict? $premise Bool)
   (sk-functional-exhausted? $premise Bool)
   (sk-functional-subscription $waiter Atom)
   (sk-functional-delivered! Atom Bool)
   (add-space-atom! $space SpaceAtom Bool)
   ;; Withdrawal provenance is independent of truth-value evidence.
   (withdraw-rule! Number Bool)
   (rule-live? Number Bool)
   (proof-ref-negated? Number Bool)
   (proof-zero-likelihood? Proof Bool)
   (proof-unsettled-sources Proof (List Number))
   ;; Keep the reference kernel in its fold boundary: PeTTa specializes its
   ;; writable row variables there. Only the immutable diagnostic is memoized;
   ;; current drop/rebuild status is checked again before every use.
   (sk-row-has-bayes? Number SkeletonKey Number Bool)
   (proof-representative? Proof Bool)
   (proof-given-evidence Proof EvidenceSet)
   (proof-semantic Proof Atom)
   (proof-update-witness Proof Atom)
   (proof-template! Number Atom Atom Bool)
   (proof-inversion-name Number Atom)
   (proof-application-name Number Atom)
   (application-values Atom Atom (List ProofApplicationValue))
   (record-proof! Number Number Proof EvidenceSet Number Atom Proof)
   ;; Rule retirement and the physical stores exposing derived facts in &kb.
   (record-view-rule! Number Number Proof Number)
   (record-summary-rules! Number Number Proof Bool)
   (record-stored-rules! Atom Number SkeletonKey Proof Bool)
   (forget-stored-rules! Atom Number SkeletonKey Bool)
   (withdrawn-stores! (List Number) (List RetiredStore))
   (proof-live? Proof Bool)
   ;; A proof that gives way to another: a connective's formula over its parts
   ;; (a conjunction, disjunction or conditioned reading) to a compound node's
   ;; joint posterior of the same key, which reads every part apart from the
   ;; compound; a complete step to the settled step that decides it, which
   ;; reads the settling part without the compound's other parts.
   (sk-step-proof Proof Proof)
   ;; The last rule application of a proof, with its premise proofs still
   ;; references (runtime_helpers.pl).
   (same-proof? Proof Proof Bool)
   (remove-data-rows! Atom $pattern Bool)
   (remove-variant-row! Atom $row Bool)
   ;; The ordinary readers being computed, innermost first (runtime_helpers.pl).
   ;; Nested evaluations carry exclusions, so they leave the stack in place. A
   ;; reader is a row's identity, not its whole row.
   (sk-push-reader! (Number SkeletonKey Number) Atom)
   (sk-restore-readers! Atom Bool)
   ;; Shared compiler/runtime lookup hash (native, variable-safe).
   (index-hash $term Number)
   ;; A lookup column is hashed with every variable replaced by one marker
   ;; (imported Prolog helper index-hash): the integer lets SWI build a JIT hash
   ;; index on the space, while the complete key stored beside it lets =alpha
   ;; reject collisions and distinguish variable-sharing patterns.
   ;; The hashes of a statement's prefixes, its head with its first one, two, ...
   ;; arguments, up to the first argument that is not ground, longest first
   ;; (imported Prolog helper statement-prefix-hashes; see &kb_prefix).
   (statement-prefix-hashes $statement (List Number))
   ;; The hash a statement with variables is stored under, and the hashes a
   ;; pattern with a ground prefix reads such statements by besides its longest
   ;; prefix (imported Prolog helpers; see &kb_open).
   (statement-open-hash $statement Number)
   (statement-open-probes $statement (List Number))
   ;; Fact lookup extends these prefixes through an implication antecedent's
   ;; nested heads, keeping source templates selective without changing node keys.
   (kb-fact-prefix-hashes $statement (List Number))
   (kb-fact-open-hash $statement Number)
   (kb-fact-open-probes $statement (List Number))
   ;; A walk enters only nodes whose search may still have work: the node or one
   ;; below it is unexpanded, or holds parked deliveries, deferred joins or
   ;; deferred rows. Every node of a cycle reaches what the others reach, so the
   ;; nodes are kept as the components of their cycles, an acyclic graph whose
   ;; components count their work items and their pending child components; a
   ;; change of state moves the parents' counts. Whether a node is pending is
   ;; then one lookup, exact at any time (runtime_helpers.pl, "Pending work").
   ;; Work items: being unexpanded, each parked delivery, deferred join and
   ;; deferred row; sk-work! adds or takes them.
   (sk-link-pending! Number SkPattern Number SkPattern Atom)
   (sk-work! Number SkPattern Number Atom)
   (sk-pending? Number SkPattern Bool)
   (sk-pending-children Number SkPattern (List SkeletonNodeAt))
   ;; Parked deliveries, deferred joins or deferred rows at a node's hash.
   (sk-holds-work? Number Bool)
   ;; A 60-bit digest of a link term (runtime_helpers.pl).
   (link-digest Atom Number)
   (rule-truth-factor Atom Number)
   (key-context Atom Atom)
   (rule-completion-inputs Number (List SkPattern) CompletionInputs)
   (existential-key-before? Atom Atom Bool)
   (existential-outer-values? Atom Bool)
   (existential-source Atom Statement)
   (pattern-shape Atom Atom)
   (evidence-set (List Evidence) EvidenceSet)
   (evidence-entries EvidenceSet (List Evidence))
   (evidence-union EvidenceSet EvidenceSet EvidenceSet)
   (evidence-join (List EvidenceSet) EvidenceSet)
   (evidence-overlap? EvidenceSet EvidenceSet Bool)
   (evidence-subset? EvidenceSet EvidenceSet Bool)
   (evidence-subtraction EvidenceSet EvidenceSet EvidenceSet)
   (evidence-negated EvidenceSet EvidenceSet)
   (evidence-uncertain-overlap? EvidenceSet EvidenceSet Bool)
   (evidence-unique-count Number EvidenceSet EvidenceSet Number)
   (evidence-subtraction-certain EvidenceSet EvidenceSet EvidenceSet)
   (evidence-condition EvidenceSet (List Number) EvidenceSet)
   (evidence-observed-roles EvidenceSet EvidenceSet Atom)
   (evidence-inherited EvidenceSet EvidenceSet)
   (evidence-shared-facts EvidenceSet EvidenceSet (List Evidence))
   (evidence-excludes? EvidenceSet EvidenceSet Bool)
   ;; A value's dependency set, an interned node id; 0 is the empty set
   ;; (runtime_helpers.pl).
   (deps-key Number Number)
   (deps-union Number Number Number)
   (deps-join (List Number) Number)
   (deps-has? Number Number Bool)
   (deps-meet? (List Number) Number Bool)
   (deps-excluded (List Number) Number (List Number))
   (deps-within? Number Number Bool)
   (deps-mask-within? Number Number Bool)
   (deps-size Number Number)
   (deps-shared Number Number (List Number))
   (deps-entangled (List Number) (List Number))
   (deps-near-shared (List Number) (List Number))
   (deps-cut! (List Number) Number Bool)
   (deps-gc! (List Number) Bool)
   (deps-gc-due? Bool)
   (stored-refs-gc! Bool)
   (stored-refs-gc-step! Bool)
   ;; Rules whose premise only their own conclusion supports (runtime_helpers.pl).
   (rule-dormant? Number Bool)
   (rule-dormancy-wake! Atom (List Number))
   (rule-dormancy-reset! (List Number))
   (rule-dormancy-forget-temp! Bool)
   ;; Contexts of Assuming queries, which see the world, and whether their
   ;; assumptions can change a statement (runtime_helpers.pl).
   (context-create! KBContext Bool)
   ;; A branch's sample taken into its segments, the segments and the member's
   ;; segment after it; and the segments' evidence (runtime_helpers.pl).
   (regime-take! Number Number Number (List RegimeSegment) Number BaseRateEvidenceState BaseRateEvidenceState ((List RegimeSegment) Number))
   (regime-evidence Number (List RegimeSegment) BaseRateEvidenceState)
   ;; A stored proof expanded with each shared subproof printed once (runtime_helpers.pl).
   (proof_dag_expand Atom Atom)
   ;; Proof-indexed subsumption preserves root order (runtime_helpers.pl).
   (prune_answer_instances (List RuntimeResult) (List RuntimeResult))
   (grows-from? SkPattern SkPattern Bool)
   (link-open-variables SkeletonKey SkeletonKey Bool)
   (term-cost $term Number Number)
   (row-cost $row Number Number)
   (rule-lookup-needs-occurs-check Atom Bool)
   (ccls-index-occurs-matches Atom (List (SkFact Number (List SkPattern))))
   particle_merge_resample
   ;; Hypothesis mining's term helpers (runtime/hypothesis_mining.metta).
   (hypothesis-candidates Atom Atom Atom (List (Atom Atom Atom)))
   (hypothesis-failure-candidates Atom Atom Atom Atom (List (Atom Atom Atom)))
   (hypothesis-exception-pairs Atom Atom Atom Atom (List (Atom Atom Atom)))
   (hypothesis-place KB Atom Atom)
   ;; Observed predicates' term helper (runtime/observed_predicates.metta).
   (closed-world-gaps KB Atom Atom (List AnnotatedStatement))
   (hypothesis-constants Atom (List Atom))
   (hypothesis-patterns Atom (List Atom))
   (hypothesis-generalizes? Atom Atom Bool)
   (hypothesis-name Number Atom)
   (hypothesis-features Atom Atom Atom Atom Number Atom)
   ;; The hypotheses an added statement proposes, to be compiled by compileadd.
   ;; A true link fact is recorded under the two time points it links.
   (hypothesis-link-observations Atom Atom Number (List HmObservation))
   (hypothesis-truths Atom Atom Atom)
   (hypothesis-read! KB Atom Number)
   (hypothesis-layers KB Atom Atom)
   (sk-known-conclusion? $fact Bool)
   (sk-store-join! Number $waiter $conclusion Bool)
   (sk-unstore-join! Number $conclusion Bool)
   (sk-wait-handle SkeletonWaiter Number)
   (sk-waiter-at Number (List SkeletonWaiter))
   (sk-keep-child! Number $conclusion Bool)
   (sk-retire-known! Statement KBContext Bool)
   (sk-retire-searches! Bool)
   (sk-retire-wait! Number $premise $waiter Bool)
   (sk-store-wait! Number Number $premise $waiter Bool)
   (sk-store-child! Number Number $owner $child Number Bool)
   (sk-fact-watches Number (List SkPattern))
   ;; A counter's value, 0 before it is set (runtime_helpers.pl): read on every
   ;; search step, so kept native.
   (search-id-value CounterKey Number)
   (fresh-rule-id Number Number)
   ;; Inference time, process-wide (runtime_helpers.pl); reasoning never reads it.
   (inference-add! Number Bool)
   ;; Opt-in diagnostic counters kept natively; reasoning never reads them.
   (query_metrics_enabled Bool)
   (query_metrics_set_enabled Bool Bool)
   (query_metric_value Atom Number)
   (query_metric_set Atom Number Number)
   (query_metric_increment Atom Number)
))

!(declare-natives! -[semidet]-> (
   (application-rule Number ProofApplicationTemplate)
   (event-graph-prepay! (List SkeletonKey) Bool)
   (query-answer-groups (List AnnotatedStatement) (List QueryBatchResult) (List (List Atom)))
   (member-shape Atom Atom Atom)
   ;; Observed likelihoods, then Jeffrey updates; graph replacements must be compatible.
   (event-network-read SkeletonKey SkeletonFilter (List Number) EvidenceSet EventNetworkRead)
   (event-node-message Atom Number Number Expression Expression Expression Expression Expression)
   (event-node-value Atom Number Number Expression Expression Expression Expression Expression)
   (event-node-jeffrey Atom Number Number Expression Expression Expression Expression Expression)
   (jeffrey-posterior Number Number Number TV Expression STVType)
   (pearl-moments Number Atom Atom Expression STVType)
   (event-node-joint Atom Expression Number Expression Expression Expression Expression Expression)
   ;; Keep selection as an output across the FFI: nth0/4 types its third
   ;; position as an input under strict checking.
   (rule-premise Number (List SkPattern) SkPattern)
))

!(declare-natives! -[nondet]-> (
   (sk-active-reader (Number SkeletonKey Number))
   (evidence-proof-fact EvidenceSet Proof Evidence)
))

;; A higher-order bracket keeps native storage independent of runtime policy.
!(declare-natives! -[semidet]-> ((context-with-scope Atom (-[semidet]-> Atom $result) $result)))

;; Executor contracts for the mutually recursive evaluator. Implementations
;; are MeTTa in runtime/store/allowances, loaded after the computation modules.
!(declare-forward! -[det]-> (
   (sk-take! CounterKey Number Bool)
   (sk-reserve-near! Number Atom)
   (sk-evaluation-per-step Number)
   (sk-root-claim-share Number)
   (sk-root-claim-limit Number)
   (sk-branch-share Number)
   (sk-walk-per-step Number)
   (execution-open-slice! Number EvaluationSlice)
   (execution-close-slice! EvaluationSlice EvaluationTier Number)
   (execution-open-frame! (List Number) (Number Number))
   (retain-query-proof! (Number AnnotatedStatement) Bool)
   (public-forward-fact (Statement KBContext Proof TV) (Statement KBContext Proof TV))))
!(declare-forward! -[semidet]-> (
   (execution-close-frame! Number Number (List Number) (List Number))
   (context-cold-merged Number SkeletonKey SkeletonFilter SkeletonMerged)
   (context-answer-seeds! SkPattern Atom)
   (context-propagate? SkeletonKey Bool)
   (query-plan-runtime-goal (Number Statement AnnotatedStatement CompiledQueryGoal) ExecutionGoal)
))
!(declare-forward! -[nondet]-> (
   (present-query-plan-results Bool (List (Number Statement AnnotatedStatement CompiledQueryGoal)) (List (List RuntimeResult)) (List (Number AnnotatedStatement)))
   (execute-backward Number (List ExecutionGoal) Bool (List (List RuntimeResult)))
   (run-query-execution-plan Number QueryExecutionPlan Bool Bool (List (Number AnnotatedStatement)))))

;; Two views of one statement merged (backward/evaluation.metta); stored facts
;; merge by it too (forward/schema.metta).
(: sk-merge-facts
   (-[semidet]-> Bool (List Number) SkFact EvidenceSet Number SkFact EvidenceSet Number
       SkeletonPairing))
