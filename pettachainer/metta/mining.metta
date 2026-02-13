;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Inductive Predicate Mining  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(= (mining-k) 800.0)

(= (count-to-confidence $count)
   (/ $count (+ $count (mining-k))))

(= (impl-strength $alpha $beta)
   (if (> (+ $alpha $beta) 0.0)
       (/ $alpha (+ $alpha $beta))
       0.5))

(= (shared-objects () $argsb) ())
(= (shared-objects (cons $h $t) $argsb)
   (let $rst (shared-objects $t $argsb)
        (if (and (is-member $h $argsb) (not (is-member $h $rst)))
            (cons $h $rst)
            $rst)))

(= (index-of-arg $arg () $idx) 0)
(= (index-of-arg $arg (cons $h $t) $idx)
   (if (== $arg $h)
       $idx
       (index-of-arg $arg $t (+ $idx 1))))

(= (generalize-arg-key $arg $shared)
   (let $idx (index-of-arg $arg $shared 1)
        (if (> $idx 0)
            (V $idx)
            $arg)))

(= (generalize-args-key () $shared) ())
(= (generalize-args-key (cons $h $t) $shared)
   (cons (generalize-arg-key $h $shared) (generalize-args-key $t $shared)))

(= (generalized-terms-key $pa $argsa $pb $argsb)
   (let $shared (shared-objects $argsa $argsb)
   (let $premk (cons $pa (generalize-args-key $argsa $shared))
   (let $conck (cons $pb (generalize-args-key $argsb $shared))
        (terms $premk $conck)))))

(= (nth-v 1 (vmap $v1 $v2 $v3 $v4 $v5 $v6 $v7 $v8)) $v1)
(= (nth-v 2 (vmap $v1 $v2 $v3 $v4 $v5 $v6 $v7 $v8)) $v2)
(= (nth-v 3 (vmap $v1 $v2 $v3 $v4 $v5 $v6 $v7 $v8)) $v3)
(= (nth-v 4 (vmap $v1 $v2 $v3 $v4 $v5 $v6 $v7 $v8)) $v4)
(= (nth-v 5 (vmap $v1 $v2 $v3 $v4 $v5 $v6 $v7 $v8)) $v5)
(= (nth-v 6 (vmap $v1 $v2 $v3 $v4 $v5 $v6 $v7 $v8)) $v6)
(= (nth-v 7 (vmap $v1 $v2 $v3 $v4 $v5 $v6 $v7 $v8)) $v7)
(= (nth-v 8 (vmap $v1 $v2 $v3 $v4 $v5 $v6 $v7 $v8)) $v8)

(= (rewrite-v-args () $m) ())
(= (rewrite-v-args $args $m)
   (cons (rewrite-v-term (car-atom $args) $m)
         (rewrite-v-args (cdr-atom $args) $m)))

(= (rewrite-v-term-expr $a $m)
   (if (== (car-atom $a) V)
       (nth-v (car-atom (cdr-atom $a)) $m)
       (cons (car-atom $a) (rewrite-v-args (cdr-atom $a) $m))))

(= (rewrite-v-term $a $m)
   (if (is-expr $a)
       (rewrite-v-term-expr $a $m)
       $a))

(= (rewrite-v-terms $premk $conck)
   (let $m (vmap $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8)
        (terms (rewrite-v-term $premk $m)
               (rewrite-v-term $conck $m))))

(= (clear-impl-stats $kb $premk $conck)
   (collapse
     (match &kb
            (ind-impl-stats $kb $premk $conck $olda $oldb)
            (remove-atom &kb (ind-impl-stats $kb $premk $conck $olda $oldb)))))

(= (current-impl-stats $kb $premk $conck)
   (let $m (collapse (once (match &kb (ind-impl-stats $kb $premk $conck $olda $oldb) (ab $olda $oldb))))
        (if (== $m ())
            (ab 0.0 0.0)
            (car-atom $m))))

(= (clear-mined-implication-rules $kb $premk $conck)
   (let $_
        (collapse
          (match &kb
                 (rules ($args |- (: ($kb MAIN ()) ((mined_implication $premk $conck) $p) $type $tv)))
                 (remove-atom &kb (rules ($args |- (: ($kb MAIN ()) ((mined_implication $premk $conck) $p) $type $tv))))))
        (collapse
          (match &kb
                 (rules ($args |- (: ($kb MAIN ()) ((inverted (mined_implication $premk $conck) with $x1 $x2 $x3 $x4) $p) $type $tv)))
                 (remove-atom &kb (rules ($args |- (: ($kb MAIN ()) ((inverted (mined_implication $premk $conck) with $x1 $x2 $x3 $x4) $p) $type $tv))))))))

(= (emit-mined-implication $kb $premk $conck $alpha $beta)
   (let (terms $prem $conc) (rewrite-v-terms $premk $conck)
   (let* (($s (impl-strength $alpha $beta))
          ($c (count-to-confidence (+ $alpha $beta)))
          ($type (Implication (Premises $prem) (Conclusions $conc)))
          ($stmt (: (mined_implication $premk $conck) $type (STV $s $c)))
          ($_ (clear-mined-implication-rules $kb $premk $conck)))
      (compileadd $kb $stmt))))

