!(import! &self (library lib_roman))
!(import! &self (library lib_spaces))
!(import! &self (library lib_he))
!(import! &self logic_config)

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

(= (remove-index 0 (cons $_head $tail)) $tail)
(= (remove-index $idx (cons $head $tail)) (cons $head (remove-index (- $idx 1) $tail)))
(= (remove-index $_idx ()) ())

(= (seq2expr (cons $head $tail)) (if (== $tail ()) $head (cons And (cons $head $tail))))

(= (projection-evidence-proof-token (cons $proof ())) $proof)
(= (projection-evidence-proof-token (cons $proof (cons $next $rest)))
   (cons conjunction (cons $proof (cons $next $rest))))

(= (projection-evidence-step $kb $formula
      (projection-evidence-state $execs $proofs $acc-tv)
      $elem)
   (projection-evidence-state
      (append $execs ((: $kb $prf $elem $tv) (CPU $formula ($acc-tv $tv) $next-tv)))
      (append $proofs ($prf))
      $next-tv))

(= (projection-evidence-bundle $kb $head (cons $fst $rst))
   (let*
      (((projection-evidence-state $execs $proofs $tv)
           (fold-flat
              (projection-evidence-step $kb (atom_concat $head Formula))
              (projection-evidence-state ((: $kb $fstprf $fst $fsttv)) ($fstprf) $fsttv)
              $rst))
        ($proof-token (projection-evidence-proof-token $proofs)))
      (bundle-from-execs $execs $tv $proof-token)))

(= (compile-output-children $kb $type $head $idx ()) (empty))
(= (compile-output-children $kb $type $head $idx (cons $elem $rest))
   (superpose (
      (let $others (remove-index $idx (cdr-atom $type))
         (if (== $others ())
            (((: $kb $prf $type $tvin) (CPU (atom_concat $head Projection) ($tvin) $tvout)) |-
               ((: $kb (proj $idx $prf) $elem $tvout)))
            (let*
               (((premise-bundle $execs $evidence-tv $evidence-proof)
                    (projection-evidence-bundle $kb $head $others))
                 ($allargs
                    (append
                       ((: $kb $prf $type $tvin))
                       (append $execs ((CPU (atom_concat $head Projection) ($tvin $evidence-tv) $tvout)))))
                 ($proof-token ((proj $idx $prf) $evidence-proof)))
               ($allargs |- ((: $kb $proof-token $elem $tvout))))))
      (compile-outputs (: $kb $childprf $elem $childtv))
      (compile-output-children $kb $type $head (+ $idx 1) $rest))))

(= (compile-outputs (: $kb $NNprf (@ $type (cons $head $tail)) $NNtv))
   (if (and (compound-source? $type) (= (configured-compound-output-mode $head) ProjectAll))
      (compile-output-children $kb $type $head 0 $tail)
      (empty)))

(= (cpu-premise-tv-formula $f)
   (is-member $f (() NotFormula DistGreaterThanFormula DistGreaterThanDistFormula)))

(= (cpu-premise-tv FoldAllCompiled $_args $_res) (STV 1.0 1.0))
(= (cpu-premise-tv GroupedFoldAllCompiled $_args $_res) (STV 1.0 1.0))
(= (cpu-premise-tv $f $args $res) (if (cpu-premise-tv-formula $f) $res (STV 1.0 1.0)))

(= (source-premise-kb $kb $ctx $vars)
   (if (or (is-var $ctx) (is-var $vars)) (kbctx $kb) ($kb $ctx $vars)))

(= (leaf-source-bundle $kb $ctx $vars $elem)
   (let $prem-kb (source-premise-kb $kb $ctx $vars)
      (if (is-var $elem)
         (bundle-from-execs ((: $prem-kb $prf $elem $tv)) $tv $prf)
         (if (= $elem (CPU $f $args $res))
         (bundle-from-execs ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu)
         (bundle-from-execs ((: $prem-kb $prf $elem $tv)) $tv $prf)))))

(= (in_map $kb $elem)
   (if (= $elem (CPU $f $args $res))
      (prem (CPU $f $args $res) (CPU $f $args $res) (cpu-premise-tv $f $args $res) cpu)
      (prem (: $kb $prf $elem $tv) $elem $tv $prf)))

(= (tv $tv) (: $kb $prf $elem $tv))

(=
   (in_fold $formula
      ((@ $premises (head (tv $tv))) (: $res-kb $cclprf $ccltype $ccltv))
      (prem $goal $elem $tve $prfelem))
   ((cons (CPU $formula ($tv $tve) $ntv) (cons $goal $premises))
      (: $res-kb (cons $prfelem $cclprf) (cons $elem $ccltype) $ntv)))

(= (exec-goal-type (CPU $f $args $res)) (CPU $f $args $res))
(= (exec-goal-type (: $_kb $_prf $elem $_tv)) $elem)

(= (execs-goal-type $execs) (seq2expr (map-flat exec-goal-type $execs)))

(= (bundle-from-execs $execs $result-tv $proof) (premise-bundle $execs $result-tv $proof))

