(: tv-confidence (-> $truth-value Number))
(= (tv-confidence $tv)
   (if (is-var $tv) 1.0
      (case $tv
         (((STV $_s $c) (if (is-var $c) 1.0 $c))
          ((CTV $pos $neg) (min (tv-confidence $pos) (tv-confidence $neg)))
          ($_other 1.0)))))

(: goal-has-type-vars?
   (-> (| Goal
          (Statement KBContext Proof TV))
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
          (Statement KBContext Proof TV))
       Expression))
(= (goal-key $goal)
   (case $goal
      (((CPU $fun $args $res)
          (sealed
             (extract-vars (CPU $fun $args $res))
             (CPU $fun $args $res)))
       (($type ($kbid $ctx $vars) $_prf $_tv)
          (let $sealed-goal
             (sealed
                (extract-vars (quote ($type $vars)))
                (quote ($type $vars)))
             (quote ($sealed-goal ($kbid $ctx))))))))

(: normalize-expected-tv (-> $truth-value TV))
(= (normalize-expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (case $tv
         (((STV $s $c) (STV (if (is-var $s) 1.0 $s) (if (is-var $c) 1.0 $c)))
          ((CTV $pos $neg)
             (CTV (normalize-expected-tv $pos) (normalize-expected-tv $neg)))
          (no-evidence no-evidence)
          ($other (the TV $other))))))

;; CPU arguments are formula-dependent and enter through a generic execution
;; record. Normalize known TV constructors without reflective checks; retain
;; an explicit checked fallback for invalid or user-extended TV values.
(: expected-tv (-> $candidate TV))
(= (expected-tv $value) (normalize-expected-tv $value))

;; Expected TVs dispatch directly on the known formula set instead of going
;; through reduce: reduce's runtime dispatch (fun/1 + current_predicate +
;; current_op per call) dominated backward-search profiles. Failure modes are
;; preserved -- a formula clause that does not match (or yields empty) makes
;; this function fail exactly like the reduce-based call did.
(: cpu-expected-tv
   (-[nondet]-> $formula $arguments  (| TV (List $no-result))))
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
   (-> (| Goal (Statement KBContext Proof TV))
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
   (-> (| Goal
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
          (proof-score
             (brand Proof $prf) $tv)))))

(: cpu-result-confidence (-> $result Number))
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
   (-> (List (| Goal (Statement KBContext Proof TV))) Number))
(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (premises-expected-confidence-step $prem $rest))

(: premise-cons
   (-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       (List (| Goal (Statement KBContext Proof TV)))))
(= (premise-cons $premise $rest)
   (cons $premise $rest))

(: score-tv (-> Number (STV Number Number)))
(= (score-tv $score) (STV 1.0 (max 0.0 (min 1.0 $score))))

(: optimistic-revision-score (-> Number Number Number))
(= (optimistic-revision-score $current-score $candidate-score)
   (tv-confidence
      (merge-stvs
         (score-tv $current-score)
         (score-tv $candidate-score))))

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
   (-> (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)))

(: assemble-runtime-fact
   (-> Statement KBContext Proof TV
       (Statement KBContext Proof TV)))
(= (assemble-runtime-fact $type $kb $proof $tv)
   (quote ($type $kb $proof $tv)))

(= (RevisionMergeProof ($type1 $kb $prf1 $tv1) ($_type2 $_kb2 $prf2 $tv2))
   (let $merged-tv
      (case $tv1 (
         ((STV $m1 $c1)
            (case $tv2 (
               ((STV $m2 $c2)
                  (merge-stv-fields $m1 $c1 $m2 $c2))
               ($_other-tv $tv1))))
         ($_other $tv1)))
      (assemble-runtime-fact
         $type1 $kb
         (brand Proof (merge/revision $prf1 $prf2))
         $merged-tv)))

(: proof-atom-proof
   (-> (Statement KBContext Proof TV) Proof))
