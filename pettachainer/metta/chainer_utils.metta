(= (tv-confidence $tv)
   (if (is-var $tv) 1.0 (if (= $tv (STV $_s $c)) (if (is-var $c) 1.0 $c) 1.0)))

(= (first-or () $default) $default)
(= (first-or (cons $x $_rest) $_default) $x)
(= (goal-has-type-vars? ($type ($_kbid $_ctx $_vars) $_prf $_tv))
   (not (== (extract-vars $type) ())))
(= (goal-has-type-vars? (CPU $_fun $_args $_res)) false)

(= (goal-key ($type ($kbid $ctx $vars) $_prf $_tv))
   (let $sealed-type (sealed (extract-vars $type) $type)
      ($sealed-type ($kbid $ctx $vars))))
(= (goal-key (CPU $fun $args $res))
   (sealed (extract-vars (CPU $fun $args $res)) (CPU $fun $args $res)))

(= (goal-is-proof? ($type ($_kbid $_ctx $_vars) $_prf $_tv)) true)
(= (goal-is-proof? (CPU $_fun $_args $_res)) false)

(= (normalize-expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (if (= $tv (STV $s $c)) (STV (if (is-var $s) 1.0 $s) (if (is-var $c) 1.0 $c)) $tv)))

(= (cpu-expected-confidence $fun $args)
   (if (is-member $fun (() MpFormula AndFormula OrFormula LikelierThanFormula))
      (let*
         ((($a $b) $args)
           ($res
              (reduce
                 (reduce
                    (cons $fun ((normalize-expected-tv $a) (normalize-expected-tv $b)))))))
         (tv-confidence $res))
      (if (== $fun InversionFormula)
         (let*
            ((($a $b $ab) $args)
              ($res
                 (reduce
                    (reduce
                       (cons $fun
                          ((normalize-expected-tv $a) (normalize-expected-tv $b)
                             (normalize-expected-tv $ab)))))))
            (tv-confidence $res))
         1.0)))

(= (term-confidence (CPU $fun $args $res))
   (if (is-var $res) (cpu-expected-confidence $fun $args) (tv-confidence $res)))
(= (term-confidence ($_type ($_kbid $_ctx $_vars) $_prf $tv)) (tv-confidence $tv))

(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (min (term-confidence $prem) (premises-expected-confidence $rest)))

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
      (if (and (= $tv1 (STV $_m1 $_c1)) (= $tv2 (STV $_m2 $_c2))) (mergetvs $tv1 $tv2)
         $tv1)))

(= (foreach-flat $f ()) ())
(= (foreach-flat $f (cons $x $xs)) (progn ($f $x) (foreach-flat $f $xs)))

(= (contains-hash? $x) (fold-nested (|-> ($acc $elem) (or (== $elem #) $acc)) false $x))

(= (goal-key-components ($type ($kbid $ctx $vars) $_prf $_tv)) (($kbid $ctx $vars) $type))
(= (goal-key-components (CPU $_fun $_args $_res)) ())

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

(= (next-pid) (next-search-id bwd_pid))

(= (cpu-call $_steps $fun $args) (reduce (reduce (cons $fun $args))))

(= (proof-stats-by-id $pid) (match &proof ($pid $_gid $_output $_kind $score $ev $_children) ($score $ev)))

(= (proof-tree-contains-list () $needle) false)
(= (proof-tree-contains-list (cons $head $tail) $needle)
   (or (proof-tree-contains $head $needle) (proof-tree-contains-list $tail $needle)))

(= (proof-tree-contains $tree $needle)
   (let*
      (($ptree (if (= $tree (proof-ref $ptreeid)) (materialize-proof $ptreeid) $tree))
        ($pneedle
           (if (= $needle (proof-ref $pneedleid)) (materialize-proof $pneedleid)
              $needle)))
      (if (== $ptree $pneedle) true
         (if (is-expr $ptree) (proof-tree-contains-list (cdr-atom $ptree) $pneedle)
            false))))

(= (proof-term-leaf-head? $head) (is-member $head (() fact-ev CPU STV)))

(= (proof-term-children-mode $mode $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf)
         (if (== $head conjunction) (cdr-atom $prf)
            (if (== $head rule-proof) (cdr-atom (cdr-atom $prf))
               (if (is-expr $head) (cdr-atom $prf)
                  (if (== $mode proof-walk-in-kb)
                     (if (proof-term-leaf-head? $head) () (cdr-atom $prf))
                     ())))))
      ()))

(= (proof-term-children $prf) (proof-term-children-mode proof-walk-plain $prf))

(= (proof-term-evidence-children-mode $mode ()) ())
(= (proof-term-evidence-children-mode $mode (cons $child $rest))
   (append (proof-term-evidence-list-mode $mode $child)
      (proof-term-evidence-children-mode $mode $rest)))

(= (proof-term-evidence-list-mode $mode $prf)
      (if (= $prf (proof-ref $pid)) (snd (proof-stats-by-id $pid))
      (if (is-var $prf) ()
         (if (= $prf (merge/revision $left $right))
            (append (proof-term-evidence-list-mode $mode $left)
               (proof-term-evidence-list-mode $mode $right))
            (let $children (proof-term-children-mode $mode $prf)
               (if (== $children ()) (cons $prf ())
                  (proof-term-evidence-children-mode $mode $children)))))))

(= (proof-term-evidence-list $prf)
   (once (proof-term-evidence-list-mode proof-walk-plain $prf)))

(= (proof-atom-evidence-set ($_type $kb $prf $_tv))
   (list_to_set (once (proof-term-evidence-list-mode proof-walk-in-kb $prf))))

(= (evidence-sets-overlap? $set-a $set-b)
   (not (== (intersection-atom $set-a $set-b) ())))

(= (evidence-subset? $set-a $set-b) (== (subtraction-atom $set-a $set-b) ()))

(= (merge-proof-atoms $proof-a $proof-b)
   (if (== $proof-a $proof-b) $proof-a
      (let*
         ((($_typea $_kba $prfa $_tva) $proof-a)
           (($_typeb $_kbb $prfb $_tvb) $proof-b))
         (if $proof-a
            (and (= $prfa (merge/revision $_la $_ra)) (proof-tree-contains $prfa $prfb))
            (if $proof-b
               (and (= $prfb (merge/revision $_lb $_rb))
                  (proof-tree-contains $prfb $prfa))
               (let*
                  (($ev-a (proof-atom-evidence-set $proof-a))
                    ($ev-b (proof-atom-evidence-set $proof-b))
                    ($overlap? (evidence-sets-overlap? $ev-a $ev-b)))
                  (if $overlap?
                     (if (>= (term-confidence $proof-a) (term-confidence $proof-b))
                        $proof-a
                        $proof-b)
                     (if (>= (term-confidence $proof-a) (term-confidence $proof-b))
                        (RevisionMergeProof $proof-a $proof-b)
                        (RevisionMergeProof $proof-b $proof-a)))))))))
