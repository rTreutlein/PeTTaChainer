;; Shared proof scoring and bounded-agenda policy.
(: premises-expected-confidence-step
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       Number))
(= (premises-expected-confidence-step $prem $rest)
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
                (cpu-result-confidence $res))
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

(: cpu-result-confidence (-[det]-> $result Number))
(= (cpu-result-confidence $result)
   (case $result (
      ((STV $_strength $_confidence)
         (tv-confidence $result))
      ((CTV $_positive $_negative)
         (tv-confidence $result))
      ($_other 1.0))))

(: proof-score (-[det]-> Proof TV Number))
(= (proof-score $prf $tv)
   (case $prf (
      ((marginal-proj $_idx $_inner) (* 0.99 (tv-confidence $tv)))
      ($_other (tv-confidence $tv)))))

(: premises-expected-confidence
   (-[det]-> (List (| Goal (Statement KBContext Proof TV))) Number))
(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (premises-expected-confidence-step $prem $rest))

(: premise-cons
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       (List (| Goal (Statement KBContext Proof TV)))))
(= (premise-cons $premise $rest)
   (cons $premise $rest))

(: score-tv (-[det]-> Number STVType))
(= (score-tv $score) (STV 1.0 (max 0.0 (min 1.0 $score))))

(: optimistic-revision-score (-[det]-> Number Number Number))
(= (optimistic-revision-score $current-score $candidate-score)
   (tv-confidence
      (merge-stvs
         (score-tv $current-score)
         (score-tv $candidate-score))))

(: rule-marginal-score (-[det]-> (| Number NoCurrentScore) Number Number))
(= (rule-marginal-score $current-score $candidate-score)
   (if (== $current-score no-current)
      $candidate-score
      (let $score (the Number $current-score)
         (max 0.000001
            (- (max $candidate-score (optimistic-revision-score $score $candidate-score))
               $score)))))

;; The incoming score is the most value this goal can still contribute to the
;; requesting root branch. The same value-of-computation rule applies before
;; and after the first proof: use the candidate confidence as initial gain, or
;; marginal improvement over an incumbent, then discount by immediate premise
;; work and the cached probability that every premise can be proved.
(: root-proof-value-score
   (-[det]-> Number (| Number NoCurrentScore) Number Number Number Number))
(= (root-proof-value-score
      $root-bound $current-score $candidate-score
      $premise-count $success-probability)
   (let* (($gain
             (if (== $current-score no-current)
                $candidate-score
                (rule-marginal-score $current-score $candidate-score)))
          ($bounded (min $root-bound $gain)))
      (/ (* $bounded $success-probability)
         (max 1 $premise-count))))

;; A cached base-rate snapshot is usable immediately.  Its optional live fold
;; can improve confidence by at most the remaining confidence mass, while the
;; snapshot's evidence count is a lower-bound estimate of the rescan work.
(: cached-base-rate-refinement-score (-[det]-> Number TV Number))
(= (cached-base-rate-refinement-score $root-bound $tv)
   (let*
      (($confidence (tv-confidence $tv))
       ($gain-bound (max 0.000001 (- 1.0 $confidence)))
       ($expected-steps (max 1.0 (confidence-to-count $confidence))))
      (/ (min $root-bound $gain-bound) $expected-steps)))

(: frontier-proof-score (-[det]-> $proof-output Number Number))
(= (frontier-proof-score $output $score)
   (if (= $output (CPU $_fun $_args $_res))
      (max 0.000001 $score)
      $score))

(: bounded-agenda-target-size (-[det]-> Number Number))
;; Beam width is a search-policy parameter, not part of the expansion budget.
;; Keeping it fixed makes a larger budget extend the same deterministic search
;; prefix instead of changing which branches survive pruning. A batch may have
;; more roots than the ordinary beam, and unexpanded roots must never be
;; discarded merely because they share one arena.
(= (bounded-agenda-target-size $_steps)
   (let $state-values (collapse (catch (get-state bwd_root_count)))
      (max 1000
         (if (== $state-values ())
            0
            (if-error-number (car-atom $state-values) 0)))))
(: bounded-agenda-prune-factor (-[det]-> Number))
(= (bounded-agenda-prune-factor) 64)

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

(: heap-take-best (-[det]-> Number (Heap $item) (Heap $item) (Heap $item)))
(= (heap-take-best $count $src $dst)
   (if (<= $count 0)
      $dst
      (case (collapse (heap_pop $src)) (
         (() $dst)
         ((cons $pop $_rest)
            (heap-take-best-pop $count $dst $pop))))))

(: heap-take-best-pop
   (-[det]-> Number (Heap $item)
       (Number $item (Heap $item))
       (Heap $item)))
(= (heap-take-best-pop $count $dst ($key $item $rest))
   (heap-take-best
      (- $count 1)
      $rest
      (add_to_heap $dst $key $item)))

(: heap-prune-to-size (-[det]-> Number (Heap $item) (Heap $item)))
(= (heap-prune-to-size $target $agenda)
   (heap-take-best $target $agenda (empty_heap)))

(: bounded-agenda-prune (-[det]-> Number (Heap $item) (Heap $item)))
(= (bounded-agenda-prune $steps $agenda)
   (if (bounded-agenda-pruning?)
      (let*
         (($target (bounded-agenda-target-size $steps))
          ($size-values
             (collapse (heap_size $agenda)))
          ($size
             (if (== $size-values ())
                0
                (car-atom $size-values)))
          ($threshold (* $target (bounded-agenda-prune-factor))))
         (if (> $size $threshold)
            (heap-prune-to-size $target $agenda)
            $agenda))
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

(: assemble-contextual-runtime-fact
   (-[det]-> Statement KB Atom Atom Proof TV
       (Statement KBContext Proof TV)))
(= (assemble-contextual-runtime-fact
      $type $kbid $context $variables $proof $tv)
   (data
      $type
      (brand KBContext (data $kbid $context $variables))
      $proof
      $tv))
