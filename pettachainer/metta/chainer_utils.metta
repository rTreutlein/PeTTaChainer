;;;;;;;;;;;;;;;;;;;;;
;; Chainer Helpers ;;
;;;;;;;;;;;;;;;;;;;;;
;; Confidence helpers.
(= (or-1.0 $x) (if (is-var $x) 1.0 $x))

(= (tv-confidence $tv) (if (is-var $tv) 1.0 (if (= $tv (STV $_s $c)) (or-1.0 $c) 1.0)))

;; Rule-native expected confidence extraction from compiled premises.
(= (normalize-expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0) (if (= $tv (STV $s $c)) (STV (or-1.0 $s) (or-1.0 $c)) $tv)))

(= (cpu-expected-confidence $fun $args)
   (if (is-member $fun (() MpFormula AndFormula OrFormula LikelierThanFormula))
      (let*
         ((($a $b) $args)
           ($res (reduce (reduce (cons $fun ((normalize-expected-tv $a) (normalize-expected-tv $b)))))))
         (tv-confidence $res))
      1.0))

;; Unified confidence extraction for both expected and concrete terms.
(= (term-confidence $term)
   (case $term (
        ((CPU $fun $args $res) (if (is-var $res) (cpu-expected-confidence $fun $args) (tv-confidence $res)))
        ((: $_kb $_prf $_type $tv) (tv-confidence $tv))
        ($other 1.0))))

(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (min (term-confidence $prem) (premises-expected-confidence $rest)))

;; Goal typing and alpha-equivalence helpers.
(= (goal-type-key $goal) (if (proof-atom? $goal) (let (: $_kb $_prf $type $_tv) $goal $type) $goal))

(= (same-alpha-type? $a $b) (=alpha (goal-type-key $a) (goal-type-key $b)))

;; Revision helpers for truth-value merging.
(= (K) 800)

(= (confidence-to-count $conf) (/ (* $conf (K)) (- 1 (min-atom ($conf 0.9999)))))

(= (count-to-confidence $count) (/ $count (+ $count (K))))

(= (mean-update $m1 $m2 $c1 $c2) (/ (+ (* $m1 $c1) (* $m2 $c2)) (+ $c1 $c2)))

(= (mergetvs (STV $m1 $conf1) (STV $m2 $conf2))
   (let*
      (($count1 (confidence-to-count $conf1))
        ($count2 (confidence-to-count $conf2))
        ($m (mean-update $m1 $m2 $count1 $count2))
        ($c (+ $count1 $count2))
        ($conf (count-to-confidence $c)))
      (STV $m $conf)))

;; Revision adapter for merging two proof atoms with alpha-equivalent types.
(= (RevisionMergeProof (: $kb $prf1 $type1 $tv1) (: $_kb2 $prf2 $_type2 $tv2))
   (: $kb (merge/revision $prf1 $prf2) $type1 (if (and (= $tv1 (STV $_m1 $_c1)) (= $tv2 (STV $_m2 $_c2))) (mergetvs $tv1 $tv2) $tv1)))

(= (proof-atom? $term) (if (and (not (is-var $term)) (= $term (: $_kb $_prf $_type $_tv))) true false))

(= (proof-tree-contains-list () $needle) false)
(= (proof-tree-contains-list (cons $head $tail) $needle)
   (or (proof-tree-contains $head $needle) (proof-tree-contains-list $tail $needle)))

(= (proof-tree-contains $tree $needle)
   (if (== $tree $needle) true (if (is-expr $tree) (proof-tree-contains-list (cdr-atom $tree) $needle) false)))

(= (merge-proof-term? $prf) (if (= $prf (merge/revision $_a $_b)) true false))

(= (list-append () $ys) $ys)
(= (list-append (cons $x $xs) $ys) (cons $x (list-append $xs $ys)))

;; Evidence is tracked as canonical proof leaves (axiom/fact proof ids).
;; For composed proof terms (rule application, conjunction, merge/revision),
;; we collect evidence recursively from arguments only.
(= (proof-term-evidence-list $prf)
   (if (is-var $prf) () (if (is-expr $prf) (proof-term-evidence-list-args (cdr-atom $prf)) (cons $prf ()))))

(= (proof-term-evidence-list-args ()) ())
(= (proof-term-evidence-list-args (cons $head $tail))
   (list-append (proof-term-evidence-list $head) (proof-term-evidence-list-args $tail)))

(= (proof-atom-evidence-set $proof)
   (if (= $proof (: $_kb $prf $_type $_tv)) (list_to_set (proof-term-evidence-list $prf)) ()))

