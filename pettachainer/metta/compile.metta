!(import! &self (library lib_roman))
!(import! &self (library lib_spaces))
!(import! &self (library lib_he))

(= (nextctx)
   (let*
      (($mn (catch (get-state ctxid)))
        ($n (if-error $mn 0 $mn)))
      (progn (change-state! ctxid (+ $n 1)) $n)))

(= (extract-vars $expr)
   (if (is-var $expr) ($expr)
      (if (is-expr $expr)
         (let $collect-vars (|-> ($accum $arg) (if (is-var $arg) (cons $arg $accum) $accum))
            (fold-nested $collect-vars () $expr))
         ())))

(= (skolemize $rule $expra $exprb)
   (if (or (is-var $exprb) (is-var $expra)) $exprb
      (let*
         (($avars (list_to_set (extract-vars $expra)))
           ($bvars (list_to_set (extract-vars $exprb)))
           ($onlyb (\== $bvars $avars))
           ($substitute (|-> (($idx $atom) $elem) (let $elem (exists $rule $idx $avars) ((+ 1 $idx) $atom))))
           (($_ $res) (sealed $onlyb (fold-flat $substitute (0 $exprb) $onlyb))))
         $res)))

(= (addidx (cons $head $tail) $idx) (cons ($head $idx) (addidx $tail (+ $idx 1))))
(= (addidx () $idx) ())

(= (seq2expr (cons $head $tail)) (if (== $tail ()) $head (cons And (cons $head $tail))))

(= (compile-outputs (: $kb $NNprf (@ $type (cons $head $tail)) $NNtv))
   (if (and (not (is-var $head)) (is-member $head (And Or LikelierThan)))
      (let $to-proj
         (|-> (($elem $idx))
            (((: $kb $prf $type $tvin) (CPU (atom_concat $head Projection) ($tvin) $tvout)) |-
               ((: $kb (proj $idx $prf) $elem $tvout))))
         (let $cmp-out (|-> (($elem $_)) (compile-outputs (: $kb $prfn $elem $tvn)))
            (let $idtail (addidx $tail 0) (&^& $to-proj $cmp-out (superpose $idtail)))))
      (empty)))

(= (inline-premise $kb $premise)
   (case $premise (
        ((Compute $f $args -> $res) (CPU $f $args $res))
        ((Map2Dist $fun $a $b -> $out) (CPU Map2DistRuntimeFormula ($kb $fun $a $b) $out))
        ((AverageDist $pattern -> $out) (CPU DistAverageFormula ($kb $pattern) $out))
        ((FoldAllValue $pattern $value $init $fun -> $out)
           (CPU FoldAllTVRuntimeFormula ($kb $pattern $init $fun) $out))
        ((FoldAll $pattern $value $init $fun -> $out)
           (CPU FoldAllFormulaCompiled
              ((collapse (mm2compileQuery $kb (: $prf $pattern $tvin))) $pattern $value $init $fun)
              $out))
        ($other $other))))

(= (inline-premises $kb $premises) (map-flat (inline-premise $kb) $premises))

(= (cpu-premise-tv-formula $f)
   (is-member $f
      (() NotFormula
         DistGreaterThanFormula
         DistGreaterThanDistFormula
         DistMapFormula
         DistMap2Formula
         DistAverageFormula
         Map2DistRuntimeFormula
         FoldAllTVFormulaCompiled
         FoldAllTVPatternFormula
         FoldAllTVRuntimeFormula
         FoldAllValueFormulaCompiled)))

(= (cpu-premise-tv $f $args $res) (if (cpu-premise-tv-formula $f) $res (STV 1.0 1.0)))

(= (in_map $kb $elem)
   (if (= $elem (CPU $f $args $res))
      (prem (: $kb $prf (CPU $f $args $res) (cpu-premise-tv $f $args $res))
         (CPU $f $args $res)
         (cpu-premise-tv $f $args $res)
         cpu)
      (prem (: $kb $prf $elem $tv) $elem $tv $prf)))

(= (tv $tv) (: $kb $prf $elem $tv))
(= (tv $tv) (CPU $formula $args $tv))