(= (compound-all-premise-bundle $kb $ctx $vars $head $tail)
   (let*
      (($prem-kb (if (or (is-var $ctx) (is-var $vars)) (kbctx $kb) ($kb $ctx $vars)))
        ((cons (@ $fst (prem $fstgoal $fstelem $fsttv $fstprf)) $rst) (map-flat (in_map $prem-kb) $tail))
        ($init (($fstgoal) (: $prem-kb ($fstprf) ($fstelem) $fsttv)))
        (($resNNprms (: $res-kb $cclprf $ccltype $ccltv))
           (fold-flat (in_fold (atom_concat $head Formula)) $init $rst))
        (($execs $rcclprf $rccltype) ((reverse $resNNprms) (reverse $cclprf) (reverse $ccltype)))
        ($proof-token (if (= $rcclprf (cons $proof ())) $proof (cons conjunction $rcclprf))))
      (bundle-from-execs $execs $ccltv $proof-token)))

(= (compound-any-premise-child-bundle $kb $ctx $vars $head $elem)
   (let*
      (($prem-kb (if (or (is-var $ctx) (is-var $vars)) (kbctx $kb) ($kb $ctx $vars)))
        ((prem $goal $_elem $tv $proof) (in_map $prem-kb $elem)))
      (bundle-from-execs ($goal) $tv ((atom_concat $head introduction) $proof))))

(= (compound-any-premise-bundle $_kb $_ctx $_vars $_head ()) (empty))
(= (compound-any-premise-bundle $kb $ctx $vars $head (cons $elem $rest))
   (superpose (
      (compound-any-premise-child-bundle $kb $ctx $vars $head $elem)
      (compound-any-premise-bundle $kb $ctx $vars $head $rest))))

(= (compound-premise-bundle $kb $ctx $vars $head $tail)
   (let $mode (configured-compound-premise-mode $head)
      (if (= $mode Any)
         (compound-any-premise-bundle $kb $ctx $vars $head $tail)
         (compound-all-premise-bundle $kb $ctx $vars $head $tail))))

(= (compound-source? $type)
   (if (is-expr $type)
      (let $head (car-atom $type)
         (and (not (is-var $head)) (compound-connective? $head)))
      false))

(= (query-compound-child-bundle $kb $ctx $vars $premise)
   (if (compound-source? $premise)
      (let (cons $head $tail) $premise (query-compound-premise-bundle $kb $ctx $vars $head $tail))
      (if (is-expr $premise)
         (let $head (car-atom $premise)
            (if (is-var $head)
               (leaf-source-bundle $kb $ctx $vars $premise)
               (if (is-member $head
                     (Compute MapDist Map2Dist AverageDist FoldAllValue FoldAll Not GreaterThan >))
                  (once (lower-source-premise $kb $ctx $vars $premise))
                  (leaf-source-bundle $kb $ctx $vars $premise))))
         (leaf-source-bundle $kb $ctx $vars $premise))))

(= (query-compound-premise-state (premise-bundle $execs $tv $proof))
   (query-compound-state $execs ($proof) $tv))

(=
   (query-compound-premise-step $kb $ctx $vars $formula
      (query-compound-state $acc-execs $acc-proofs $acc-tv)
      $premise)
   (let*
      (((premise-bundle $execs $tv $proof) (query-compound-child-bundle $kb $ctx $vars $premise)))
      (query-compound-state
         (append $acc-execs (append $execs ((CPU $formula ($acc-tv $tv) $next-tv))))
         (append $acc-proofs ($proof))
         $next-tv)))

(= (query-compound-premise-bundle $kb $ctx $vars $head (cons $fst $rst))
   (let*
      (((query-compound-state $execs $proofs $ccltv)
           (fold-flat
              (query-compound-premise-step $kb $ctx $vars (atom_concat $head Formula))
              (query-compound-premise-state (query-compound-child-bundle $kb $ctx $vars $fst))
              $rst))
        ($rcclprf (reverse $proofs))
        ($proof-token (if (= $rcclprf (cons $proof ())) $proof (cons conjunction $rcclprf))))
      (bundle-from-execs $execs $ccltv $proof-token)))

(= (compound-direct-query-compute? $items)
   (if (== $items ()) false
      (case $items (
         ((cons (Compute $_f $_args $_res) $_rest) true)
         ((cons $_item $rest) (compound-direct-query-compute? $rest))))))

(= (query-compound-child-needs-bundle? $premise)
   (if (compound-source? $premise)
      (query-compound-needs-bundle? $premise)
      (if (is-expr $premise)
         (let $head (car-atom $premise)
            (if (is-var $head) false
               (is-member $head
                  (Compute MapDist Map2Dist AverageDist FoldAllValue FoldAll Not GreaterThan >))))
         false)))

(= (compound-direct-query-bundle? $items)
   (if (== $items ()) false
      (case $items (
         ((cons $item $rest)
            (or (query-compound-child-needs-bundle? $item)
               (compound-direct-query-bundle? $rest)))))))

(= (query-compound-needs-bundle? $term)
   (if (is-expr $term) (compound-direct-query-bundle? (cdr-atom $term)) false))

(= (compile-adapter-chain plain (: $kb $prf (@ $type (cons $head $tail)) $tv))
   (if (compound-source? $type)
      (let*
         (((premise-bundle $execs $result-tv $proof-token)
              (compound-premise-bundle $kb
                 $ctx
                 $vars
                 $head
                 $tail))
           ($exec-type (execs-goal-type $execs)))
         (superpose (($execs |- ((: $kb $proof-token $type $result-tv)))
                     (if (== $exec-type $type) (empty)
                        (compile-adapter-chain plain (: $kb $prfa $exec-type $atv))))))
      (empty)))
