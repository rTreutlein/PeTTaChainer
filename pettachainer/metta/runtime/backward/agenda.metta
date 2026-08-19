
(: goal-agenda-kind-requested-in-state?
   (-[det]-> AgendaKind GoalAgendaState Bool))
(= (goal-agenda-kind-requested-in-state? $kind
      (goal-agenda-state
         $_generation $_issued-revision $_issued-score
         $requested-lanes))
   (stored-list-member? $kind $requested-lanes))

(: goal-agenda-state-request
   (-[det]-> AgendaKind Number Number GoalAgendaState GoalAgendaState))
(= (goal-agenda-state-request $kind $issued-revision $issued-score
      (goal-agenda-state
         $generation $_old-revision $_old-score
         $requested-lanes))
   (goal-agenda-state
      (+ $generation 1) $issued-revision $issued-score
      (if (stored-list-member? $kind $requested-lanes)
         $requested-lanes
         (cons $kind $requested-lanes))))

(: remove-goal-agenda-kind
   (-[det]-> AgendaKind (List AgendaKind) (List AgendaKind)))
(= (remove-goal-agenda-kind $_kind ()) ())
(= (remove-goal-agenda-kind $kind (cons $first $rest))
   (if (== $kind $first)
      (remove-goal-agenda-kind $kind $rest)
      (cons $first (remove-goal-agenda-kind $kind $rest))))

(: goal-agenda-state-clear
   (-[det]-> AgendaKind GoalAgendaState GoalAgendaState))
(= (goal-agenda-state-clear $kind
      (goal-agenda-state
         $generation $issued-revision $issued-score
         $requested-lanes))
   (goal-agenda-state
      $generation $issued-revision $issued-score
      (remove-goal-agenda-kind $kind $requested-lanes)))

;; Replace a goal row's agenda state. The removal must see the exact stored
;; row, so callers pass the row they fetched via goal-by-id.
(: set-goal-agenda-state!
   (-[semidet]-> StoredGoalRow GoalAgendaState (| Bool (List $none))))
(= (set-goal-agenda-state!
      (stored-goal-row $gid $depth $goal $expanded $state)
      $next-state)
   (progn
      (remove-atom &goal
         (stored-goal-row $gid $depth $goal $expanded $state))
      (once
         (chainer-add-atom &goal
            (stored-goal-row $gid $depth $goal $expanded $next-state)))))

(: goal-agenda-kind-requested? (-[det]-> Number AgendaKind Bool))
(= (goal-agenda-kind-requested? $gid $kind)
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() false)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded $state)
             $_rest)
            (goal-agenda-kind-requested-in-state? $kind $state))))))

(: goal-agenda-bonus
   (-[det]-> (| Goal (Statement KBContext Proof TV)) Number))
(= (goal-agenda-bonus $goal)
   (let $closed-proof-bonus
      (if (goal-has-type-vars? $goal) 0.0 1.0)
      (case $goal (
         (($_type ($_kbid $_ctx $_vars) $_prf $_tv)
            $closed-proof-bonus)
         ($_other 2.0)))))

(: agenda-kind-score (-[det]-> AgendaKind Number Number))
(= (agenda-kind-score $kind $gid)
   (case $kind (
      (agenda-aggregate
         (let $hits (collapse (once (aggregate-by-id $gid)))
            (case $hits (
               (() 0.0)
               ((cons
                   (stored-aggregate-row
                      $_agg-gid $_child-gid $_args
                      $base-score $_pending $_current-pid)
                   $_rest)
                  $base-score)))))
      ($_goal-kind (goal-demand-sum $gid)))))

(: AgendaEntryDisposition Type)
(: agenda-claimed AgendaEntryDisposition)
(: agenda-retoken AgendaEntryDisposition)
(: agenda-cancelled AgendaEntryDisposition)
(: agenda-stale AgendaEntryDisposition)

(: agenda-entry-owned? (-[det]-> AgendaEntry Bool))
(= (agenda-entry-owned?
      (agenda-entry $kind $gid
         (agenda-revision-token $_demand-revision $generation)))
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() false)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded
                (goal-agenda-state
                   $current-generation $issued-revision $_issued-score
                   $requested-lanes))
             $_rest)
            (if (== $generation $current-generation)
               (goal-agenda-kind-requested-in-state? $kind
                  (goal-agenda-state
                     $current-generation $issued-revision $_issued-score
                     $requested-lanes))
               false))))))

(: goal-agenda-issued-score (-[det]-> Number Number))
(= (goal-agenda-issued-score $gid)
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() 0.0)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded
                (goal-agenda-state
                   $_generation $_issued-revision $issued-score
                   $_requested-lanes))
             $_rest)
            $issued-score)))))

