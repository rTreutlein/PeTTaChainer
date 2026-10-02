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
   (Alias (KB Statement (| ExtractValue ExtractInheritanceTV ExtractTV) $a
             (-[semidet]-> $b $c $b) AggregateFinish AggregateTVMode)))
(: GroupedFoldSpec
   (Alias (KB Statement $a (| ExtractValue ExtractInheritanceTV ExtractTV) $b
             (-[semidet]-> $c $d $c) AggregateFinish AggregateTVMode)))

;; What a value belongs to: a statement in a context, a fold, or one group of
;; a grouped fold.
(: SkeletonKey Type)
;; A fold's arguments come out of a CPU goal, whose arguments are polymorphic;
;; they are typed as a fold spec once, where the fold is computed.
(: sk-key (-[det]-> Statement KBContext SkeletonKey))
(: sk-fold (-[det]-> $spec SkeletonKey))
(: sk-group (-[det]-> $spec SkeletonKey))

;; owner rule-id conclusion premises remaining-premises premise-keys
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
(: sk-val (-[det]-> SkFact (List Evidence) Number SkeletonValue))
(: sk-goal-val (-[det]-> Goal Proof (List Evidence) Number SkeletonValue))
(: sk-none SkeletonValue)
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
(: SkeletonDirty Type)
(: sk-dirty (-[det]-> SkeletonKey SkeletonDirty))
(: SkeletonFresh Type)
(: sk-fresh (-[det]-> SkPattern SkeletonFresh))
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

;; --- Spaces -------------------------------------------------------------------