(= (proof-atom-proof ($_type $_kb $prf $_tv)) $prf)

(: foreach-flat
   (-[det]-> (-[det]-> $item $effect)
       (List $item) (List $none)))
(= (foreach-flat $f ()) ())
(= (foreach-flat $f (cons $x $xs))
   (progn ($f $x) (foreach-flat $f $xs)))

(: foreach-flat-semidet
   (-[semidet]-> (-[semidet]-> $item $effect)
       (List $item) (List $none)))
(= (foreach-flat-semidet $_f ()) ())
(= (foreach-flat-semidet $f (cons $x $xs))
   (progn
      ($f $x)
      (foreach-flat-semidet $f $xs)))

(: chainer-acyclic-term? (-> $term Bool))
(= (chainer-acyclic-term? $term)
   (== (collapse
          (callPredicate (Predicate (cyclic_term $term))))
       ()))

(: chainer-add-atom
   (-[nondet]-> $space $expression  (| Bool (List $no-result))))
(= (chainer-add-atom $space $expr)
   (if (chainer-acyclic-term? $expr)
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

(: cpu-call (-[nondet]-> Number $formula $arguments  $result))
(= (cpu-call $_steps $fun $args) (reduce (reduce (cons $fun $args))))

(: proof-stats-by-id
   (-[semidet]-> Number (Number (List Evidence))))
(= (proof-stats-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_gid $_output $_kind
            $score $ev $_children)
         (quote ($score $ev)))))

(: proof-term-leaf-head? (-> $head Bool))
(= (proof-term-leaf-head? $head) (is-member $head (() fact-ev CPU STV CTV)))

(: proof-term-children-mode
   (-> $mode Proof (List Proof)))
(= (proof-term-children-mode $mode $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf)
         (if (== $head conjunction) (cdr-atom $prf)
            (if (== $mode proof-walk-in-kb)
               (if (proof-term-leaf-head? $head) () (cdr-atom $prf))
               ())))
      ()))

(: proof-term-evidence-children-mode
   (-[semidet]-> $mode (List Proof) (List Evidence)))
(= (proof-term-evidence-children-mode $mode ()) ())
(= (proof-term-evidence-children-mode $mode (cons $child $rest))
   (append
      (proof-term-evidence-list-mode $mode $child)
      (proof-term-evidence-children-mode $mode $rest)))

(: evidence-negate (-> Evidence Evidence))
(= (evidence-negate $ev)
   (case $ev (
      ((fact-ev $kb $prf $type) (not-fact-ev $kb $prf $type))
      ((not-fact-ev $kb $prf $type) (fact-ev $kb $prf $type))
      ($other (not-ev $other)))))

(: evidence-negate-list
   (-> (List Evidence) (List Evidence)))
(= (evidence-negate-list ()) ())
(= (evidence-negate-list (cons $ev $rest))
   (cons (evidence-negate $ev) (evidence-negate-list $rest)))

(: proof-term-negated? (-> Proof Bool))
(= (proof-term-negated? $prf)
   (if (is-expr $prf) (== (car-atom $prf) negated) false))

(: proof-term-evidence-list-mode
   (-[semidet]-> $mode Proof (List Evidence)))
(= (proof-term-evidence-list-mode $mode $prf)
   (case $prf (
      ((@ $_ref (proof-ref $pid))
         (let ($_score $evidence)
            (proof-stats-by-id (the Number $pid))
            $evidence))
      ((@ $_merge (merge/revision $left $right))
         (let*
            (($left-proof (brand Proof $left))
             ($right-proof (brand Proof $right)))
            (append
               (proof-term-evidence-list-mode $mode $left-proof)
               (proof-term-evidence-list-mode $mode $right-proof))))
      ($_other
         (if (is-var $prf) ()
            (if (assumption-proof? $prf) ()
               (if (proof-term-negated? $prf)
                  (let $inner-proof
                     (brand Proof (car-atom (cdr-atom $prf)))
                     (evidence-negate-list
                        (proof-term-evidence-list-mode
                           $mode $inner-proof)))
                  (let $children (proof-term-children-mode $mode $prf)
                     (if (== $children ()) (cons $prf ())
                        (proof-term-evidence-children-mode $mode $children))))))))))

