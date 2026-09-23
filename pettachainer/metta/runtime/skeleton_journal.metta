;; Skeleton spaces and the ingestion journal.
;;
;; The backward chainer keeps a durable skeleton: expanded goal patterns, their
;; answers, complete rule instances (rows), and partial joins waiting on a
;; premise. Truth values are never stored there; evaluation computes them and keeps
;; each row's view in &sk_view until something below it changes.
;;
;; This module loads before every writer of &kb and of the rule spaces so they
;; can journal their additions. Ingestion only records; the next query
;; activates new facts and rules against already-expanded patterns.

;; (node-hash pattern)
!(bind! &sk_expanded (new-space))
;; (head pattern): expanded fact patterns by statement head, for activation
!(bind! &sk_node_head (new-space))
;; (node-hash pattern key)
!(bind! &sk_answer (new-space))
;; (node-hash pattern waiter): a partial join or a group fold waiting on a node
!(bind! &sk_wait (new-space))
;; (node-hash pattern child-pattern)
!(bind! &sk_child (new-space))
;; (key-hash key row-hash (row-ident conclusion premises))
!(bind! &sk_row (new-space))
;; (link-hash (kind from to)): child links, answers and use edges already
;; recorded
!(bind! &sk_link (new-space))
;; (key-hash key parent-key): the parent's value depends on key
!(bind! &sk_use (new-space))
;; (fold-args-hash fold-node member-pattern)
!(bind! &sk_fold (new-space))
;; (member-node-hash member-pattern fold-node)
!(bind! &sk_member_of (new-space))
;; (group-key-hash group-key group-node)
!(bind! &sk_group_of (new-space))
;; (key-hash key row-hash view): the current view of each row and fold
!(bind! &sk_view (new-space))
;; One evaluation's reachable keys (key-hash key), reachable rows by creation
;; number (seq item), and the keys whose views each pass changed
;; (sk-changed pass key-hash)
!(bind! &sk_reach (new-space))
!(bind! &sk_order (new-space))
!(bind! &sk_changed (new-space))
;; (sk-dirty key): cached evaluations above key are stale
!(bind! &sk_dirty (new-space))
;; (sk-pending-rule id) and (sk-pending-fact key)
!(bind! &sk_pending (new-space))
;; (sk-delivery node key): new answers waiting to reach the joins on their node
!(bind! &sk_answer_queue (new-space))
;; (sk-deferred owner rule conclusion premises keys): rows found after the
;; budget ran out
!(bind! &sk_deferred (new-space))
;; rows and waiters created from query-local rules, removed after the query
!(bind! &sk_temp (new-space))
;; (sk-fresh pattern): children linked since the walk last looked
!(bind! &sk_fresh (new-space))
;; (node-hash pattern): nodes visited by the current search walk
!(bind! &sk_seen (new-space))
;; (key-hash key): keys already invalidated by the current dirty walk
!(bind! &sk_dirty_seen (new-space))

(: SkeletonKey Type)
(: sk-key (-[det]-> Atom Atom SkeletonKey))
(: sk-fold (-[det]-> Atom SkeletonKey))
(: sk-group (-[det]-> Atom SkeletonKey))

(: SkeletonDirty Type)
(: sk-dirty (-[det]-> Atom SkeletonDirty))

(: SkeletonFresh Type)
(: sk-fresh (-[det]-> Atom SkeletonFresh))
(: SkeletonDelivery Type)
(: sk-delivery (-[det]-> Atom Atom SkeletonDelivery))
(: SkeletonDeferred Type)
(: sk-deferred (-[det]-> Atom Atom Atom Atom Atom SkeletonDeferred))

(: SkeletonPending Type)
(: sk-pending-rule (-[det]-> Number SkeletonPending))
(: sk-pending-fact (-[det]-> SkeletonKey SkeletonPending))

(: sk-space-nonempty? (-[det]-> %Undefined% Bool))
(= (sk-space-nonempty? $space)
   (not (== (collapse (once (match $space $_row true))) ())))

;; Nothing has been expanded before the first query, so bulk loading journals
;; nothing.
(: sk-note-rule! (-[det]-> %Undefined% Atom))
(= (sk-note-rule! $id)
   (if (sk-space-nonempty? &sk_expanded)
      (let $_row (add-atom &sk_pending (sk-pending-rule $id)) ())
      ()))

(: sk-note-fact! (-[det]-> %Undefined% %Undefined% Atom))
(= (sk-note-fact! $type $kbctx)
   (let* (($key (sk-key $type $kbctx))
          ($_pending
             (if (sk-space-nonempty? &sk_expanded)
                (let $_row (add-atom &sk_pending (sk-pending-fact $key)) ())
                ()))
          ($_dirty
             (if (sk-space-nonempty? &sk_view)
                (let $_row (add-atom &sk_dirty (sk-dirty $key)) ())
                ())))
      ()))
