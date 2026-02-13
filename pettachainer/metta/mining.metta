;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Inductive Predicate Mining  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!(import! &self (library lib_import))
!(use-module! assoc)
!(import_prolog_function (superpose (empty_assoc put_assoc get_assoc)))

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

(= (assoc-get-var $assoc $key)
   (case (get_assoc $key $assoc)
      (($a ($a $assoc))
       (Empty ($v (put_assoc $key $assoc $v))))) )

(= (rewrite-v-step $expr ($accum $assoc))
   (if (= $expr (V $n))
       (let ($v $nassoc) (assoc-get-var $assoc $n)
            ((cons $v $accum) $nassoc))
       (if (is-expr $expr)
           (let ($nacc $nassoc) (foldr-flat rewrite-v-step (() $assoc) $expr) ((cons $nacc $accum) $nassoc))
           ((cons $expr $accum) $assoc))))

(= (rewrite-v-terms $premk $conck)
   (let (($prem $conc) $_assoc) (foldr-flat rewrite-v-step (() (empty_assoc)) ($premk $conck))
        (terms $prem $conc)))

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

(= (update-directional-by-key $kb $premk $conck $sa $ca $sb $cb)
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

(= (update-and-emit-directional $kb $premk $conck $sa $ca $sb $cb)
   (let (ab $alpha $beta) (update-directional-by-key $kb $premk $conck $sa $ca $sb $cb)
        (emit-mined-implication $kb $premk $conck $alpha $beta)))

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
       (superpose ((update-and-emit-directional $kb $premab $concab $sa $ca $sb $cb)
                   (update-and-emit-directional $kb $premba $concba $sb $cb $sa $ca)))))))

(= (mine-candidate $kb $stmtid $pa $args $tva $cid $pb $argsb $tvb)
   (if (== $cid $stmtid)
       (empty)
       (if (already-seen-candidate $stmtid $cid)
           (empty)
           (let $_ (add-atom &kb (ind-seen-pair $stmtid $cid))
                (if (share-any-arg $args $argsb)
                    (mine-predicate-pair $kb $pa $args $tva $pb $argsb $tvb)
                    (empty))))))

(= (mine-arg-step (minectx $kb $stmtid $pa $args $tva) $arg)
   (let $_ (collapse
             (match &mining_index
                    (ind-arg-index $kb $arg $cid $pb $argsb $tvb)
                    (mine-candidate $kb $stmtid $pa $args $tva $cid $pb $argsb $tvb)))
        (minectx $kb $stmtid $pa $args $tva)))

(= (mine-fact-match $kb $stmtid $pa $args $tva)
   (let $_ (foldl-atom $args (minectx $kb $stmtid $pa $args $tva) mine-arg-step)
        (clear-seen-candidates $stmtid)))

(= (index-arg-step (idxctx $kb $stmtid $pa $args $tv) $arg)
   (let $_ (add-atom &mining_index (ind-arg-index $kb $arg $stmtid $pa $args $tv))
        (idxctx $kb $stmtid $pa $args $tv)))

(= (index-fact-args $kb $stmtid $pa $args $tv)
   (foldl-atom $args (idxctx $kb $stmtid $pa $args $tv) index-arg-step))

(= (process-on-add $kb (: $prf $type $tv))
   (if (= $type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
       ()
       (if (and (not (is-expr $prf)) (is-expr $type))
           (let* (($pa (car-atom $type))
                  ($args (cdr-atom $type)))
                 (superpose ((mine-fact-match $kb $prf $pa $args $tv)
                             (index-fact-args $kb $prf $pa $args $tv))))
            ())))

(= (compileadd $kb $stmt)
  (let $atoms (mm2compile $kb $stmt)
  (let $added (add-atom &kb $atoms)
  (let $_ (process-on-add $kb $stmt)
       $added))))
