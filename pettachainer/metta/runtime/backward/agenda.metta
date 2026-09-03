;; Agenda entry ownership: which queued token for a goal is allowed to run.
;;
;; This layer owns the goal-agenda-state row stored on each goal row — a
;; generation counter, the demand revision and score a token was issued at,
;; and the set of requested lanes — together with the request, claim, clear,
;; and release operations over it. A heap entry is only a token; this row is
;; the lock. At pop time an entry runs only if it still owns its lane, its
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

(: remove-goal-agenda-kind
   (-[det]-> AgendaKind (List AgendaKind) (List AgendaKind)))
(= (remove-goal-agenda-kind $_kind ()) ())
(= (remove-goal-agenda-kind $kind (cons $head $rest))
   (if (== $kind $head)
      (remove-goal-agenda-kind $kind $rest)
      (cons $head (remove-goal-agenda-kind $kind $rest))))

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

(: goal-agenda-kind-requested?
   (-[det]-> Number AgendaKind Bool))
(= (goal-agenda-kind-requested? $gid $kind)
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() false)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded
                (goal-agenda-state
                   $_generation $_issued-revision $_issued-score
                   $requested-lanes))
             $_rest)
            (stored-list-member? $kind $requested-lanes))))))

(: agenda-entry-owned? (-[det]-> AgendaEntry Bool))
(= (agenda-entry-owned?
      (agenda-entry $kind $gid
         (agenda-revision-token $_revision $generation)))
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() false)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded
                (goal-agenda-state
                   $stored-generation $_stored-revision
                   $_issued-score $requested-lanes))
             $_rest)
            (and
               (== $generation $stored-generation)
               (stored-list-member? $kind $requested-lanes)))))))

(: release-pruned-agenda-entry!
   (-[det]-> AgendaEntry (List $none)))
(= (release-pruned-agenda-entry!
      (agenda-entry $kind $gid
         (agenda-revision-token $_revision $generation)))
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() ())
         ((cons
             (stored-goal-row
                $stored-gid $depth $goal $expanded
                (goal-agenda-state
                   $stored-generation $issued-revision $issued-score
                   $requested-lanes))
             $_rest)
            (if (== $generation $stored-generation)
               (if (stored-list-member? $kind $requested-lanes)
                  (set-goal-agenda-state!
                     (stored-goal-row
                        $stored-gid $depth $goal $expanded
                        (goal-agenda-state
                           $stored-generation $issued-revision
                           $issued-score $requested-lanes))
                     (goal-agenda-state
                        $stored-generation $issued-revision $issued-score
                        (remove-goal-agenda-kind $kind $requested-lanes)))
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
                   $issued-score $requested-lanes))
             $_rest)
            (if (not (== $generation $stored-generation))
               agenda-stale
               (if (not (stored-list-member? $kind $requested-lanes))
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
                                                                $_lkey $stored-key
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
                                     $issued-score $requested-lanes))
                               (goal-agenda-state
                                  $generation $current-revision $current-score
                                  (if (== $disposition agenda-retoken)
                                     $requested-lanes
                                     (remove-goal-agenda-kind
                                        $kind $requested-lanes))))))
                     $disposition))))))))
