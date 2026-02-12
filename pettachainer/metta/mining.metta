;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Inductive Predicate Mining  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(= (mining-k) 800.0)

(= (confidence-to-count $conf)
   (/ (* (min $conf 0.9999) (mining-k))
      (- 1.0 (min $conf 0.9999))))

(= (count-to-confidence $count)
   (/ $count (+ $count (mining-k))))

(= (clear-impl-stats $kb $pa $pb)
   (collapse
     (match &kb
            (ind-impl-stats $kb $pa $pb $olda $oldb)
            (remove-atom &kb (ind-impl-stats $kb $pa $pb $olda $oldb)))))

(= (current-impl-stats $kb $pa $pb)
   (let $m (collapse (once (match &kb (ind-impl-stats $kb $pa $pb $olda $oldb) (ab $olda $oldb))))
        (if (== $m ())
            (ab 0.0 0.0)
            (car-atom $m))))

(= (impl-strength $alpha $beta)
   (if (> (+ $alpha $beta) 0.0)
       (/ $alpha (+ $alpha $beta))
       0.5))

(= (impl-type-for-args $pa $pb (cons $a1 ()))
   (Implication (Premises ($pa $x1)) (Conclusions ($pb $x1))))
(= (impl-type-for-args $pa $pb (cons $a1 (cons $a2 ())))
   (Implication (Premises ($pa $x1 $x2)) (Conclusions ($pb $x1 $x2))))
(= (impl-type-for-args $pa $pb (cons $a1 (cons $a2 (cons $a3 ()))))
   (Implication (Premises ($pa $x1 $x2 $x3)) (Conclusions ($pb $x1 $x2 $x3))))
(= (impl-type-for-args $pa $pb (cons $a1 (cons $a2 (cons $a3 (cons $a4 ())))))
   (Implication (Premises ($pa $x1 $x2 $x3 $x4)) (Conclusions ($pb $x1 $x2 $x3 $x4))))
(= (impl-type-for-args $pa $pb (cons $a1 (cons $a2 (cons $a3 (cons $a4 (cons $a5 ()))))))
   (Implication (Premises ($pa $x1 $x2 $x3 $x4 $x5)) (Conclusions ($pb $x1 $x2 $x3 $x4 $x5))))
(= (impl-type-for-args $pa $pb (cons $a1 (cons $a2 (cons $a3 (cons $a4 (cons $a5 (cons $a6 ())))))))
   (Implication (Premises ($pa $x1 $x2 $x3 $x4 $x5 $x6)) (Conclusions ($pb $x1 $x2 $x3 $x4 $x5 $x6))))
(= (impl-type-for-args $pa $pb (cons $a1 (cons $a2 (cons $a3 (cons $a4 (cons $a5 (cons $a6 (cons $a7 ()))))))))
   (Implication (Premises ($pa $x1 $x2 $x3 $x4 $x5 $x6 $x7)) (Conclusions ($pb $x1 $x2 $x3 $x4 $x5 $x6 $x7))))
(= (impl-type-for-args $pa $pb (cons $a1 (cons $a2 (cons $a3 (cons $a4 (cons $a5 (cons $a6 (cons $a7 (cons $a8 ())))))))))
   (Implication (Premises ($pa $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8)) (Conclusions ($pb $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8))))
(= (impl-type-for-args $pa $pb $args) (empty))

(= (clear-mined-implication-root $kb $pa $pb)
   (collapse
     (match &kb
            (: ($kb MAIN ()) (mined_implication $pa $pb) $oldtype $oldtv)
            (remove-atom &kb (: ($kb MAIN ()) (mined_implication $pa $pb) $oldtype $oldtv)))))

(= (clear-mined-implication-rules $kb $pa $pb)
   (let $_
        (collapse
          (match &kb
                 (rules ($args |- (: ($kb MAIN ()) ((mined_implication $pa $pb) $p) $type $tv)))
                 (remove-atom &kb (rules ($args |- (: ($kb MAIN ()) ((mined_implication $pa $pb) $p) $type $tv))))))
         (collapse
           (match &kb
                  (rules ($args |- (: ($kb MAIN ()) ((inverted (mined_implication $pa $pb) with $x1 $x2 $x3 $x4) $p) $type $tv)))
                  (remove-atom &kb (rules ($args |- (: ($kb MAIN ()) ((inverted (mined_implication $pa $pb) with $x1 $x2 $x3 $x4) $p) $type $tv))))))))

(= (emit-mined-implication-type $kb $pa $pb $args (empty) $alpha $beta)
   (empty))

(= (emit-mined-implication-type $kb $pa $pb $args $type $alpha $beta)
   (let* (($s (impl-strength $alpha $beta))
          ($c (count-to-confidence (+ $alpha $beta)))
          ($stmt (: (mined_implication $pa $pb) $type (STV $s $c)))
          ($_ (clear-mined-implication-root $kb $pa $pb))
          ($_ (clear-mined-implication-rules $kb $pa $pb)))
     (compileadd $kb $stmt)))

(= (emit-mined-implication $kb $pa $pb $args $alpha $beta)
   (let $type (impl-type-for-args $pa $pb $args)
        (emit-mined-implication-type $kb $pa $pb $args $type $alpha $beta)))

(= (bump-directional-implication $kb $pa $pb $sa $ca $sb $cb)
   (let* (($w (min $ca $cb))
          ($ainc (* $w (* $sa $sb)))
          ($binc (* $w (* $sa (- 1.0 $sb))))
          ($cur (current-impl-stats $kb $pa $pb))
          ((ab $olda $oldb) $cur)
          ($newa (+ $olda $ainc))
          ($newb (+ $oldb $binc))
          ($_ (clear-impl-stats $kb $pa $pb))
          ($_ (add-atom &kb (ind-impl-stats $kb $pa $pb $newa $newb))))
      (ab $newa $newb)))

(= (refresh-mined-implication $kb $pa $pb $args)
   (let $cur (current-impl-stats $kb $pa $pb)
   (let (ab $alpha $beta) $cur
        (emit-mined-implication $kb $pa $pb $args $alpha $beta))))

(= (mine-predicate-pair $kb $pa $pb $args (STV $sa $ca) (STV $sb $cb))
   (if (== $pa $pb)
       (empty)
       (let $_ (superpose ((bump-directional-implication $kb $pa $pb $sa $ca $sb $cb)
                           (bump-directional-implication $kb $pb $pa $sb $cb $sa $ca)))
            (superpose ((refresh-mined-implication $kb $pa $pb $args)
                        (refresh-mined-implication $kb $pb $pa $args))))))

(= (mine-fact-match $kb $pa $args $tva)
   (collapse
     (match &kb
            (: ($kb MAIN ()) $prfb $typeb $tvb)
            (if (and (not (is-expr $prfb)) (is-expr $typeb))
                (let $pb (car-atom $typeb)
                (let $argsb (cdr-atom $typeb)
                     (if (== $argsb $args)
                         (mine-predicate-pair $kb $pa $pb $args $tva $tvb)
                         (empty))))
                (empty)))))

(= (mine-on-add $kb (: $prf $type $tv))
   (if (= $type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
       (empty)
       (if (and (not (is-expr $prf)) (is-expr $type))
           (let $pa (car-atom $type)
           (let $args (cdr-atom $type)
                (mine-fact-match $kb $pa $args $tv)))
           (empty))))

(= (compileadd $kb $stmt)
  (let $atoms (mm2compile $kb $stmt)
  (let $added (add-atom &kb $atoms)
  (let $_ (mine-on-add $kb $stmt)
       $added))))
