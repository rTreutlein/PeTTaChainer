;; Shared proof scoring and bounded-agenda policy.
(: premises-expected-confidence
   (-[det]-> (List (| Goal (Statement KBContext Proof TV))) Number))
(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (case $prem
      (((CPU $fun $args $res)
          (if (= $rest
                 (cons
                    (CPU CTVModusPonensFormula
                       (quote ($res $rule-tv))
                       $_mp-tv)
                    $remaining))
             (let $expected (first-cpu-expected-tv $fun $args)
                (if (== $expected ())
                   (min
                      (term-confidence (CPU $fun $args $res))
                      (premises-expected-confidence $rest))
                   (min-atom
                      ((tv-confidence $expected)
                       (cpu-expected-confidence
                          CTVModusPonensFormula
                          (quote ($expected $rule-tv)))
                       (premises-expected-confidence
                          (cdr-atom $rest))))))
             (min
                (term-confidence (CPU $fun $args $res))
                (premises-expected-confidence $rest))))
       ($other
          (min
             (term-confidence $other)
             (premises-expected-confidence $rest))))))

(: term-confidence
   (-[det]-> (| Goal
          (Statement KBContext Proof TV))
       Number))
(= (term-confidence $proof-term)
   (case $proof-term
      (((CPU $fun $args $res)
          (let $base
             (if (is-var $res)
                (cpu-expected-confidence $fun $args)
                (case $res (
                   ((STV $_strength $_confidence) (tv-confidence $res))
                   ((CTV $_positive $_negative) (tv-confidence $res))
                   ($_other 1.0))))
             (if (== $fun AndMarginalProjection) (* 0.99 $base) $base)))
       (($_type ($_kbid $_ctx $_vars) $prf $tv)
          ;; Historically the marginal-projection arm of proof-score matched
          ;; an unbound proof token first, applying this optimism discount but
          ;; also binding the caller's variable. Preserve the search heuristic
          ;; explicitly without mutating an open goal.
          (if (is-var $prf)
             (* 0.99 (tv-confidence $tv))
             (proof-score
                $prf $tv)))
       ($_other 0.0))))

(: proof-score (-[det]-> Proof TV Number))
(= (proof-score $prf $tv)
   (case $prf (
      ((marginal-proj $_idx $_inner) (* 0.99 (tv-confidence $tv)))
      ($_other (tv-confidence $tv)))))

;; Forward beam width is independent of the invocation's remaining budget.
(: bounded-agenda-target-size (-[det]-> Number))
(= (bounded-agenda-target-size) 1000)

(: set-bounded-agenda-pruning (-[det]-> Bool Bool))
(= (set-bounded-agenda-pruning $enabled) (change-state! bounded_agenda_pruning $enabled))
(: bounded-agenda-pruning? (-[det]-> Bool))
(= (bounded-agenda-pruning?)
   (let $state-values
      (collapse
         (catch
            (get-state bounded_agenda_pruning)))
      (if (== $state-values ())
         true
         (if-error-bool
            (car-atom $state-values) true))))

(: heap-prune-to-size (-[semidet]-> Number (Heap $item) (Heap $item)))
(= (heap-prune-to-size $target $agenda)
   (let (heap-split $kept $_discarded)
      (heap-split-best $target $agenda (empty_heap))
      $kept))

(: HeapSplit Type)
(: heap-split (-[det]-> (Heap $item) (Heap $item) HeapSplit))

(: heap-split-best
   (-[semidet]-> Number (Heap $item) (Heap $item) HeapSplit))
(= (heap-split-best $count $src $kept)
   (if (<= $count 0)
      (heap-split $kept $src)
      (if (heap-empty? $src)
         (heap-split $kept $src)
         (heap-split-best-pop $count $kept (heap_pop $src)))))

(: heap-split-best-pop
   (-[semidet]-> Number (Heap $item)
       (Number $item (Heap $item)) HeapSplit))
(= (heap-split-best-pop $count $kept ($key $item $rest))
   (heap-split-best
      (- $count 1) $rest
      (add_to_heap $kept $key $item)))

(: bounded-agenda-prune-needed? (-[det]-> (Heap $item) Bool))
(= (bounded-agenda-prune-needed? $agenda)
   (if (bounded-agenda-pruning?)
      (let* (($target (bounded-agenda-target-size))
             ($size-values (collapse (heap_size $agenda)))
             ($size
                (if (== $size-values ())
                   0
                   (car-atom $size-values))))
         (> $size (* $target 64)))
      false))

(: bounded-agenda-prune (-[semidet]-> (Heap $item) (Heap $item)))
(= (bounded-agenda-prune $agenda)
   (if (bounded-agenda-prune-needed? $agenda)
      (heap-prune-to-size (bounded-agenda-target-size) $agenda)
      $agenda))

(: RevisionMergeProof
   (-[det]-> (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)))

(: assemble-runtime-fact
   (-[det]-> Statement KBContext Proof TV
       (Statement KBContext Proof TV)))
(= (assemble-runtime-fact $type $kb $proof $tv)
   (data $type $kb $proof $tv))
