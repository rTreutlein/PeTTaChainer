(: NoCurrentScore Type)
(: no-current NoCurrentScore)

(: NoProjectionKey Type)
(: no-projection-key NoProjectionKey)

(: ProofRef Type)
(: proof-ref (-> Number ProofRef))

(: Evidence Type)
(: fact-ev (-> $kb $proof $type Evidence))
(: not-fact-ev (-> $kb $proof $type Evidence))
(: rule-ev (-> $kb $rule Evidence))
(: not-ev (-> $evidence Evidence))

(: BaseRateSource Type)
(: user BaseRateSource)
(: computed BaseRateSource)
(: forward-approx BaseRateSource)

(: BaseRateEntry Type)
(: base-rate (-> $kb $pattern TV BaseRateSource $mode BaseRateEntry))

(: UniverseSizeEntry Type)
(: universe-size (-> $kb Number UniverseSizeEntry))

;; Forward incremental member updates call this implementation from
;; compiled_query_runtime, which is imported later in the module graph.
(: member-inheritance-tv (-> $kb BaseRateEvidenceState TV))

(: tv-confidence (-> $truth-value Number))
(= (tv-confidence $tv)
   (if (is-var $tv) 1.0
      (case $tv
         (((STV $_s $c) (if (is-var $c) 1.0 $c))
          ((CTV $pos $neg) (min (tv-confidence $pos) (tv-confidence $neg)))
          ($_other 1.0)))))

(: goal-has-type-vars?
   (-> (| Goal
          ($type ($kb $context $variables) $proof TV))
       Bool))
(= (goal-has-type-vars? $goal)
   (case $goal
      (((CPU $fun $args $res)
          (not (== (extract-vars (CPU $fun $args $res)) ())))
       (($type ($_kbid $_ctx $vars) $_prf $_tv)
          (or (not (== (extract-vars $type) ()))
              (not (== $vars Nil)))))))

(: goal-key
   (-> (| Goal
          ($type ($kb $context $variables) $proof TV))
       Expression))
(= (goal-key ($type ($kbid $ctx $vars) $_prf $_tv))
   (let $sealed-goal (sealed (extract-vars ($type $vars)) ($type $vars))
      ($sealed-goal ($kbid $ctx))))
(= (goal-key (CPU $fun $args $res)) (sealed (extract-vars (CPU $fun $args $res)) (CPU $fun $args $res)))

(: normalize-expected-tv (-> $truth-value $truth-value))
(= (normalize-expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (case $tv
         (((STV $s $c) (STV (if (is-var $s) 1.0 $s) (if (is-var $c) 1.0 $c)))
          ((CTV $pos $neg)
             (CTV (normalize-expected-tv $pos) (normalize-expected-tv $neg)))
          ($other $other)))))

;; CPU arguments are formula-dependent and enter through a generic execution
;; record.  Once dispatch identifies a TV formula, check the normalized value
;; at this single boundary.
(: expected-tv (-> $candidate TV))
(= (expected-tv $value) (the TV (normalize-expected-tv $value)))

;; Expected TVs dispatch directly on the known formula set instead of going
;; through reduce: reduce's runtime dispatch (fun/1 + current_predicate +
;; current_op per call) dominated backward-search profiles. Failure modes are
;; preserved -- a formula clause that does not match (or yields empty) makes
;; this function fail exactly like the reduce-based call did.
(: cpu-expected-tv
   (-> $formula $arguments (| TV (List $no-result))))
(= (cpu-expected-tv $fun ($a))
   (if (== $fun NotFormula)
      (if (is-var $a)
         (STV 1.0 1.0)
         (NotFormula (expected-tv $a)))
      ()))

