;; Skeleton types, spaces and the ingestion journal.
;;
;; The backward chainer keeps a durable skeleton: expanded goal patterns, their
;; answers, complete rule instances (rows), and partial joins waiting on a
;; premise. Truth values are never stored there; evaluation computes them and
;; keeps each row's view in &sk_view until something below it changes.
;;
;; This module loads before every writer of &kb and of the rule spaces so they
;; can journal their additions. Ingestion only records; the next query
;; activates new facts and rules against already-expanded patterns.

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
(datatype SkeletonJoin (sk-join SkeletonWaiter SkeletonKey))
(datatype SkeletonDeferred (sk-deferred SkPattern Number SkFact (List SkPattern) (List SkeletonKey)))
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

(: sk-input-changed! (-[det]-> KB Atom))
(= (sk-input-changed! $kb)
   (let* (($_catalog (source-catalog-changed! $kb))
          ($epoch (next-search-id sk_input_id))
          ($_old (context-remove! &sk_input_epoch ($kb $_epoch)))
          ($_new (context-add! &sk_input_epoch ($kb $epoch)))) ()))

(: sk-input-epoch (-[det]-> SkeletonKey Number))
(= (sk-input-epoch $key)
   (let $kb (case $key (
           ((sk-key $_type ($kbid $_ctx $_vars)) $kbid)
           (($_aggregate $args) (brand KB (car-atom $args)))))
      (chainer-first-or 0 (collapse (once (match &ctx_sk_input_epoch ($kb $epoch) $epoch))))))

(: sk-clear-root-cap! (-[det]-> Number SkeletonKey Atom))
(= (sk-clear-root-cap! $hash $key)
   (let $_cleared (collapse (match &ctx_sk_root_exhausted ($hash $stored $cap)
            (if (=alpha $stored $key)
               (context-remove! &sk_root_exhausted ($hash $stored $cap)) (empty))))
      ()))

;; Claim state: -1 outside a claim, 0/1 prepaid row credits, -2 exhausted.
;; The pass's cutset depth is 64 outside a paid pass; sk_claim_cut is 1 once
;; a nested conditioning used its approximation (see sk-deepen).
!(change-state! sk_claim_state -1)
!(change-state! sk_claim_depth 64)
!(change-state! sk_claim_cut 0)

;; A key changed again before the evaluation took it is recorded once: each
;; record schedules every reader of the key.
(: sk-dirty! (-[det]-> SkeletonKey Atom))
(= (sk-dirty! $key)
   (let $hash (index-hash $key)
      (if (== (collapse (once (match &ctx_sk_dirty ($hash $stored) (if (=alpha $stored $key) true (empty))))) ())
         (let $_row (context-add! &sk_dirty ($hash $key)) ())
         ())))

;; A deferred branch read holds its consumer only until that exact read is
;; settled. Keep ordinary stale-input debt separate: branch settlement cannot
;; discharge it.
(datatype SkeletonHold sk-stale-input (sk-branch-hold Number SkeletonKey Number (List Number)))

;; --- Query metrics ------------------------------------------------------------

;; --- Journal ------------------------------------------------------------------

;; Nothing has been expanded before the first query, so bulk loading journals
;; nothing. A new rule can also give a dormant rule's premise support, and a
;; new fact one whose search found no fact of its statement: those rules are
;; started again on the nodes already expanded (docs/metta/dormant_rules.md).
;; A forward run's copy of a derived value is no support and wakes nothing.
;; A query's own rule leaves with the query, so it wakes, as a fact does, only
;; the dormant rules whose search lacked its conclusion: dropping every
;; verdict would make each query judge every rule again.
(: sk-pend-rule! (-[det]-> Number Atom))
(= (sk-pend-rule! $id) (let $_row (add-atom &sk_pending_rules (sk-pending-rule $id)) ()))

(: sk-note-rule! (-[det]-> Number (Statement KBContext Proof TV) Atom))
(= (sk-note-rule! $id ($type $kbctx $_proof $_tv))
   (let* (($permanent (< $id 1000000000))
          ($_input (if $permanent (sk-input-changed! (brand KB (car-atom $kbctx))) ()))
          ($woken (if $permanent (rule-dormancy-reset!) (rule-dormancy-wake! $type))))
      (if (space-row-present? &sk_expanded (quote ($_hash $_pattern)))
         (foreach-flat sk-pend-rule! (cons $id $woken))
         ())))

(: sk-wake-dormant! (-[det]-> Statement Bool Atom))
(= (sk-wake-dormant! $type $expanded)
   (let $woken (rule-dormancy-wake! $type)
      (if $expanded (foreach-flat sk-pend-rule! (the (List Number) $woken)) ())))

(: sk-note-fact! (-[det]-> Statement KBContext Atom))
(= (sk-note-fact! $type $kbctx)
   (let* (($key (sk-key $type $kbctx))
          ($_input (sk-input-changed! (brand KB (car-atom $kbctx))))
          ($_cap-cleared (sk-clear-root-cap! (index-hash $key) $key))
          ($_retired (sk-retire-known! $type $kbctx))
          ($expanded (space-row-present? &sk_expanded (quote ($_hash $_pattern))))
          ($_pending
             (if $expanded
                (let $_pending-row (add-atom &sk_pending_facts (sk-pending-fact $key)) ())
                ()))
          ($_woken (if (== (search-id-value sk_forward_run) 1) () (sk-wake-dormant! $type $expanded)))
          ($_dirty
             ;; A root caches its merged value even when no row has ever
             ;; produced a version. Empty and fact-only merges need the same
             ;; dirty-key refresh as row readers; both existence probes stop
             ;; at their first entry, so ingestion stays constant cost.
             (if (if (space-row-present? &ctx_sk_latest (quote ($_hash $_key $_version))) true
                     (space-row-present? &ctx_sk_merged (quote ($_mhash $_mkey $_deps $_value $_root))))
                (sk-dirty! $key)
                ())))
      ()))


(: sk-node-hash (-[det]-> SkPattern Number))
(= (sk-node-hash $pattern)
   (case $pattern (
      ((CPU $_fun $args $_res) (index-hash $args))
      (($type $kbctx $_proof $_tv) (index-hash (sk-key $type $kbctx))))))

(datatype SkeletonNodeAt (sk-node-at Number SkPattern))

(datatype SkeletonPriorFold (sk-prior-fold Number Atom))
