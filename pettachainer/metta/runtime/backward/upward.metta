;; Forward chaining over the skeleton (docs/metta/forward_skeleton_unification.md).
;;
;; A forward run grows the skeleton upward from the keys it takes: each rule
;; with a premise matching a taken key starts a join with that premise bound,
;; whose other premises read the stored facts and the keys the skeleton
;; already has, never expanding anything. Complete joins are ordinary rows,
;; evaluated by the ordinary evaluation, so self-support, reader-specific
;; versions, conditioning and base rates behave as they do for queries.
;; A taken key's value is also stored in &kb (kb-publish-prediction!).

;; The least evidence, in observations (n = c k / (1 - c)), a derived key's
;; value needs for the run to build on it. Process-wide.
!(change-state! forward_min_evidence 1.0)

(: forward-min-evidence (-[det]-> Number))
(= (forward-min-evidence) (the Number (car-atom (collapse (get-state forward_min_evidence)))))

(: set-forward-min-evidence (-[det]-> Number Bool))
(= (set-forward-min-evidence $n) (change-state! forward_min_evidence $n))

;; --- Upward joins --------------------------------------------------------------

(: sk-forward-start-step (-[semidet]-> SkeletonKey Atom Atom Atom))
(= (sk-forward-start-step $key $_acc $trigger)
   (let $_started (collapse
      (let (sk-match $id $premises $conclusion) (discover-triggered-applications $key $trigger)
         (sk-advance! (sk-partial $conclusion $id $conclusion () $premises ())))) ()))

;; A taken key starts, for every rule premise it matches (by its statement's
;; head and by the KB-wide wildcard), a join with that premise bound to it.
(: sk-forward-start! (-[semidet]-> SkeletonKey Atom))
(= (sk-forward-start! $key)
   (case $key (
      ((sk-key $type $kbctx)
         (case (forward-premise-keys (assemble-stored-runtime-fact $type $kbctx $_proof $_tv)) (
            (($head $wildcard)
               (fold-semidet (sk-forward-start-step $key) ()
                  (if (== $head $wildcard) (cons $head ()) (cons $head (cons $wildcard ()))))))))
      ($_fold ()))))

;; A key whose value rests on less than the minimum evidence is not built on;
;; a point rests on unlimited evidence. An implication's value is read by its
;; positive branch, as its Beta is.
(: sk-forward-weak? (-[semidet]-> SkeletonKey Bool))
(= (sk-forward-weak? $key)
   (case (sk-key-value $key) (
      ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps)
         (let $read (case $tv (((CTV $pos $_neg) $pos) ($_stv $tv)))
            (let $c (tv-confidence $read) (if (>= $c 1.0) false (< (confidence-to-count $c) (forward-min-evidence))))))
      ($_none true))))

;; --- The run ----------------------------------------------------------------

(datatype SkeletonForwardItem (sk-fwd-seed SkeletonKey) (sk-fwd-key SkeletonKey) (sk-fwd-rest SkeletonKey))

;; The share of a run's units its own facts get before the carried agenda
;; competes for the rest. Process-wide.
!(change-state! forward_seed_share 1)

(: forward-seed-share (-[det]-> Number))
(= (forward-seed-share) (the Number (car-atom (collapse (get-state forward_seed_share)))))

(: set-forward-seed-share (-[det]-> Number Bool))
(= (set-forward-seed-share $share) (change-state! forward_seed_share $share))

(: sk-taken-value (-[det]-> SkeletonKey SkeletonValue))
(= (sk-taken-value $key)
   (let $hash (index-hash $key)
      (case (collapse (once (match &sk_forward_taken ($hash $stored $value)
               (if (=alpha $stored $key) $value (empty))))) (
         ((cons $value $_rest) $value)
         (() sk-none)))))

;; A key's forward bookkeeping leaves when it is replaced or the key is frozen
;; (forgetting.metta).
(: sk-forget-taken! (-[det]-> Number SkeletonKey Atom))
(= (sk-forget-taken! $hash $key)
   (let $_removed
      (collapse (match &sk_forward_taken ($hash $stored $value)
         (if (=alpha $stored $key) (remove-atom &sk_forward_taken ($hash $stored $value)) (empty))))
      ()))