(= (compile-adapter-chain plain (: $_kb $_prf $_type $_tv)) (empty))
(= (compile-adapter-chain query (: $kb $prf $type $tv))
   (if (and (is-expr $type) (let $head (car-atom $type) (and (not (is-var $head)) (== $head Not))))
      (let $a (car-atom (cdr-atom $type))
         (((: $kb $inner-prf $a $inner-tv) (CPU NotFormula ($inner-tv) $tv))
            |-
            ((: $kb (negated $inner-prf) $type $tv))))
      (if (compound-source? $type)
         (if (query-compound-needs-bundle? $type)
            (let*
               (((cons $head $tail) $type)
                 ((premise-bundle $execs $result-tv $proof-token)
                    (once (query-compound-premise-bundle $kb $ctx $vars $head $tail))))
               (($execs |- ((: $kb ($prf $proof-token) $type $result-tv)))))
            (compile-adapter-chain plain (: $kb $prf $type $tv)))
         (let*
            (((premise-bundle $execs $result-tv $proof-token)
                 (once (lower-source-premise $kb $ctx $vars $type)))
              ($exec-type (execs-goal-type $execs)))
            (if (and (not (is-var $type)) (not (== $exec-type $type)))
               (superpose (($execs |- ((: $kb ($prf $proof-token) $type $result-tv)))
                           (compile-adapter-chain plain (: $kb $prfa $exec-type $atv))))
               (empty))))))

(= (add-query-add-to-ctx $expr) (add-atom ctx $expr))

(= (lower-source-premise-non-open $kb $ctx $vars $premise)
   (if (compound-source? $premise)
      (let (cons $head $tail) $premise (compound-premise-bundle $kb $ctx $vars $head $tail))
      (case $premise (
           ((Implication (cons Premises $_premises) (cons Conclusions $_conclusions))
              (leaf-source-bundle $kb $ctx $vars $premise))
           ((Compute $f $args -> $res)
              (bundle-from-execs ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu))
           ((Compute $f $args $res)
              (bundle-from-execs ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu))
           ((MapDist $fun $a $value -> $out)
              (bundle-from-execs
                 ((: ($kb $ctx $vars) $prfa $a $tv_a) (CPU DistMapFormula ($fun $value) $out))
                 (STV 1.0 1.0)
                 $prfa))
           ((Map2Dist $fun $a $valuea $b $valueb -> $out)
              (bundle-from-execs
                 ((: ($kb $ctx $vars) $prfa $a $tv_a) (: ($kb $ctx $vars) $prfb $b $tv_b)
                    (CPU DistMap2Formula (quote ($fun $valuea $valueb)) $out))
                 (STV 1.0 1.0)
                 (conjunction $prfa $prfb)))
           ((AverageDist $pattern $value -> $out)
              (bundle-from-execs
                 ((CPU FoldAllCompiled
                       ($kb $pattern
                          (extract-value $pattern $value)
                          (SumCount (PointMass 0.0) 0)
                          DistSumCountAcc
                          dist-average
                          result-tv)
                       $out))
                 (STV 1.0 1.0)
                 cpu))
           ((FoldAllValue $pattern $init $fun -> $out)
              (bundle-from-execs
                 ((CPU FoldAllCompiled ($kb $pattern extract-tv $init $fun identity result-tv) $out))
                 (STV 1.0 1.0)
                 cpu))
           ((FoldAll $pattern $value $init $fun -> $out)
              (bundle-from-execs
                 ((CPU FoldAllCompiled
                       ($kb $pattern
                          (extract-value $pattern $value)
                          $init
                          $fun
                          identity
                          unit-stv)
                       $out))
                 (STV 1.0 1.0)
                 cpu))
           ((Not $a)
              (let $prem-kb (source-premise-kb $kb $ctx $vars)
                 (bundle-from-execs ((: $prem-kb $prfa $a $tv_a) (CPU NotFormula ($tv_a) $tv)) $tv (negated $prfa))))
           (($rel $a $b)
              (if (is-member $rel (GreaterThan >))
                 (if (is-var $b) (bundle-from-execs ((CPU DistGreaterThanDistFormula ($a $b) $tv)) $tv cpu)
                    (bundle-from-execs ((CPU DistGreaterThanFormula ($a $b) $tv)) $tv cpu))
                 (bundle-from-execs ((: ($kb $ctx $vars) $prf ($rel $a $b) $tv)) $tv $prf)))
           ($other (bundle-from-execs ((: ($kb $ctx $vars) $prf $other $tv)) $tv $prf))))))

(= (lower-source-premise $kb $ctx $vars $premise)
   (if (and (is-expr $premise) (is-var (car-atom $premise)))
      (if (== (cdr-atom $premise) ())
         (leaf-source-bundle $kb $ctx $vars (car-atom $premise))
         (leaf-source-bundle $kb $ctx $vars $premise))
      (lower-source-premise-non-open $kb $ctx $vars $premise)))