(= (bump-directional-by-key $kb $premk $conck $sa $ca $sb $cb)
   (let* (($w (min $ca $cb))
          ($ainc (* $w (* $sa $sb)))
          ($binc (* $w (* $sa (- 1.0 $sb))))
          ($cur (current-impl-stats $kb $premk $conck))
          ((ab $olda $oldb) $cur)
          ($newa (+ $olda $ainc))
          ($newb (+ $oldb $binc))
          ($_ (clear-impl-stats $kb $premk $conck))
          ($_ (add-atom &kb (ind-impl-stats $kb $premk $conck $newa $newb))))
       (ab $newa $newb)))

(= (refresh-mined-implication $kb $premk $conck)
   (let $cur (current-impl-stats $kb $premk $conck)
   (let (ab $alpha $beta) $cur
        (emit-mined-implication $kb $premk $conck $alpha $beta))))

(= (share-any-arg () $argsb) False)
(= (share-any-arg (cons $h $t) $argsb)
   (if (is-member $h $argsb)
       True
       (share-any-arg $t $argsb)))

(= (already-seen-candidate $stmtid $cid)
   (if (== (collapse (once (match &kb (ind-seen-pair $stmtid $cid) ok))) ())
       False
       True))

(= (clear-seen-candidates $stmtid)
   (collapse
     (match &kb
            (ind-seen-pair $stmtid $cid)
            (remove-atom &kb (ind-seen-pair $stmtid $cid)))))

(= (mine-predicate-pair $kb $pa $argsa (STV $sa $ca) $pb $argsb (STV $sb $cb))
   (let (terms $premab $concab) (generalized-terms-key $pa $argsa $pb $argsb)
   (let (terms $premba $concba) (generalized-terms-key $pb $argsb $pa $argsa)
   (if (and (== $premab $concab) (== $premba $concba))
       (empty)
       (let $_ (superpose ((bump-directional-by-key $kb $premab $concab $sa $ca $sb $cb)
                           (bump-directional-by-key $kb $premba $concba $sb $cb $sa $ca)))
            (superpose ((refresh-mined-implication $kb $premab $concab)
                        (refresh-mined-implication $kb $premba $concba))))))))

(= (mine-candidate $kb $stmtid $pa $args $tva $cid $pb $argsb $tvb)
   (if (== $cid $stmtid)
       (empty)
       (if (already-seen-candidate $stmtid $cid)
           (empty)
           (let $_ (add-atom &kb (ind-seen-pair $stmtid $cid))
                (if (share-any-arg $args $argsb)
                    (mine-predicate-pair $kb $pa $args $tva $pb $argsb $tvb)
                    (empty))))))

(= (mine-by-arg $kb $stmtid $pa $args $tva $arg)
   (collapse
     (match &mining_index
            (ind-arg-index $kb $arg $cid $pb $argsb $tvb)
            (mine-candidate $kb $stmtid $pa $args $tva $cid $pb $argsb $tvb))))

(= (mine-fact-match-args $kb $stmtid $pa $args $tva ()) (empty))
(= (mine-fact-match-args $kb $stmtid $pa $args $tva (cons $h $t))
   (let $_ (mine-by-arg $kb $stmtid $pa $args $tva $h)
        (mine-fact-match-args $kb $stmtid $pa $args $tva $t)))

(= (mine-fact-match $kb $stmtid $pa $args $tva)
   (let $_ (mine-fact-match-args $kb $stmtid $pa $args $tva $args)
        (clear-seen-candidates $stmtid)))

(= (index-fact-args $kb $stmtid $pa $args $tv ()) (empty))
(= (index-fact-args $kb $stmtid $pa $args $tv (cons $h $t))
   (let $_ (add-atom &mining_index (ind-arg-index $kb $h $stmtid $pa $args $tv))
        (index-fact-args $kb $stmtid $pa $args $tv $t)))

(= (index-on-add $kb (: $prf $type $tv))
   (if (= $type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
       (empty)
       (if (and (not (is-expr $prf)) (is-expr $type))
           (let $pa (car-atom $type)
           (let $args (cdr-atom $type)
                (index-fact-args $kb $prf $pa $args $tv $args)))
           (empty))))

(= (mine-on-add $kb (: $prf $type $tv))
   (if (= $type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
       (empty)
       (if (and (not (is-expr $prf)) (is-expr $type))
            (let $pa (car-atom $type)
            (let $args (cdr-atom $type)
                 (mine-fact-match $kb $prf $pa $args $tv)))
            (empty))))

(= (compileadd $kb $stmt)
  (let $atoms (mm2compile $kb $stmt)
  (let $added (add-atom &kb $atoms)
  (let $_ (superpose ((mine-on-add $kb $stmt) True))
  (let $_ (superpose ((index-on-add $kb $stmt) True))
       $added)))))