(: sk-record-taken! (-[semidet]-> SkeletonKey Atom))
(= (sk-record-taken! $key)
   (let* (($hash (index-hash $key))
          ($value (sk-key-value $key))
          ($_old (sk-forget-taken! $hash $key)))
      (add-atom &sk_forward_taken ($hash $key $value))))

;; The keys of the stale rows that read a key: needing them brings the rows
;; back and recomputes them.
(: sk-stale-readers (-[det]-> SkeletonKey (List SkeletonKey)))
(= (sk-stale-readers $key)
   (let $hash (index-hash $key)
      (collapse (match &ctx_sk_stale_reader ($hash $stored $khash $rhash)
         (if (=alpha $stored $key)
            (match &sk_row ($khash $rkey $rhash (sk-row $ident $concl $premises $seq)) $rkey)
            (empty))))))

(: sk-item-key (-[det]-> SkeletonItem SkeletonKey))
(= (sk-item-key (sk-row-item $_seq $_khash $key $_rhash $_row)) $key)
(= (sk-item-key (sk-fold-check $_hash $fold)) $fold)

;; A reader whose value differs from the one a run last built on goes on the
;; agenda by how far it moved from it. Work a budget cut off is therefore found
;; again by the next run that reaches the reader.
(: sk-changed-step (-[semidet]-> (Heap SkeletonForwardItem) SkeletonKey (Heap SkeletonForwardItem)))
(= (sk-changed-step $agenda $key)
   (let* (($now (sk-key-value $key)) ($taken (sk-taken-value $key)))
      (if (sk-same-view? $now $taken) $agenda
         (add_to_heap $agenda (- 0 (sk-change $now $taken)) (sk-fwd-key $key)))))

;; Taking a key records the value built on, updates the base-rate estimates
;; over it with that value and starts the joins it triggers. A rest item only
;; computes the readers its key's first take left stale.
(: sk-forward-take! (-[semidet]-> SkeletonForwardItem SkeletonKey Atom))
(= (sk-forward-take! $item $key)
   (case $item (
      ((sk-fwd-rest $_key) ())
      ($_take
         (let* (($_taken (sk-record-taken! $key))
                ($_aggregates
                   (case (sk-key-value $key) (
                      ((sk-val $fact $_ev $_deps)
                         (case (sk-value $key sk-any-filter (forward-rate-folds $fact)) (
                            ((sk-val $counted $_cev $_cdeps) (forward-maintain-aggregates! aggregate-update $counted))
                            ($_derived (forward-maintain-aggregates! aggregate-remove $fact)))))
                      ($_none ())))))
            (sk-forward-start! $key))))))

(datatype SkeletonForwardEntry (sk-fwd-at Number SkeletonForwardItem SkeletonKey))

;; The keys of the rows reading a key, current or stale.
(: sk-reader-keys-step (-[det]-> (List SkeletonKey) SkeletonForwardEntry (List SkeletonKey)))
(= (sk-reader-keys-step $acc (sk-fwd-at $_priority $_item $key))
   (append-flat (sk-reader-keys $key) $acc))

(: sk-reader-keys (-[det]-> SkeletonKey (List SkeletonKey)))
(= (sk-reader-keys $key)
   (append-flat (map-flat sk-item-key (sk-readers $key)) (sk-stale-readers $key)))

;; A key whose readers a run left stale goes back on the agenda as a rest item.
(: sk-rest-step
   (-[det]-> (Heap SkeletonForwardItem) SkeletonForwardEntry (Heap SkeletonForwardItem)))
(= (sk-rest-step $agenda (sk-fwd-at $priority $_item $key))
   (if (== (sk-stale-readers $key) ()) $agenda (add_to_heap $agenda $priority (sk-fwd-rest $key))))

