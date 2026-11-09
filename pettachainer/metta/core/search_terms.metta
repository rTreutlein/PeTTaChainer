;; Search/value term schemas and structural node hashing.
;; --- Types --------------------------------------------------------------------

(: SkFact (Alias (Statement KBContext Proof TV)))
;; A goal pattern: a fact goal or a computation, as rule premises are.
(: SkPattern (Alias (| Goal (Statement KBContext Proof TV))))

(: ScalarFoldSpec
   (Alias (KB Statement (| ExtractValue ExtractTV) $a
             (-[semidet]-> $b $c $b) AggregateFinish AggregateTVMode)))
(: GroupedFoldSpec
   (Alias (KB Statement $a (| ExtractValue ExtractTV) $b
             (-[semidet]-> $c $d $c) AggregateFinish AggregateTVMode)))

;; What a value belongs to: a statement in a context, a fold, one group of a
;; grouped fold, a compound's prior (sk-prior, #142), or a connective's own
;; evidence for the completions of its parts (sk-evidence, #142).
(datatype SkeletonKey
   ;; A fold's arguments come out of a CPU goal, whose arguments are polymorphic;
   ;; they are typed as a fold spec once, where the fold is computed.
   (sk-key Statement KBContext)
   (sk-fold $spec)
   (sk-group $spec)
   (sk-prior $spec)
   (sk-evidence $spec))

;; a key a conditioned read takes as known true or false, or a complete
;; statement a closed read takes as unfounded (docs/metta/complete_predicates.md)
(datatype SkeletonGiven (sk-given Number SkeletonKey Bool) (sk-unfounded Number SkeletonKey))

(datatype SkeletonFilter
   ;; the proof and truth-value pattern a consumer asks for
   (sk-filter Proof TV)
   sk-any-filter)

;; owner rule-id conclusion done-premises remaining-premises premise-keys.
;; The premises taken so far are kept most recent first, apart from the ones
;; left, so a stored join holds each premise once.
(datatype SkeletonWaiter
   (sk-partial SkPattern Number SkFact (List SkPattern) (List SkPattern) (List SkeletonKey)))

(datatype CompletionInputs no-completion-inputs (completion-inputs SkeletonKey (List SkPattern) SkFact (List SkPattern) Bool))

(datatype ApplicationInputs
   ;; derivation pin, shared frontier, node route, entanglement, completion route
   (application-inputs Bool Bool Bool ApplicationEntanglement CompletionInputs))

;; A row: which rule over which premise keys, its conclusion and premises with
;; proof and truth-value variables unbound, and its creation number.
(datatype SkeletonIdent (sk-ident Number (List SkeletonKey) SkeletonKey))
(datatype SkeletonRow (sk-row SkeletonIdent SkFact (List SkPattern) Number))

;; A computed value: a fact with its evidence and the hashes of the keys it
;; depends on, a computation or fold result with the proof that replaces a `cpu`
;; token, or nothing.
(datatype SkeletonValue
   (sk-val SkFact EvidenceSet Number)
   (sk-goal-val Goal Proof EvidenceSet Number)
   sk-none)

;; Admission failure permits the ordinary reader; an admitted empty posterior
;; does not. Keep that distinction outside the durable value representation.
(datatype EventNetworkRead no-event-model (event-posterior SkeletonValue))

;; The merge of two views, or, for views that share an uncertain statement
;; and neither of which contains the other's evidence, the statements to
;; condition on, the union of their dependencies, and the more confident
;; view, kept when the merge is not conditioned
;; (docs/metta/overlap_conditioning.md)
(datatype SkeletonPairing (sk-paired SkeletonValue) (sk-overlap (List SkeletonKey) Number SkeletonValue))
;; Public output only; never an ordinary view or a materializable proof.
(datatype SkeletonWaitingAnswer (sk-waiting SkeletonValue))
(datatype SkeletonVersion
   ;; row creation number, row hash, view
   (sk-version Number Number SkeletonValue))

(datatype SkeletonLink
   (sk-child-link SkPattern SkPattern)
   (sk-answer-link SkPattern SkeletonKey)
   (sk-use-link SkeletonKey SkeletonKey)
   (sk-join-link SkeletonWaiter SkeletonKey))

;; creation-number key-hash key row-hash row
(datatype SkeletonItem
   (sk-row-item Number Number SkeletonKey Number SkeletonRow)
   ;; a fold to recompute at the end of a pass: fold key hash, fold key
   (sk-fold-check Number SkeletonKey))
(datatype SkeletonDelivery (sk-delivery SkPattern SkeletonKey))
;; a delivery taken off the queue with its number
(datatype SkeletonQueued (sk-queued Number SkeletonDelivery))
;; A join to read its premise's keys again: its owner, rule and the identity
;; of its stored waiter
;; (sk-defer-join!).
(datatype SkeletonJoin (sk-join SkPattern Number Number))
;; A rule to start again at its owner (sk-defer-rule!).
(datatype SkeletonDeferred (sk-deferred SkPattern Number))
(datatype SkeletonPending (sk-pending-rule Number) (sk-pending-fact SkeletonKey))

;; Store schemas and indexing contracts: prolog/store_schema.pl.
;; The bootstrap installs their specialized interfaces before loading this module.

;; --- Evaluation types and state ------------------------------------------------

;; An implication instance fold's tally, by fold hash: its KB's hazard, its
;; sample counter, and per branch (P(B|A), P(B|not A)) the segments of its
;; samples' regimes, ['regime-segment', Id, W, M] (runtime_helpers.pl,
;; regime-take!). Each member's segment per branch (0: none) and contribution,
;; by member hash and fold hash; a segment merged into another, by fold hash
;; and its id; the members reading a statement directly, by the statement's
;; key hash, so a reader's own sample is found by the keys it excludes; and the
;; folds with members to take, by fold hash.
(datatype RegimeSegment (regime-segment Number Number Number))
(datatype InstanceRegimeState (instance-regimes Number Number (List RegimeSegment) (List RegimeSegment)))

