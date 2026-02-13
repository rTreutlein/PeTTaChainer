;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Inductive Predicate Mining  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!(import! &self (library lib_import))
!(use-module! assoc)
!(import_prolog_function (superpose (empty_assoc put_assoc get_assoc)))

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

(= (generalize-args-key () $shared) ())
(= (generalize-args-key (cons $h $t) $shared)
   (let $idx (index-of-arg $h $shared 1)
        (cons (if (> $idx 0) (V $idx) $h)
              (generalize-args-key $t $shared))))

(= (generalized-terms-key $pa $argsa $pb $argsb)
   (let* (($shared (shared-objects $argsa $argsb))
          ($premk (cons $pa (generalize-args-key $argsa $shared)))
          ($conck (cons $pb (generalize-args-key $argsb $shared))))
     (terms $premk $conck)))

(= (rewrite-v-step $expr ($accum $assoc))
   (if (= $expr (V $n))
       (let ($v $nassoc)
            (case (get_assoc $n $assoc)
               (($a ($a $assoc))
                (Empty ($v (put_assoc $n $assoc $v)))))
            ((cons $v $accum) $nassoc))
       (if (is-expr $expr)
           (let ($nacc $nassoc) (foldr-flat rewrite-v-step (() $assoc) $expr) ((cons $nacc $accum) $nassoc))
           ((cons $expr $accum) $assoc))))

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
   (let ($prem $conc) (fst (foldr-flat rewrite-v-step (() (empty_assoc)) ($premk $conck)))
   (let* (($sum (+ $alpha $beta))
          ($s (if (> $sum 0.0) (/ $alpha $sum) 0.5))
          ($c (/ $sum (+ $sum 800.0)))
          ($type (Implication (Premises $prem) (Conclusions $conc)))
          ($stmt (: (mined_implication $premk $conck) $type (STV $s $c)))
          ($_ (clear-mined-implication-rules $kb $premk $conck)))
      (compileadd $kb $stmt))))

(= (update-directional-by-key $kb $premk $conck $sa $ca $sb $cb)
   (let* (($w (min $ca $cb))
          ($ainc (* $w (* $sa $sb)))
          ($binc (* $w (* $sa (- 1.0 $sb))))
          ($m (collapse (once (match &kb (ind-impl-stats $kb $premk $conck $olda $oldb) (ab $olda $oldb)))) )
          ($cur (if (== $m ()) (ab 0.0 0.0) (car-atom $m)))
          ((ab $olda $oldb) $cur)
          ($newa (+ $olda $ainc))
          ($newb (+ $oldb $binc))
          ($_ (collapse (match &kb
                              (ind-impl-stats $kb $premk $conck $olda2 $oldb2)
                              (remove-atom &kb (ind-impl-stats $kb $premk $conck $olda2 $oldb2)))))
          ($_ (add-atom &kb (ind-impl-stats $kb $premk $conck $newa $newb))))
        (ab $newa $newb)))

(= (mine-predicate-pair $kb $pa $argsa (STV $sa $ca) $pb $argsb (STV $sb $cb))
   (let* (((terms $premab $concab) (generalized-terms-key $pa $argsa $pb $argsb))
          ((terms $premba $concba) (generalized-terms-key $pb $argsb $pa $argsa)))
     (if (and (== $premab $concab) (== $premba $concba))
         (empty)
         (superpose
           ((let (ab $alpha $beta) (update-directional-by-key $kb $premab $concab $sa $ca $sb $cb)
              (emit-mined-implication $kb $premab $concab $alpha $beta))
            (let (ab $alpha $beta) (update-directional-by-key $kb $premba $concba $sb $cb $sa $ca)
              (emit-mined-implication $kb $premba $concba $alpha $beta)))))))

(= (mine-candidate $kb $stmtid $pa $args $tva $cid $pb $argsb $tvb)
   (if (== $cid $stmtid)
       (empty)
       (if (not (== (collapse (once (match &kb (ind-seen-pair $stmtid $cid) ok))) ()))
           (empty)
           (let $_ (add-atom &kb (ind-seen-pair $stmtid $cid))
                (if (not (== (shared-objects $args $argsb) ()))
                    (mine-predicate-pair $kb $pa $args $tva $pb $argsb $tvb)
                    (empty))))))

(= (mine-arg-step (minectx $kb $stmtid $pa $args $tva) $arg)
   (let $_ (collapse
             (match &mining_index
                    (ind-arg-index $kb $arg $cid $pb $argsb $tvb)
                    (mine-candidate $kb $stmtid $pa $args $tva $cid $pb $argsb $tvb)))
        (minectx $kb $stmtid $pa $args $tva)))

(= (index-arg-step (idxctx $kb $stmtid $pa $args $tv) $arg)
   (let $_ (add-atom &mining_index (ind-arg-index $kb $arg $stmtid $pa $args $tv))
        (idxctx $kb $stmtid $pa $args $tv)))

(= (process-on-add $kb (: $prf $type $tv))
   (if (= $type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
       ()
       (if (and (not (is-expr $prf)) (is-expr $type))
           (let* (($pa (car-atom $type))
                  ($args (cdr-atom $type)))
                 (superpose
                   ((let $_ (foldl-atom $args (minectx $kb $prf $pa $args $tv) mine-arg-step)
                      (collapse
                        (match &kb
                               (ind-seen-pair $prf $cid)
                               (remove-atom &kb (ind-seen-pair $prf $cid)))))
                    (foldl-atom $args (idxctx $kb $prf $pa $args $tv) index-arg-step))))
           ())))

(= (compileadd $kb $stmt)
   (let* (($atoms (mm2compile $kb $stmt))
          ($added (add-atom &kb $atoms))
          ($_ (process-on-add $kb $stmt)))
     $added))