(: proof-atom-evidence-set
   (-[semidet]-> (Statement KBContext Proof TV)
       (List Evidence)))
(= (proof-atom-evidence-set ($_type $kb $prf $_tv))
   (list_to_set
      (once
         (proof-term-evidence-list-mode
            proof-walk-in-kb (brand Proof $prf)))))

(: evidence-intersection
   (-> (List Evidence) (List Evidence) (List Evidence)))
(= (evidence-intersection $set-a $set-b)
   (fold-flat
      (evidence-intersection-step $set-b)
      () $set-a))

(: evidence-intersection-step
   (-> (List Evidence) (List Evidence) Evidence (List Evidence)))
(= (evidence-intersection-step $set-b $acc $entry)
   (if (is-member $entry $set-b)
      (cons $entry $acc)
      $acc))

(: evidence-sets-overlap?
   (-> (List Evidence) (List Evidence) Bool))
(= (evidence-sets-overlap? $set-a $set-b)
   (not (== (evidence-intersection $set-a $set-b) ())))

(: fact-evidence-only-step
   (-> (List Evidence) Evidence (List Evidence)))
(= (fact-evidence-only-step $acc $entry)
   (if (= $entry (rule-ev $_kb $_name))
      $acc
      (append $acc (cons $entry ()))))

(: fact-evidence-only
   (-> (List Evidence) (List Evidence)))
(= (fact-evidence-only $ev) (fold-flat fact-evidence-only-step () $ev))

;; The non-fact part of an evidence set (rule applications and hypotheses).
;; Two proofs are genuinely *dependent* only when these overlap: sharing a fact
;; is poolable (lifting-merge factors the shared fact out), whereas sharing a
;; rule or hypothesis means pooling would double-count its uncertainty.
(: non-fact-evidence
   (-> (List Evidence) (List Evidence)))
(= (non-fact-evidence $ev) (subtraction-atom $ev (fact-evidence-only $ev)))
(: evidence-sets-dependent?
   (-> (List Evidence) (List Evidence) Bool))
(= (evidence-sets-dependent? $set-a $set-b)
   (evidence-sets-overlap? (non-fact-evidence $set-a) (non-fact-evidence $set-b)))

(: premise-evidence-overlap?
   (-> (List Evidence) (List Evidence) Bool))
(= (premise-evidence-overlap? $seen $pev)
   (evidence-sets-overlap? (fact-evidence-only $seen) (fact-evidence-only $pev)))

(: evidence-subset?
   (-> (List Evidence) (List Evidence) Bool))
(= (evidence-subset? $set-a $set-b) (== (subtraction-atom $set-a $set-b) ()))

(: proof-term-contains-negated-list? (-> (List Proof) Bool))
(= (proof-term-contains-negated-list? ()) false)
(= (proof-term-contains-negated-list? (cons $child $rest))
   (or (proof-term-contains-negated? $child) (proof-term-contains-negated-list? $rest)))

(: proof-term-contains-negated? (-> Proof Bool))
(= (proof-term-contains-negated? $prf)
   (if (is-var $prf) false
      (if (proof-term-negated? $prf) true
         (if (is-expr $prf) (proof-term-contains-negated-list? (cdr-atom $prf)) false))))

(: rule-evidence-head (-> Proof Proof))
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
   (-> KBContext Proof (List Evidence)))
(= (rule-application-evidence $kb $prf)
   (once
      (if (= $kb ($kbid $_ctx $_vars))
         (let $name (rule-evidence-head $prf)
            (if (is-expr $name) ()
               (if (rule-evidence-registered?
                     (brand KB $kbid) (brand Proof $name))
                  (cons
                     (rule-ev
                        (brand KB $kbid) (brand Proof $name))
                     ())
                  ())))
         ())))

