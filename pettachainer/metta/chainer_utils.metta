(= (tv-confidence $tv)
   (if (is-var $tv) 1.0
      (if (= $tv (STV $_s $c)) (if (is-var $c) 1.0 $c)
         (if (= $tv (CTV $pos $neg)) (min (tv-confidence $pos) (tv-confidence $neg)) 1.0))))

(= (goal-has-type-vars? ($type ($_kbid $_ctx $vars) $_prf $_tv))
   (or (not (== (extract-vars $type) ())) (not (== $vars Nil))))
(= (goal-has-type-vars? (CPU $fun $args $res))
   (not (== (extract-vars (CPU $fun $args $res)) ())))

(= (goal-key ($type ($kbid $ctx $vars) $_prf $_tv))
   (let $sealed-goal (sealed (extract-vars ($type $vars)) ($type $vars))
      ($sealed-goal ($kbid $ctx))))
(= (goal-key (CPU $fun $args $res)) (sealed (extract-vars (CPU $fun $args $res)) (CPU $fun $args $res)))

(= (normalize-expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (if (= $tv (STV $s $c)) (STV (if (is-var $s) 1.0 $s) (if (is-var $c) 1.0 $c))
         (if (= $tv (CTV $pos $neg)) (CTV (normalize-expected-tv $pos) (normalize-expected-tv $neg)) $tv))))

(= (cpu-expected-tv $fun $args)
   (if (== $fun CTVModusPonensFormula)
      (let*
         ((($a $ctv) $args)
           ($res
              (reduce
                 (reduce
                    (cons $fun
                       ((normalize-expected-tv $a) (normalize-expected-tv $ctv)))))))
         $res)
      (if (is-member $fun (() AndFormula OrFormula LikelierThanFormula))
      (let*
         ((($a $b) $args)
           ($res (reduce (reduce (cons $fun ((normalize-expected-tv $a) (normalize-expected-tv $b)))))))
         $res)
      (if (== $fun NotFormula)
         (let $a (car-atom $args)
            (if (is-var $a)
               (STV 1.0 1.0)
               (if (= $a (STV $s $c))
                  (STV (if (is-var $s) 1.0 (- 1 $s)) (if (is-var $c) 1.0 $c))
                  (let (STV $s $c) (normalize-expected-tv $a) (STV (- 1 $s) $c)))))
         (if (== $fun CTVInversionFormula)
            (let*
               ((($a $b $ctv) $args)
                 ($na (normalize-expected-tv $a))
                 ($nb (normalize-expected-tv $b))
                 ($nctv (normalize-expected-tv $ctv))
                 ($res
                    (if (or (is-var $a) (is-var $b))
                       (CTV
                          (STV 1.0 (* (min-atom ((tv-confidence $na) (tv-confidence $nb) (tv-confidence $nctv))) 0.9))
                          (STV 1.0 (* (min-atom ((tv-confidence $na) (tv-confidence $nb) (tv-confidence $nctv))) 0.9)))
                       (reduce (reduce (cons $fun ($na $nb $nctv)))))))
               $res)
            ())))))

(= (first-cpu-expected-tv $fun $args)
   (let $res (let $hits (collapse (cpu-expected-tv $fun $args)) (if (== $hits ()) () (car-atom $hits)))
      $res))

(= (cpu-expected-confidence $fun $args)
   (let $res (first-cpu-expected-tv $fun $args)
      (if (== $res ()) 1.0 (tv-confidence $res))))

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

(= (term-confidence (CPU $fun $args $res))
   (if (is-var $res) (cpu-expected-confidence $fun $args) (tv-confidence $res)))
(= (term-confidence ($_type ($_kbid $_ctx $_vars) $_prf $tv)) (tv-confidence $tv))

(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (premises-expected-confidence-step $prem $rest))

(= (score-tv $score) (STV 1.0 (max 0.0 (min 1.0 $score))))

(= (optimistic-revision-score $current-score $candidate-score)
   (tv-confidence (mergetvs (score-tv $current-score) (score-tv $candidate-score))))

(= (rule-marginal-score no-current $candidate-score) $candidate-score)
(= (rule-marginal-score $current-score $candidate-score)
   (max 0.000001
      (- (max $candidate-score (optimistic-revision-score $current-score $candidate-score))
         $current-score)))

(= (bounded-agenda-target-size $steps) (min 1000 (max 1 $steps)))
(= (bounded-agenda-prune-factor) 64)

(= (set-bounded-agenda-pruning $enabled) (change-state! bounded_agenda_pruning $enabled))
(= (bounded-agenda-pruning?)
   (let $enabled (catch (get-state bounded_agenda_pruning))
      (if-error $enabled true $enabled)))

(= (heap-take-best $count $src $dst)
   (if (or (<= $count 0) (== (heap_size $src) 0)) $dst
      (let*
         (($rest (get_from_heap $src $key $item))
          ($next (add_to_heap $dst $key $item)))
         (heap-take-best (- $count 1) $rest $next))))

(= (heap-prune-to-size $target $agenda)
   (heap-take-best $target $agenda (empty_heap)))

(= (bounded-agenda-prune $steps $agenda)
   (if (not (bounded-agenda-pruning?)) $agenda
      (let*
         (($target (bounded-agenda-target-size $steps))
          ($size (heap_size $agenda))
          ($threshold (* $target (bounded-agenda-prune-factor))))
         (if (> $size $threshold)
            (heap-prune-to-size $target $agenda)
            $agenda))))

(= (confidence-to-count $conf) (/ (* $conf 800) (- 1 (min-atom ($conf 0.9999)))))