(= (cpu-expected-tv $fun ($a $b))
   (case $fun
      ((CTVModusPonensFormula
         (CTVModusPonensFormula
            (expected-tv $a) (expected-tv $b)))
       (CTVFormula
         (CTVFormula (expected-tv $a) (expected-tv $b)))
       (AndFormula
         (AndFormula (expected-tv $a) (expected-tv $b)))
       (OrFormula
         (OrFormula (expected-tv $a) (expected-tv $b)))
       (LikelierThanFormula
         (LikelierThanFormula
            (expected-tv $a) (expected-tv $b)))
       (()
         (cons () ((expected-tv $a) (expected-tv $b))))
       ($_other ()))))

(= (cpu-expected-tv $fun ($a $b $ctv))
   (if (== $fun CTVInversionFormula)
      (let*
         (($na (expected-tv $a))
          ($nb (expected-tv $b))
          ($nctv (expected-tv $ctv))
          ($confidence
             (* (min-atom
                  ((tv-confidence $na)
                   (tv-confidence $nb)
                   (tv-confidence $nctv)))
                0.9)))
         (if (or (is-var $a) (is-var $b))
            (CTV (STV 1.0 $confidence) (STV 1.0 $confidence))
            (CTVInversionFormula $na $nb $nctv)))
      ()))

(: first-cpu-expected-tv
   (-> $formula $arguments (| TV (List $no-result))))
(= (first-cpu-expected-tv $fun $args)
   (let $res (let $hits (collapse (cpu-expected-tv $fun $args)) (if (== $hits ()) () (car-atom $hits)))
      $res))

(: cpu-expected-confidence (-> $formula $arguments Number))
(= (cpu-expected-confidence $fun $args)
   (let $res (first-cpu-expected-tv $fun $args)
      (if (== $res ()) 1.0 (tv-confidence $res))))

(: premises-expected-confidence-step
   (-> (| Goal
          ($type ($kb $context $variables) $proof TV))
       (List (| Goal
                ($rest-type ($rest-kb $rest-context $rest-variables)
                   $rest-proof TV)))
       Number))
(= (premises-expected-confidence-step (CPU $fun $args $mid-tv) (cons (CPU CTVModusPonensFormula ($mid-tv $rule-tv) $_mp-tv) $rest))
   (let $expected (first-cpu-expected-tv $fun $args)
      (if (== $expected ())
         (min (term-confidence (CPU $fun $args $mid-tv))
            (premises-expected-confidence (cons (CPU CTVModusPonensFormula ($mid-tv $rule-tv) $_mp-tv) $rest)))
         (min-atom
            ((tv-confidence $expected)
             (cpu-expected-confidence CTVModusPonensFormula ($expected $rule-tv))
             (premises-expected-confidence $rest))))))
(= (premises-expected-confidence-step (CPU $fun $args $res) $rest)
   (if (= $rest (cons (CPU CTVModusPonensFormula ($res $_rule-tv) $_mp-tv) $_tail))
      (empty)
      (min (term-confidence (CPU $fun $args $res)) (premises-expected-confidence $rest))))
(= (premises-expected-confidence-step $prem $rest)
   (if (= $prem (CPU $_fun $_args $_res))
      (empty)
      (min (term-confidence $prem) (premises-expected-confidence $rest))))

(: term-confidence
   (-> (| Goal
          ($type ($kb $context $variables) $proof TV))
       Number))
(= (term-confidence $proof-term)
   (case $proof-term
      (((CPU $fun $args $res)
          (let $base
             (if (is-var $res)
                (cpu-expected-confidence $fun $args)
                (tv-confidence $res))
             (if (== $fun AndMarginalProjection) (* 0.99 $base) $base)))
       (($_type ($_kbid $_ctx $_vars) $prf $tv)
          (proof-score $prf $tv)))))

(: proof-score ($proof $truth-value -[det]-> Number))
(= (proof-score $prf $tv)
   (case $prf (
      ((marginal-proj $_idx $_inner) (* 0.99 (tv-confidence $tv)))
      ($_other (tv-confidence $tv)))))

(: premises-expected-confidence
   (-> (List (| Goal
                ($type ($kb $context $variables) $proof TV)))
       Number))
(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (let $hits (collapse (premises-expected-confidence-step $prem $rest))
      (if (== $hits ()) (empty) (car-atom $hits))))