;; Forward materialization and backward rule application must attach exactly
;; the same provenance.  Otherwise a materialized rule result looks like a new
;; independent fact when the backward chainer rediscovers that rule path.
(: rule-result-evidence
   (-[semidet]-> (Statement KBContext Proof TV)
       (List Evidence) (List Evidence)))
(= (rule-result-evidence ($_type $kb $prf $_tv) $ev)
   (let*
      (($base
          (if (proof-term-contains-negated? $prf)
             (list_to_set (once (proof-term-evidence-list-mode proof-walk-in-kb $prf)))
             $ev))
       ($rule-ev (rule-application-evidence $kb $prf)))
      (if (== $rule-ev ()) $base (list_to_set (append $base $rule-ev)))))

(: projection-proof-key
   (-> Proof (| (projection-key $index $base) NoProjectionKey)))
(= (projection-proof-key $prf)
   (case $prf (
      ((marginal-proj $idx $base) (projection-key $idx $base))
      (((proj $idx $base) $_evidence) (projection-key $idx $base))
      ($_ no-projection-key))))

(: strict-projection-proof? (-> Proof Bool))
(= (strict-projection-proof? $prf)
   (case $prf (
      (((proj $_idx $_base) $_evidence) true)
      ($_ false))))

(: projection-dominates? (-> Proof Proof Bool))
(= (projection-dominates? $prf-a $prf-b)
   (let $key-a (projection-proof-key $prf-a)
      (and (not (== $key-a no-projection-key))
         (and (== $key-a (projection-proof-key $prf-b))
            (and (strict-projection-proof? $prf-a)
               (not (strict-projection-proof? $prf-b)))))))

(: merge-proof-candidates
   (-> ((Statement KBContext Proof TV) (List Evidence))
       ((Statement KBContext Proof TV) (List Evidence))
       ((Statement KBContext Proof TV) (List Evidence))))
(= (merge-proof-candidates ($proof-a $ev-a) ($proof-b $ev-b))
   (if (== $proof-a $proof-b)
      ($proof-a (list_to_set (append $ev-a $ev-b)))
      (let*
         (($overlap? (evidence-sets-overlap? $ev-a $ev-b))
          ($all-ev (list_to_set (append $ev-a $ev-b)))
          ($proof-token-a (proof-atom-proof $proof-a))
          ($proof-token-b (proof-atom-proof $proof-b)))
         (if (projection-dominates? $proof-token-a $proof-token-b)
            ($proof-a $ev-a)
            (if (projection-dominates? $proof-token-b $proof-token-a)
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

(: proof-candidate-pair
   (-> (Statement KBContext Proof TV) (List Evidence)
       ((Statement KBContext Proof TV) (List Evidence))))
(= (proof-candidate-pair $proof $evidence)
   (quote ($proof $evidence)))

(: merge-proof-atoms
   (-[semidet]-> (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)))
(= (merge-proof-atoms $proof-a $proof-b)
   (let ($merged $_ev)
      (merge-proof-candidates
         (proof-candidate-pair
            $proof-a (proof-atom-evidence-set $proof-a))
         (proof-candidate-pair
            $proof-b (proof-atom-evidence-set $proof-b)))
      $merged))

;; Base-rate cache operations are shared by forward chaining and the compiled
;; query runtime, so they must be available before either consumer is loaded.
(: base-rate-cache-entries (-> KB Statement (List BaseRateEntry)))
(= (base-rate-cache-entries $kbid $pattern)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $mode)
         (if (=alpha $stored $pattern)
            (base-rate $kbid $stored $tv $source $mode)
            (empty)))))

(: base-rate-cache-entries-for-mode
   (-> KB Statement $mode (List BaseRateEntry)))
(= (base-rate-cache-entries-for-mode $kbid $pattern $mode)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $emode)
         (if (and (=alpha $stored $pattern)
                  (or (== $emode any) (== $emode $mode)))
            (base-rate $kbid $stored $tv $source $emode)
            (empty)))))