(= (mergetvs (STV $m1 $conf1) (STV $m2 $conf2))
   (let*
      (($count1 (confidence-to-count $conf1))
        ($count2 (confidence-to-count $conf2))
        ($m (/ (+ (* $m1 $count1) (* $m2 $count2)) (+ $count1 $count2)))
        ($c (+ $count1 $count2))
        ($conf (/ $c (+ $c 800))))
      (STV $m $conf)))

(= (RevisionMergeProof ($type1 $kb $prf1 $tv1) ($_type2 $_kb2 $prf2 $tv2))
   ($type1 $kb
      (merge/revision $prf1 $prf2)
      (if (and (= $tv1 (STV $_m1 $_c1)) (= $tv2 (STV $_m2 $_c2))) (mergetvs $tv1 $tv2) $tv1)))

(= (foreach-flat $f ()) ())
(= (foreach-flat $f (cons $x $xs)) (progn ($f $x) (foreach-flat $f $xs)))

(= (chainer-add-atom $space $expr)
   (if (== (collapse (callPredicate (Predicate (cyclic_term $expr)))) ())
      (add-atom $space $expr)
      (empty)))


(= (next-search-id $key)
   (let*
      (($mn (catch (get-state $key)))
        ($n (if-error $mn 0 $mn)))
      (progn (change-state! $key (+ $n 1)) $n)))

(= (next-gid) (next-search-id bwd_gid))

(= (next-pid) (next-search-id bwd_pid))

(= (cpu-call $_steps $fun $args) (reduce (reduce (cons $fun $args))))

(= (proof-stats-by-id $pid) (match &proof ($pid $_gid $_output $_kind $score $ev $_children) ($score $ev)))

(= (proof-term-leaf-head? $head) (is-member $head (() fact-ev CPU STV CTV)))

(= (proof-term-children-mode $_mode (@ $prf (head conjunction))) (cdr-atom $prf))
(= (proof-term-children-mode proof-walk-in-kb (@ $prf (head $head)))
   (if (proof-term-leaf-head? $head) () (cdr-atom $prf)))
(= (proof-term-children-mode $_mode $_prf) ())

(= (proof-term-children $prf) (proof-term-children-mode proof-walk-plain $prf))

(= (proof-term-evidence-children-mode $mode ()) ())
(= (proof-term-evidence-children-mode $mode (cons $child $rest))
   (append (proof-term-evidence-list-mode $mode $child)
      (proof-term-evidence-children-mode $mode $rest)))

(= (evidence-negate $ev)
   (case $ev (
      ((fact-ev $kb $prf $type) (not-fact-ev $kb $prf $type))
      ((not-fact-ev $kb $prf $type) (fact-ev $kb $prf $type))
      ($other (not-ev $other)))))

(= (evidence-negate-list ()) ())
(= (evidence-negate-list (cons $ev $rest))
   (cons (evidence-negate $ev) (evidence-negate-list $rest)))

(= (proof-term-negated? $prf)
   (if (is-expr $prf) (== (car-atom $prf) negated) false))

(= (proof-term-evidence-list-mode $mode (@ $prf (proof-ref $pid))) (snd (proof-stats-by-id $pid)))
(= (proof-term-evidence-list-mode $mode (@ $prf (merge/revision $left $right)))
   (append (proof-term-evidence-list-mode $mode $left) (proof-term-evidence-list-mode $mode $right)))
(= (proof-term-evidence-list-mode $mode $prf)
   (if (is-var $prf) ()
      (if (assumption-proof? $prf) ()
         (if (proof-term-negated? $prf)
            (evidence-negate-list (proof-term-evidence-list-mode $mode (car-atom (cdr-atom $prf))))
            (let $children (proof-term-children-mode $mode $prf)
               (if (== $children ()) (cons $prf ()) (proof-term-evidence-children-mode $mode $children)))))))

(= (proof-term-evidence-list $prf) (once (proof-term-evidence-list-mode proof-walk-plain $prf)))

(= (proof-atom-evidence-set ($_type $kb $prf $_tv))
   (list_to_set (once (proof-term-evidence-list-mode proof-walk-in-kb $prf))))

(= (evidence-sets-overlap? $set-a $set-b) (not (== (intersection-atom $set-a $set-b) ())))

(= (fact-evidence-only-step $acc $entry)
   (if (= $entry (rule-ev $_kb $_name)) $acc (append $acc ($entry))))

(= (fact-evidence-only $ev) (fold-flat fact-evidence-only-step () $ev))

(= (premise-evidence-overlap? $seen $pev)
   (evidence-sets-overlap? (fact-evidence-only $seen) (fact-evidence-only $pev)))

(= (evidence-subset? $set-a $set-b) (== (subtraction-atom $set-a $set-b) ()))

(= (proof-term-contains-negated-list? ()) false)
(= (proof-term-contains-negated-list? (cons $child $rest))
   (or (proof-term-contains-negated? $child) (proof-term-contains-negated-list? $rest)))

(= (proof-term-contains-negated? $prf)
   (if (is-var $prf) false
      (if (proof-term-negated? $prf) true
         (if (is-expr $prf) (proof-term-contains-negated-list? (cdr-atom $prf)) false))))

(= (merge-proof-atoms $proof-a $proof-b)
   (if (== $proof-a $proof-b) $proof-a
      (let*
         (($ev-a (proof-atom-evidence-set $proof-a))
           ($ev-b (proof-atom-evidence-set $proof-b))
           ($overlap? (evidence-sets-overlap? $ev-a $ev-b)))
         (if $overlap?
            (if (>= (term-confidence $proof-a) (term-confidence $proof-b)) $proof-a $proof-b)
            (if (>= (term-confidence $proof-a) (term-confidence $proof-b))
               (RevisionMergeProof $proof-a $proof-b)
               (RevisionMergeProof $proof-b $proof-a))))))