(: score-tv (-> Number TV))
(= (score-tv $score) (STV 1.0 (max 0.0 (min 1.0 $score))))

(: optimistic-revision-score (-> Number Number Number))
(= (optimistic-revision-score $current-score $candidate-score)
   (tv-confidence (mergetvs (score-tv $current-score) (score-tv $candidate-score))))

(: rule-marginal-score (-> (| Number NoCurrentScore) Number Number))
(= (rule-marginal-score $current-score $candidate-score)
   (if (== $current-score no-current)
      $candidate-score
      (let $score (the Number $current-score)
         (max 0.000001
            (- (max $candidate-score (optimistic-revision-score $score $candidate-score))
               $score)))))

(: frontier-proof-score (-> $proof-output Number Number))
(= (frontier-proof-score $output $score)
   (if (= $output (CPU $_fun $_args $_res))
      (max 0.000001 $score)
      $score))

(: bounded-agenda-target-size (-> Number Number))
(= (bounded-agenda-target-size $steps) (min 1000 (max 1 $steps)))
(: bounded-agenda-prune-factor (-> Number))
(= (bounded-agenda-prune-factor) 64)

(: set-bounded-agenda-pruning (-> Bool Bool))
(= (set-bounded-agenda-pruning $enabled) (change-state! bounded_agenda_pruning $enabled))
(: bounded-agenda-pruning? (-> Bool))
(= (bounded-agenda-pruning?)
   (let $enabled (catch (get-state bounded_agenda_pruning))
      (if-error-bool $enabled true)))

(: heap-take-best (-> Number $heap $heap $heap))
(= (heap-take-best $count $src $dst)
   (if (or (<= $count 0) (== (heap_size $src) 0)) $dst
      (let*
         (($rest (get_from_heap $src $key $item))
          ($next (add_to_heap $dst $key $item)))
         (heap-take-best (- $count 1) $rest $next))))

(: heap-prune-to-size (-> Number $heap $heap))
(= (heap-prune-to-size $target $agenda)
   (heap-take-best $target $agenda (empty_heap)))

(: bounded-agenda-prune (-> Number $heap $heap))
(= (bounded-agenda-prune $steps $agenda)
   (if (not (bounded-agenda-pruning?)) $agenda
      (let*
         (($target (bounded-agenda-target-size $steps))
          ($size (heap_size $agenda))
          ($threshold (* $target (bounded-agenda-prune-factor))))
         (if (> $size $threshold)
            (heap-prune-to-size $target $agenda)
            $agenda))))

(: RevisionMergeProof
   (-> ($type1 $kb $proof1 TV) ($type2 $kb2 $proof2 TV)
       ($type1 $kb $merged-proof TV)))
(= (RevisionMergeProof ($type1 $kb $prf1 $tv1) ($_type2 $_kb2 $prf2 $tv2))
   ($type1 $kb
      (merge/revision $prf1 $prf2)
      (if (and (= $tv1 (STV $_m1 $_c1)) (= $tv2 (STV $_m2 $_c2))) (mergetvs $tv1 $tv2) $tv1)))

(: proof-atom-proof (-> ($type $kb $proof TV) $proof))
(= (proof-atom-proof ($_type $_kb $prf $_tv)) $prf)

(: foreach-flat
   (-> (-> $item $effect) (List $item) (List $none)))
(= (foreach-flat $f ()) ())
(= (foreach-flat $f (cons $x $xs))
   (progn ($f $x) (foreach-flat $f $xs)))

(: chainer-add-atom
   (-> $space $expression (| Bool (List $no-result))))
(= (chainer-add-atom $space $expr)
   (if (== (collapse (callPredicate (Predicate (cyclic_term $expr)))) ())
      (add-atom $space $expr)
      (empty)))

(: next-search-id (-> $counter-key Number))
(= (next-search-id $key)
   (let*
      (($mn (catch (get-state $key)))
        ($n (if-error-number $mn 0)))
      (progn (change-state! $key (+ $n 1)) $n)))