(=
   (append-premise-bundle (compiled-premises $current-execs $current-proofs $current-tv)
      (premise-bundle $execs $tv $proof))
   (if (== $current-execs ()) (compiled-premises $execs ($proof) $tv)
      (compiled-premises
         (append $current-execs (append $execs ((CPU AndFormula ($current-tv $tv) $next-tv))))
         (append $current-proofs ($proof))
         $next-tv)))

(= (compile-same-var-in-list? $_var ()) false)
(= (compile-same-var-in-list? $var (cons $head $tail))
   (or (== $var $head) (compile-same-var-in-list? $var $tail)))

(= (compile-var-list-subtract () $_exclude) ())
(= (compile-var-list-subtract (cons $var $rest) $exclude)
   (if (compile-same-var-in-list? $var $exclude)
      (compile-var-list-subtract $rest $exclude)
      (cons $var (compile-var-list-subtract $rest $exclude))))

(= (compile-has-vars? $vars) (not (== $vars ())))

(= (fold-existential-premise-bundle $kb $ctx $vars $premise $group-vars)
   (let $prem-kb (source-premise-kb $kb $ctx $vars)
      (if (== $group-vars ())
         (bundle-from-execs
            ((CPU FoldAllCompiled
                 ($prem-kb $premise extract-tv (STV 0.0 1.0) OrFormula identity result-tv)
                 $fold-tv))
            $fold-tv
            cpu)
         (bundle-from-execs
            ((CPU GroupedFoldAllCompiled
                 ($prem-kb $premise $group-vars extract-tv (STV 0.0 1.0) OrFormula identity result-tv)
                 $fold-tv))
            $fold-tv
            cpu))))

(= (existential-foldable-premise? $premise)
   (if (is-expr $premise)
      (let $head (car-atom $premise)
         (if (is-var $head) true
            (not
               (is-member $head
                  (Implication Compute MapDist Map2Dist AverageDist FoldAllValue FoldAll Not GreaterThan >)))))
      true))

(= (lower-source-premise-with-existentials $kb $ctx $vars $premise)
   (if (and (is-expr $premise) (and (not (is-var (car-atom $premise))) (== (car-atom $premise) ExistentialFold)))
      (let $args (cdr-atom $premise)
         (fold-existential-premise-bundle $kb $ctx $vars (car-atom $args) (car-atom (cdr-atom $args))))
      (lower-source-premise $kb $ctx $vars $premise)))

(= (compile-premise-local-vars $conclusion-vars $other-vars $premise)
   (let $premise-vars (list_to_set (extract-vars $premise))
      (compile-var-list-subtract (compile-var-list-subtract $premise-vars $conclusion-vars) $other-vars)))

(= (compile-premise-has-existentials? $conclusion-vars $other-vars $premise)
   (let $local-vars (compile-premise-local-vars $conclusion-vars $other-vars $premise)
      (and (existential-foldable-premise? $premise) (compile-has-vars? $local-vars))))

(= (compile-premise-group-vars $conclusion-vars $other-vars $premise)
   (let*
      (($premise-vars (list_to_set (extract-vars $premise)))
        ($local-vars (compile-premise-local-vars $conclusion-vars $other-vars $premise)))
      (compile-var-list-subtract $premise-vars $local-vars)))

(= (partition-existential-premises-walk $_conclusion-vars $_prior-vars $normal $folded ())
   ($normal $folded))
(= (partition-existential-premises-walk $conclusion-vars $prior-vars $normal $folded (cons $premise $rest))
   (let*
      (($premise-vars (list_to_set (extract-vars $premise)))
        ($rest-vars (list_to_set (extract-vars $rest)))
        ($other-vars (append $prior-vars $rest-vars))
        ($nprior (append $prior-vars $premise-vars)))
      (if (compile-premise-has-existentials? $conclusion-vars $other-vars $premise)
         (let $group-vars (compile-premise-group-vars $conclusion-vars $other-vars $premise)
            (partition-existential-premises-walk $conclusion-vars $nprior $normal (append $folded ((ExistentialFold $premise $group-vars))) $rest))
         (partition-existential-premises-walk $conclusion-vars $nprior (append $normal ($premise)) $folded $rest))))

(= (partition-existential-premises $conclusion-vars $premises)
   (let*
      ((($normal $folded)
          (partition-existential-premises-walk $conclusion-vars () () () $premises)))
      (append $normal $folded)))

(= (lower-source-premises-step $kb $ctx $vars $acc $premise)
   (append-premise-bundle $acc
      (lower-source-premise-with-existentials $kb $ctx $vars $premise)))

(= (lower-source-premises-list $kb $ctx $vars $premises)
   (fold-flat (lower-source-premises-step $kb $ctx $vars)
      (compiled-premises () () (STV 1.0 1.0))
      $premises))

(= (lower-source-premises $kb $ctx $vars $premises $conclusions)
   (let*
      (($conclusion-vars (list_to_set (extract-vars $conclusions)))
        ($ordered-premises (partition-existential-premises $conclusion-vars $premises)))
      (lower-source-premises-list $kb $ctx $vars $ordered-premises)))

(= (lower-source-premises $kb $ctx $vars $premises)
   (lower-source-premises-list $kb $ctx $vars $premises))