(: base-rate-cache-remove-entry!
   (-[det]-> BaseRateEntry Bool))
(= (base-rate-cache-remove-entry! $entry)
   (remove-atom &base_rate_cache $entry))

(: base-rate-cache-remove! (-> KB Statement (List $none)))
(= (base-rate-cache-remove! $kbid $pattern)
   (let $_
      (foreach-flat base-rate-cache-remove-entry!
         (base-rate-cache-entries $kbid $pattern))
      ()))

(: base-rate-cache-remove-derived!
   (-> KB Statement $mode (List $none)))
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

(: cached-base-rate
   (-[nondet]-> KB Statement  (| TV (List $no-result))))
(= (cached-base-rate $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) ()
         (let (base-rate $_kbid $_stored $tv $_source $_mode)
            (car-atom $entries)
            ($tv)))))

(: base-rate-user-set? (-> KB Statement Bool))
(= (base-rate-user-set? $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) false
         (let (base-rate $_kbid $_stored $_tv $source $_mode)
            (car-atom $entries)
            (== $source user)))))

(: store-base-rate! (-> KB Statement TV (List $none)))
(= (store-base-rate! $kbid $pattern $tv)
   (let*
      (($stored (copy_term $pattern))
       ($_old (base-rate-cache-remove! $kbid $pattern))
       ($_new
          (add-atom &base_rate_cache
             (base-rate $kbid $stored $tv user any))))
      ()))

(: set-base-rate (-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (store-base-rate! $kbid $pattern $tv))

(: clear-base-rate (-> KB Statement (List $none)))
(= (clear-base-rate $kbid $pattern)
   (base-rate-cache-remove! $kbid $pattern))

(: store-computed-base-rate!
   (-> KB Statement TV $mode (List $none)))
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
   (-> KB Statement TV $mode (List $none)))
(= (store-forward-base-rate! $kbid $pattern $tv $mode)
   (if (or (== $tv no-evidence) (base-rate-user-set? $kbid $pattern)) ()
      (let*
         (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove-derived! $kbid $pattern $mode))
          ($_new
             (add-atom &base_rate_cache
                (base-rate $kbid $stored $tv forward-approx $mode))))
         ())))

(: invalidate-computed-base-rates! (-> KB (List $none)))
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

(: universe-size-entries (-> KB (List UniverseSizeEntry)))
(= (universe-size-entries $kbid)
   (collapse
      (match &universe_size (universe-size $kbid $n)
         (universe-size $kbid $n))))

(: universe-size-remove-entry!
   (-[det]-> UniverseSizeEntry Bool))
(= (universe-size-remove-entry! $entry)
   (remove-atom &universe_size $entry))

