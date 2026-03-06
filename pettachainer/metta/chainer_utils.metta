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

(= (RevisionMergeProof (: $kb $prf1 $type1 $tv1) (: $_kb2 $prf2 $_type2 $tv2))
   (: $kb (merge/revision $prf1 $prf2) $type1 (if (and (= $tv1 (STV $_m1 $_c1)) (= $tv2 (STV $_m2 $_c2))) (mergetvs $tv1 $tv2) $tv1)))

(= (list-append () $ys) $ys)
(= (list-append (cons $x $xs) $ys) (cons $x (list-append $xs $ys)))

(= (list-reverse-acc () $acc) $acc)
(= (list-reverse-acc (cons $head $tail) $acc) (list-reverse-acc $tail (cons $head $acc)))

(= (list-reverse $xs) (list-reverse-acc $xs ()))

(= (proof-atom? $term) (if (and (not (is-var $term)) (= $term (: $_kb $_prf $_type $_tv))) true false))

(= (goal-key-eq? $a $b)
   (if (= $a (: $kba $_prfa $typea $_tva))
      (if (= $b (: $kbb $_prfb $typeb $_tvb))
         (and (== $kba $kbb) (or (== $typea $typeb) (=alpha $typea $typeb)))
         false)
      (or (== $a $b) (=alpha $a $b))))

(= (next-search-id $key)
   (let $mn (catch (get-state $key))
      (let $n (if-error $mn 0 $mn) (progn (change-state! $key (+ $n 1)) $n))))

(= (next-gid) (next-search-id bwd_gid))

(= (next-aid) (next-search-id bwd_aid))

(= (next-pid) (next-search-id bwd_pid))

(= (next-fid) (next-search-id bwd_fid))

(= (proof-score-by-id $pid)
   (let $scores (collapse (match &proof_store (proof-score $pid $score) $score))
      (if (== $scores ()) 0.0 (car-atom $scores))))

(= (proof-tv-by-id $pid)
   (let $tvs (collapse (match &proof_store (proof-tv $pid $tv) $tv))
      (if (== $tvs ()) (STV 1.0 1.0) (car-atom $tvs))))

(= (proof-evidence-by-id $pid)
   (let $evidence (collapse (match &proof_store (proof-evidence $pid $ev) $ev))
      (if (== $evidence ()) () (car-atom $evidence))))

(= (proof-kind-by-id $pid)
   (let $kinds (collapse (match &proof_store (proof-kind $pid $kind) $kind))
      (if (== $kinds ()) (empty) (car-atom $kinds))))

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

(= (proof-term-evidence-list $prf)
   (if (= $prf (proof-ref $pid)) (proof-evidence-by-id $pid)
      (if (is-var $prf) () (if (is-expr $prf) (proof-term-evidence-list-args (cdr-atom $prf)) (cons $prf ())))))

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