(= (lower-query-assumption-premise $kb $ctx $vars $premise)
   (if (is-var $premise) (lower-source-premise $kb $ctx $vars $premise)
      (if (is-expr $premise)
         (let $head (car-atom $premise)
            (if (is-var $head) (lower-source-premise $kb $ctx $vars $premise)
               (if (== $head Implication)
                  (leaf-source-bundle $kb $ctx $vars $premise)
                  (if (== $head Not)
                     (let $prem-kb (source-premise-kb $kb $ctx $vars)
                        (bundle-from-execs ((: $prem-kb $prf (car-atom (cdr-atom $premise)) (STV 0.0 1.0))) (STV 1.0 1.0) $prf))
                     (lower-source-premise $kb $ctx $vars $premise)))))
         (lower-source-premise $kb $ctx $vars $premise))))

(= (lower-query-assumption-premises-step $kb $ctx $vars $acc $premise)
   (append-premise-bundle $acc (lower-query-assumption-premise $kb $ctx $vars $premise)))

(= (lower-query-assumption-premises $kb $ctx $vars $premises)
   (fold-flat (lower-query-assumption-premises-step $kb $ctx $vars)
      (compiled-premises () () (STV 1.0 1.0))
      $premises))

(= (lower-query-assumption-premise-false $kb $ctx $vars $premise)
   (if (is-var $premise)
      (bundle-from-execs ((: ($kb $ctx $vars) $prf $premise (STV 0.0 1.0))) (STV 0.0 1.0) $prf)
      (if (is-expr $premise)
         (let $head (car-atom $premise)
            (if (is-var $head)
               (bundle-from-execs ((: ($kb $ctx $vars) $prf $premise (STV 0.0 1.0))) (STV 0.0 1.0) $prf)
               (if (== $head Not)
                  (let $prem-kb (source-premise-kb $kb $ctx $vars)
                     (bundle-from-execs ((: $prem-kb $prf (car-atom (cdr-atom $premise)) (STV 1.0 1.0))) (STV 0.0 1.0) (negated $prf)))
                  (if (== $head Implication)
                     (bundle-from-execs
                        ((: ($kb $ctx $vars) $prf $premise (CTV (STV 0.0 1.0) (STV 1.0 1.0))))
                        (CTV (STV 0.0 1.0) (STV 1.0 1.0))
                        $prf)
                     (bundle-from-execs ((: ($kb $ctx $vars) $prf $premise (STV 0.0 1.0))) (STV 0.0 1.0) $prf)))))
         (bundle-from-execs ((: ($kb $ctx $vars) $prf $premise (STV 0.0 1.0))) (STV 0.0 1.0) $prf))))

(= (lower-query-assumption-premises-negative $kb $ctx $vars ())
   (compiled-premises () () (STV 0.0 1.0)))
(= (lower-query-assumption-premises-negative $kb $ctx $vars (cons $premise $rest))
   (fold-flat (lower-query-assumption-premises-step $kb $ctx $vars)
      (append-premise-bundle
         (compiled-premises () () (STV 1.0 1.0))
         (lower-query-assumption-premise-false $kb $ctx $vars $premise))
      $rest))

(= (build-implication-plan $kb $prf $premises $conclusions)
   (let*
      (((compiled-premises $execs $proofs $atv) (once (lower-source-premises $kb $ctx $vars $premises $conclusions)))
        ($shape-kb ($kb $ctx $vars))
        ($a (execs-goal-type $execs))
        ($b (seq2expr $conclusions))
        ($nb (skolemize $prf $a $b))
        ($na (skolemize $prf $b $a))
        ($skip-inverse (or (disable-inversion-proof-id? $prf) (contains-cpu? $a))))
      (compiled-implication $shape-kb
         $a
         $b
         $nb
         $na
         $skip-inverse
         $execs
         $proofs
         $atv)))

(= (bidirectional-implication-type? $Type)
   (if (is-expr $Type)
      (let $head (car-atom $Type)
         (and (not (is-var $head)) (bidirectional-implication-form? $head)))
      false))

(= (compile-query-adds (: $kb $prf $type $tv))
   (collapse (compile-adapter-chain query (: $kb $prf $type $tv))))


(= (compile $kb $stmt) (compile_ $kb $stmt))

(= (kbctx $kb) (if (is-expr $kb) $kb ($kb MAIN Nil)))

(= (context-polymorphic-facts-key $kb) (atom_concat context_polymorphic_facts_ $kb))

(= (set-context-polymorphic-facts $kb $enabled)
   (change-state! (context-polymorphic-facts-key $kb) $enabled))

(= (context-polymorphic-facts? $kb)
   (let $menabled (catch (get-state (context-polymorphic-facts-key $kb)))
      (if-error $menabled false $menabled)))

(= (compile-fact-kb $kb)
   (if (is-expr $kb) $kb
      (if (context-polymorphic-facts? $kb) ($kb $ctx $vars) ($kb MAIN Nil))))

(= (map-nested2 $f ()) ())
(= (map-nested2 $f (cons $x $xs))
   (if (is-expr $x) ($f (cons (map-nested2 $f $x) (map-nested2 $f $xs)))
      ($f (cons ($f $x) (map-nested2 $f $xs)))))

(= (toQuery $elem) (if (=? $elem (exists $_1 $_2 $_3)) $var $elem))

(= (contains-cpu? $term)
   (if (is-var $term) false
      (if (is-expr $term)
         (or (== (car-atom $term) CPU)
            (fold-flat (|-> ($acc $elem) (or $acc (contains-cpu? $elem))) false (cdr-atom $term)))
         false)))