;; Once a wave's keys are taken, the run searches the folds their joins read
;; that no search expanded yet, as a query would, and evaluates every row
;; reading them in one evaluation, so a row two of them reach is computed
;; once. The readers whose value changed join the agenda, and so do the wave's
;; keys whose readers the allowance left stale.
;; Existence judgments nest the witness and floor folds. Drain those within
;; the same allowance even when no intermediate value can start another wave;
;; ordinary folds retain their next-wave scheduling.
(: sk-forward-folds! (-[semidet]-> (List SkPattern) (List SkPattern)))
(= (sk-forward-folds! $searched)
   (if (if (<= (search-id-value sk_budget) 0) true (<= (search-id-value sk_walk_budget) 0))
      $searched
      (let $folds
            (collapse (match &sk_forward_folds ($hash $fold)
               (if (sk-existential-fold? $fold)
                  (let $_removed (remove-atom &sk_forward_folds ($hash $fold)) $fold) (empty))))
         (if (== $folds ()) $searched
            (let $_walked (sk-walk! $folds) (sk-forward-folds! (append-flat $searched $folds)))))))

(: sk-forward-wave!
   (-[semidet]-> (Heap SkeletonForwardItem) (List SkeletonForwardEntry) (Heap SkeletonForwardItem)))
(= (sk-forward-wave! $agenda $entries)
   (let* (($initial-folds
             (collapse (match &sk_forward_folds ($hash $fold)
                (let $_removed (remove-atom &sk_forward_folds ($hash $fold)) $fold))))
          ($_searched (if (== $initial-folds ()) () (sk-walk! $initial-folds)))
          ($folds (sk-forward-folds!
             (collapse (let $fold (superpose $initial-folds)
                (if (sk-existential-fold? $fold) $fold (empty))))))
          ($readers (list_to_set
             (fold-flat append-flat (fold-semidet sk-reader-keys-step () $entries)
                (map-flat sk-reader-keys (fold-semidet sk-root-keys-step () $folds)))))
          ($_needed (sk-need-roots! $readers))
          ($_evaluated (sk-evaluate!))
          ($changed (fold-semidet sk-changed-step $agenda $readers)))
      (if (> (search-id-value sk_eval_budget) 0) $changed (fold-semidet sk-rest-step $changed $entries))))

(datatype SkeletonWave (sk-wave (List SkeletonForwardEntry) (Heap SkeletonForwardItem) (List SkeletonKey)))

;; A wave takes the agenda's keys in order of how far each key changed while
;; the rows they bring fit the room: new rows of their joins (rows numbered
;; since the wave began) and stale readers (counted by key hash). The key
;; that fills it is the last. A seed
;; is always taken. A derived key is not taken twice in a run, nor when its
;; value is the one last built on or rests on less than the minimum evidence.
(: sk-forward-wave
   (-[semidet]-> Number Number (Heap SkeletonForwardItem) (List SkeletonForwardEntry) (List SkeletonKey)
       SkeletonWave))
(= (sk-forward-wave $room $stale $agenda $wave $taken)
   (if (if (heap-empty? $agenda) true
          (if (== $wave ()) false (>= (+ $stale (search-id-value sk_row_seq)) $room)))
      (sk-wave $wave $agenda $taken)
      (case (heap_pop $agenda) (
         (($priority $item $rest)
            (let* (($key (case $item (((sk-fwd-seed $k) $k) ((sk-fwd-key $k) $k) ((sk-fwd-rest $k) $k))))
                   ($skip
                      (case $item (
                         ((sk-fwd-key $_k)
                            (if (stored-list-member? $key $taken) true
                               (if (sk-forward-weak? $key) true
                                  (sk-same-view? (sk-key-value $key) (sk-taken-value $key)))))
                         ($_other false)))))
               (if $skip (sk-forward-wave $room $stale $rest $wave $taken)
                  (let* (($hash (index-hash $key))
                         ($more (match-count &sk_stale_reader ($hash $_stored $_khash $_rhash)))
                         ($_taken (sk-forward-take! $item $key)))
                     (sk-forward-wave $room (+ $stale $more) $rest (cons (sk-fwd-at $priority $item $key) $wave)
                        (case $item (((sk-fwd-key $_k) (cons $key $taken)) ($_other $taken))))))))))))

