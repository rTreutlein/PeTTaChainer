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
         (let $collect-vars
            (|-> ($accum $arg) (if (is-var $arg) (cons $arg $accum) $accum))
            (fold-nested $collect-vars () $expr))
         ())))

(= (skolemize $rule $expra $exprb)
   (if (or (is-var $exprb) (is-var $expra)) $exprb
      (let*
         (($avars (list_to_set (extract-vars $expra)))
           ($bvars (list_to_set (extract-vars $exprb)))
           ($onlyb (\== $bvars $avars))
           ($substitute
              (|-> (($idx $atom) $elem)
                 (let $elem (exists $rule $idx $avars) ((+ 1 $idx) $atom))))
           (($_ $res) (sealed $onlyb (fold-flat $substitute (0 $exprb) $onlyb))))
         $res)))

(= (addidx (cons $head $tail) $idx) (cons ($head $idx) (addidx $tail (+ $idx 1))))
(= (addidx () $idx) ())

(= (seq2expr (cons $head $tail)) (if (== $tail ()) $head (cons And (cons $head $tail))))

(= (compile-outputs (: $kb $NNprf (@ $type (cons $head $tail)) $NNtv))
   (if (and (not (is-var $head)) (is-member $head (And Or LikelierThan)))
      (let $to-proj
         (|-> (($elem $idx))
            (((: $kb $prf $type $tvin)
                  (CPU (atom_concat $head Projection) ($tvin) $tvout))
               |-
               ((: $kb (proj $idx $prf) $elem $tvout))))
         (let*
            (($cmp-out (|-> (($elem $_)) (compile-outputs (: $kb $prfn $elem $tvn)))
              ($idtail (addidx $tail 0)))
            (&^& $to-proj $cmp-out (superpose $idtail)))))
      (empty)))

(= (cpu-premise-tv-formula $f)
   (is-member $f
      (() NotFormula
         DistGreaterThanFormula
         DistGreaterThanDistFormula
         DistMapFormula
         DistMap2Formula)))
(= (cpu-premise-tv FoldAllCompiled ($_kb $_pattern $_extractor $_init $_fun $_finish result-tv) $res) $res)
(= (cpu-premise-tv FoldAllCompiled ($_kb $_pattern $_extractor $_init $_fun $_finish unit-stv) $_res)
   (STV 1.0 1.0))
(= (cpu-premise-tv $f $args $res) (if (cpu-premise-tv-formula $f) $res (STV 1.0 1.0)))
(= (in_map $kb $elem)
   (if (= $elem (CPU $f $args $res))
      (prem (CPU $f $args $res)
         (CPU $f $args $res)
         (cpu-premise-tv $f $args $res)
         cpu)
      (prem (: $kb $prf $elem $tv) $elem $tv $prf)))
(= (tv $tv) (: $kb $prf $elem $tv))
(= 
   (in_fold $formula
      ((@ $premises (head (tv $tv))) (: $kb $cclprf $ccltype $ccltv))
      (prem $goal $elem $tve $prfelem))
   ((cons (CPU $formula ($tv $tve) $ntv) (cons $goal $premises))
      (: $kb (cons $prfelem $cclprf) (cons $elem $ccltype) $ntv)))
(= (exec-goal-type (CPU $f $args $res)) (CPU $f $args $res))
(= (exec-goal-type (: $_kb $_prf $elem $_tv)) $elem)
(= (bundle-from-execs $execs $result-tv $proof)
   (premise-bundle (map-flat exec-goal-type $execs) $execs $result-tv $proof))
(= (compound-premise-bundle $kb $ctx $vars $head $tail)
   (let*
      (((cons (@ $fst (prem $fstgoal $fstelem $fsttv $fstprf)) $rst) (map-flat (in_map $kb) $tail))
       ($init (($fstgoal) (: $kb ($fstprf) ($fstelem) $fsttv)))
       (($resNNprms (: $kb $cclprf $ccltype $ccltv)) (fold-flat (in_fold (atom_concat $head Formula)) $init $rst))
       (($execs $rcclprf $rccltype) ((reverse $resNNprms) (reverse $cclprf) (reverse $ccltype)))
       ($proof-token (if (= $rcclprf (cons $proof ())) $proof (cons conjunction $rcclprf))))
      (bundle-from-execs $execs $ccltv $proof-token)))
(= (compound-source? (cons $head $_tail))
   (and (not (is-var $head)) (is-member $head (And Or LikelierThan))))
(= (compound-source? $_type) false)
(= (compile-adapter-chain plain (: $kb $prf (cons $head $tail) $tv))
   (if (and (not (is-var $head)) (is-member $head (And Or LikelierThan)))
      (let*
((
            (premise-bundle $exec-types $execs $result-tv $proof-token)
            (compound-premise-bundle $kb $ctx $vars $head $tail)))
         (superpose
            (($execs |- ((: $kb $proof-token (cons $head $tail) $result-tv)))
             (if (== (seq2expr $exec-types) (cons $head $tail)) (empty)
                (compile-adapter-chain plain (: $kb $prfa (seq2expr $exec-types) $atv))))))
      (empty)))