(= (disable-inversion-proof-id? $prf) (or (= $prf (mined_implication $_ $_)) (= $prf (no_inverse $_))))

(= (index-source-implication $_kb (: $_prf (Implication (cons Premises ($_premise)) (cons Conclusions ($_conclusion))) $_tv))
   ())
(= (index-source-implication $_kb $_stmt) ())

(= (implication-proof-token $proofs)
   (case $proofs (
      (() cpu)
      ((cons $proof ()) $proof)
      ((cons $proof $rest)
         (cons conjunction (cons $proof $rest))))))

(= (compile-implication-forward-rules $shape-kb $adapter-kb $prf $tv $a $b $execs $proofs $atv)
   (superpose (
      (once
         (let*
            (($proof-token (implication-proof-token $proofs))
              ($allargs
                 (append $execs
                    ((CPU CTVFormula ($atv $tv) $btv)))))
            ($allargs |- ((: $shape-kb ($prf $proof-token) $b $btv)))))
      (if (is-var $b) (empty) (compile-outputs (: $adapter-kb ($prf $prfb) $b $btv2)))
      (if (is-var $a) (empty) (compile-adapter-chain plain (: $adapter-kb $prfa $a $atv))))))

(= (base-rate-premise $kb $pattern $brtv)
   (CPU FoldAllCompiled
      ($kb $pattern extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv)
      $brtv))

(= (inverse-implication $kb $prf $a $b $itv)
   (let*
      (($a1 (copy_term (map-nested2 toQuery $a)))
        ($b1 (copy_term (map-nested2 toQuery $b))))
      (((: ($kb $ctx $vars) $prfb_wit $b $btv_wit)
            (base-rate-premise $kb $a1 $atv)
            (base-rate-premise $kb $b1 $btv)
            (CPU CTVInversionFormula ($atv $btv $itv) $iitv)
            (CPU CTVFormula ($btv_wit $iitv) $mp-tv))
         |-
         ((: ($kb $ctx $vars) ((inverted $prf with cpu cpu) $prfb_wit) $a $mp-tv)))))


(= (compile_ $kb (@ $stmt (: $prf $Type $tv)))
   (if (is-var $Type) (empty)
      (if (= $Type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (($plan (build-implication-plan $kb $prf $premises $conclusions))
	              ((compiled-implication $shape-kb $a $b $nb $na $skip-inverse $execs $proofs $atv) $plan))
	            (superpose (
	                 (compile-implication-forward-rules $shape-kb (kbctx $kb) $prf $tv $a $b $execs $proofs $atv)
	                 (if (not $skip-inverse) (inverse-implication $kb $prf $na $b $tv) (empty))
	                 (if (or $skip-inverse (is-var $na)) (empty)
	                    (compile-outputs (: ((inverted $prf $w $pa1 $pa2) $pb2) $na $natv)))
	                 (if (or $skip-inverse (is-var $b)) (empty) (compile-adapter-chain plain (: $pb2 $b $btv2))))))
         (if (bidirectional-implication-type? $Type)
            (let ($_head (cons Premises $left) (cons Conclusions $right)) $Type
               (superpose (
                  (compile_ $kb (: (bi-forward $prf)
                     (Implication (cons Premises $left) (cons Conclusions $right))
                     $tv))
                  (compile_ $kb (: (bi-backward $prf)
                     (Implication (cons Premises $right) (cons Conclusions $left))
                     $tv)))))
            (let $fact-kb (compile-fact-kb $kb)
	               (superpose ((() |- ((: $fact-kb $prf $Type $tv)))
	                           (compile-outputs (: $fact-kb $prf $Type $tv)))))))))


(= (implication-query-known-tv-parts $tv)
   (if (is-var $tv)
      (implication-query-tv-parts $pos-tv $neg-tv (CTV $pos-tv $neg-tv))
      (let (CTV $pos-tv $neg-tv) $tv
         (implication-query-tv-parts $pos-tv $neg-tv $tv))))