(: next-gid (-> Number))
(= (next-gid) (next-search-id bwd_gid))

(: next-pid (-> Number))
(= (next-pid) (next-search-id bwd_pid))

(: cpu-call (-> Number $formula $arguments $result))
(= (cpu-call $_steps $fun $args) (reduce (reduce (cons $fun $args))))

(: proof-stats-by-id
   (-> Number (Number (List $evidence))))
(= (proof-stats-by-id $pid)
   (the (Number (List Evidence))
      (match &proof
         ($pid $_gid $_output $_kind $score $ev $_children)
         ($score $ev))))

(: proof-term-leaf-head? (-> $head Bool))
(= (proof-term-leaf-head? $head) (is-member $head (() fact-ev CPU STV CTV)))

(: proof-term-children-mode
   (-> $mode $proof (List $proof-child)))
(= (proof-term-children-mode $mode $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf)
         (if (== $head conjunction) (cdr-atom $prf)
            (if (== $mode proof-walk-in-kb)
               (if (proof-term-leaf-head? $head) () (cdr-atom $prf))
               ())))
      ()))

(: proof-term-evidence-children-mode
   (-> $mode (List $proof-child) (List $evidence)))
(= (proof-term-evidence-children-mode $mode ()) ())
(= (proof-term-evidence-children-mode $mode (cons $child $rest))
   (append (proof-term-evidence-list-mode $mode $child)
      (proof-term-evidence-children-mode $mode $rest)))

(: evidence-negate (-> $evidence Evidence))
(= (evidence-negate $ev)
   (case $ev (
      ((fact-ev $kb $prf $type) (not-fact-ev $kb $prf $type))
      ((not-fact-ev $kb $prf $type) (fact-ev $kb $prf $type))
      ($other (not-ev $other)))))

(: evidence-negate-list
   (-> (List $evidence) (List Evidence)))
(= (evidence-negate-list ()) ())
(= (evidence-negate-list (cons $ev $rest))
   (cons (evidence-negate $ev) (evidence-negate-list $rest)))

(: proof-term-negated? (-> $proof Bool))
(= (proof-term-negated? $prf)
   (if (is-expr $prf) (== (car-atom $prf) negated) false))

(: proof-term-evidence-list-mode
   (-> $mode $proof (List $evidence)))
(= (proof-term-evidence-list-mode $mode $prf)
   (case $prf (
      ((@ $_ref (proof-ref $pid))
         (let ($_score $evidence)
            (proof-stats-by-id (the Number $pid))
            $evidence))
      ((@ $_merge (merge/revision $left $right))
         (append (proof-term-evidence-list-mode $mode $left)
            (proof-term-evidence-list-mode $mode $right)))
      ($_other
         (if (is-var $prf) ()
            (if (assumption-proof? $prf) ()
               (if (proof-term-negated? $prf)
                  (evidence-negate-list (proof-term-evidence-list-mode $mode (car-atom (cdr-atom $prf))))
                  (let $children (proof-term-children-mode $mode $prf)
                     (if (== $children ()) (cons $prf ())
                        (proof-term-evidence-children-mode $mode $children))))))))))

(: proof-atom-evidence-set
   (-> ($type $kb $proof $truth-value) (List $evidence)))
(= (proof-atom-evidence-set ($_type $kb $prf $_tv))
   (list_to_set (once (proof-term-evidence-list-mode proof-walk-in-kb $prf))))

(: evidence-intersection
   (-> (List $evidence) (List $evidence) (List $evidence)))
(= (evidence-intersection $set-a $set-b)
   (the (List Evidence) (intersection-atom $set-a $set-b)))

(: evidence-sets-overlap?
   (-> (List $evidence) (List $evidence) Bool))
(= (evidence-sets-overlap? $set-a $set-b)
   (not (== (evidence-intersection $set-a $set-b) ())))

(: fact-evidence-only-step
   (-> (List $evidence) $evidence (List $evidence)))