(: clear-universe-size (-> KB (List $none)))
(= (clear-universe-size $kbid)
   (let*
      (($_remove
          (foreach-flat universe-size-remove-entry!
             (universe-size-entries $kbid)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-universe-size (-> KB Number (List $none)))
(= (set-universe-size $kbid $n)
   (let*
      (($_old (clear-universe-size $kbid))
       ($_new (add-atom &universe_size (universe-size $kbid $n)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: kb-universe-size
   (-> KB (| Number UniverseSizeUnavailable)))
(= (kb-universe-size $kbid)
   (let $entries (universe-size-entries $kbid)
      (if (== $entries ()) no-universe-size
         (let (universe-size $_kbid $n) (car-atom $entries) $n))))

(: inheritance-subjects (-[det]-> KB (List Statement)))
(= (inheritance-subjects $kbid)
   (list_to_set
      (collapse
         (match &inheritance_subject ($kbid $subj) $subj))))

;; Concept metadata and aggregate finalizers are shared by both forward and
;; backward execution, so they must be available before forward_chainer loads.
(: record-concept-node! (-> KB Statement (| Bool (List $none))))
(= (record-concept-node! $kbid $node)
   (if (is-var $node) ()
      (once
         (add-atom &concept_node ($kbid $node)))))

(: record-inheritance-nodes!
   (-> KB Statement Statement (| Bool (List $none))))
(= (record-inheritance-nodes! $kbid $subj $concept)
   (progn
      (record-concept-node! $kbid $subj)
      (record-concept-node! $kbid $concept)))

(: default-concept-prior-confidence (-> Number))
(= (default-concept-prior-confidence) 0.000001)

(: concept-prior-confidence-entries
   (-> KB (List ConceptPriorConfidence)))
(= (concept-prior-confidence-entries $kbid)
   (collapse
      (match &concept_prior_confidence
         (concept-prior-confidence $kbid $c)
         (concept-prior-confidence $kbid $c))))

(: concept-prior-confidence-remove-entry!
   (-[det]-> ConceptPriorConfidence Bool))
(= (concept-prior-confidence-remove-entry! $entry)
   (remove-atom &concept_prior_confidence $entry))

(: clear-concept-prior-confidence (-> KB (List $none)))
(= (clear-concept-prior-confidence $kbid)
   (let*
      (($_remove
          (foreach-flat concept-prior-confidence-remove-entry!
             (concept-prior-confidence-entries $kbid)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-concept-prior-confidence (-> KB Number (List $none)))
(= (set-concept-prior-confidence $kbid $c)
   (let*
      (($_old (clear-concept-prior-confidence $kbid))
       ($_new
          (add-atom &concept_prior_confidence
             (concept-prior-confidence $kbid $c)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: kb-concept-prior-confidence (-> KB Number))
(= (kb-concept-prior-confidence $kbid)
   (let $entries (concept-prior-confidence-entries $kbid)
      (if (== $entries ()) (default-concept-prior-confidence)
         (let (concept-prior-confidence $_kbid $c)
            (car-atom $entries)
            $c))))

(: known-concept-node? (-> KB Statement Bool))
(= (known-concept-node? $kbid $node)
   (not
      (== (collapse
             (once
                (match &concept_node ($kbid $node) true)))
          ())))

(: concept-nodes (-[det]-> KB (List Statement)))
(= (concept-nodes $kbid)
   (list_to_set
      (collapse
         (match &concept_node ($kbid $node) $node))))

(: concept-node-prior-tv (-> KB Statement TV))
(= (concept-node-prior-tv $kbid $node)
   (if (known-concept-node? $kbid $node)
      (let $n (list-len (concept-nodes $kbid))
         (if (<= $n 0) no-evidence
            (STV (/ 1.0 $n)
               (kb-concept-prior-confidence $kbid))))
      no-evidence))

(: ConceptNodePriorFormula (-[det]-> KB Statement TV))
(= (ConceptNodePriorFormula $kbid $node)
   (concept-node-prior-tv $kbid $node))

(: resolve-base-rate-prior (-> BaseRatePrior TV))
(= (resolve-base-rate-prior (ConceptNodePriorRuntime $kbid $node))
   (concept-node-prior-tv
      (brand KB $kbid) (brand Statement $node)))
(= (resolve-base-rate-prior (STV $s $c)) (STV $s $c))
(= (resolve-base-rate-prior no-evidence) no-evidence)

(: WeightedBaseRateWithPriorTv
   (-[semidet]-> BaseRateEvidenceWithPriorState TV))
(= (WeightedBaseRateWithPriorTv
      (BaseRateEvidenceWithPrior $prior $ev))
   (BaseRateWithPriorFormula
      (resolve-base-rate-prior (brand BaseRatePrior $prior))
      (WeightedBaseRateTv $ev)))

(: member-inheritance-tv (-> KB BaseRateEvidenceState TV))
(= (member-inheritance-tv $kbid $ev)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedCountBaseRateTv $ev)
         (WeightedUniverseBaseRateTv
            (the Number $universe-size) $ev))))