(datatype SkeletonRun (sk-run (Heap SkeletonForwardItem) (List SkeletonKey)))

;; Waves run while the allowance stays above the floor and the agenda lasts.
;; Each wave commits to its one result, so the loop leaves no choice points.
;; Returns the agenda left and the derived keys taken.
(: sk-forward-loop! (-[semidet]-> Number (Heap SkeletonForwardItem) (List SkeletonKey) SkeletonRun))
(= (sk-forward-loop! $floor $agenda $taken)
   (let $room (- (search-id-value sk_eval_budget) $floor)
      (if (<= $room 0) (sk-run $agenda $taken)
         (case (sk-forward-wave $room (- 0 (search-id-value sk_row_seq)) $agenda () $taken) (
            ((sk-wave () $left $all) (sk-run $left $all))
            ((sk-wave $wave $left $all)
               (sk-forward-loop! $floor (bounded-agenda-prune (once (sk-forward-wave! $left $wave))) $all)))))))

(: sk-seed-step (-[semidet]-> (Heap SkeletonForwardItem) (Statement KBContext Proof TV) (Heap SkeletonForwardItem)))
(= (sk-seed-step $agenda ($type $kbctx $_proof $_tv))
   (let $key (sk-key $type $kbctx)
      (add_to_heap $agenda (- 0 (sk-change (sk-key-value $key) sk-none)) (sk-fwd-seed $key))))

(: sk-seed-item? (-[det]-> SkeletonForwardItem Bool))
(= (sk-seed-item? $item) (case $item (((sk-fwd-seed $_key) true) ($_other false))))

;; Carried items join the run's first part when they are seeds, the second
;; when they are not.
(: sk-carried-step
   (-[det]-> Bool (Heap SkeletonForwardItem) (Number SkeletonForwardItem) (Heap SkeletonForwardItem)))
(= (sk-carried-step $seeds $agenda ($priority $item))
   (if (== (sk-seed-item? $item) $seeds) (add_to_heap $agenda $priority $item) $agenda))

;; The carried agenda keeps every seed, which a caller chose, and the run's
;; best other items, at most the agenda bound.
(: sk-carry! (-[semidet]-> KB Number (Heap SkeletonForwardItem) Atom))
(= (sk-carry! $kb $count $agenda)
   (if (heap-empty? $agenda) ()
      (case (heap_pop $agenda) (
         (($priority $item $rest)
            (if (sk-seed-item? $item)
               (let $_kept (add-atom &sk_forward_agenda ($kb $priority $item)) (sk-carry! $kb $count $rest))
               (if (<= $count 0) (sk-carry! $kb $count $rest)
                  (let $_kept (add-atom &sk_forward_agenda ($kb $priority $item))
                     (sk-carry! $kb (- $count 1) $rest)))))))))

(: sk-key-result (-[semidet]-> (List (Statement KBContext Proof TV)) SkeletonKey (List (Statement KBContext Proof TV))))
(= (sk-key-result $results $key)
   (case (case (event-network-read $key sk-any-filter () (ev-set 0)) (
            ((event-posterior $posterior) $posterior)
            (no-event-model (sk-key-value $key)))) (
      ((sk-val $fact $ev $deps)
         (let $type (car-atom $fact)
            (if (head-is-member? $type (ExistsJudgment ExistentialAlternatives Not)) $results
               ;; A negation is a view of its statement, never stored. An open
               ;; key's value holds for every instance, and an instance query
               ;; would read a stored copy of it as a report of its own
               ;; derivation: only closed keys are stored.
               (let $_stored (if (== (extract-vars $type) ()) (kb-publish-prediction! $key (sk-val $fact $ev $deps)) ())
                  (cons $fact $results)))))
      ($_none $results))))