(= (fact-evidence-only-step $acc $entry)
   (if (= $entry (rule-ev $_kb $_name))
      $acc
      (append $acc (the (List Evidence) ($entry)))))

(: fact-evidence-only
   (-> (List $evidence) (List $evidence)))
(= (fact-evidence-only $ev) (fold-flat fact-evidence-only-step () $ev))

;; The non-fact part of an evidence set (rule applications and hypotheses).
;; Two proofs are genuinely *dependent* only when these overlap: sharing a fact
;; is poolable (lifting-merge factors the shared fact out), whereas sharing a
;; rule or hypothesis means pooling would double-count its uncertainty.
(: non-fact-evidence
   (-> (List $evidence) (List $evidence)))
(= (non-fact-evidence $ev) (subtraction-atom $ev (fact-evidence-only $ev)))
(: evidence-sets-dependent?
   (-> (List $evidence) (List $evidence) Bool))
(= (evidence-sets-dependent? $set-a $set-b)
   (evidence-sets-overlap? (non-fact-evidence $set-a) (non-fact-evidence $set-b)))

(: premise-evidence-overlap?
   (-> (List $evidence) (List $evidence) Bool))
(= (premise-evidence-overlap? $seen $pev)
   (evidence-sets-overlap? (fact-evidence-only $seen) (fact-evidence-only $pev)))

(: evidence-subset?
   (-> (List $evidence) (List $evidence) Bool))
(= (evidence-subset? $set-a $set-b) (== (subtraction-atom $set-a $set-b) ()))

(: proof-term-contains-negated-list? (-> (List $proof) Bool))
(= (proof-term-contains-negated-list? ()) false)
(= (proof-term-contains-negated-list? (cons $child $rest))
   (or (proof-term-contains-negated? $child) (proof-term-contains-negated-list? $rest)))

(: proof-term-contains-negated? (-> $proof Bool))
(= (proof-term-contains-negated? $prf)
   (if (is-var $prf) false
      (if (proof-term-negated? $prf) true
         (if (is-expr $prf) (proof-term-contains-negated-list? (cdr-atom $prf)) false))))

(: rule-evidence-head (-> $proof $rule-name))
(= (rule-evidence-head $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf)
         (if (is-expr $head)
            (if (= $head (inverted $inv with $_pa $_pb)) $inv
               (if (= $head (bi-forward $fwd)) $fwd
                  (if (= $head (bi-backward $bwd)) $bwd
                     (if (= $head (no_inverse $inner)) $inner $head))))
            $head))
      $prf))

(: rule-application-evidence
   (-> $kb $proof (List Evidence)))
(= (rule-application-evidence $kb $prf)
   (if (= $kb ($kbid $_ctx $_vars))
      (let $name (rule-evidence-head $prf)
         (if (is-expr $name) ()
            (if (rule-evidence-registered? $kbid $name)
               (cons (rule-ev $kbid $name) ())
               ())))
      ()))

;; Forward materialization and backward rule application must attach exactly
;; the same provenance.  Otherwise a materialized rule result looks like a new
;; independent fact when the backward chainer rediscovers that rule path.
(: rule-result-evidence
   (-> ($type $kb $proof $truth-value) (List $evidence) (List $evidence)))
(= (rule-result-evidence ($_type $kb $prf $_tv) $ev)
   (let*
      (($base
          (if (proof-term-contains-negated? $prf)
             (list_to_set (once (proof-term-evidence-list-mode proof-walk-in-kb $prf)))
             $ev))
       ($rule-ev (rule-application-evidence $kb $prf)))
      (if (== $rule-ev ()) $base (list_to_set (append $base $rule-ev)))))

(: projection-proof-key
   (-> $proof (| (projection-key $index $base) NoProjectionKey)))
(= (projection-proof-key $prf)
   (case $prf (
      ((marginal-proj $idx $base) (projection-key $idx $base))
      (((proj $idx $base) $_evidence) (projection-key $idx $base))
      ($_ no-projection-key))))

