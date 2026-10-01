;; Forward chaining over the skeleton (docs/metta/forward_skeleton_unification.md).
;;
;; A forward run grows the skeleton upward from the keys it takes: each rule
;; with a premise matching a taken key starts a join with that premise bound,
;; whose other premises read the stored facts and the keys the skeleton
;; already has, never expanding anything. Complete joins are ordinary rows,
;; evaluated by the ordinary evaluation, so self-support, reader-specific
;; versions, conditioning and base rates behave as they do for queries.
;; A taken key's value is also stored in &kb (sk-forward-store!).

!(import_prolog_function nth0)

;; nth0/4 removes the indexed element while unifying it with its third
;; argument. Its relational modes can branch, but every result preserves the
;; element type of the input list.
(: nth0
   (-[nondet]-> $index (List $item) $item (List $item)))

;; The least evidence, in observations (n = c k / (1 - c)), a derived key's
;; value needs for the run to build on it. Process-wide.
!(change-state! forward_min_evidence 1.0)

(: forward-min-evidence (-[det]-> Number))
(= (forward-min-evidence) (the Number (car-atom (collapse (get-state forward_min_evidence)))))

(: set-forward-min-evidence (-[det]-> Number Bool))
(= (set-forward-min-evidence $n) (change-state! forward_min_evidence $n))

;; --- Upward joins --------------------------------------------------------------

(: sk-forward-start-step (-[semidet]-> SkeletonKey Atom Atom Atom))
(= (sk-forward-start-step (sk-key $type $kbctx) $_acc $trigger)
   (let $_started
      (collapse
         (let* ((($pattern $id $idx) (match prem_index ($trigger $pattern $id $idx) ($pattern $id $idx)))
                ((runtime-rule-row $id $ccls $prems)
                   (match rules (runtime-rule-row $id $ccls $prems) (runtime-rule-row $id $ccls $prems)))
                ($_rest (nth0 $idx $prems (assemble-stored-runtime-fact $type $kbctx $_proof $_tv))))
            (if (chainer-acyclic-term? $ccls)
               (sk-advance! (sk-partial $ccls $id $ccls $prems $prems ()))
               (empty))))
      ()))

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

;; --- Change -----------------------------------------------------------------

;; A value read as a Beta distribution over its strength, from its n
;; observations; no value is Beta(1, 1).
(: sk-value-beta (-[det]-> SkeletonValue (Number Number)))
(= (sk-value-beta $value)
   (case $value (
      ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps)
         (case $tv (
            ((STV $s $c) (sk-beta-of $s $c))
            ((CTV (STV $s $c) $_negative) (sk-beta-of $s $c))
            ($_other (data 1.0 1.0)))))
      ($_none (data 1.0 1.0)))))

(: sk-beta-of (-[det]-> Number Number (Number Number)))
(= (sk-beta-of $s $c)
   (let $n (confidence-to-count $c) (data (+ (* $s $n) 1.0) (+ (* (- 1.0 $s) $n) 1.0))))

;; How far a value moved: the KL divergence of its new Beta from its old one.
(: sk-change (-[det]-> SkeletonValue SkeletonValue Number))
(= (sk-change $new $old)
   (let* ((($a1 $b1) (sk-value-beta $new))
          (($a2 $b2) (sk-value-beta $old)))
      (beta_kl $a1 $b1 $a2 $b2)))

(: sk-key-value (-[semidet]-> SkeletonKey SkeletonValue))
(= (sk-key-value $key) (sk-value $key sk-any-filter ()))

;; A key whose value rests on less than the minimum evidence is not built on.
(: sk-forward-weak? (-[semidet]-> SkeletonKey Bool))
(= (sk-forward-weak? $key)
   (case (sk-key-value $key) (
      ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps)
         (< (confidence-to-count (tv-confidence $tv)) (forward-min-evidence)))
      ($_none true))))

;; --- The run ----------------------------------------------------------------

(: SkeletonForwardItem Type)
(: sk-fwd-seed (-[det]-> SkeletonKey SkeletonForwardItem))
(: sk-fwd-key (-[det]-> SkeletonKey SkeletonForwardItem))

;; Per key, the value a forward run last built on.
(: &sk_forward_taken (SpaceOf (Number SkeletonKey SkeletonValue)))
!(bind! &sk_forward_taken (new-space))

