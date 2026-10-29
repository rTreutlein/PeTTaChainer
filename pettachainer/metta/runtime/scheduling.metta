;; Shared proof scoring and bounded-agenda policy.
(: premises-expected-confidence (-[det]-> (List (| Goal (Statement KBContext Proof TV))) Number))
(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (case $prem
      ;; A formula whose result modus ponens reads next, compared without
      ;; unifying: a rule's own CTV formula also precedes it.
      (((CPU $fun $args $res)
          (if (if (= $rest
                     (cons
                        (CPU CTVModusPonensFormula (quote ($mp-premise-tv $rule-tv)) $_mp-tv)
                        $remaining))
                 (== $mp-premise-tv $res)
                 false)
             (let $expected (first-cpu-expected-tv $fun $args)
                (if (== $expected ())
                   (min
                      (term-confidence (CPU $fun $args $res))
                      (premises-expected-confidence $rest))
                   (min-atom
                      ((tv-confidence $expected)
                       (cpu-expected-confidence CTVModusPonensFormula (quote ($expected $rule-tv)))
                       (premises-expected-confidence (cdr-atom $rest))))))
             (min (term-confidence (CPU $fun $args $res)) (premises-expected-confidence $rest))))
       ($other (min (term-confidence $other) (premises-expected-confidence $rest))))))

(: term-confidence (-[det]-> (| Goal (Statement KBContext Proof TV)) Number))
(= (term-confidence $proof-term)
   (case $proof-term
      (((CPU $fun $args $res)
          (let $base (if (is-var $res) (cpu-expected-confidence $fun $args) (tv-confidence $res))
             ;; A settled step adds nothing beyond the complete step it gives
             ;; way to, so it drives no search of its own: it reads the
             ;; nodes other joins expand and the facts read at once.
             (if (== $fun SettlesFormula) 0.0 $base)))
       (($_type ($_kbid $_ctx $_vars) $_prf $tv) (tv-confidence $tv))
       ($_other 0.0))))

;; Forward beam width is independent of the invocation's remaining budget.
(: bounded-agenda-target-size (-[det]-> Number))
(= (bounded-agenda-target-size) 1000)

!(change-state! bounded_agenda_pruning true)
(: set-bounded-agenda-pruning (-[det]-> Bool Bool))
(= (set-bounded-agenda-pruning $enabled) (change-state! bounded_agenda_pruning $enabled))

(: HeapSplit Type)
(: heap-split (-[det]-> (Heap $item) (Heap $item) HeapSplit))

(: heap-split-best (-[semidet]-> Number (Heap $item) (Heap $item) HeapSplit))
(= (heap-split-best $count $src $kept)
   (if (<= $count 0)
      (heap-split $kept $src)
      (if (heap-empty? $src)
         (heap-split $kept $src)
         (heap-split-best-pop $count $kept (heap_pop $src)))))

(: heap-split-best-pop (-[semidet]-> Number (Heap $item) (Number $item (Heap $item)) HeapSplit))
(= (heap-split-best-pop $count $kept ($key $item $rest))
   (heap-split-best (- $count 1) $rest (add_to_heap $kept $key $item)))

(: bounded-agenda-prune-needed? (-[det]-> (Heap $item) Bool))
(= (bounded-agenda-prune-needed? $agenda)
   (if (the Bool (car-atom (collapse (get-state bounded_agenda_pruning))))
      (let* (($target (bounded-agenda-target-size))
             ($size-values (collapse (heap_size $agenda)))
             ($size (if (== $size-values ()) 0 (car-atom $size-values))))
         (> $size (* $target 64)))
      false))

(: bounded-agenda-prune (-[semidet]-> (Heap $item) (Heap $item)))
(= (bounded-agenda-prune $agenda)
   (if (bounded-agenda-prune-needed? $agenda)
      (let (heap-split $kept $_discarded) (heap-split-best (bounded-agenda-target-size) $agenda (empty_heap)) $kept)
      $agenda))

(: RevisionMergeProof
   (-[det]-> (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)))

(: assemble-runtime-fact (-[det]-> Statement KBContext Proof TV (Statement KBContext Proof TV)))
(= (assemble-runtime-fact $type $kb $proof $tv) (data $type $kb $proof $tv))