(=
   (in_fold $formula
      ((@ $premises (head (tv $tv))) (: $kb $cclprf $ccltype $ccltv))
      (prem $goal $elem $tve $prfelem))
   ((cons (CPU $formula ($tv $tve) $ntv) (cons $goal $premises))
      (: $kb (cons $prfelem $cclprf) (cons $elem $ccltype) $ntv)))

(= (inTemplate $kb $formula $head $tail)
   (let*
      (((cons (@ $fst (prem $fstgoal $fstelem $fsttv $fstprf)) $rst) (map-flat (in_map $kb) $tail))
        ($init (($fstgoal) (: $kb ($fstprf) ($fstelem) $fsttv)))
        (($resNNprms (: $kb $cclprf $ccltype $ccltv)) (fold-flat (in_fold $formula) $init $rst))
        (($rcclprf $rccltype) ((reverse $cclprf) (reverse $ccltype))))
      ((reverse $resNNprms) |- ((: $kb (cons conjunction $rcclprf) (cons $head $rccltype) $ccltv)))))

(= (compile-inputs (: $kb $prf (CPU $f $args $res) $tv))
   ((cons (CPU $f $args $res) ()) |- ((: $kb cpu (CPU $f $args $res) (cpu-premise-tv $f $args $res)))))
(= (compile-inputs (: $kb $prf (cons $head $tail) $tv))
   (if (and (not (is-var $head)) (is-member $head (And Or LikelierThan)))
      (superpose ((inTemplate $kb (atom_concat $head Formula) $head $tail)
                  (compile-inputs (: $kb $prf (superpose $tail) $tv))))
      (empty)))

(= (uPmapf2 $elem $accum)
   (if (= $elem (: $kb $prfa $type $tv))
      (case $type (
           ((Not $a) (cons (: $kb $prfa $a $tv_a) (cons (CPU NotFormula ($tv_a) $tv) $accum)))
           ((MapDist $fun $a -> $out)
              (cons (: $kb $prfa $a $tv_a) (cons (CPU DistMapFormula ($fun $tv_a) $out) $accum)))
           ((Map2Dist $fun $a $b -> $out)
              (cons (: $kb $prfb $b $tv_b)
                 (cons (: $kb $prfa $a $tv_a) (cons (CPU DistMap2Formula ($fun $tv_a $tv_b) $out) $accum))))
           ((AverageDist $pattern -> $out) (cons (CPU DistAverageFormula ($kb $pattern) $out) $accum))
           (($rel $a $b)
              (if (is-member $rel (GreaterThan >))
                 (if (is-expr $b)
                    (cons (: $kb $prfb $b $tv_b)
                       (cons (: $kb $prfa $a $tv_a)
                          (cons (CPU DistGreaterThanDistFormula ($tv_a $tv_b) $tv) $accum)))
                    (cons (: $kb $prfa $a $tv_a) (cons (CPU DistGreaterThanFormula ($tv_a $b) $tv) $accum)))
                 (cons $elem $accum)))
           ($other (cons $elem $accum))))
      (cons $elem $accum)))

(= (updatePremises $premises) (foldr-flat uPmapf2 () $premises))

(= (postCore ($premises |- $conclusions) $actionB $actionA)
   (let $npremises (updatePremises $premises)
      (if (and (= $conclusions ((: $kb $prf $type $tv)) (not (is-var $type))))
         (if (= $type (Implication (cons Premises $apremises) (cons Conclusions $bconclusions)))
            (let*
               (($a (seq2expr $apremises))
                 ($b (seq2expr $bconclusions)))
               (superpose (
                    (post
                       ((union-atom $npremises ((: $kb $prfa $a $atv) (CPU MpFormula ($atv $tv) $btv))) |-
                          ((: $kb ($prf $prfa) $b $btv))))
                    ($actionB $b)
                    ($actionA $a))))
            (if (and (= $type ($relation $a) (== $relation Not)))
               (post ((union-atom $npremises ((CPU NotFormula ($tv) $ntv))) |- ((: $kb $prf $a $ntv))))
               ($npremises |- $conclusions)))
         ($npremises |- $conclusions))))

(= (post $stmt) (postCore $stmt compile-outputs compile-inputs))

(= (postQuery $stmt) (postCore $stmt compile-inputs compile-outputs))


(= (compile) (.: post compile_))

(= (kbctx $kb) (if (is-expr $kb) $kb ($kb MAIN Nil)))