(: sk-taken-value (-[det]-> SkeletonKey SkeletonValue))
(= (sk-taken-value $key)
   (let $hash (index-hash $key)
      (case (collapse (once (match &sk_forward_taken ($hash $stored $value)
               (if (=alpha $stored $key) $value (empty))))) (
         ((cons $value $_rest) $value)
         (() sk-none)))))

(: sk-record-taken! (-[semidet]-> SkeletonKey Atom))
(= (sk-record-taken! $key)
   (let* (($hash (index-hash $key))
          ($value (sk-key-value $key))
          ($_old (collapse (match &sk_forward_taken ($hash $stored $was)
             (if (=alpha $stored $key) (remove-atom &sk_forward_taken ($hash $stored $was)) (empty))))))
      (add-atom &sk_forward_taken ($hash $key $value))))

;; The keys of the stale rows that read a key: needing them brings the rows
;; back and recomputes them.
(: sk-stale-readers (-[det]-> SkeletonKey (List SkeletonKey)))
(= (sk-stale-readers $key)
   (let $hash (index-hash $key)
      (collapse (match &sk_stale_reader ($hash $stored $khash $rhash)
         (if (=alpha $stored $key)
            (match &sk_row ($khash $rkey $rhash (sk-row $ident $concl $premises $seq)) $rkey)
            (empty))))))

(: sk-item-key (-[det]-> SkeletonItem SkeletonKey))
(= (sk-item-key (sk-row-item $_seq $_khash $key $_rhash $_row)) $key)
(= (sk-item-key (sk-fold-check $_hash $fold)) $fold)


;; A reader whose value differs from the one a run last built on goes on the
;; agenda by how far it moved from it. Work a budget cut off is therefore found
;; again by the next run that reaches the reader.
(: sk-changed-step
   (-[semidet]-> (Heap SkeletonForwardItem) SkeletonKey (Heap SkeletonForwardItem)))
(= (sk-changed-step $agenda $key)
   (let* (($now (sk-key-value $key))
          ($taken (sk-taken-value $key)))
      (if (sk-same-view? $now $taken) $agenda
         (add_to_heap $agenda (- 0 (sk-change $now $taken)) (sk-fwd-key $key)))))

;; Taking a key records the value built on, updates the base-rate estimates
;; over it with that value, starts the joins it triggers, searches the folds
;; they read that no search expanded yet, as a query would, and evaluates every
;; row reading it. The readers whose value changed join the agenda.
(: sk-forward-take! (-[semidet]-> (Heap SkeletonForwardItem) SkeletonKey (Heap SkeletonForwardItem)))
(= (sk-forward-take! $agenda $key)
   (let* (($_taken (sk-record-taken! $key))
          ($_aggregates
             (case (sk-key-value $key) (
                ((sk-val $fact $_ev $_deps)
                   (case (sk-value $key sk-any-filter (forward-rate-folds $fact)) (
                      ((sk-val $counted $_cev $_cdeps) (forward-maintain-aggregates! aggregate-update $counted))
                      ($_derived (forward-maintain-aggregates! aggregate-remove $fact)))))
                ($_none ()))))
          ($_joins (sk-forward-start! $key))
          ($folds
             (collapse (match &sk_forward_folds ($hash $fold)
                (let $_taken (remove-atom &sk_forward_folds ($hash $fold)) $fold))))
          ($_searched (if (== $folds ()) () (sk-search! (fold-semidet (sk-push 0) (empty_heap) $folds))))
          ($readers (list_to_set (append-flat (map-flat sk-item-key (sk-readers $key)) (sk-stale-readers $key))))
          ($_needed (fold-semidet (sk-need! 0) () $readers))
          ($_evaluated (sk-evaluate!)))
      (fold-semidet sk-changed-step $agenda $readers)))

