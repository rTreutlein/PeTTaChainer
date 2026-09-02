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
               (match &aggregate
                  (stored-aggregate-row
                     $gid $_child $_args $base-score
                     $_pending $_current)
                  $base-score))))
      (goal-demand-sum $gid)))

(: goal-agenda-kind-requested-in-state?
   (-[det]-> AgendaKind GoalAgendaState Bool))
(= (goal-agenda-kind-requested-in-state? $kind
      (goal-agenda-state
         $_generation $_issued-revision $_issued-score $requested-lanes))
   (stored-list-member? $kind $requested-lanes))

(: remove-goal-agenda-kind
   (-[det]-> AgendaKind (List AgendaKind) (List AgendaKind)))
(= (remove-goal-agenda-kind $_kind ()) ())
(= (remove-goal-agenda-kind $kind (cons $head $rest))
   (if (== $kind $head)
      (remove-goal-agenda-kind $kind $rest)
      (cons $head (remove-goal-agenda-kind $kind $rest))))

(: goal-agenda-state-request
   (-[det]-> AgendaKind Number Number GoalAgendaState GoalAgendaState))
(= (goal-agenda-state-request $kind $revision $score
      (goal-agenda-state
         $generation $_issued-revision $_issued-score $requested-lanes))
   (goal-agenda-state
      (+ $generation 1) $revision $score
      (if (stored-list-member? $kind $requested-lanes)
         $requested-lanes
         (cons $kind $requested-lanes))))

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
                $_stored-gid $_depth $_goal $_expanded $state)
             $_rest)
            (goal-agenda-kind-requested-in-state? $kind $state))))))

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

(: clear-goal-agenda-kind!
   (-[det]-> StoredGoalRow AgendaKind (List $none)))
(= (clear-goal-agenda-kind!
      (stored-goal-row
         $gid $depth $goal $expanded
         (goal-agenda-state
            $generation $issued-revision $issued-score $requested-lanes))
      $kind)
   (set-goal-agenda-state!
      (stored-goal-row
         $gid $depth $goal $expanded
         (goal-agenda-state
            $generation $issued-revision $issued-score $requested-lanes))
      (goal-agenda-state
         $generation $issued-revision $issued-score
         (remove-goal-agenda-kind $kind $requested-lanes))))

(: release-pruned-agenda-entry!
   (-[det]-> AgendaEntry (List $none)))
(= (release-pruned-agenda-entry! $entry)
   (let $hits (collapse (once (goal-by-id
      (case $entry (
         ((agenda-entry $_kind $gid $_token) $gid))))))
      (case $hits (
         (() ())
         ((cons $row $_rest)
            (case $entry (
               ((agenda-entry $kind $_gid $_token)
                  (if (agenda-entry-owned? $entry)
                     (let $_clear
                        (clear-goal-agenda-kind!
                           (the StoredGoalRow $row) $kind)
                        ())
                     ())))))))))

(: claim-owned-goal-agenda-entry!
   (-[det]-> StoredGoalRow AgendaEntry AgendaClaimDisposition))
(= (claim-owned-goal-agenda-entry!
      (stored-goal-row
         $gid $depth $goal $expanded
         (goal-agenda-state
            $generation $issued-revision $issued-score $requested-lanes))
      (agenda-entry $kind $gid
         (agenda-revision-token $entry-revision $generation)))
   (let* (($current-score (agenda-kind-score $kind $gid))
          ($current-revision (goal-demand-revision $gid))
          ($next-state
             (goal-agenda-state
                $generation $current-revision $current-score
                (remove-goal-agenda-kind $kind $requested-lanes)))
          ($cancelled
             (if (<= $current-score 0.0) true
                (if (== $kind agenda-expand)
                   (if
                      (not (== $entry-revision $current-revision))
                      (if (< (* $current-score 2.0) $issued-score)
                         (if (goal-has-type-vars? $goal) false
                            (let* (($key
                                       (brand ProofGoalKey
                                          (goal-key $goal)))
                                    ($hash (goal-key-hash $key)))
                               (not
                                  (==
                                     (collapse
                                        (once
                                           (match &proof_goal
                                              ($hash $_lookup-key
                                                 $stored-key $_pid)
                                              (if (=alpha $stored-key $key)
                                                 true
                                                 (empty)))))
                                     ()))))
                         false)
                      false)
                   false))))
      (if $cancelled
         (let $_clear
            (set-goal-agenda-state!
               (stored-goal-row
                  $gid $depth $goal $expanded
                  (goal-agenda-state
                     $generation $issued-revision $issued-score
                     $requested-lanes))
               $next-state)
            agenda-cancelled)
         (if (not (== $current-score $issued-score))
            (let $_refresh
               (set-goal-agenda-state!
                  (stored-goal-row
                     $gid $depth $goal $expanded
                     (goal-agenda-state
                        $generation $issued-revision $issued-score
                        $requested-lanes))
                  (goal-agenda-state
                     $generation $current-revision $current-score
                     $requested-lanes))
               agenda-retoken)
            (let $_clear
               (set-goal-agenda-state!
                  (stored-goal-row
                     $gid $depth $goal $expanded
                     (goal-agenda-state
                        $generation $issued-revision $issued-score
                        $requested-lanes))
                  $next-state)
               agenda-claimed)))))

(: claim-goal-agenda-entry!
   (-[det]-> AgendaEntry AgendaClaimDisposition))
(= (claim-goal-agenda-entry! $entry)
   (case $entry (
      ((agenda-entry $kind $gid
          (agenda-revision-token $revision $generation))
         (let $hits (collapse (once (goal-by-id $gid)))
            (case $hits (
               (() agenda-cancelled)
               ((cons
                   (stored-goal-row
                      $_stored-gid $_depth $_goal $_expanded
                      (goal-agenda-state
                         $stored-generation $stored-revision
                         $_issued-score $requested-lanes))
                   $_rest)
                  (if
                     (not (== $generation $stored-generation))
                     agenda-stale
                     (if
                        (not
                           (stored-list-member?
                              $kind $requested-lanes))
                        agenda-cancelled
                        (claim-owned-goal-agenda-entry!
                           (stored-goal-row
                              $_stored-gid $_depth $_goal $_expanded
                              (goal-agenda-state
                                 $stored-generation $stored-revision
                                 $_issued-score $requested-lanes))
                           $entry)))))))))))