(: clear-owned-goal-agenda-kind!
   (-[det]-> Number AgendaKind Number (List $none)))
(= (clear-owned-goal-agenda-kind! $gid $kind $generation)
   (let $_clear
      (collapse
         (clear-owned-goal-agenda-kind-row!
            $gid $kind $generation))
      ()))

(: clear-owned-goal-agenda-kind-row!
   (-[semidet]-> Number AgendaKind Number (List $none)))
(= (clear-owned-goal-agenda-kind-row! $gid $kind $generation)
   (let*
      (($row (goal-by-id $gid))
       ((stored-goal-row
            $_stored-gid $_depth $_goal $_expanded $state)
          $row)
       ((goal-agenda-state
            $generation $_issued-revision $_issued-score
            $_requested-lanes)
          $state)
       ($_set
          (set-goal-agenda-state! $row
             (goal-agenda-state-clear $kind $state))))
      ()))

(: claim-equal-score-goal-agenda-kind!
   (-[det]-> Number AgendaKind Number Number Number (List $none)))
(= (claim-equal-score-goal-agenda-kind!
      $gid $kind $generation $revision $score)
   (let $_claim
      (collapse
         (claim-equal-score-goal-agenda-kind-row!
            $gid $kind $generation $revision $score))
      ()))

(: claim-equal-score-goal-agenda-kind-row!
   (-[semidet]-> Number AgendaKind Number Number Number (List $none)))
(= (claim-equal-score-goal-agenda-kind-row!
      $gid $kind $generation $revision $score)
   (let*
      (($row (goal-by-id $gid))
       ((stored-goal-row
            $_stored-gid $_depth $_goal $_expanded $state)
          $row)
       ((goal-agenda-state
            $generation $_issued-revision $_issued-score
            $requested-lanes)
          $state)
       ($next-state
          (goal-agenda-state-clear $kind
             (goal-agenda-state
                $generation $revision $score
                $requested-lanes)))
       ($_set (set-goal-agenda-state! $row $next-state)))
      ()))

(: agenda-kind-runnable?
   (-[det]-> AgendaKind Number Number Bool))
(= (agenda-kind-runnable? $kind $gid $score)
   (case $kind (
      (agenda-expand
         (let $hits (collapse (once (goal-by-id $gid)))
            (case $hits (
               (() false)
               ((cons
                   (stored-goal-row
                      $_stored-gid $_depth $_goal $expanded $_state)
                   $_rest)
                  (if $expanded false (> $score 0.0)))))))
      (agenda-resume (> $score 0.0))
      (agenda-refresh true)
      (agenda-aggregate
         (if (== (collapse (once (aggregate-by-id $gid))) ())
            false
            true)))))

;; This is the sole entry validation and claim policy. Ownership is checked
;; before evaluating demand so stale entries cannot mutate the demand cache or
;; revision. An owned entry evaluates demand before comparing its token because
;; a cache miss may advance the revision. Claiming clears only its current lane.
(: claim-goal-agenda-entry!
   (-[det]-> AgendaEntry AgendaEntryDisposition))
(= (claim-goal-agenda-entry!
      (agenda-entry $kind $gid
         (agenda-revision-token $demand-revision $generation)))
   (let $entry
      (agenda-entry $kind $gid
         (agenda-revision-token $demand-revision $generation))
      (if (agenda-entry-owned? $entry)
         (let $score (agenda-kind-score $kind $gid)
            (if (== $demand-revision
                   (goal-demand-revision $gid))
               (let* (($_clear
                         (clear-owned-goal-agenda-kind!
                            $gid $kind $generation)))
                  (if (agenda-kind-runnable? $kind $gid $score)
                     agenda-claimed
                     agenda-cancelled))
               (if (== $score (goal-agenda-issued-score $gid))
                  (let $_claim
                     (claim-equal-score-goal-agenda-kind!
                        $gid $kind $generation
                        (goal-demand-revision $gid) $score)
                     (if (agenda-kind-runnable? $kind $gid $score)
                        agenda-claimed
                        agenda-cancelled))
                  (if (agenda-kind-runnable? $kind $gid $score)
                     agenda-retoken
                     (let $_clear
                        (clear-owned-goal-agenda-kind!
                           $gid $kind $generation)
                        agenda-cancelled)))))
         agenda-stale)))

(: release-pruned-agenda-entry! (-[det]-> AgendaEntry (List $none)))
(= (release-pruned-agenda-entry!
      (agenda-entry $kind $gid
         (agenda-revision-token $_demand-revision $generation)))
   (if (== $kind agenda-expand)
      (let $_clear
         (collapse
            (clear-owned-goal-agenda-kind!
               $gid agenda-expand $generation))
         ())
      ()))