(= (evidence-sets-overlap? () $set-b) false)
(= (evidence-sets-overlap? (cons $head $tail) $set-b)
   (or (is-member $head $set-b) (evidence-sets-overlap? $tail $set-b)))

(= (merge-proof-atoms $proof-a $proof-b)
   (if (== $proof-a $proof-b) $proof-a
      (if (and (proof-atom? $proof-a) (proof-atom? $proof-b))
         (let (: $_kba $prfa $_ta $_tva) $proof-a
            (let (: $_kbb $prfb $_tb $_tvb) $proof-b
               (if (and (merge-proof-term? $prfa) (proof-tree-contains $prfa $prfb)) $proof-a
                  (if (and (merge-proof-term? $prfb) (proof-tree-contains $prfb $prfa)) $proof-b
                     (let*
                        (($ev-a (proof-atom-evidence-set $proof-a))
                          ($ev-b (proof-atom-evidence-set $proof-b))
                          ($overlap? (evidence-sets-overlap? $ev-a $ev-b)))
                        (if $overlap?
                           (if (>= (term-confidence $proof-a) (term-confidence $proof-b)) $proof-a $proof-b)
                           (if (>= (term-confidence $proof-a) (term-confidence $proof-b))
                              (RevisionMergeProof $proof-a $proof-b)
                              (RevisionMergeProof $proof-b $proof-a))))))))
         $proof-a)))

;; Global goal cache (space-backed): unique by alpha-equivalent type.
(= (goal-cache-upsert $gcache $goal)
   (let*
      (($hits
           (collapse
              (match $gcache (gmerge $old-goal)
                 (if (same-alpha-type? $old-goal $goal) $old-goal (empty)))))
        ($_ (fold-flat (|-> ($acc $old-goal) (progn (remove-atom $gcache (gmerge $old-goal)) $acc)) () $hits))
        ($merged-goal (fold-flat merge-proof-atoms $goal $hits))
        ($_ (add-atom $gcache (gmerge $merged-goal))))
      $merged-goal))

;; Build queue items from rule matches for a goal.
(= (candidate-item $score $args $goal $cont)
   (let $item (cand ($args |- $goal) $cont) (qitem $score (copy_term $item))))

(= (heap-drop-resume-cand $heap $rid $proof)
   (if (== (heap_size $heap) 0) (empty_heap)
      (let*
         (($rest (get_from_heap $heap $priority (qitem $score $payload)))
           ($nrest (heap-drop-resume-cand $rest $rid $proof))
           ($drop?
              (case $payload (
                   ((resume-cand $rid $rtype $_cand) (same-alpha-type? $rtype $proof))
                   ($_p false)))))
         (if $drop? $nrest (add_to_heap $nrest $priority (qitem $score $payload))))))

;; Resume cache (space-backed): unique by (rid + alpha-equivalent type).
(= (resume-cache-upsert $rcache $rid $proof)
   (let*
      (($hits
           (collapse
              (match $rcache (rmerge $rid $old-proof)
                 (if (same-alpha-type? $old-proof $proof) $old-proof (empty)))))
        ($_
           (fold-flat (|-> ($acc $old-proof) (progn (remove-atom $rcache (rmerge $rid $old-proof)) $acc))
              ()
              $hits))
        ($merged-proof (fold-flat merge-proof-atoms $proof $hits))
        ($_ (add-atom $rcache (rmerge $rid $merged-proof))))
      $merged-proof))

(=
   (resume-merge-enqueue (state $pq $rcache $gcache)
      $rid
      $prem
      $proved-goal
      $rest
      $goal
      $parent-score
      $rest-cont)
   (let*
      (($merged-proof (resume-cache-upsert $rcache $rid $proved-goal))
        ($_u (= $prem $merged-proof))
        ($new-score (min $parent-score (term-confidence $merged-proof)))
        ($clean-pq (heap-drop-resume-cand $pq $rid $proved-goal))
        ($next
           (state-enqueue-item (state $clean-pq $rcache $gcache)
              (qitem $new-score
                 (resume-cand $rid (goal-type-key $merged-proof) (cand ($rest |- $goal) $rest-cont))))))
      (reduce $next)))

(=
   (resume-merge-enqueue-cont $state
      $proved-goal
      (cons (resume $rid $prem $rest $goal $parent-score) $rest-cont))
   (resume-merge-enqueue $state
      $rid
      $prem
      $proved-goal
      $rest
      $goal
      $parent-score
      $rest-cont))
