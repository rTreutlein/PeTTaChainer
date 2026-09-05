;; Agenda entry ownership: which queued token for a goal is allowed to run.
;;
;; This layer owns the goal-agenda-state row stored on each goal row — a
;; generation counter, the demand revision and score a token was issued at,
;; and whether work is pending. A goal has one pending operation: expansion
;; before it is expanded, then fold refreshes if it is an aggregate. Expansion
;; is claimed before the fold source exists, so those operations never coexist.
;; A heap entry is only a token; this row is the lock. At pop time an entry runs
;; only if it still owns the pending operation, its
;; demand revision is current, and its score matches what was issued;
;; otherwise it is stale, cancelled, or reissued.
;;
;; It exists because the agenda heap cannot be edited in place: goals are
;; re-enqueued freely and correctness lives entirely in validation at pop.
;; Concentrating that policy here means the scheduler never reasons about
;; stale entries itself — claim-goal-agenda-entry! is the sole gate — and
;; ownership is decided before demand is evaluated, so a dead token can
;; never mutate the demand cache or revision.
;;
;; A re-woken closed expansion whose demand revision advanced and whose
;; score collapsed is cancelled at pop when an alpha-equivalent durable
;; proof already exists — reissuing it would re-run satisfied work.
;; Ordinary claims pay no proof bookkeeping; that lookup belongs to this
;; rare re-wake path only.

(: AgendaClaimDisposition Type)
(: agenda-stale AgendaClaimDisposition)
(: agenda-cancelled AgendaClaimDisposition)
(: agenda-retoken AgendaClaimDisposition)
(: agenda-claimed AgendaClaimDisposition)

(: agenda-kind-score (-[det]-> AgendaKind Number Number))
(= (agenda-kind-score $_kind $gid)
   (if (== $_kind agenda-aggregate)
      (chainer-first-or 0.0
         (collapse
            (once
               (match &fold_source
                  (fold-source-row
                     $gid $_child $_args $base-score
                     $_budget $_approx)
                  $base-score))))
      (goal-demand-sum $gid)))

(: set-goal-agenda-state!
   (-[det]-> StoredGoalRow GoalAgendaState (List $none)))
(= (set-goal-agenda-state!
      (stored-goal-row
         $gid $depth $goal $expanded $agenda-state)
      $next-state)
   (let* (($_remove
              (remove-atom &goal
                 (stored-goal-row
                    $gid $depth $goal $expanded $agenda-state)))
           ($_add
              (collapse
                 (once
                    (chainer-add-atom &goal
                       (stored-goal-row
                          $gid $depth $goal $expanded $next-state))))))
      ()))

(: goal-agenda-requested? (-[det]-> Number Bool))
(= (goal-agenda-requested? $gid)
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() false)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded
                (goal-agenda-state
                   $_generation $_issued-revision $_issued-score
                   $requested?))
             $_rest)
            (== $requested? true))))))

(: agenda-entry-owned? (-[det]-> AgendaEntry Bool))
(= (agenda-entry-owned?
      (agenda-entry $_kind $gid
         (agenda-revision-token $_revision $generation)))
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() false)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded
                (goal-agenda-state
                   $stored-generation $_stored-revision
                   $_issued-score $requested?))
             $_rest)
            (and
               (== $generation $stored-generation)
               (== $requested? true)))))))

(: release-pruned-agenda-entry!
   (-[det]-> AgendaEntry (List $none)))
(= (release-pruned-agenda-entry!
      (agenda-entry $_kind $gid
         (agenda-revision-token $_revision $generation)))
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() ())
         ((cons
             (stored-goal-row
                $stored-gid $depth $goal $expanded
                (goal-agenda-state
                   $stored-generation $issued-revision $issued-score
                   $requested?))
             $_rest)
            (if (== $generation $stored-generation)
               (if (== $requested? true)
                  (set-goal-agenda-state!
                     (stored-goal-row
                        $stored-gid $depth $goal $expanded
                        (goal-agenda-state
                           $stored-generation $issued-revision
                           $issued-score $requested?))
                     (goal-agenda-state
                        $stored-generation $issued-revision $issued-score false))
                  ())
               ()))))))

(: claim-goal-agenda-entry!
   (-[det]-> AgendaEntry AgendaClaimDisposition))
(= (claim-goal-agenda-entry!
      (agenda-entry $kind $gid
         (agenda-revision-token $entry-revision $generation)))
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() agenda-cancelled)
         ((cons
             (stored-goal-row
                $_stored-gid $depth $goal $expanded
                (goal-agenda-state
                   $stored-generation $issued-revision
                   $issued-score $requested?))
             $_rest)
            (if (not (== $generation $stored-generation))
               agenda-stale
               (if (== $requested? false)
                  agenda-cancelled
                  (let* (($current-score (agenda-kind-score $kind $gid))
                         ($current-revision (goal-demand-revision $gid))
                         ($cancelled
                            (if (<= $current-score 0.0) true
                               (if (== $kind agenda-expand)
                                  (if
                                     (not (== $entry-revision $current-revision))
                                     (if (< (* $current-score 2.0) $issued-score)
                                        (if (goal-has-type-vars? $goal) false
                                           ;; Only a current proof justifies dropping the
                                           ;; expansion; retired proofs stay in &proof_goal.
                                           (let* (($key
                                                      (brand ProofGoalKey
                                                         (goal-key $goal)))
                                                   ($hash (index-hash $key)))
                                              (not
                                                 (==
                                                    (collapse
                                                       (once
                                                          (match &proof_current
                                                             (current-row $hash $_ohash
                                                                $stored-key
                                                                $_okey $_pid)
                                                             (if (=alpha $stored-key $key)
                                                                true
                                                                (empty)))))
                                                    ()))))
                                        false)
                                     false)
                                  false)))
                         ($disposition
                            (if $cancelled agenda-cancelled
                               (if (== $current-score $issued-score)
                                  agenda-claimed
                                  agenda-retoken)))
                         ($_state
                            (set-goal-agenda-state!
                               (stored-goal-row
                                  $gid $depth $goal $expanded
                                  (goal-agenda-state
                                     $generation $issued-revision
                                     $issued-score $requested?))
                               (goal-agenda-state
                                  $generation $current-revision $current-score
                                  (== $disposition agenda-retoken)))))
                     $disposition))))))))