(: strict-projection-proof? (-> $proof Bool))
(= (strict-projection-proof? $prf)
   (case $prf (
      (((proj $_idx $_base) $_evidence) true)
      ($_ false))))

(: projection-dominates? (-> $proof $proof Bool))
(= (projection-dominates? $prf-a $prf-b)
   (let $key-a (projection-proof-key $prf-a)
      (and (not (== $key-a no-projection-key))
         (and (== $key-a (projection-proof-key $prf-b))
            (and (strict-projection-proof? $prf-a)
               (not (strict-projection-proof? $prf-b)))))))

(: merge-proof-candidates
   (-> (($type-a $kb-a $proof-a TV) (List Evidence))
       (($type-b $kb-b $proof-b TV) (List Evidence))
       (($merged-type $merged-kb $merged-proof TV) (List Evidence))))
(= (merge-proof-candidates ($proof-a $ev-a) ($proof-b $ev-b))
   (if (== $proof-a $proof-b) ($proof-a (list_to_set (append $ev-a $ev-b)))
      (let*
         (($overlap? (evidence-sets-overlap? $ev-a $ev-b))
          ($all-ev (list_to_set (append $ev-a $ev-b))))
         (if (projection-dominates? (proof-atom-proof $proof-a) (proof-atom-proof $proof-b))
            ($proof-a $ev-a)
            (if (projection-dominates? (proof-atom-proof $proof-b) (proof-atom-proof $proof-a))
               ($proof-b $ev-b)
               (if $overlap?
                  (if (>= (term-confidence $proof-a)
                          (term-confidence $proof-b))
                     ($proof-a $ev-a)
                     ($proof-b $ev-b))
                  (if (>= (term-confidence $proof-a)
                          (term-confidence $proof-b))
                     ((RevisionMergeProof $proof-a $proof-b) $all-ev)
                     ((RevisionMergeProof $proof-b $proof-a) $all-ev))))))))

(: merge-proof-atoms
   (-> ($type $kb $proof-a TV) ($type $kb $proof-b TV)
       ($type $kb $merged-proof TV)))
(= (merge-proof-atoms $proof-a $proof-b)
   (let ($merged $_ev)
      (merge-proof-candidates
         ($proof-a (proof-atom-evidence-set $proof-a))
         ($proof-b (proof-atom-evidence-set $proof-b)))
      $merged))

;; Base-rate cache operations are shared by forward chaining and the compiled
;; query runtime, so they must be available before either consumer is loaded.
(: base-rate-cache-entries (-> $kb $pattern (List BaseRateEntry)))
(= (base-rate-cache-entries $kbid $pattern)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $mode)
         (if (=alpha $stored $pattern)
            (base-rate $kbid $stored $tv $source $mode)
            (empty)))))

(: base-rate-cache-entries-for-mode
   (-> $kb $pattern $mode (List BaseRateEntry)))
(= (base-rate-cache-entries-for-mode $kbid $pattern $mode)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $emode)
         (if (and (=alpha $stored $pattern)
                  (or (== $emode any) (== $emode $mode)))
            (base-rate $kbid $stored $tv $source $emode)
            (empty)))))

(: base-rate-cache-remove-entry! (-> BaseRateEntry Bool))
(= (base-rate-cache-remove-entry! $entry)
   (remove-atom &base_rate_cache $entry))

(: base-rate-cache-remove! (-> $kb $pattern (List $none)))
(= (base-rate-cache-remove! $kbid $pattern)
   (let $_
      (foreach-flat base-rate-cache-remove-entry!
         (base-rate-cache-entries $kbid $pattern))
      ()))

(: base-rate-cache-remove-derived!
   (-> $kb $pattern $mode (List $none)))
(= (base-rate-cache-remove-derived! $kbid $pattern $mode)
   (let $_
      (foreach-flat base-rate-cache-remove-entry!
         (collapse
            (match &base_rate_cache
               (base-rate $kbid $stored $tv $source $mode)
               (if (and (not (== $source user)) (=alpha $stored $pattern))
                  (base-rate $kbid $stored $tv $source $mode)
                  (empty)))))
      ()))