(= (compile-adapter-chain plain (: $_kb $_prf $_type $_tv)) (empty))
(= (compile-adapter-chain query (: $kb $prf $type $tv))
   (if (compound-source? $type) (compile-adapter-chain plain (: $kb $prf $type $tv))
      (let*
         (((premise-bundle $exec-types $execs $result-tv $proof-token)
              (once (lower-source-premise $kb $ctx $vars $type)))
           ($exec-type (seq2expr $exec-types)))
         (if (and (not (is-var $type)) (not (== $exec-type $type)))
            (superpose
               (($execs |- ((: $kb ($prf $proof-token) $type $result-tv)))
                (compile-adapter-chain plain (: $kb $prfa $exec-type $atv))))
            (empty)))))
(= (lower-source-premise $kb $ctx $vars $premise)
   (if (and (= $premise (cons $head $tail))
         (not (is-var $head))
         (is-member $head (And Or LikelierThan)))
      (compound-premise-bundle $kb $ctx $vars $head $tail)
      (case $premise (
        ((Compute $f $args -> $res)
           (bundle-from-execs
              ((CPU $f $args $res))
              (cpu-premise-tv $f $args $res)
              cpu))
        ((MapDist $fun $a -> $out)
           (bundle-from-execs
              ((: ($kb $ctx $vars) $prfa $a $tv_a) (CPU DistMapFormula ($fun $tv_a) $out))
              $out
              $prfa))
        ((Map2Dist $fun $a $b -> $out)
           (bundle-from-execs
              ((: ($kb $ctx $vars) $prfa $a $tv_a)
                 (: ($kb $ctx $vars) $prfb $b $tv_b)
                 (CPU DistMap2Formula (quote ($fun $tv_a $tv_b)) $out))
              $out
              (rule-proof conjunction $prfa $prfb)))
        ((AverageDist $pattern -> $out)
           (bundle-from-execs
              ((CPU FoldAllCompiled
                 ($kb $pattern extract-tv (SumCount (PointMass 0.0) 0) DistSumCountAcc dist-average result-tv)
                 $out))
              $out
              cpu))
        ((FoldAllValue $pattern $_value $init $fun -> $out)
           (bundle-from-execs
              ((CPU FoldAllCompiled
                 ($kb $pattern extract-tv $init $fun identity result-tv)
                 $out))
              $out
              cpu))
        ((FoldAll $pattern $value $init $fun -> $out)
           (bundle-from-execs
              ((CPU FoldAllCompiled
                 ($kb $pattern (extract-value $pattern $value) $init $fun identity unit-stv)
                 $out))
              (STV 1.0 1.0)
              cpu))
        ((Not $a)
           (bundle-from-execs
              ((: ($kb $ctx $vars) $prfa $a $tv_a) (CPU NotFormula ($tv_a) $tv))
              $tv
              $prfa))
        (($rel $a $b)
           (if (is-member $rel (GreaterThan >))
              (if (is-expr $b)
                 (bundle-from-execs
                    ((: ($kb $ctx $vars) $prfa $a $tv_a)
                       (: ($kb $ctx $vars) $prfb $b $tv_b)
                       (CPU DistGreaterThanDistFormula ($tv_a $tv_b) $tv))
                    $tv
                    (rule-proof conjunction $prfa $prfb))
                 (bundle-from-execs
                    ((: ($kb $ctx $vars) $prfa $a $tv_a)
                       (CPU DistGreaterThanFormula ($tv_a $b) $tv))
                    $tv
                    $prfa))
              (bundle-from-execs ((: ($kb $ctx $vars) $prf ($rel $a $b) $tv)) $tv $prf)))
        ($other
           (bundle-from-execs ((: ($kb $ctx $vars) $prf $other $tv)) $tv $prf))))))

(= (append-premise-bundle
      (compiled-premises $current-execs $current-proofs $current-tv)
      (premise-bundle $_exec-types $execs $tv $proof))
   (if (== $current-execs ()) (compiled-premises $execs ($proof) $tv)
      (compiled-premises
         (append $current-execs (append $execs ((CPU AndFormula ($current-tv $tv) $next-tv))))
         (append $current-proofs ($proof))
         $next-tv)))

(= (lower-source-premises-step $kb $ctx $vars $acc $premise)
   (append-premise-bundle $acc (lower-source-premise $kb $ctx $vars $premise)))

(= (lower-source-premises $kb $ctx $vars $premises)
   (fold-flat
      (lower-source-premises-step $kb $ctx $vars)
      (compiled-premises () () (STV 1.0 1.0))
      $premises))