(= (implication $kb $prf $a $b $itv)
   (((: ($kb $ctx $vars) $prfa $a $atv) (CPU MpFormula ($itv $atv) $btv)) |-
      ((: ($kb $ctx $vars) ($prf $prfa) $b $btv))))

(= (map-nested2 $f ()) ())
(= (map-nested2 $f (cons $x $xs))
   (if (is-expr $x) ($f (cons (map-nested2 $f $x) (map-nested2 $f $xs)))
      ($f (cons ($f $x) (map-nested2 $f $xs)))))

(= (toQuery $elem) (if (is-var $elem) # (if (=? $elem (exists $_1 $_2 $_3)) $var $elem)))

(= (inverse-implication $kb $prf $a $b $itv)
   (let*
      (($a1 (map-nested2 toQuery $a))
        ($b1 (map-nested2 toQuery $b)))
      (((: ($kb $ctx $vars) $prfa $a1 $atv) (: ($kb $ctx $vars) $prfb $b1 $btv)
            (CPU InversionFormula ($atv $btv $itv) $iitv)
            (: ($kb $ctx $vars) $prfb $b $btv)
            (CPU MpFormula ($iitv $btv) $atv))
         |-
         ((: ($kb $ctx $vars) ((inverted $prf with $prfxa $prfax $prfxb $prfbx) $prfb) $a $atv)))))


(= (compile_ $kb (@ $stmt (: $prf $Type $tv)))
   (if (is-var $Type) (empty)
      (if (= $Type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (($a (seq2expr (inline-premises $kb $premises)))
              ($b (seq2expr $conclusions))
              ($nb (skolemize $prf $a $b))
              ($na (skolemize $prf $b $a)))
            (superpose ((implication $kb $prf $a $nb $tv)
                        (if (is-var $nb) (empty) (compile-outputs (: (kbctx $kb) ($prf $prfa) $nb $btv)))
                        (if (is-var $a) (empty) (compile-inputs (: (kbctx $kb) $prfa $a $atv)))
                        (if (not (= $prf (mined_implication $_ $_)))
                           (inverse-implication $kb
                              $prf
                              $na
                              $b
                              $tv)
                           (empty))
                        (if (is-var $na) (empty)
                           (compile-outputs (: ((inverted $prf $pa $pb1) $pb2) $na $natv)))
                        (if (is-var $b) (empty) (compile-inputs (: $pb2 $b $btv2))))))
         (superpose ((() |- ((: ($kb MAIN Nil) $prf $Type $tv)))
                     (compile-outputs (: ($kb MAIN Nil) $prf $Type $tv)))))))


(= (compileQuery $kb (: $prf $Type $tv))
   (if (is-var $Type) ((() |- ((: (kbctx $kb) $prf $Type $tv))) ())
      (if (= $Type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (($a (seq2expr (inline-premises $kb $premises)))
              ($b (seq2expr $conclusions)))
            ((postQuery (((: (kbctx $kb) $prfa $a (STV 1.0 1.0))) |- ((: (kbctx $kb) $prfb $b $itv))))
               (collapse
                  (postQuery
                     (superpose ((compile-inputs (: (kbctx $kb) $prfb $b $btv))
                                 (compile-outputs (: (kbctx $kb) $prfa $a $atv))))))))
         ((postQuery (() |- ((: (kbctx $kb) $prf $Type $tv))))
            (collapse (postQuery (compile-inputs (: (kbctx $kb) $prf $Type $tv))))))))


(= (mm2compile $kb $stmt)
   (progn (remove-all-atoms ctx) (superpose ((mm2stmt (compile $kb $stmt)) (get-atoms ctx)))))

(= (mm2stmt $stmt) (case $stmt (((() |- ($ccl)) $ccl) (($prms |- ($ccl)) (rules ($prms |- $ccl))))))


(= (mm2compileQuery $kb $stmt)
   (case (compileQuery $kb $stmt) (
        (((() |- ($ccl)) $adds)
           (let*
              (($tail (map-flat mm2stmt $adds))
                ($lst (cons (goal $ccl) $tail)))
              (superpose
                 $lst)))
        (((((: ($kbid $_ctx $_vars) $prf $type $tv)) |- ((: ($kbid $_ctx $_vars) $prf1 $type1 $tv1))) $adds)
           (let*
              (($vars (extract-vars $type))
                ($mvars (if (== $vars ()) Nil $vars))
                ($ctx (nextctx))
                ($ctxatom (: ($kbid $ctx $mvars) (ctx proof $ctx) $type $tv))
                ($goalatom (goal (: ($kbid $ctx $mvars) $prf1 $type1 $tv1)))
                ($tail (map-flat mm2stmt $adds))
                ($lst (union-atom ($goalatom $ctxatom) $tail)))
              (superpose
                 $lst)))
        ($a (notsupported mm2compileQuery $kb $stmt $a)))))

(= (checkStmt $stmt)
   (and (= $stmt (: $prf $type $tv))
      (and (not (is-var $prf))
         (or (= $type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
            (== (extract-vars $type) ())))))

(= (checkQuery $query) (= $query (: $prf $type $tv)))

(= (mf $kb ($kb $t)) $t)

(= (internalize-proof-structure $term)
   (if (is-var $term) $term
      (if (= $term (: $kb $prf $type $tv)) ($type $kb $prf $tv)
         (if (is-expr $term)
            (cons (internalize-proof-structure (car-atom $term))
               (internalize-proof-structure-list (cdr-atom $term)))
            $term))))

(= (internalize-proof-structure-list ()) ())
(= (internalize-proof-structure-list (cons $head $tail))
   (cons (internalize-proof-structure $head) (internalize-proof-structure-list $tail)))

(= (externalize-proof-structure $term)
   (if (is-var $term) $term
      (if (= $term ($type ($kbid $ctx $vars) $prf $tv)) (: ($kbid $ctx $vars) $prf $type $tv)
         (if (is-expr $term)
            (cons (externalize-proof-structure (car-atom $term))
               (externalize-proof-structure-list (cdr-atom $term)))
            $term))))

(= (externalize-proof-structure-list ()) ())
(= (externalize-proof-structure-list (cons $head $tail))
   (cons (externalize-proof-structure $head) (externalize-proof-structure-list $tail)))

(= (pretty-prf-token $prf)
   (case $prf (
        ((mined_implication $premk $conck) (Implication (cons Premises ($premk)) (cons Conclusions ($conck))))
        ($other $other))))

(= (pretty-prf $prf) (if (is-expr $prf) (map-nested2 pretty-prf-token $prf) $prf))

(= (lookup-mined-tv $premk $conck $fallback-tv)
   (let $m (collapse (once (match &kb ($itype ($kbid MAIN ()) (mined_implication $premk $conck) $itv) $itv)))
      (if (== $m ()) $fallback-tv (car-atom $m))))

(= (extract-mined-itv-from-args $args $fallback-tv)
   (if (= $args ($_prem (CPU MpFormula ($itv $_atv) $_btv))) $itv
      (if (= $args (cons $h $t))
         (if (= $h (CPU MpFormula ($itv $_atv2) $_btv2)) $itv (extract-mined-itv-from-args $t $fallback-tv))
         $fallback-tv)))

(= (pretty (: $prf $type $tv)) (: (pretty-prf $prf) $type $tv))
(= (pretty (rules ($args |- $goal)))
   (if (= $goal (: $kb ((mined_implication $premk $conck) $p) $type $tv))
      (let*
         (($ptv
              (if (is-var $tv)
                 (let*
                    (($tv1 (extract-mined-itv-from-args $args $tv))
                      ($tv2 (lookup-mined-tv $premk $conck $tv1)))
                    $tv2)
                 $tv)))
         (: mined_implication ((pretty-prf-token (mined_implication $premk $conck)) $p) $type $ptv))
      (pretty $goal)))
(= (pretty (: $kb $prf $type $tv))
   (if (is-expr $kb)
      (if (= $kb ($kbid MAIN Nil)) (: (pretty-prf $prf) $type $tv)
         (let ($_ $idx $vars) $kb
            (let*
               (($x (map-flat (mf $kb) (collapse (match &kb ($t $kb $p $tv2) ($kb $t)))))
                 ($ptype (Implication (cons Premises $x) (cons Conclusions ($type)))))
               (: (pretty-prf $prf) $ptype $tv))))
      (: (pretty-prf $prf) $type $tv)))