(= (compileQuery $kb (: $prf $Type $tv))
   (if (is-var $Type) ((() |- ((: (kbctx $kb) $prf $Type $tv))) ())
      (if (= $Type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (($vars (extract-vars $Type))
              ($mvars (if (== $vars ()) Nil $vars))
              ($pos-ctx (nextctx))
              ($neg-ctx (nextctx))
              ($pos-shape-kb ($kb $pos-ctx $mvars))
              ($neg-shape-kb ($kb $neg-ctx $mvars))
              ($condition (seq2expr $premises))
              ((compiled-premises $pos-execs $_pos-proofs $_pos-atv)
                 (once (lower-query-assumption-premises $kb $pos-ctx $mvars $premises)))
		              ((compiled-premises $neg-execs $_neg-proofs $_neg-atv)
		                 (once (lower-query-assumption-premises-negative $kb $neg-ctx $mvars $premises)))
	              ($b (seq2expr $conclusions))
	              ($pos-ctxatoms (query-context-premise-adds $kb $pos-ctx $mvars $pos-execs))
	              ($neg-ctxatoms (query-context-premise-adds $kb $neg-ctx $mvars $neg-execs))
	              ($pos-adapter-adds (collapse (compile-adapter-chain query (: $pos-shape-kb $pos-prf $b $pos-adapter-tv))))
	              ($neg-adapter-adds (collapse (compile-adapter-chain query (: $neg-shape-kb $neg-prf $b $neg-adapter-tv))))
              ($pos-adds (union-atom $pos-ctxatoms $pos-adapter-adds))
              ($neg-adds (union-atom $neg-ctxatoms $neg-adapter-adds))
		              ($all-adds
	                  (union-atom
	                     $pos-adds
	                     $neg-adds)))
			            (let*
		               (((implication-query-tv-parts $known-pos-tv $known-neg-tv $known-tv)
		                    (implication-query-known-tv-parts $tv))
		                 ($known-pos-goal (: $pos-shape-kb $pos-prf $b $known-pos-tv))
		                 ($known-neg-goal (: $neg-shape-kb $neg-prf $b $known-neg-tv))
			                 ($known-goal (: (kbctx $kb) (total-implication $pos-prf $neg-prf) $Type $known-tv)))
		               ((($known-pos-goal $known-neg-goal) |- ($known-goal)) $all-adds)))
         (if (bidirectional-implication-type? $Type)
            (let ($_head (cons Premises $left) (cons Conclusions $right)) $Type
               (let*
                  (($vars (extract-vars $Type))
                    ($mvars (if (== $vars ()) Nil $vars))
                    ($left-ctx (nextctx))
                    ($right-ctx (nextctx))
                    ($left-shape-kb ($kb $left-ctx $mvars))
                    ($right-shape-kb ($kb $right-ctx $mvars))
                    ((compiled-premises $left-execs $_left-proofs $_left-atv)
                       (once (lower-query-assumption-premises $kb $left-ctx $mvars $left)))
                    ((compiled-premises $right-execs $_right-proofs $_right-atv)
                       (once (lower-query-assumption-premises $kb $right-ctx $mvars $right)))
                    ($left-goal (: $left-shape-kb $left-prf (seq2expr $right) $left-tv))
                    ($right-goal (: $right-shape-kb $right-prf (seq2expr $left) $right-tv))
                    ($left-ctxatoms (query-context-premise-adds $kb $left-ctx $mvars $left-execs))
                    ($right-ctxatoms (query-context-premise-adds $kb $right-ctx $mvars $right-execs))
                    ($left-adapter-adds (collapse (compile-adapter-chain query (: $left-shape-kb $left-prf (seq2expr $right) $left-adapter-tv))))
                    ($right-adapter-adds (collapse (compile-adapter-chain query (: $right-shape-kb $right-prf (seq2expr $left) $right-adapter-tv))))
                    ($adds (union-atom
                       (union-atom $left-ctxatoms $left-adapter-adds)
                       (union-atom $right-ctxatoms $right-adapter-adds)))
		                    ($goal (: (kbctx $kb) (bidirectional $left-prf $right-prf) $Type $tv)))
	                  ((($left-goal $right-goal (CPU AndFormula ($left-tv $right-tv) $tv)) |- ($goal)) $adds)))
            (((() |- ((: (kbctx $kb) $prf $Type $tv))) (compile-query-adds (: (kbctx $kb) $prf $Type $tv))))))))


(= (mm2compile $kb $stmt)
   (progn (remove-all-atoms ctx) (superpose ((mm2stmt (compile $kb $stmt)) (get-atoms ctx)))))

(= (mm2stmt $stmt) (case $stmt (((() |- ($ccl)) $ccl) (($prms |- ($ccl)) (rules ($prms |- $ccl))))))

(= (query-temp-rule-premise (Compute $f $args $res)) (Compute $f $args -> $res))
(= (query-temp-rule-premise $premise) $premise)

(= (query-compound-type? $type)
   (if (is-expr $type)
      (let $head (car-atom $type)
         (if (is-var $head) false (is-member $head (And Or LikelierThan))))
      false))

(= (query-compound-needs-temp-rule? $term)
   (query-compound-needs-bundle? $term))

(= (compound-query-temp-stmt (: $_prf $type $_tv))
   (let*
      (((cons $_head $tail) $type)
        ($premises (map-flat query-temp-rule-premise $tail)))
	      (: query-compound
	         (Implication (cons Premises $premises) (cons Conclusions ($type)))
	         (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))

(= (default-query-assumption-tv $type $tv)
   (if (is-var $tv)
      (if (= $type (Implication (cons Premises $_premises) (cons Conclusions $_conclusions)))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))
         (STV 1.0 1.0))
      $tv))

(= (query-context-assumed-implication-rules $kbid $ctx $mvars $ctxprf $type $tv)
   (if (is-var $type) ()
      (if (= $type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (((compiled-premises $execs $proofs $atv)
                 (once (lower-source-premises $kbid $ctx $mvars $premises $conclusions)))
              ($shape-kb ($kbid $ctx $mvars))
              ($a (execs-goal-type $execs))
              ($b (seq2expr $conclusions)))
            (collapse
               (compile-implication-forward-rules $shape-kb $shape-kb $ctxprf $tv $a $b $execs $proofs $atv)))
         ())))

(= (query-context-premise-assumption-adds $kbid $ctx $mvars $ctxprf $type $tv)
   (append
      ((() |- ((: ($kbid $ctx $mvars) $ctxprf $type $tv))))
      (query-context-assumed-implication-rules $kbid $ctx $mvars $ctxprf $type $tv)))