(: &sk_expanded (SpaceOf (Number SkPattern)))
!(bind! &sk_expanded (new-space))
;; expanded fact patterns by a copy of their statement and context, so
;; activation finds the ones a new fact or rule conclusion unifies with in one
;; match and gets them back uninstantiated
(: &sk_node_terms (SpaceOf (Statement KBContext SkPattern)))
!(bind! &sk_node_terms (new-space))
(: &sk_answer (SpaceOf (Number SkPattern SkeletonKey)))
!(bind! &sk_answer (new-space))
;; partial joins waiting on a node
(: &sk_wait (SpaceOf (Number SkPattern SkeletonWaiter)))
!(bind! &sk_wait (new-space))
(: &sk_child (SpaceOf (Number SkPattern SkPattern)))
!(bind! &sk_child (new-space))
(: &sk_row (SpaceOf (Number SkeletonKey Number SkeletonRow)))
!(bind! &sk_row (new-space))
;; child links, answers and use edges already recorded, by link hash
(: &sk_link (SpaceOf (Number SkeletonLink)))
!(bind! &sk_link (new-space))
;; member key -> a fold or group key over it
(: &sk_use (SpaceOf (Number SkeletonKey SkeletonKey)))
!(bind! &sk_use (new-space))
;; base-rate fold -> a member that joined or changed since the fold last took it
(: &sk_rate_dirty (SpaceOf (Number SkeletonKey SkeletonKey)))
!(bind! &sk_rate_dirty (new-space))
;; base-rate cache pattern hash -> a fold key reading that pattern's entries
(: &sk_rate_folds (SpaceOf (Number SkeletonKey)))
!(bind! &sk_rate_folds (new-space))
;; key -> a row reading it directly, by row key hash and row hash
(: &sk_reader (SpaceOf (Number SkeletonKey Number Number)))
!(bind! &sk_reader (new-space))
;; key -> the fact a forward run stored for it in &kb, with its value's
;; evidence and what that value was derived through
(: &sk_forward_stored (SpaceOf (Number SkeletonKey SkFact (List Evidence) Number)))
!(bind! &sk_forward_stored (new-space))
;; key -> a stale row that read it, by row key hash and row hash
(: &sk_stale_reader (SpaceOf (Number SkeletonKey Number Number)))
!(bind! &sk_stale_reader (new-space))
;; fold node -> member node
(: &sk_fold (SpaceOf (Number SkPattern SkPattern)))
!(bind! &sk_fold (new-space))
;; member node -> fold node
(: &sk_member_of (SpaceOf (Number SkPattern SkPattern)))
!(bind! &sk_member_of (new-space))
;; group key -> its grouped fold node
(: &sk_group_of (SpaceOf (Number SkeletonKey SkPattern)))
!(bind! &sk_group_of (new-space))
;; each row's and fold's latest view, and the views it replaced
(: &sk_latest (SpaceOf (Number SkeletonKey SkeletonVersion)))
!(bind! &sk_latest (new-space))
(: &sk_view (SpaceOf (Number SkeletonKey Number SkeletonValue)))
!(bind! &sk_view (new-space))
;; every dependency a row's views ever had, by key hash and row hash
(: &sk_support (SpaceOf (Number Number Number)))
!(bind! &sk_support (new-space))
;; a key's merged value for an open pattern and no exclusion, with the
;; dependencies of the versions it merged
(: SkeletonMerged Type)
(: sk-merged (-[det]-> Number SkeletonKey Number SkeletonValue SkeletonMerged))
(: &sk_merged (SpaceOf (sk-merged Number SkeletonKey Number SkeletonValue)))
!(bind! &sk_merged (new-space))
;; rows not evaluated yet, and the rows one evaluation scheduled per pass
(: &sk_new (SpaceOf (sk-row-item Number Number SkeletonKey Number SkeletonRow)))
!(bind! &sk_new (new-space))
(: &sk_queued (SpaceOf (Number Number Number)))
!(bind! &sk_queued (new-space))
;; fold key hash -> hash of a member key that changed since the fold's check
(: &sk_fold_pending (SpaceOf (Number Number)))
!(bind! &sk_fold_pending (new-space))
;; rows waiting for conditioning, by key and row hash, with its cost bound,
;; and the rows this evaluation paid it for
(: &sk_given_pending (SpaceOf (Number Number Number)))
!(bind! &sk_given_pending (new-space))
(: &sk_given_granted (SpaceOf (Number Number)))
!(bind! &sk_given_granted (new-space))
;; keys whose value changed outside evaluation
(: &sk_dirty (SpaceOf (sk-dirty SkeletonKey)))
!(bind! &sk_dirty (new-space))
;; rules and facts added since the last activation
(: &sk_pending_rules (SpaceOf (sk-pending-rule Number)))
!(bind! &sk_pending_rules (new-space))
(: &sk_pending_facts (SpaceOf (sk-pending-fact SkeletonKey)))
!(bind! &sk_pending_facts (new-space))
;; new answers waiting to reach the joins on their node
;; by a unique delivery number: nodes may unify, so a delivery is removed by
;; its number, never by its pattern
(: &sk_answer_queue (SpaceOf (Number SkeletonDelivery)))
!(bind! &sk_answer_queue (new-space))
;; deliveries an earlier query left over, by node hash
(: &sk_parked (SpaceOf (Number Number SkeletonDelivery)))
!(bind! &sk_parked (new-space))
;; joins an answer reached after the row allowance ran out, by owner hash and
;; join hash
(: &sk_deferred_joins (SpaceOf (Number Number SkeletonJoin)))
!(bind! &sk_deferred_joins (new-space))
;; rows found after the row allowance ran out, by owner hash and row hash
(: &sk_deferred
   (SpaceOf (Number Number (sk-deferred SkPattern Number SkFact (List SkPattern) (List SkeletonKey)))))
