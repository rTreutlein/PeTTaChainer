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

(: remove-data-rows! (-[det]-> Atom $pattern Bool))
(: remove-variant-row! (-[det]-> Atom $row Bool))

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
(: SkeletonKey Type)
;; A fold's arguments come out of a CPU goal, whose arguments are polymorphic;
;; they are typed as a fold spec once, where the fold is computed.
(: sk-key (-[det]-> Statement KBContext SkeletonKey))
(: sk-fold (-[det]-> $spec SkeletonKey))
(: sk-group (-[det]-> $spec SkeletonKey))
(: sk-prior (-[det]-> $spec SkeletonKey))
(: sk-evidence (-[det]-> $spec SkeletonKey))

;; a key a conditioned read takes as known true or false, or a complete
;; statement a closed read takes as unfounded (docs/metta/complete_predicates.md)
(: SkeletonGiven Type)
(: sk-given (-[det]-> Number SkeletonKey Bool SkeletonGiven))
(: sk-unfounded (-[det]-> Number SkeletonKey SkeletonGiven))

(: SkeletonFilter Type)
;; the proof and truth-value pattern a consumer asks for
(: sk-filter (-[det]-> Proof TV SkeletonFilter))
(: sk-any-filter SkeletonFilter)

;; owner rule-id conclusion done-premises remaining-premises premise-keys.
;; The premises taken so far are kept most recent first, apart from the ones
;; left, so a stored join holds each premise once.
(: SkeletonWaiter Type)
(: sk-partial
   (-[det]-> SkPattern Number SkFact (List SkPattern) (List SkPattern) (List SkeletonKey)
       SkeletonWaiter))

;; A row: which rule over which premise keys, its conclusion and premises with
;; proof and truth-value variables unbound, and its creation number.
(: SkeletonIdent Type)
(: sk-ident (-[det]-> Number (List SkeletonKey) SkeletonKey SkeletonIdent))
(: SkeletonRow Type)
(: sk-row (-[det]-> SkeletonIdent SkFact (List SkPattern) Number SkeletonRow))

;; A computed value: a fact with its evidence and the hashes of the keys it
;; depends on, a computation or fold result with the proof that replaces a `cpu`
;; token, or nothing.
(: SkeletonValue Type)
(: sk-val (-[det]-> SkFact EvidenceSet Number SkeletonValue))

;; The merge of two views, or, for views that share an uncertain statement
;; and neither of which contains the other's evidence, the statements to
;; condition on, the union of their dependencies, and the more confident
;; view, kept when the merge is not conditioned
;; (docs/metta/overlap_conditioning.md)
(: SkeletonPairing Type)
(: sk-paired (-[det]-> SkeletonValue SkeletonPairing))
(: sk-overlap (-[det]-> (List SkeletonKey) Number SkeletonValue SkeletonPairing))
;; Two views of one statement merged (backward/evaluation.metta); stored facts
;; merge by it too (forward/schema.metta).
(: sk-merge-facts
   (-[semidet]-> Bool (List Number) SkFact EvidenceSet Number SkFact EvidenceSet Number
       SkeletonPairing))
(: sk-goal-val (-[det]-> Goal Proof EvidenceSet Number SkeletonValue))
(: sk-none SkeletonValue)
;; Public output only; never an ordinary view or a materializable proof.
(: SkeletonWaitingAnswer Type)
(: sk-waiting (-[det]-> SkeletonValue SkeletonWaitingAnswer))
(: SkeletonVersion Type)
;; row creation number, row hash, view
(: sk-version (-[det]-> Number Number SkeletonValue SkeletonVersion))

(: SkeletonLink Type)
(: sk-child-link (-[det]-> SkPattern SkPattern SkeletonLink))
(: sk-answer-link (-[det]-> SkPattern SkeletonKey SkeletonLink))
(: sk-use-link (-[det]-> SkeletonKey SkeletonKey SkeletonLink))
(: sk-join-link (-[det]-> SkeletonWaiter SkeletonKey SkeletonLink))

;; creation-number key-hash key row-hash row
(: SkeletonItem Type)
(: sk-row-item (-[det]-> Number Number SkeletonKey Number SkeletonRow SkeletonItem))
;; a fold to recompute at the end of a pass: fold key hash, fold key
(: sk-fold-check (-[det]-> Number SkeletonKey SkeletonItem))
(: SkeletonDelivery Type)
(: sk-delivery (-[det]-> SkPattern SkeletonKey SkeletonDelivery))
;; a delivery taken off the queue with its number
(: SkeletonQueued Type)
(: sk-queued (-[det]-> Number SkeletonDelivery SkeletonQueued))
(: SkeletonJoin Type)
(: sk-join (-[det]-> SkeletonWaiter SkeletonKey SkeletonJoin))
(: SkeletonDeferred Type)
(: sk-deferred
   (-[det]-> SkPattern Number SkFact (List SkPattern) (List SkeletonKey) SkeletonDeferred))