;; Each take commits to its one result, so the loop leaves no choice points.
;; The agenda takes the key that changed most. A seed is taken when it is on
;; top and costs no step; a derived key costs one, and one resting on less
;; than the minimum evidence is not taken. Returns the derived keys taken.
(: sk-forward-loop! (-[semidet]-> Number (Heap SkeletonForwardItem) (List SkeletonKey) (List SkeletonKey)))
(= (sk-forward-loop! $steps $agenda $taken)
   (if (heap-empty? $agenda) $taken
      (case (heap_pop $agenda) (
         (($_priority $item $rest)
            (case $item (
               ((sk-fwd-seed $seed) (sk-forward-loop! $steps (bounded-agenda-prune (once (sk-forward-take! $rest $seed))) $taken))
               ((sk-fwd-key $key)
                  (if (<= $steps 0) $taken
                     (if (if (stored-list-member? $key $taken) true (sk-forward-weak? $key))
                        (sk-forward-loop! $steps $rest $taken)
                        (sk-forward-loop! (- $steps 1) (bounded-agenda-prune (once (sk-forward-take! $rest $key))) (cons $key $taken))))))))))))

(: sk-seed-step (-[semidet]-> (Heap SkeletonForwardItem) (Statement KBContext Proof TV) (Heap SkeletonForwardItem)))
(= (sk-seed-step $agenda ($type $kbctx $_proof $_tv))
   (let $key (sk-key $type $kbctx)
      (add_to_heap $agenda (- 0 (sk-change (sk-key-value $key) sk-none)) (sk-fwd-seed $key))))

;; A derived key the run built on has its value stored in &kb, like a fact, so a
;; later query reads it without searching for it again. It replaces the fact an
;; earlier run stored for the key and keeps the value's evidence and what it
;; was derived through, so no reader uses it to support itself. A value that is
;; one of the key's stored facts needs no copy: removing an identical copy
;; would remove the fact too.
(: sk-forward-store! (-[semidet]-> SkeletonKey Atom))
(= (sk-forward-store! $key)
   (case (sk-key-value $key) (
      ((sk-val ($type $kbctx $proof $tv) $ev $deps)
         (let* (($hash (index-hash $key))
                ($fact (assemble-runtime-fact $type $kbctx $proof $tv))
                ($_old
                   (collapse (match &sk_forward_stored ($hash $stored $old $old-ev $old-deps)
                      (if (=alpha $stored $key)
                         (let* (($_kb (remove-atom &kb $old))
                                ($_unindex (kb-unindex-fact! $old))
                                ($_row (remove-atom &sk_forward_stored ($hash $stored $old $old-ev $old-deps))))
                            ())
                         (empty)))))
                ($_copy
                   (if (space-row-present? &kb $fact) ()
                      (let* (($_stored (add-atom &sk_forward_stored ($hash $key $fact $ev $deps)))
                             ($_kb (add-atom &kb $fact)))
                         (kb-index-fact! live $fact)))))
            (sk-note-fact! $type $kbctx)))
      ($_none ()))))

(: sk-key-result (-[semidet]-> (List (Statement KBContext Proof TV)) SkeletonKey (List (Statement KBContext Proof TV))))
(= (sk-key-result $results $key)
   (case (sk-key-value $key) (
      ((sk-val $fact $_ev $_deps) (let $_stored (sk-forward-store! $key) (cons (sk-full-fact $fact) $results)))
      ($_none $results))))

;; Forward-chains from caller-selected facts within `$steps` derived keys,
;; stores the values of the keys it built on and returns them, most recent
;; first. A run has one
;; result: backtracking into it would repeat its work.
(: forward-chain
   (-[nondet]-> Number KB (List (Statement KBContext Proof TV))
       (List (Statement KBContext Proof TV))))
(= (forward-chain $steps $kb $facts)
   (once (let* (($_mode (change-state! sk_forward_run 1))
          ($_seen (remove-data-rows! &sk_seen (quote ($hash $node))))
          ($_budget (change-state! sk_budget (+ $steps 1)))
          ($_walk (change-state! sk_walk_budget (* (sk-walk-per-step) (+ $steps 1))))
          ($_rows (change-state! sk_row_budget (* 10 (+ $steps 1))))
          ($_evaluation (change-state! sk_eval_budget (* (sk-evaluation-per-step) (+ $steps 1))))
          ($_unneeded (remove-data-rows! &sk_needed (quote ($hash $key $depth))))
          ($_activate (sk-activate-pending!))
          ($taken (sk-forward-loop! $steps (fold-semidet sk-seed-step (empty_heap) (list_to_set $facts)) ()))
          ($_off (change-state! sk_forward_run 0)))
      (fold-semidet sk-key-result () $taken))))