(= (build-implication-plan $kb $prf $premises $conclusions)
   (let*
      (((compiled-premises $execs $proofs $atv) (once (lower-source-premises $kb $ctx $vars $premises)))
       ($shape-kb ($kb $ctx $vars))
       ($a (seq2expr (map-flat exec-goal-type $execs)))
       ($b (seq2expr $conclusions))
       ($nb (skolemize $prf $a $b))
       ($na (skolemize $prf $b $a))
       ($skip-inverse (or (disable-inversion-proof-id? $prf) (contains-cpu? $a))))
      (compiled-implication $shape-kb $a $b $nb $na $skip-inverse $execs $proofs $atv)))
(= (compile-query-adds (: $kb $prf $type $tv))
   (collapse (compile-adapter-chain query (: $kb $prf $type $tv))))
(= (compile $kb $stmt) (compile_ $kb $stmt))
(= (kbctx $kb) (if (is-expr $kb) $kb ($kb MAIN Nil)))
(= (map-nested2 $f ()) ())
(= (map-nested2 $f (cons $x $xs))
   (if (is-expr $x) ($f (cons (map-nested2 $f $x) (map-nested2 $f $xs)))
      ($f (cons ($f $x) (map-nested2 $f $xs)))))
(= (toQuery $elem)
   (if (is-var $elem) # (if (=? $elem (exists $_1 $_2 $_3)) $var $elem)))

(= (contains-cpu? $term)
   (if (is-var $term) false
      (if (is-expr $term)
         (or (== (car-atom $term) CPU)
            (fold-flat (|-> ($acc $elem) (or $acc (contains-cpu? $elem))) false (cdr-atom $term)))
         false)))

(= (disable-inversion-proof-id? $prf)
   (or (= $prf (mined_implication $_ $_)) (= $prf (no_inverse $_))))

(= (inverse-implication $kb $prf $a $b $itv)
   (let*
      (($a1 (map-nested2 toQuery $a))
        ($b1 (map-nested2 toQuery $b)))
      (((: ($kb $ctx $vars) $prfa_est $a1 $atv)
            (: ($kb $ctx $vars) $prfb_est $b1 $btv_est)
            (CPU InversionFormula ($atv $btv_est $itv) $iitv)
            (: ($kb $ctx $vars) $prfb_wit $b $btv_wit)
            (CPU MpFormula ($iitv $btv_wit) $atv))
         |-
         ((: ($kb $ctx $vars)
               ((inverted $prf with $prfa_est $prfb_est) $prfb_wit)
               $a
               $atv)))))

(= (compile_ $kb (@ $stmt (: $prf $Type $tv)))
   (if (is-var $Type) (empty)
      (if
         (= $Type
            (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (($plan (build-implication-plan $kb $prf $premises $conclusions))
             ((compiled-implication $shape-kb $a $b $nb $na $skip-inverse $execs $proofs $atv) $plan))
            (superpose
               ((once
                    (let*
                       (($proof-token
                           (case $proofs (
                                (() cpu)
                                ((cons $proof ()) $proof)
                                ((cons $proof $rest)
                                   (cons rule-proof (cons conjunction (cons $proof $rest)))))))
                        ($allargs (append $execs ((CPU MpFormula ($tv $atv) $btv)))))
                       ($allargs |- ((: $shape-kb ($prf $proof-token) $b $btv)))))
                (if (is-var $nb) (empty)
                   (compile-outputs (: (kbctx $kb) ($prf $prfa) $nb $btv)))
                (if (is-var $a) (empty)
                   (compile-adapter-chain plain (: (kbctx $kb) $prfa $a $atv)))
                (if (not $skip-inverse)
                   (inverse-implication $kb $prf $na $b $tv)
                   (empty))
                (if (or $skip-inverse (is-var $na)) (empty)
                   (compile-outputs
                      (: ((inverted $prf $pa $pb1) $pb2) $na $natv)))
                (if (or $skip-inverse (is-var $b)) (empty)
                   (compile-adapter-chain plain (: $pb2 $b $btv2))))))
         (superpose
            ((() |- ((: ($kb MAIN Nil) $prf $Type $tv)))
             (compile-outputs (: ($kb MAIN Nil) $prf $Type $tv)))))))
(= (compileQuery $kb (: $prf $Type $tv))
   (if (is-var $Type) ((() |- ((: (kbctx $kb) $prf $Type $tv))) ())
      (if
         (= $Type
            (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (($plan (build-implication-plan $kb $prf $premises $conclusions))
             ((compiled-implication $shape-kb $a $b $_nb $_na $_skip-inverse $_execs $_proofs $_atv) $plan))
            ((((: $shape-kb $prfa $a (STV 1.0 1.0))) |- ((: $shape-kb $prfb $b $itv)))
               (collapse
                  (superpose
                     ((compile-adapter-chain plain (: $shape-kb $prfb $b $btv))
                      (compile-outputs (: $shape-kb $prfa $a $atv)))))))
         (((() |- ((: (kbctx $kb) $prf $Type $tv)))
            (compile-query-adds (: (kbctx $kb) $prf $Type $tv)))))))
(= (mm2compile $kb $stmt)
   (progn (remove-all-atoms ctx)
      (superpose ((mm2stmt (compile $kb $stmt))
                  (get-atoms ctx)))))
(= (mm2stmt $stmt)
   (case $stmt (
        ((() |- ($ccl)) $ccl)
        (($prms |- ($ccl)) (rules ($prms |- $ccl))))))

(= (mm2compileQuery $kb $stmt)
   (let $compiled (compileQuery $kb $stmt)
      (if (= $compiled (((() |- ($ccl)) $adds)))
         (let*
            (($tail (map-flat mm2stmt $adds)))
            (compiled-query $ccl $tail))
         (if
            (= $compiled
               ((((: ($kbid $_ctx $_vars) $prf $type $tv)) |-
                     ((: ($kbid $_ctx $_vars) $prf1 $type1 $tv1)))
                  $adds))
            (let*
               (($vars (extract-vars $type))
                 ($mvars (if (== $vars ()) Nil $vars))
                 ($ctx (nextctx))
                 ($ctxatom (: ($kbid $ctx $mvars) (ctx proof $ctx) $type $tv))
                 ($tail (map-flat mm2stmt $adds))
                 ($goal (: ($kbid $ctx $mvars) $prf1 $type1 $tv1))
                 ($all-adds (union-atom ($ctxatom) $tail)))
               (compiled-query $goal $all-adds))
            (notsupported mm2compileQuery $kb $stmt $compiled)))))

(= (mf $kb ($kb $t)) $t)

(= (internalize-proof-structure $term)
   (if (is-var $term) $term
      (if (= $term (: $kb $prf $type $tv)) ($type $kb $prf $tv)
         (if (is-expr $term)
            (cons (internalize-proof-structure (car-atom $term))
               (internalize-proof-structure-list (cdr-atom $term)))
            $term))))

(= (internalize-proof-structure-list $terms)
   (if (== $terms ()) () (map-flat internalize-proof-structure $terms)))

(= (externalize-proof-structure $term)
   (if (is-var $term) $term
      (if (= $term ($type ($kbid $ctx $vars) $prf $tv))
         (: ($kbid $ctx $vars) $prf $type $tv)
         (if (is-expr $term)
            (cons (externalize-proof-structure (car-atom $term))
               (externalize-proof-structure-list (cdr-atom $term)))
            $term))))

(= (externalize-proof-structure-list $terms)
   (if (== $terms ()) () (map-flat externalize-proof-structure $terms)))

(= (mm2compileQueryInternal $kb $stmt)
   (let*
      (((compiled-query $raw-goal $raw-adds) (car-atom (collapse (mm2compileQuery $kb $stmt)))))
      (compiled-query
         (internalize-proof-structure $raw-goal)
         (internalize-proof-structure-list $raw-adds))))

(= (pretty-prf-token $prf)
   (if (= $prf (mined_implication $premk $conck))
      (Implication (cons Premises ($premk)) (cons Conclusions ($conck)))
      $prf))

(= (pretty-prf $prf) (if (is-expr $prf) (map-nested2 pretty-prf-token $prf) $prf))

(= (lookup-mined-tv $premk $conck $fallback-tv)
   (let $m
      (collapse
         (once
            (match &kb ($itype ($kbid MAIN ()) (mined_implication $premk $conck) $itv)
               $itv)))
      (if (== $m ()) $fallback-tv (car-atom $m))))

(= (extract-mined-itv-from-args $args $fallback-tv)
   (if (= $args ($_prem (CPU MpFormula ($itv $_atv) $_btv))) $itv
      (if (= $args (cons $h $t))
         (if (= $h (CPU MpFormula ($itv $_atv2) $_btv2)) $itv
            (extract-mined-itv-from-args $t $fallback-tv))
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
         (: mined_implication
            ((pretty-prf-token (mined_implication $premk $conck)) $p)
            $type
            $ptv))
      (pretty $goal)))
(= (pretty (: $kb $prf $type $tv))
   (if (is-expr $kb)
      (if (= $kb ($kbid MAIN Nil)) (: (pretty-prf $prf) $type $tv)
         (let*
            ((($_ $idx $vars) $kb)
              ($x (map-flat (mf $kb) (collapse (match &kb ($t $kb $p $tv2) ($kb $t)))))
              ($ptype (Implication (cons Premises $x) (cons Conclusions ($type)))))
            (: (pretty-prf $prf) $ptype $tv)))
      (: (pretty-prf $prf) $type $tv)))