(: SkeletonPending Type)
(: sk-pending-rule (-[det]-> Number SkeletonPending))
(: sk-pending-fact (-[det]-> SkeletonKey SkeletonPending))

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
(: RegimeSegment Type)
(: regime-segment (-[det]-> Number Number Number RegimeSegment))
(: InstanceRegimeState Type)
(: instance-regimes (-[det]-> Number Number (List RegimeSegment) (List RegimeSegment) InstanceRegimeState))
;; A branch's sample taken into its segments, the segments and the member's
;; segment after it; and the segments' evidence (runtime_helpers.pl).
(: regime-take! (-[det]-> Number Number Number (List RegimeSegment) Number BaseRateEvidenceState BaseRateEvidenceState ((List RegimeSegment) Number)))
(: regime-evidence (-[det]-> Number (List RegimeSegment) BaseRateEvidenceState))

(: SourceList (Newtype Atom))
(: source-list (-[det]-> (List Atom) SourceList))
(: source-list-union (-[det]-> SourceList SourceList SourceList))
(: SupportCounts Type)
(: support-counts (-[det]-> Number Number Number Number Number SupportCounts))
(: observation-keys (-[det]-> SourceList (List Number)))
(: observation-sources (-[det]-> (| EvidenceSet Evidence) SourceList))
(: update-likelihood-support! (-[det]-> Atom Atom SourceList Number Number Bool))
(: likelihood-support-counts (-[det]-> Atom SupportCounts))
(: likelihood-sources (-[det]-> Atom Number SourceList))
(: likelihood-support-admissible? (-[det]-> Atom SourceList Bool))

(: SkeletonBranch Type)
(: sk-cut-view (-[det]-> (List Number) SkeletonValue SkeletonBranch))

;; Deferred exclusion reads, by row digest. MAIN requests survive queries;
;; an Assuming world keeps only its own requests until that world ends.
(: SkeletonBranchRequest Type)
(: sk-wanted (-[det]-> Number Number SkeletonKey Number (List Number) SkeletonBranchRequest))

!(change-state! sk_branch_budget 0)
!(change-state! sk_root_claim_budget 0)
!(change-state! sk_root_claim_cap 0)
;; The ordinary readers being computed, innermost first (runtime_helpers.pl).
;; Nested evaluations carry exclusions, so they leave the stack in place. A
;; reader is a row's identity, not its whole row.
(: sk-push-reader! (-[det]-> (Number SkeletonKey Number) Atom))
(: sk-restore-readers! (-[det]-> Atom Bool))
(: sk-active-reader (-[nondet]-> (Number SkeletonKey Number)))
!(change-state! sk_branch_unpaid 0)
!(change-state! sk_representative_budget 0)

!(change-state! sk_branch_at 0)

;; a key's merged value for an open pattern and no exclusion, with the
;; dependencies of the versions it merged
(: SkeletonMerged Type)
(: sk-merged (-[det]-> Number SkeletonKey Number SkeletonValue SkeletonMerged))

;; rows waiting for conditioning, by key and row hash, with estimated cost,
;; and the rows this evaluation paid it for; a key's merge waiting for
;; conditioning has row hash -1 (docs/metta/overlap_conditioning.md)
(: SkeletonRootLimit Type)
(: sk-root-limit (-[det]-> Number Number SkeletonRootLimit))

!(change-state! sk_input_id 0)

(: sk-input-changed! (-[det]-> KB Atom))
(= (sk-input-changed! $kb)
   (let* (($epoch (next-search-id sk_input_id))
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
(: SkeletonHold Type)
(: sk-stale-input SkeletonHold)
(: sk-branch-hold (-[det]-> Number SkeletonKey Number (List Number) SkeletonHold))

;; --- Query metrics ------------------------------------------------------------

;; Inference time, process-wide (runtime_helpers.pl); reasoning never reads it.
(: inference-clock (-[det]-> Number))
(: inference-add! (-[det]-> Number Bool))

;; Opt-in diagnostic counters kept natively; reasoning never reads them.
(: query_metrics_enabled (-[det]-> Bool))
(: query_metrics_set_enabled (-[det]-> Bool Bool))
(: query_metric_value (-[det]-> Atom Number))
(: query_metric_set (-[det]-> Atom Number Number))
(: query_metric_increment (-[det]-> Atom Number))

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

;; MAIN identity and mutable evaluation scope are separate. These native
;; operations own Assuming's read-through value overlay.
(: context-add! (-[det]-> Atom $row Bool))
(: context-remove! (-[det]-> Atom $row Bool))
(: set-context-reuse-threshold (-[det]-> Number Bool))
(: context-searching? (-[det]-> Atom Bool))
(: context-rule-visible? (-[det]-> Number Bool))
(: context-search-goal (-[det]-> SkPattern SkPattern))
(: context-answer-seeds! (-[det]-> SkPattern Bool))
(: context-seeded? (-[det]-> Statement KBContext Bool))
(: context-addition (-[det]-> RuntimeAddition RuntimeAddition))
(: context-note-rule! (-[det]-> Number SkFact Bool))
(: context-leaves (-[det]-> SkeletonKey (List SkFact)))
(: context-finish! (-[semidet]-> Number Number (List SkPattern) (List (List RuntimeResult)) (List (List RuntimeResult))))
(: context-clear! (-[det]-> Bool))

(: context-rule-premises (-[det]-> SkFact (List SkPattern) (List SkPattern)))

(: context-propagate? (-[semidet]-> SkeletonKey Bool))

(: context-rule-enabled? (-[det]-> Atom Bool))

(: context-start! (-[det]-> Bool))

(: context-cold-merged (-[semidet]-> Number SkeletonKey SkeletonFilter SkeletonMerged))
