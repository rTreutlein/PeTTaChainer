(= (or-1.0 $x) (if (is-var $x) 1.0 $x))

(= (tv-confidence $tv) (if (is-var $tv) 1.0 (if (= $tv (STV $_s $c)) (or-1.0 $c) 1.0)))

(= (normalize-expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0) (if (= $tv (STV $s $c)) (STV (or-1.0 $s) (or-1.0 $c)) $tv)))

(= (cpu-expected-confidence $fun $args)
   (if (is-member $fun (() MpFormula AndFormula OrFormula LikelierThanFormula))
      (let*
         ((($a $b) $args)
           ($res (reduce (reduce (cons $fun ((normalize-expected-tv $a) (normalize-expected-tv $b)))))))
         (tv-confidence $res))
      1.0))

(= (term-confidence $term)
   (case $term (
        ((CPU $fun $args $res) (if (is-var $res) (cpu-expected-confidence $fun $args) (tv-confidence $res)))
        (($_type ($_kbid $_ctx $_vars) $_prf $tv) (tv-confidence $tv))
        ((: $_kb $_prf $_type $tv) (tv-confidence $tv))
        ($other 1.0))))

(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (min (term-confidence $prem) (premises-expected-confidence $rest)))

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

(= (RevisionMergeProof ($type1 $kb $prf1 $tv1) ($_type2 $_kb2 $prf2 $tv2))
   ($type1 $kb
      (merge/revision $prf1 $prf2)
      (if (and (= $tv1 (STV $_m1 $_c1)) (= $tv2 (STV $_m2 $_c2))) (mergetvs $tv1 $tv2) $tv1)))

(= (list-append () $ys) $ys)
(= (list-append (cons $x $xs) $ys) (cons $x (list-append $xs $ys)))

(= (list-reverse-acc () $acc) $acc)
(= (list-reverse-acc (cons $head $tail) $acc) (list-reverse-acc $tail (cons $head $acc)))

(= (list-reverse $xs) (list-reverse-acc $xs ()))

(= (proof-atom? $term)
   (if (not (is-var $term))
      (or (= $term ($_type ($_kbid $_ctx $_vars) $_prf $_tv)) (= $term (: $_kb $_prf $_type $_tv)))
      false))

(= (goal-key-components $goal)
   (if (= $goal (: $kb $_prf $type $_tv)) ($kb $type)
      (if (= $goal ($type ($kbid $_ctx $_vars) $_prf $_tv)) (($kbid $_ctx $_vars) $type) ())))

(= (goal-key-eq? $a $b)
   (let $keya (goal-key-components $a)
      (if (== $keya ()) (or (== $a $b) (=alpha $a $b))
         (let ($kba $typea) $keya
            (let $keyb (goal-key-components $b)
               (if (== $keyb ()) false
                  (let ($kbb $typeb) $keyb
                     (and (== $kba $kbb) (or (== $typea $typeb) (=alpha $typea $typeb))))))))))

(= (next-search-id $key)
   (let*
      (($mn (catch (get-state $key)))
        ($n (if-error $mn 0 $mn)))
      (progn (change-state! $key (+ $n 1)) $n)))

(= (next-gid) (next-search-id bwd_gid))

(= (next-aid) (next-search-id bwd_aid))

(= (next-pid) (next-search-id bwd_pid))

(= (next-fid) (next-search-id bwd_fid))

(= (proof-score-by-id $pid) (match &proof_score ($pid $score) $score))

(= (proof-tv-by-id $pid)
   (let $tvs (collapse (once (match &proof_tv ($pid $tv) $tv)))
      (if (== $tvs ()) (STV 1.0 1.0) (car-atom $tvs))))

(= (proof-evidence-by-id $pid) (match &proof_evidence ($pid $ev) $ev))

(= (proof-kind-by-id $pid) (match &proof_kind ($pid $kind) $kind))

(= (proof-term-tree $prf) (if (= $prf (proof-ref $pid)) (materialize-proof $pid) $prf))

(= (proof-tree-contains-list () $needle) false)
(= (proof-tree-contains-list (cons $head $tail) $needle)
   (or (proof-tree-contains $head $needle) (proof-tree-contains-list $tail $needle)))

(= (proof-tree-contains $tree $needle)
   (let*
      (($ptree (proof-term-tree $tree))
        ($pneedle (proof-term-tree $needle)))
      (if (== $ptree $pneedle) true
         (if (is-expr $ptree) (proof-tree-contains-list (cdr-atom $ptree) $pneedle) false))))

(= (merge-proof-term? $prf) (if (= $prf (merge/revision $_a $_b)) true false))

(= (rule-proof-id? $prf) (not (== (collapse (once (match &rule_proof_ids ($prf true) true))) ())))

(= (proof-term-children $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf)
         (if (== $head conjunction) (cdr-atom $prf)
            (if (is-expr $head) (cdr-atom $prf) (if (rule-proof-id? $head) (cdr-atom $prf) ()))))
      ()))

(= (proof-term-evidence-list-children ()) ())
(= (proof-term-evidence-list-children (cons $head $tail))
   (list-append (proof-term-evidence-list $head) (proof-term-evidence-list-children $tail)))

(= (proof-term-evidence-list $prf)
   (if (= $prf (proof-ref $pid)) (proof-evidence-by-id $pid)
      (if (is-var $prf) ()
         (if (= $prf (merge/revision $left $right))
            (list-append (proof-term-evidence-list $left) (proof-term-evidence-list $right))
            (let $children (proof-term-children $prf)
               (if (== $children ()) (cons $prf ()) (proof-term-evidence-list-children $children)))))))

(= (proof-atom-evidence-set ($_type $_kb $prf $_tv)) (list_to_set (proof-term-evidence-list $prf)))

(= (proof-atom-prf ($_type $_kb $prf $_tv)) $prf)

(= (evidence-sets-overlap? () $set-b) false)
(= (evidence-sets-overlap? (cons $head $tail) $set-b)
   (or (is-member $head $set-b) (evidence-sets-overlap? $tail $set-b)))

(= (merge-proof-atoms $proof-a $proof-b)
   (if (== $proof-a $proof-b) $proof-a
      (let*
         (($prfa (proof-atom-prf $proof-a))
           ($prfb (proof-atom-prf $proof-b)))
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
                        (RevisionMergeProof $proof-b $proof-a)))))))))