!(bind! &sk_deferred (new-space))
;; rows and waiters created from query-local rules, removed after the query
(: &sk_temp_rows (SpaceOf (Number SkeletonKey Number SkeletonRow)))
!(bind! &sk_temp_rows (new-space))
(: &sk_temp_waits (SpaceOf (Number SkPattern SkeletonWaiter)))
!(bind! &sk_temp_waits (new-space))
;; children linked since the walk last looked
(: &sk_fresh (SpaceOf (sk-fresh SkPattern)))
!(bind! &sk_fresh (new-space))
;; each expanded or linked node's search score: the best value a join
;; waiting on it assigned
(: &sk_score (SpaceOf (Number SkPattern Number)))
!(bind! &sk_score (new-space))
;; rows one evaluation must recompute for a change from outside it, with the
;; changed keys that forced them, and which row was already forced by which
(: &sk_forced (SpaceOf (Number Number Number)))
!(bind! &sk_forced (new-space))
(: &sk_forced_used (SpaceOf (Number Number Number)))
!(bind! &sk_forced_used (new-space))
;; fact keys that answered a node, by key hash, and by their statement and
;; context for structural lookup
(: &sk_keys (SpaceOf (Number SkeletonKey)))
!(bind! &sk_keys (new-space))
(: &sk_key_terms (SpaceOf (Statement KBContext Number)))
!(bind! &sk_key_terms (new-space))
;; the same keys by statement prefix, as &kb_prefix and &kb_open index &kb:
;; ground keys under each prefix hash, keys with variables apart
(: &sk_key_prefix (SpaceOf (Number Statement KBContext Number)))
!(bind! &sk_key_prefix (new-space))
(: &sk_key_open (SpaceOf (Statement KBContext Number)))
!(bind! &sk_key_open (new-space))
;; per reading key: the hashes of the keys unifying with it, its own first
(: &sk_unifiers (SpaceOf (Number SkeletonKey (List Number))))
!(bind! &sk_unifiers (new-space))
;; reading keys with a cached set, by a copy of their statement and context
(: &sk_reader_terms (SpaceOf (Statement KBContext Number SkeletonKey)))
!(bind! &sk_reader_terms (new-space))
;; (kb pattern) of a fold's compiled member goal, by hash
(: &sk_fold_members (SpaceOf (Number Atom SkPattern)))
!(bind! &sk_fold_members (new-space))
;; (kb subject concept) of the Member producers installed, by hash
(: &sk_member_rules (SpaceOf (Number Atom)))
!(bind! &sk_member_rules (new-space))
;; the current query's roots
(: &sk_roots (SpaceOf (Number SkPattern)))
!(bind! &sk_roots (new-space))
;; nodes the current walk visited
(: &sk_seen (SpaceOf (Number SkPattern)))
!(bind! &sk_seen (new-space))
;; keys the current query's roots read, directly or through rows and folds,
;; with the fewest such steps from a root
(: &sk_needed (SpaceOf (Number SkeletonKey Number)))
!(bind! &sk_needed (new-space))
;; rows whose inputs changed while no query needed them, by key and row hash
(: &sk_stale (SpaceOf (Number Number)))
!(bind! &sk_stale (new-space))
;; stale rows the current query needs, recomputed by its evaluation
(: &sk_refresh (SpaceOf (Number Number)))
!(bind! &sk_refresh (new-space))
;; rows the evaluation needs that the stale cascade reached while it ran, by
;; key and row hash, and those it brought current again already
(: &sk_restale (SpaceOf (Number Number)))
!(bind! &sk_restale (new-space))
(: &sk_restaled (SpaceOf (Number Number)))
!(bind! &sk_restaled (new-space))

;; --- Query metrics ------------------------------------------------------------

;; Opt-in diagnostic counters kept natively; reasoning never reads them.
(: query_metrics_enabled (-[det]-> Bool))
(: query_metrics_set_enabled (-[det]-> Bool Bool))
(: query_metric_value (-[det]-> Atom Number))
(: query_metric_set (-[det]-> Atom Number Number))
(: query_metric_increment (-[det]-> Atom Number))

;; --- Journal ------------------------------------------------------------------

;; Nothing has been expanded before the first query, so bulk loading journals
;; nothing.
(: sk-note-rule! (-[det]-> Number Atom))
(= (sk-note-rule! $id)
   (if (not (== (collapse (once (match &sk_expanded ($_hash $_pattern) true))) ()))
      (let $_row (add-atom &sk_pending_rules (sk-pending-rule $id)) ())
      ()))

(: sk-note-fact! (-[det]-> Statement KBContext Atom))
(= (sk-note-fact! $type $kbctx)
   (let* (($key (sk-key $type $kbctx))
          ($_pending
             (if (not (== (collapse (once (match &sk_expanded ($_hash $_pattern) true))) ()))
                (let $_pending-row (add-atom &sk_pending_facts (sk-pending-fact $key)) ())
                ()))
          ($_dirty
             (if (not (== (collapse (once (match &sk_latest ($_hash $_key $_version) true))) ()))
                (let $_dirty-row (add-atom &sk_dirty (sk-dirty $key)) ())
                ())))
      ()))