(: cached-base-rate ($kb $pattern -[nondet]-> (| TV (List $no-result))))
(= (cached-base-rate $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) ()
         (let (base-rate $_kbid $_stored $tv $_source $_mode)
            (car-atom $entries)
            ($tv)))))

(: base-rate-user-set? (-> $kb $pattern Bool))
(= (base-rate-user-set? $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) false
         (let (base-rate $_kbid $_stored $_tv $source $_mode)
            (car-atom $entries)
            (== $source user)))))

(: store-base-rate! (-> $kb $pattern TV (List $none)))
(= (store-base-rate! $kbid $pattern $tv)
   (let*
      (($stored (copy_term $pattern))
       ($_old (base-rate-cache-remove! $kbid $pattern))
       ($_new
          (add-atom &base_rate_cache
             (base-rate $kbid $stored $tv user any))))
      ()))

(: set-base-rate (-> $kb $pattern TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (store-base-rate! $kbid $pattern $tv))

(: clear-base-rate (-> $kb $pattern (List $none)))
(= (clear-base-rate $kbid $pattern)
   (base-rate-cache-remove! $kbid $pattern))

(: store-computed-base-rate!
   (-> $kb $pattern TV $mode (List $none)))
(= (store-computed-base-rate! $kbid $pattern $tv $mode)
   (if (base-rate-user-set? $kbid $pattern) ()
      (let*
         (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove-derived! $kbid $pattern $mode))
          ($_new
             (add-atom &base_rate_cache
                (base-rate $kbid $stored $tv computed $mode))))
         ())))

(: store-forward-base-rate!
   (-> $kb $pattern TV $mode (List $none)))
(= (store-forward-base-rate! $kbid $pattern $tv $mode)
   (if (or (== $tv no-evidence) (base-rate-user-set? $kbid $pattern)) ()
      (let*
         (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove-derived! $kbid $pattern $mode))
          ($_new
             (add-atom &base_rate_cache
                (base-rate $kbid $stored $tv forward-approx $mode))))
         ())))

(: invalidate-computed-base-rates! (-> $kb (List $none)))
(= (invalidate-computed-base-rates! $kbid)
   (let*
      (($entries
          (collapse
             (match &base_rate_cache
                (base-rate $kbid $stored $tv $source $mode)
                (if (== $source user) (empty)
                   (base-rate $kbid $stored $tv $source $mode)))))
       ($_ (foreach-flat base-rate-cache-remove-entry! $entries)))
      ()))

(: universe-size-entries (-> $kb (List UniverseSizeEntry)))
(= (universe-size-entries $kbid)
   (collapse
      (match &universe_size (universe-size $kbid $n)
         (universe-size $kbid $n))))

(: universe-size-remove-entry! (-> UniverseSizeEntry Bool))
(= (universe-size-remove-entry! $entry)
   (remove-atom &universe_size $entry))

(: clear-universe-size (-> $kb (List $none)))
(= (clear-universe-size $kbid)
   (let*
      (($_remove
          (foreach-flat universe-size-remove-entry!
             (universe-size-entries $kbid)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-universe-size (-> $kb Number (List $none)))
(= (set-universe-size $kbid $n)
   (let*
      (($_old (clear-universe-size $kbid))
       ($_new (add-atom &universe_size (universe-size $kbid $n)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: kb-universe-size
   (-> $kb (| Number UniverseSizeUnavailable)))
(= (kb-universe-size $kbid)
   (let $entries (universe-size-entries $kbid)
      (if (== $entries ()) no-universe-size
         (let (universe-size $_kbid $n) (car-atom $entries) $n))))

(: inheritance-subjects ($kb -[det]-> (List $subject)))
(= (inheritance-subjects $kbid)
   (list_to_set
      (collapse
         (match &inheritance_subject ($kbid $subj) $subj))))