(: SourceList (Newtype Atom))
(: source-list (-[det]-> (List Atom) SourceList))
(datatype SupportCounts (support-counts Number Number Number Number Number))

(datatype SkeletonBranch (sk-cut-view (List Number) SkeletonValue))

;; Deferred exclusion reads, by row digest. MAIN requests survive queries;
;; an Assuming world keeps only its own requests until that world ends.
(datatype SkeletonBranchRequest (sk-wanted Number Number SkeletonKey Number (List Number)))

!(change-state! sk_branch_unpaid 0)


;; a key's merged value for an open pattern and no exclusion, with the
;; dependencies of the versions it merged
(datatype SkeletonMerged (sk-merged Number SkeletonKey Number SkeletonValue))

;; rows waiting for conditioning, by key and row hash, with estimated cost,
;; and the rows this evaluation paid it for; a key's merge waiting for
;; conditioning has row hash -1 (docs/metta/overlap_conditioning.md)
(datatype SkeletonRootLimit (sk-root-limit Number Number))

!(change-state! sk_input_id 0)

(: sk-node-hash (-[det]-> SkPattern Number))
(= (sk-node-hash $pattern)
   (case $pattern (
      ((CPU $_fun $args $_res) (index-hash $args))
      (($type $kbctx $_proof $_tv) (index-hash (sk-key $type $kbctx))))))

;; Whether two patterns are the node one hash stands for: the same statement
;; and context, or the same fold arguments, whatever their proof and value
;; patterns. The hash only finds candidates.
(: sk-same-node? (-[det]-> SkPattern SkPattern Bool))
(= (sk-same-node? $a $b)
   (case (data $a $b) (
      (((CPU $_f $args $_r) (CPU $_g $other $_s)) (=alpha $args $other))
      ((($type $kbctx $_p $_t) ($other-type $other-kbctx $_q $_u)) (=alpha (sk-key $type $kbctx) (sk-key $other-type $other-kbctx)))
      ($_mixed false))))

(datatype SkeletonNodeAt (sk-node-at Number SkPattern))

(datatype SkeletonPriorFold (sk-prior-fold Number Atom))