(= (query-context-premise-adds-step $kbid $ctx $mvars ($idx $adds) $premise)
   (let $ctxprf (if (== $idx 0) (ctx proof $ctx) (ctx proof $ctx $idx))
      (if (= $premise (CPU $_fun $_args $_res))
         ($idx $adds)
         (if (= $premise (: $_kb $_prf $type $tv))
            ((+ $idx 1)
	               (append $adds
	                  (query-context-premise-assumption-adds $kbid $ctx $mvars $ctxprf $type
	                     (default-query-assumption-tv $type $tv))))
            ($idx $adds)))))

(= (query-context-premise-adds $kbid $ctx $mvars $premises)
   (let*
      ((($_idx $adds) (fold-flat (query-context-premise-adds-step $kbid $ctx $mvars) (0 ()) $premises)))
      $adds))

(= (mm2compileQuery-from-compiled $kb $stmt $compiled)
   (if (= $compiled (((() |- ($ccl)) $adds)))
      (compiled-query (internalize-proof-structure $ccl)
         (internalize-proof-structure-list (map-flat mm2stmt $adds)))
      (if
         (= $compiled
            ((((: ($kbid $_ctx $_vars) $prf $type $tv)) |- ((: ($kbid $_ctx $_vars) $prf1 $type1 $tv1)))
               $adds))
         (let*
            (($vars (extract-vars $type))
              ($mvars (if (== $vars ()) Nil $vars))
              ($ctx (nextctx))
              ($ctxatom (: ($kbid $ctx $mvars) (ctx proof $ctx) $type $tv))
              ($goal (: ($kbid $ctx $mvars) $prf1 $type1 $tv1))
              ($all-adds (union-atom ($ctxatom) (map-flat mm2stmt $adds))))
	            (compiled-query (internalize-proof-structure $goal)
	               (internalize-proof-structure-list $all-adds)))
	         (if
	            (= $compiled (($prms |- ($ccl)) $adds))
            (compiled-query (internalize-proof-structure $ccl)
               (internalize-proof-structure-list
                  (cons (mm2stmt ($prms |- ($ccl))) (map-flat mm2stmt $adds))))
            (notsupported mm2compileQuery $kb $stmt $compiled)))))

(= (mm2compileQuery $kb $stmt)
   (case $stmt (
      ((: $prf $type $tv)
         (if (query-compound-type? $type)
            (if (query-compound-needs-temp-rule? $type)
               (compiled-query
                  (internalize-proof-structure (: (kbctx $kb) $prf $type $tv))
                  (map-flat internalize-proof-structure
                     (collapse (mm2compile $kb (compound-query-temp-stmt $stmt)))))
               (mm2compileQuery-from-compiled $kb $stmt (compileQuery $kb $stmt)))
            (mm2compileQuery-from-compiled $kb $stmt (compileQuery $kb $stmt))))
      ($_ (mm2compileQuery-from-compiled $kb $stmt (compileQuery $kb $stmt))))))

(= (mf $kb ($kb $t)) $t)

(= (internalize-proof-structure $term)
   (if (== $term ()) ()
      (if (is-var $term) $term
      (if (= $term (: $kb $prf $type $tv)) ($type $kb $prf $tv)
         (if (is-expr $term)
            (cons (internalize-proof-structure (car-atom $term))
               (internalize-proof-structure-list (cdr-atom $term)))
            $term)))))

(= (internalize-proof-structure-list $terms)
   (if (== $terms ()) ()
      (cons (internalize-proof-structure (car-atom $terms))
         (internalize-proof-structure-list (cdr-atom $terms)))))

(= (externalize-proof-structure $term)
   (if (== $term ()) ()
      (if (is-var $term) $term
      (if (= $term ($type $kb $prf $tv))
         (if (and (is-expr $kb) (= $kb ($kbid $ctx $vars))) (: ($kbid $ctx $vars) $prf $type $tv) $term)
         (if (is-expr $term)
            (cons (externalize-proof-structure (car-atom $term))
               (externalize-proof-structure-list (cdr-atom $term)))
            $term)))))

(= (externalize-proof-structure-list $terms)
   (if (== $terms ()) ()
      (cons (externalize-proof-structure (car-atom $terms))
         (externalize-proof-structure-list (cdr-atom $terms)))))

(= (pretty-prf-token $prf)
   (if (= $prf (mined_implication $premk $conck))
      (Implication (cons Premises ($premk)) (cons Conclusions ($conck)))
      $prf))

(= (pretty-prf $prf) (if (is-expr $prf) (map-nested2 pretty-prf-token $prf) $prf))

(= (lookup-mined-tv $premk $conck $fallback-tv)
   (let $m (collapse (once (match &kb ($itype ($kbid MAIN ()) (mined_implication $premk $conck) $itv) $itv)))
      (if (== $m ()) $fallback-tv (car-atom $m))))

(= (extract-mined-itv-from-args $args $fallback-tv)
   (if (= $args ($_prem (CPU CTVFormula ($_atv $itv) $_btv))) $itv
      (if (= $args (cons $h $t))
         (if (= $h (CPU CTVFormula ($_atv2 $itv) $_btv2)) $itv
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
         (: mined_implication ((pretty-prf-token (mined_implication $premk $conck)) $p) $type $ptv))
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
