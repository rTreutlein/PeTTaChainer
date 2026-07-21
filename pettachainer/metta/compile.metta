;; Compiler overview
;; -----------------
;; Statements enter through compile_ (stored facts and rules) or compileQuery
;; (temporary query goals). Source-level premises are lowered to executable
;; goals plus a combined TV and proof token. Adapter rules bridge compound or
;; computed source expressions to the simple fact shape consumed by the
;; chainer. mm2compile/mm2compileQuery then translate that external compiler
;; representation to the tuple layout used by the MORK runtime.

;; Allocate a distinct context for assumptions introduced while compiling an
;; implication query. Contexts must not be shared because their assumed facts
;; are query-local.
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

;; Replace variables which occur only in the antecedent with stable `exists`
;; markers. In an inverted rule those variables cannot be recovered from the
;; new premise, so leaving them as ordinary variables would make unrelated
;; witnesses unify.
(= (skolemize $rule $expra $exprb)
   (if (or (is-var $exprb) (is-var $expra)) $exprb
      (let*
         (($avars (list_to_set (extract-vars $expra)))
           ($bvars (list_to_set (extract-vars $exprb)))
           ($onlyb (\== $bvars $avars))
           ($substitute (|-> (($idx $atom) $elem) (let $elem (exists $rule $idx $avars) ((+ 1 $idx) $atom))))
           (($_ $res) (sealed $onlyb (fold-flat $substitute (0 $exprb) $onlyb))))
         $res)))

(= (remove-index 0 (cons $_head $tail)) $tail)
(= (remove-index $idx (cons $head $tail)) (cons $head (remove-index (- $idx 1) $tail)))
(= (remove-index $_idx ()) ())

(= (seq2expr (cons $head $tail)) (if (== $tail ()) $head (cons And (cons $head $tail))))

;; A projection from a compound connective can depend on the other children as
;; evidence. Preserve all their proof identities so later overlap checks see
;; the complete dependency set, while avoiding a redundant conjunction node
;; for the one-proof case.
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
      (premise-bundle $execs $tv $proof-token)))

;; Emit projection adapters recursively for every child of a configured
;; compound output. The strong projection uses the other children as evidence;
;; And additionally exposes a weak marginal projection so independently queried
;; conjuncts can later be pooled back to their common source.
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
      (if (== $head And)
         (((: $kb $prf $type $tvin) (CPU AndMarginalProjection ($tvin) $tvout)) |-
            ((: $kb (marginal-proj $idx $prf) $elem $tvout)))
         (empty))
      (compile-outputs (: $kb $childprf $elem $childtv))
      (compile-output-children $kb $type $head (+ $idx 1) $rest))))

(= (compile-outputs (: $kb $NNprf (@ $type (cons $head $tail)) $NNtv))
   (if (and (compound-source? $type) (= (configured-compound-output-mode $head) ProjectAll))
      (compile-output-children $kb $type $head 0 $tail)
      (empty)))

;; CPU goals normally constrain values and therefore contribute unit evidence.
;; These formulas instead compute a TV which must participate in the enclosing
;; premise TV. Aggregates opt into that behavior through their explicit tv-mode.
(= (cpu-premise-tv-formula $f)
   (is-member $f (() NotFormula DistGreaterThanFormula DistGreaterThanDistFormula)))

(= (aggregate-args-tv-mode $args)
   (if (= $args ($_kb $_pattern $_extractor $_init $_fun $_finish $tv-mode)) $tv-mode
      (if (= $args ($_gkb $_gpattern $_group $_gextractor $_ginit $_gfun $_gfinish $gtv-mode)) $gtv-mode
         unit-stv)))

(= (cpu-premise-tv $f $args $res)
   (if (is-member $f (FoldAllCompiled GroupedFoldAllCompiled))
      (if (== (aggregate-args-tv-mode $args) result-tv) $res (STV 1.0 1.0))
      (if (cpu-premise-tv-formula $f) $res (STV 1.0 1.0))))

(= (source-premise-kb $kb $ctx $vars)
   (if (or (is-var $ctx) (is-var $vars)) (kbctx $kb) ($kb $ctx $vars)))

;; Normalize one source premise to the compiler's common bundle:
;;   premise-bundle(executable goals, evidence TV, proof token).
;; Keeping this boundary uniform lets compound, computed, and ordinary fact
;; premises be combined by the same folds below.
(= (leaf-source-bundle $kb $ctx $vars $elem)
   (let $prem-kb (source-premise-kb $kb $ctx $vars)
      (if (is-var $elem)
         (premise-bundle ((: $prem-kb $prf $elem $tv)) $tv $prf)
         (if (= $elem (CPU $f $args $res))
         (premise-bundle ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu)
         (premise-bundle ((: $prem-kb $prf $elem $tv)) $tv $prf)))))

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

;; Lower a connective whose configured premise mode is All. Every child must
;; succeed, child TVs are folded with <Head>Formula, and the proof token records
;; the conjunction of the child proofs. This is the general conjunction-
;; introduction mechanism for And premises; it is connective-generic so the
;; same machinery also serves other All-mode connectives.
(= (compound-all-premise-bundle $kb $ctx $vars $head $tail)
   (let*
      (($prem-kb (if (or (is-var $ctx) (is-var $vars)) (kbctx $kb) ($kb $ctx $vars)))
        ((cons (@ $fst (prem $fstgoal $fstelem $fsttv $fstprf)) $rst) (map-flat (in_map $prem-kb) $tail))
        ($init (($fstgoal) (: $prem-kb ($fstprf) ($fstelem) $fsttv)))
        (($resNNprms (: $res-kb $cclprf $ccltype $ccltv))
           (fold-flat (in_fold (atom_concat $head Formula)) $init $rst))
        (($execs $rcclprf $rccltype) ((reverse $resNNprms) (reverse $cclprf) (reverse $ccltype)))
        ($proof-token (if (= $rcclprf (cons $proof ())) $proof (cons conjunction $rcclprf))))
      (premise-bundle $execs $ccltv $proof-token)))

;; Lower one alternative of an Any-mode connective. Only one child is evidence,
;; so the proof is labelled as an introduction of the enclosing connective
;; rather than as a conjunction of all children.
(= (compound-any-premise-child-bundle $kb $ctx $vars $head $elem)
   (let*
      (($prem-kb (if (or (is-var $ctx) (is-var $vars)) (kbctx $kb) ($kb $ctx $vars)))
        ((prem $goal $_elem $tv $proof) (in_map $prem-kb $elem)))
      (premise-bundle ($goal) $tv ((atom_concat $head introduction) $proof))))

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

;; Compound lowering is deliberately configuration-driven. Merely being an
;; expression is insufficient: ordinary predicates such as (Friend a b) must
;; remain fact lookups and must not be interpreted as logical connectives.
(= (compound-source? $type)
   (if (is-expr $type)
      (let $head (car-atom $type)
         (and (not (is-var $head)) (compound-connective? $head)))
      false))

;; Query compounds need recursive lowering because a child may itself be a
;; compound or a source-level computation. A plain predicate child stays a leaf
;; lookup so it can use the normal chainer indexes.
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

;; Accumulate a direct compound-query rule in source order. Appending both goals
;; and proofs is intentional: the returned `(conjunction ...)` proof mirrors the
;; order written by the caller, while each TV fold consumes the same ordering.
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
        ($rcclprf $proofs)
        ($proof-token (if (= $rcclprf (cons $proof ())) $proof (cons conjunction $rcclprf))))
      (premise-bundle $execs $ccltv $proof-token)))

;; A direct bundle is required when normal plain adapters cannot faithfully
;; express a child: nested compounds and computations must be lowered inside
;; the query rule rather than looked up as already materialized facts.
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

;; Three-or-more-child compound queries are also lowered directly. The ordinary
;; adapter path was designed around binary rule shapes; forcing an n-ary query
;; through it can lose the complete ordered proof bundle. This is the explicit
;; specialization which makes `(And A B C ...)` synthesize one query-local
;; conjunction-introduction rule with proof `(conjunction a b c ...)`.
(= (compound-nary-query? $items)
   (case $items (
      ((cons $_a (cons $_b (cons $_c $_rest))) true)
      ($_ false))))

(= (query-compound-needs-bundle? $term)
   (if (is-expr $term)
      (let $items (cdr-atom $term)
         (or (compound-nary-query? $items) (compound-direct-query-bundle? $items)))
      false))

;; An open proof variable should be replaced by the generated bundle itself.
;; A named/structured query proof is instead retained as an outer provenance
;; label around that bundle.
(= (query-compound-proof-token $prf $proof-token)
   (if (is-var $prf) $proof-token ($prf $proof-token)))

;; Build reusable adapters for source expressions found in stored rules. Each
;; adapter derives the requested compound from its lowered children. Recursing
;; on a different executable type ensures any intermediate source syntax also
;; receives an adapter, without regenerating the identical rule.
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

;; Query adapters differ from stored-rule adapters in three places:
;; 1. Not is exposed as an explicit negated proof;
;; 2. complex/n-ary compounds get one query-local direct bundle; and
;; 3. other computed source forms are lowered and bridged only when their
;;    executable goal shape differs from the requested source expression.
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
               (($execs |- ((: $kb (query-compound-proof-token $prf $proof-token) $type $result-tv)))))
            (compile-adapter-chain plain (: $kb $prf $type $tv)))
         (let*
            (((premise-bundle $execs $result-tv $proof-token)
                 (once (lower-source-premise $kb $ctx $vars $type)))
              ($exec-type (execs-goal-type $execs)))
            (if (and (not (is-var $type)) (not (== $exec-type $type)))
               (superpose (($execs |- ((: $kb ($prf $proof-token) $type $result-tv)))
                           (compile-adapter-chain plain (: $kb $prfa $exec-type $atv))))
               (empty))))))

;; Lower the supported source-language premise forms to executable chainer/CPU
;; goals. This function owns the semantic translation (including which TV and
;; proof token a computation contributes); callers only combine its bundles.
(= (lower-source-premise-non-open $kb $ctx $vars $premise)
   (if (compound-source? $premise)
      (let (cons $head $tail) $premise (compound-premise-bundle $kb $ctx $vars $head $tail))
      (case $premise (
           ((Implication (cons Premises $_premises) (cons Conclusions $_conclusions))
              (leaf-source-bundle $kb $ctx $vars $premise))
           ((Compute $f $args -> $res)
              (premise-bundle ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu))
           ((Compute $f $args $res)
              (premise-bundle ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu))
           ((MapDist $fun $a $value -> $out)
              (premise-bundle
                 ((: ($kb $ctx $vars) $prfa $a $tv_a) (CPU DistMapFormula ($fun $value) $out))
                 (STV 1.0 1.0)
                 $prfa))
           ((Map2Dist $fun $a $valuea $b $valueb -> $out)
              (premise-bundle
                 ((: ($kb $ctx $vars) $prfa $a $tv_a) (: ($kb $ctx $vars) $prfb $b $tv_b)
                    (CPU DistMap2Formula (quote ($fun $valuea $valueb)) $out))
                 (STV 1.0 1.0)
                 (conjunction $prfa $prfb)))
           ((AverageDist $pattern $value -> $out)
              (premise-bundle
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
              (premise-bundle
                 ((CPU FoldAllCompiled ($kb $pattern extract-tv $init $fun identity result-tv) $out))
                 (STV 1.0 1.0)
                 cpu))
           ((FoldAll $pattern $value $init $fun -> $out)
              (premise-bundle
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
                 (premise-bundle ((: $prem-kb $prfa $a $tv_a) (CPU NotFormula ($tv_a) $tv)) $tv (negated $prfa))))
           (($rel $a $b)
              (if (is-member $rel (GreaterThan >))
                 (if (is-var $b) (premise-bundle ((CPU DistGreaterThanDistFormula ($a $b) $tv)) $tv cpu)
                    (premise-bundle ((CPU DistGreaterThanFormula ($a $b) $tv)) $tv cpu))
                 (premise-bundle ((: ($kb $ctx $vars) $prf ($rel $a $b) $tv)) $tv $prf)))
           ($other (premise-bundle ((: ($kb $ctx $vars) $prf $other $tv)) $tv $prf))))))

;; Variable-headed expressions require the generic fact path. Dispatching them
;; through the structural cases above would mistake an unknown predicate head
;; for compiler syntax and could specialize the query incorrectly.
(= (lower-source-premise $kb $ctx $vars $premise)
   (if (and (is-expr $premise) (is-var (car-atom $premise)))
      (if (== (cdr-atom $premise) ())
         (leaf-source-bundle $kb $ctx $vars (car-atom $premise))
         (leaf-source-bundle $kb $ctx $vars $premise))
      (lower-source-premise-non-open $kb $ctx $vars $premise)))

;; Combine premise bundles left-to-right. AndFormula is inserted only between
;; non-empty bundles so the first premise supplies the initial TV and no fake
;; unit-evidence proof is introduced.
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

;; A premise-local variable denotes existential evidence, not a variable which
;; should escape into the compiled rule. Collapse all matching witnesses with
;; OrFormula; retain group variables when the premise is correlated with the
;; conclusion or another premise so each binding gets its own aggregate.
(= (fold-existential-premise-bundle $kb $ctx $vars $premise $group-vars)
   (let $prem-kb (source-premise-kb $kb $ctx $vars)
      (if (== $group-vars ())
         (premise-bundle
            ((CPU FoldAllCompiled
                 ($prem-kb $premise extract-tv (STV 0.0 1.0) OrFormula identity result-tv)
                 $fold-tv))
            $fold-tv
            cpu)
         (premise-bundle
            ((CPU GroupedFoldAllCompiled
                 ($prem-kb $premise $group-vars extract-tv (STV 0.0 1.0) OrFormula identity result-tv)
                 $fold-tv))
            $fold-tv
            cpu))))

;; Only ordinary fact-like premises are safe to rewrite as existential folds.
;; Compiler forms and computations have their own lowering and binding rules;
;; folding them as database patterns would change their meaning.
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

;; Partition before lowering so existential-only premises run after normal
;; premises. This lets variables shared with other premises be bound first and
;; correctly distinguishes genuinely local variables from correlated ones.
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

;; Premises of an implication *query* are temporary assumptions. A positive
;; `(Not A)` assumption is represented by an A-shaped contextual fact with
;; strength zero, allowing ordinary fact matching while preserving its logical
;; truth through the bundle TV.
(= (lower-query-assumption-premise $kb $ctx $vars $premise)
   (if (and (is-expr $premise) (not (is-var (car-atom $premise))))
      (let $head (car-atom $premise)
         (if (== $head Implication)
            (leaf-source-bundle $kb $ctx $vars $premise)
            (if (== $head Not)
               (let $prem-kb (source-premise-kb $kb $ctx $vars)
                  (premise-bundle ((: $prem-kb $prf (car-atom (cdr-atom $premise)) (STV 0.0 1.0))) (STV 1.0 1.0) $prf))
               (lower-source-premise $kb $ctx $vars $premise))))
      (lower-source-premise $kb $ctx $vars $premise)))

(= (lower-query-assumption-premises-step $kb $ctx $vars $acc $premise)
   (append-premise-bundle $acc (lower-query-assumption-premise $kb $ctx $vars $premise)))

(= (lower-query-assumption-premises $kb $ctx $vars $premises)
   (fold-flat (lower-query-assumption-premises-step $kb $ctx $vars)
      (compiled-premises () () (STV 1.0 1.0))
      $premises))

;; Construct the refuting side of a total-implication query: the first premise
;; is assumed false and all remaining premises true. This is the counterexample
;; condition used to compute the negative component of the implication CTV.
(= (lower-query-assumption-premise-false $kb $ctx $vars $premise)
   (if (and (is-expr $premise) (not (is-var (car-atom $premise))))
      (let $head (car-atom $premise)
         (if (== $head Not)
            (let $prem-kb (source-premise-kb $kb $ctx $vars)
               (premise-bundle ((: $prem-kb $prf (car-atom (cdr-atom $premise)) (STV 1.0 1.0))) (STV 0.0 1.0) (negated $prf)))
            (if (== $head Implication)
               (premise-bundle
                  ((: ($kb $ctx $vars) $prf $premise (CTV (STV 0.0 1.0) (STV 1.0 1.0))))
                  (CTV (STV 0.0 1.0) (STV 1.0 1.0))
                  $prf)
               (premise-bundle ((: ($kb $ctx $vars) $prf $premise (STV 0.0 1.0))) (STV 0.0 1.0) $prf))))
      (premise-bundle ((: ($kb $ctx $vars) $prf $premise (STV 0.0 1.0))) (STV 0.0 1.0) $prf)))

(= (lower-query-assumption-premises-negative $kb $ctx $vars ())
   (compiled-premises () () (STV 0.0 1.0)))
(= (lower-query-assumption-premises-negative $kb $ctx $vars (cons $premise $rest))
   (fold-flat (lower-query-assumption-premises-step $kb $ctx $vars)
      (append-premise-bundle
         (compiled-premises () () (STV 1.0 1.0))
         (lower-query-assumption-premise-false $kb $ctx $vars $premise))
      $rest))

(= (bidirectional-implication-type? $Type)
   (if (is-expr $Type)
      (let $head (car-atom $Type)
         (and (not (is-var $head)) (bidirectional-implication-form? $head)))
      false))

(= (compile-query-adds (: $kb $prf $type $tv))
   (collapse (compile-adapter-chain query (: $kb $prf $type $tv))))


;; Normalize a public KB id to its default runtime shape. Query contexts already
;; arrive shaped as `(kbid ctx vars)` and must pass through unchanged.
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

(= (disable-inversion-proof-id? $prf) (= $prf (no_inverse $_)))

;; Preserve the dependency shape of a rule application. Zero-premise rules are
;; CPU-derived, one premise needs no wrapper, and multiple premises must retain
;; an explicit conjunction for overlap detection and proof rendering.
(= (implication-proof-token $proofs)
   (case $proofs (
      (() cpu)
      ((cons $proof ()) $proof)
      ((cons $proof $rest)
         (cons conjunction (cons $proof $rest))))))

;; Rules stored with an STV need a CTV derived from antecedent/consequent base
;; rates before modus ponens can use them. An explicit CTV already carries both
;; directions and therefore needs no runtime base-rate scans.
(= (compile-implication-ctv-execs $_kb $_a $_b (CTV $pos $neg))
   (implication-ctv-execs () (CTV $pos $neg)))
(= (compile-implication-ctv-execs $kb $a $b (STV $s $c))
   (let*
      (($a1 (copy_term (map-nested2 toQuery $a)))
        ($b1 (copy_term (map-nested2 toQuery $b))))
      (implication-ctv-execs
         ((base-rate-premise $kb $a1 $rule-atv)
          (base-rate-premise $kb $b1 $rule-btv)
          (CPU ImplicationCTVFormula ($rule-atv $rule-btv (STV $s $c)) $rule-ctv))
         $rule-ctv)))

;; A negated conclusion is stored as positive evidence for its inner expression
;; with a negated proof and transformed TV. Keeping the runtime type positive
;; lets it share the ordinary fact indexes.
(= (compile-implication-output $prf $proof-token $b $btv)
   (case $b (
      ((Not $inner)
         (compiled-output
            ((CPU NotFormula ($btv) $out-tv))
            (negated ($prf $proof-token))
            $inner
            $out-tv))
      ($other
         (compiled-output () ($prf $proof-token) $other $btv)))))

;; Emit the forward rule plus the adapters needed on both sides. The shape KB is
;; context-sensitive for assumption queries, while adapter-kb controls where
;; reusable source-shape adapters are indexed.
(= (compile-implication-forward-rules $kb $shape-kb $adapter-kb $prf $tv $a $b $execs $proofs $atv)
   (superpose (
      (once
         (let*
            (($proof-token (implication-proof-token $proofs))
              ((implication-ctv-execs $ctv-execs $rule-ctv)
                 (compile-implication-ctv-execs $kb $a $b $tv))
              ((compiled-output $out-execs $out-prf $out-type $out-tv)
                 (compile-implication-output $prf $proof-token $b $btv))
              ($allargs
                 (append $execs
                    (append $ctv-execs
                       (append
                          ((CPU CTVModusPonensFormula ($atv $rule-ctv) $btv))
                          $out-execs)))))
            ($allargs |- ((: $shape-kb $out-prf $out-type $out-tv)))))
      (if (is-var $b) (empty) (compile-outputs (: $adapter-kb ($prf $prfb) $b $btv2)))
      (if (is-var $a) (empty) (compile-adapter-chain plain (: $adapter-kb $prfa $a $atv))))))

(= (rule-evidence-base-name $prf)
   (if (= $prf (bi-forward $fwd)) $fwd
      (if (= $prf (bi-backward $bwd)) $bwd
         (if (= $prf (no_inverse $inner)) $inner
            $prf))))

(= (rule-evidence-registered? $kbid $name)
   (not (== (collapse (once (match &rule_evidence_names ($kbid $name) true))) ())))

(= (register-rule-evidence! $kb $prf)
   (let $name (rule-evidence-base-name $prf)
      (if (is-expr $name) ()
         (if (logic-rule? $name) ()
            (if (rule-evidence-registered? $kb $name) ()
               (add-atom &rule_evidence_names ($kb $name)))))))

;; Estimate the base rate required to reinterpret an STV rule as a CTV. Open
;; inheritance antecedents use universe-aware weighted evidence; ordinary
;; patterns use the generic evidence accumulator.
(= (base-rate-premise-default $kb $pattern $brtv)
   (if (and (= $pattern (Inheritance $x $_concept)) (is-var $x))
      (CPU FoldAllCompiled
         ($kb $pattern (extract-inheritance-tv $kb $pattern) (BaseRateEvidence 0.0 0.0)
            WeightedBaseRateAcc (weighted-base-rate-in-universe $kb) result-tv)
         $brtv)
      (CPU FoldAllCompiled
         ($kb $pattern extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv)
         $brtv)))

;; A concrete inheritance target may have a configured/dynamic concept prior.
;; Seed its fold with that prior so sparse observations revise the prior instead
;; of silently behaving like an uninformative generic predicate.
(= (base-rate-premise $kb $pattern $brtv)
   (if (and (= $pattern (Inheritance $x $subj)) (and (is-var $x) (not (is-var $subj))))
      (CPU FoldAllCompiled
         ($kb $pattern (extract-inheritance-tv $kb $pattern)
            (BaseRateEvidenceWithPrior (ConceptNodePriorRuntime $kb $subj) (BaseRateEvidence 0.0 0.0))
            WeightedBaseRateWithPriorAcc (weighted-base-rate-with-prior-in-universe $kb) result-tv)
         $brtv)
      (base-rate-premise-default $kb $pattern $brtv)))

;; Compile the backward use of an implication by deriving its CTV, applying TV
;; inversion, and then using the observed consequent as modus-ponens evidence.
;; This is emitted only when the main compiler has proved the antecedent is
;; invertible (no CPU goals and no explicit no_inverse marker).
(= (inverse-implication $kb $prf $a $b $itv)
   (let*
      (($a1 (copy_term (map-nested2 toQuery $a)))
        ($b1 (copy_term (map-nested2 toQuery $b))))
      (((: ($kb $ctx $vars) $prfb_wit $b $btv_wit)
            (base-rate-premise $kb $a1 $atv)
            (base-rate-premise $kb $b1 $btv)
            (CPU ImplicationCTVFormula ($atv $btv $itv) $rule-ctv)
            (CPU CTVInversionFormula ($atv $btv $rule-ctv) $iitv)
            (CPU CTVModusPonensFormula ($btv_wit $iitv) $mp-tv))
         |-
         ((: ($kb $ctx $vars) ((inverted $prf with cpu cpu) $prfb_wit) $a $mp-tv)))))

;; Concrete Inheritance assertions also act as implication-like rules over
;; members. Materializing these views once at compile time lets ordinary rule
;; indexing and inference handle inheritance without a separate chainer path.
(= (concrete-inheritance-link? $subj $concept)
   (and (not (is-var $subj)) (not (is-var $concept))))

(= (compile-derived-inheritance-views $kb $prf $subj $concept $tv)
   (superpose
      ((compile_ $kb
          (: (inheritance-implication $prf)
             (Implication
                (Premises (Inheritance $x $subj))
                (Conclusions (Inheritance $x $concept)))
             $tv))
       (compile_ $kb
          (: (no_inverse (member-inheritance-implication $prf))
             (Implication
                (Premises (Member $x $subj))
                (Conclusions (Member $x $concept)))
             (CTV $tv (STV 0.0 1.0)))))))

;; A total-implication context represents a hypothetical instance of the
;; queried subject. Top-level Inheritance premises about a rule's conclusion
;; subject transfer to that instance; every other premise is subject-specific
;; auxiliary evidence and must be specialized against MAIN. Examples:
;;
;;   friendSmokingRule: both premises are auxiliary to conclusion subject $y.
;;   lighterHeatsPlastic: `Inheritance $x madeOfPlastic` transfers, while
;;                        `Operation $x opLighter` is auxiliary.
(= (inheritance-context-premise? $premise $subj)
   (if (= $premise (Inheritance $premise-subj $_concept))
      (== $premise-subj $subj)
      false))

(= (inheritance-lift-auxiliary-premises () $_subj) ())
(= (inheritance-lift-auxiliary-premises (cons $premise $rest) $subj)
   (if (inheritance-context-premise? $premise $subj)
      (inheritance-lift-auxiliary-premises $rest $subj)
      (cons $premise (inheritance-lift-auxiliary-premises $rest $subj))))

;; Pair a grounded rule instance with its original template. Contextual
;; Inheritance premises keep their grounded concept but replace the concrete
;; subject with the query's hypothetical instance; auxiliary premises remain
;; grounded MAIN facts.
(= (inheritance-lift-parts () () $_source-subj $_instance)
   (lift-parts () ()))
(= (inheritance-lift-parts
      (cons $ground-premise $ground-rest)
      (cons $source-premise $source-rest)
      $source-subj $instance)
   (let (lift-parts $contextual $auxiliary)
      (inheritance-lift-parts $ground-rest $source-rest $source-subj $instance)
      (if (inheritance-context-premise? $source-premise $source-subj)
         (let (Inheritance $_ground-subj $ground-concept) $ground-premise
            (lift-parts
               (cons (Inheritance $instance $ground-concept) $contextual)
               $auxiliary))
         (lift-parts $contextual (cons $ground-premise $auxiliary)))))

;; Compile a specialized relational rule into one fixed query context. The
;; rule's positive STV is already its conditional estimate; unlike an observed
;; Inheritance link it does not need to be inferred again from population base
;; rates. Explicit CTV rules retain both branches.
(= (inheritance-lift-ctv (CTV $pos $neg)) (CTV $pos $neg))
(= (inheritance-lift-ctv (STV $s $c))
   (CTV (STV $s $c) (STV 0.0 1.0)))

(= (compile-inheritance-lift-instance $kb $lift-kb
      (: $prf
         (Implication (cons Premises $ground-premises)
            (Conclusions (Inheritance $ground-subj $ground-concept)))
         $tv)
      (: $_source-prf
         (Implication (cons Premises $source-premises)
            (Conclusions (Inheritance $source-subj $_source-concept)))
         $_source-tv))
   (let*
      ((($kb $ctx $vars) $lift-kb)
       ((lift-parts $contextual-premises $auxiliary-premises)
          (inheritance-lift-parts
             $ground-premises $source-premises $source-subj $instance))
       ($lift-premises
          (if (== $contextual-premises ())
             ((Inheritance $instance $ground-subj))
             $contextual-premises))
       ((compiled-premises $main-execs $main-proofs $main-atv)
          (once (lower-source-premises $kb MAIN Nil $auxiliary-premises
             ((Inheritance $ground-subj $ground-concept)))))
       ((compiled-premises $context-execs $context-proofs $context-atv)
          (once (lower-source-premises $kb $ctx $vars $lift-premises
             ((Inheritance $instance $ground-concept)))))
       ($source-proof (implication-proof-token $main-proofs))
       ($context-proof (implication-proof-token $context-proofs))
       ($all-evidence
          (CPU AndFormula ($main-atv $context-atv) $all-atv))
       ($rule-ctv (inheritance-lift-ctv $tv))
       ($modus-ponens
          (CPU CTVModusPonensFormula ($all-atv $rule-ctv) $out-tv))
       ($out
          (: $lift-kb
             ((inheritance-rule-lift $prf) $source-proof $context-proof)
             (Inheritance $instance $ground-concept) $out-tv)))
      ((append $main-execs
          (append $context-execs ($all-evidence $modus-ponens))) |- ($out))))

;; A grounded lift is one specialization job. The common specialization engine
;; below handles template indexing and late facts for both ordinary compiler
;; specialization and these Inheritance views.
(= (emit-specialization $kb
      (inheritance-lift-specialization $stmt $source-stmt))
   (let $stored
      (collapse
         (once
            (match &inheritance_lift_instance ($kb $candidate $_source)
               (if (=alpha $candidate $stmt) true (empty)))))
      (if (not (== $stored ())) (empty)
         (let*
            (($stmt-copy (copy_term $stmt))
             ($source-copy (copy_term $source-stmt))
             ($_instance
                (add-atom &inheritance_lift_instance
                   ($kb $stmt-copy $source-copy))))
            (empty)))))

(= (compile-inheritance-lifts-for-context $kb $lift-kb)
   (match &inheritance_lift_instance ($kb $ground-stmt $source-stmt)
      (let* (($ground-copy (copy_term $ground-stmt))
             ($source-copy (copy_term $source-stmt)))
         (compile-inheritance-lift-instance
            $kb $lift-kb $ground-copy $source-copy))))

;; On rule addition, emit every instance already supported by stored facts and
;; retain the template for facts added later. No open lifted rule enters the KB.
(= (compile-inheritance-rule-lifts $kb $stmt $premises $conclusions)
   (if (= $conclusions ((Inheritance $subj $_concept)))
      (let $auxiliary (inheritance-lift-auxiliary-premises $premises $subj)
         (if (== $auxiliary ()) (empty)
            (let*
               (($ground-copy (copy_term $stmt))
                ($source-copy (copy_term $stmt))
                ((: $_prf $ground-type $_tv) $ground-copy)
                ($ground-premises (impl-premises $ground-type))
                ((Inheritance $ground-subj $_ground-concept)
                   (car-atom (impl-conclusions $ground-type)))
                ($ground-auxiliary
                   (inheritance-lift-auxiliary-premises
                      $ground-premises $ground-subj))
                ($job
                   (inheritance-lift-specialization
                      $ground-copy $source-copy)))
               (specialize-rule-add $kb $ground-auxiliary $job))))
      (empty)))

;; --- Rule specialization against structural facts -------------------------
;;
;; A premise is a specialization *trigger* when its head is a registered
;; specializing predicate and it still contains variables to ground (so a
;; ground (Symmetric Friend) premise is never re-triggered). When a rule has
;; trigger premises we do not emit the generic variable-headed rule; instead we
;; store the rule as a template and emit one ground instance per matching fact.
;; The instance keeps the trigger premise (now ground), so its truth value is
;; threaded exactly as the uncompiled rule would, and its conclusion head is
;; concrete -- giving precise indexing instead of the `any` wildcard.

(= (specialization-trigger? $premise)
   (if (is-expr $premise)
      (let $head (car-atom $premise)
         (if (is-var $head) false
            (and (specializing-predicate? $head)
               (not (== (extract-vars $premise) ())))))
      false))

(= (rule-trigger-premises ()) ())
(= (rule-trigger-premises (cons $prem $rest))
   (if (specialization-trigger? $prem)
      (cons $prem (rule-trigger-premises $rest))
      (rule-trigger-premises $rest)))

(= (impl-premises (Implication (cons Premises $premises) (cons Conclusions $_conclusions))) $premises)
(= (impl-conclusions (Implication (cons Premises $_premises) (cons Conclusions $conclusions))) $conclusions)

(= (fact-head $type) (if (is-expr $type) (car-atom $type) $type))

;; Both structural rules and Inheritance lifts use the same indexed template
;; store. A job carries the emitter to run after its trigger list is grounded.
;; Keeping the triggers with the job lets a newly added fact use this one path
;; regardless of which compiler feature requested specialization.
(= (specialization-template-registered? $kb $head $job)
   (not (== (collapse
      (match &spec_template ($kb $head $_triggers $stored-job)
         (if (=alpha $stored-job $job) true (empty)))) ())))

(= (register-specialization-templates! $_kb () $_triggers $_job) ())
(= (register-specialization-templates! $kb (cons $trigger $rest) $triggers $job)
   (let $head (fact-head $trigger)
      (let $_register
         (if (specialization-template-registered? $kb $head $job) ()
            (let ($triggers-copy $job-copy) (copy_term ($triggers $job))
               (add-atom &spec_template
                  ($kb $head $triggers-copy $job-copy))))
         (register-specialization-templates! $kb $rest $triggers $job))))

;; Idempotency is per grounded statement, not merely per rule type: distinct
;; proof ids or TVs are independent evidence even when their types coincide.
;; The rule-add and fact-add paths may discover the same statement, so retain
;; the full statement as the stable deduplication key.
(= (spec-done? $kb $gstmt)
   (not (== (collapse (match &spec_done ($kb $stored)
                         (if (=alpha $stored $gstmt) true (empty)))) ())))

(= (mark-spec-done! $kb $gstmt)
   (let $copy (copy_term $gstmt)
      (add-atom &spec_done ($kb $copy))))

;; Compiler backends may contribute additional fact providers for structural
;; specialization. PeTTaChainer's default provider reads its native KB; MM2
;; adds a provider that reads compiler metadata directly from MORK.
(= (compiler-specialization-fact $kb $trigger)
   (match &kb ($candidate ($kb $_ctx $_vars) $_prf $_tv)
      (let $trigger $candidate $candidate)))

;; Bind the trigger variables by matching each remaining trigger against the
;; compiler-visible fact providers; $body shares those variables, so it comes
;; out ground.
(= (ground-triggers $_kb () $body) $body)
(= (ground-triggers $kb (cons $trigger $rest) $body)
   (let $candidate (compiler-specialization-fact $kb $trigger)
      (let $trigger $candidate
         (ground-triggers $kb $rest $body))))

(= (emit-specialization $kb
      (compile-specialization (: $gprf $gtype $gtv)))
   (let $gstmt (: $gprf $gtype $gtv)
      (if (spec-done? $kb $gstmt) (empty)
         (let $_ (mark-spec-done! $kb $gstmt)
            (compile_ $kb $gstmt)))))

;; Rule-add: retain the job for later facts and also ground it against facts
;; already in the KB.
(= (specialize-rule-add $kb $triggers $job)
   (let $_register
      (register-specialization-templates! $kb $triggers $triggers $job)
      (emit-specialization $kb (ground-triggers $kb $triggers $job))))

;; Fact-add: the new fact is not in &kb yet, so pin the trigger it satisfies
;; directly in each compatible position, then resolve the remaining triggers
;; against the store.
(= (ground-specialization-with-fact $_kb $_fact () $_before $_job) (empty))
(= (ground-specialization-with-fact $kb $fact
      (cons $trigger $rest) $before $job)
   (superpose
      ((let $_ (let $trigger $fact ok)
          (ground-triggers $kb (append $before $rest) $job))
       (ground-specialization-with-fact $kb $fact $rest
          (append $before ($trigger)) $job))))

(= (compile-specialization-fact-triggers $kb $type)
   (let $head (fact-head $type)
      (match &spec_template ($kb $head $stored-triggers $stored-job)
         (let ($triggers $job) (copy_term ($stored-triggers $stored-job))
            (emit-specialization $kb
               (ground-specialization-with-fact
                  $kb $type $triggers () $job))))))

;; Retraction support for the unified specialization store. Templates and
;; grounded completion markers must disappear with their source statement;
;; otherwise a later fact can resurrect a removed rule, and a clean re-add can
;; be suppressed by stale idempotency state.
(= (specialization-statement-name $stmt)
   (case $stmt (((: $name $_type $_tv) $name) ($_other no-specialization-name))))

(= (specialization-job-name $job)
   (case $job (
      ((compile-specialization $stmt) (specialization-statement-name $stmt))
      ((inheritance-lift-specialization $_ground $source) (specialization-statement-name $source))
      ($_other no-specialization-name))))

(= (remove-specialization-state! $name)
   (let*
      (($_templates
          (collapse
             (match &spec_template ($kb $head $triggers $job)
                (if (== (specialization-job-name $job) $name)
                   (remove-atom &spec_template ($kb $head $triggers $job))
                   (empty)))))
       ($_done
          (collapse
             (match &spec_done ($kb $stmt)
                (if (== (specialization-statement-name $stmt) $name)
                   (remove-atom &spec_done ($kb $stmt))
                   (empty)))))
       ($_lifts
          (collapse
             (match &inheritance_lift_instance ($kb $stmt $source)
                (if (== (specialization-statement-name $source) $name)
                   (remove-atom &inheritance_lift_instance
                      ($kb $stmt $source))
                   (empty))))))
      ()))

;; Main statement compiler.
;;
;; Implications become forward rules, optional inverse rules, and adapters.
;; Bidirectional forms are split into two ordinary implications. Facts are
;; stored directly, with extra derived views for concrete Inheritance links and
;; projections for configured compound outputs. Structural specialization is
;; checked before generic implication compilation so variable-headed templates
;; never leak into the broad `any` index.
(= (compile_ $kb (@ $stmt (: $prf $Type $tv)))
   (if (is-var $Type) (empty)
      (if (= $Type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
       (let $triggers (rule-trigger-premises $premises)
        (if (not (== $triggers ()))
         (specialize-rule-add $kb $triggers
            (compile-specialization (: $prf $Type $tv)))
         (let*
            (($_evidence-reg (register-rule-evidence! $kb $prf))
             ((compiled-premises $execs $proofs $atv)
                (once (lower-source-premises $kb $ctx $vars $premises $conclusions)))
             ($shape-kb ($kb $ctx $vars))
             ($a (seq2expr $premises))
             ($b (seq2expr $conclusions))
             ($na (skolemize $prf $b $a))
             ;; Guard inversion on the *lowered* premises: a premise that lowers to a
             ;; CPU computation (FoldAll, Compute, ...) cannot be inverted. $a is the
             ;; clean antecedent expression for base-rate patterns and never carries a
             ;; CPU head, so the check must look at $execs, not $a.
             ($skip-inverse (or (disable-inversion-proof-id? $prf) (contains-cpu? (execs-goal-type $execs)))))
	            (superpose (
	                 (compile-implication-forward-rules $kb $shape-kb (kbctx $kb) $prf $tv $a $b $execs $proofs $atv)
	                 (if (not $skip-inverse) (inverse-implication $kb $prf $na $b $tv) (empty))
	                 (if (or $skip-inverse (is-var $na)) (empty)
	                    (compile-outputs (: ((inverted $prf $w $pa1 $pa2) $pb2) $na $natv)))
	                 (if (or $skip-inverse (is-var $b)) (empty) (compile-adapter-chain plain (: $pb2 $b $btv2)))
	                 (compile-inheritance-rule-lifts $kb (: $prf $Type $tv)
	                    $premises $conclusions))))))
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
               (if (= $Type (Member $obj $class))
                  (superpose ((() |- ((: $fact-kb $prf $Type $tv)))
                              (compile-specialization-fact-triggers $kb $Type)))
               (if (= $Type (Inheritance $subj $concept))
                  (superpose (
                     (() |- ((: $fact-kb $prf $Type $tv)))
                     (if (concrete-inheritance-link? $subj $concept)
                        (compile-derived-inheritance-views
                           $kb $prf $subj $concept $tv)
                        (empty))
                     (compile-specialization-fact-triggers $kb $Type)
                     (compile-outputs (: $fact-kb $prf $Type $tv))))
                  (superpose ((() |- ((: $fact-kb $prf $Type $tv)))
                              (compile-specialization-fact-triggers $kb $Type)
                              (compile-outputs (: $fact-kb $prf $Type $tv)))))))))))


(= (implication-query-known-tv-parts $tv)
   (if (is-var $tv)
      (implication-query-tv-parts $pos-tv $neg-tv (CTV $pos-tv $neg-tv))
      (if (= $tv (CTV $pos-tv $neg-tv))
         (implication-query-tv-parts $pos-tv $neg-tv $tv)
         (implication-query-tv-parts $tv $stv-neg-tv (CTV $tv $stv-neg-tv)))))

;; One side of a total-implication / bidirectional query: allocate a fresh
;; query context, lower the premises (negatively for the refuting side of a
;; total implication, positively otherwise), and collect the context + adapter
;; atoms the chainer needs to resolve this side's conclusion. Returns the ground
;; shape-kb, the fresh proof var (shared with the caller's goal and proof
;; token), the conclusion expression, and the side's adds.
(= (query-side $kb $mvars $negative? $premises $conclusion-side)
   (let*
      (($ctx (nextctx))
       ($shape-kb ($kb $ctx $mvars))
       ((compiled-premises $execs $_proofs $_atv)
          (once (if $negative?
                   (lower-query-assumption-premises-negative $kb $ctx $mvars $premises)
                   (lower-query-assumption-premises $kb $ctx $mvars $premises))))
       ($goal-expr (seq2expr $conclusion-side))
       ($adds
          (union-atom
             (query-context-premise-adds $kb $ctx $mvars $execs)
             (collapse (compile-adapter-chain query (: $shape-kb $prf $goal-expr $adapter-tv))))))
      (qside $shape-kb $prf $goal-expr $adds)))

;; The two sides of a total-implication query share one conclusion $b and differ
;; only in polarity. Returns the ground shape-kbs, $b, the fresh pos/neg proof
;; vars (used by the caller in its known goals and proof token), and all adds.
(= (query-pos-neg-scaffold $kb $mvars $premises $conclusions)
   (let*
      (((qside $pos-shape-kb $pos-prf $b $pos-adds)
          (query-side $kb $mvars false $premises $conclusions))
       ((qside $neg-shape-kb $neg-prf $_b $neg-adds)
          (query-side $kb $mvars true $premises $conclusions)))
      (query-scaffold $pos-shape-kb $neg-shape-kb $b $pos-prf $neg-prf
         (union-atom $pos-adds $neg-adds))))

(= (compile-inheritance-query $kb $subj $concept)
   (let*
      (;; Constrain the root proof so ordinary public Inheritance rules cannot
       ;; answer beside the total-implication producer. The wrapper is removed
       ;; when results are externalized; it is selection state, not evidence.
       ($goal (: (kbctx $kb) (inheritance-query-result $proof)
          (Inheritance $subj $concept) $tv))
       ($member-goal (: (kbctx $kb)
          (inheritance-query-result (member-inheritance-fold cpu))
          (Inheritance $subj $concept) $member-tv))
       ;; Build empirical samples through ordinary compiled Member queries. This
       ;; lets rule-derived memberships contribute while retaining their proof
       ;; identities for overlap and cycle checks before aggregation.
       ($member-sample-pattern
          (MemberInheritanceSample
             $member-obj $subj $concept $member-atv $member-btv))
       ($member-sample-goal
          (: (kbctx $kb)
             (member-inheritance-sample $member-aprf $member-bprf)
             $member-sample-pattern
             (STV 1.0 1.0)))
       ($member-sample-rule
          (((: (kbctx $kb) $member-aprf
                (Member $member-obj $subj) $member-atv)
            (: (kbctx $kb) $member-bprf
                (Member $member-obj $concept) $member-btv))
             |- ($member-sample-goal)))
       ($member-rule
          (((CPU FoldAllCompiled
                 ($kb
                    $member-sample-pattern
                    (extract-value $member-sample-pattern
                       (WeightedTv $member-atv $member-btv))
                    (BaseRateEvidence 0.0 0.0)
                    WeightedBaseRateAcc
                    (member-inheritance $kb)
                    result-tv)
                 $member-fold-tv)
            (CPU MemberInheritanceEvidenceFormula
               ($member-fold-tv) $member-tv))
             |- ($member-goal)))
       ($member-adds ($member-sample-rule $member-rule))
       ($premises ((Inheritance $x $subj)))
       ($conclusions ((Inheritance $x $concept)))
       ($mvars ($x))
       ((query-scaffold $pos-shape-kb $neg-shape-kb $b $pos-prf $neg-prf $all-adds)
          (query-pos-neg-scaffold $kb $mvars $premises $conclusions))
       ($lift-adds
          (union-atom
             (collapse (compile-inheritance-lifts-for-context $kb $pos-shape-kb))
             (collapse (compile-inheritance-lifts-for-context $kb $neg-shape-kb))))
       ($known-pos-goal (: $pos-shape-kb $pos-prf $b $induction-tv))
       ($known-neg-goal (: $neg-shape-kb $neg-prf $b $negative-tv))
       ($induction-goal (: (kbctx $kb) (inheritance-query-result
          (total-implication-frontier
             (inheritance-implication-fold (total-implication $pos-prf $neg-prf))))
          (Inheritance $subj $concept) $induction-tv))
       ($induction-rule (($known-pos-goal $known-neg-goal) |- ($induction-goal))))
      (((() |- ($goal))
         (union-atom $member-adds
            (union-atom $all-adds
               (union-atom $lift-adds ($induction-rule))))))))

;; Compile a public query into one goal rule plus temporary additions.
;; Implication queries require positive and refuting assumption contexts;
;; bidirectional queries require one context per direction. A concrete
;; Inheritance query accepts only the total-implication producer plus the
;; explicitly separate Member producer; ordinary direct proofs cannot answer
;; its constrained root goal.
;; Ordinary queries remain a direct known goal with only the adapters their
;; source syntax requires.
(= (compileQuery $kb (: $prf $Type $tv))
   (if (is-var $Type) ((() |- ((: (kbctx $kb) $prf $Type $tv))) ())
      (if (= $Type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (($vars (extract-vars $Type))
             ($mvars (if (== $vars ()) Nil $vars))
             ((query-scaffold $pos-shape-kb $neg-shape-kb $b $pos-prf $neg-prf $all-adds)
                (query-pos-neg-scaffold $kb $mvars $premises $conclusions))
             ((implication-query-tv-parts $known-pos-tv $known-neg-tv $known-tv)
                (implication-query-known-tv-parts $tv))
             ($known-pos-goal (: $pos-shape-kb $pos-prf $b $known-pos-tv))
             ($known-neg-goal (: $neg-shape-kb $neg-prf $b $known-neg-tv))
             ;; The two contextual answers are alternative evaluations of one
             ;; conditional, not independent conjuncts. Mark their combining
             ;; frontier so shared source facts remain admissible.
             ($known-goal (: (kbctx $kb)
                (total-implication-frontier
                   (total-implication $pos-prf $neg-prf))
                $Type $known-tv)))
            ((($known-pos-goal $known-neg-goal) |- ($known-goal)) $all-adds))
         (if (bidirectional-implication-type? $Type)
            (let ($_head (cons Premises $left) (cons Conclusions $right)) $Type
               (let*
                  (($vars (extract-vars $Type))
                    ($mvars (if (== $vars ()) Nil $vars))
                    ((qside $left-shape-kb $left-prf $left-goal-expr $left-adds)
                       (query-side $kb $mvars false $left $right))
                    ((qside $right-shape-kb $right-prf $right-goal-expr $right-adds)
                       (query-side $kb $mvars false $right $left))
                    ($left-goal (: $left-shape-kb $left-prf $left-goal-expr $left-tv))
                    ($right-goal (: $right-shape-kb $right-prf $right-goal-expr $right-tv))
                    ($goal (: (kbctx $kb) (bidirectional $left-prf $right-prf) $Type $tv)))
                  ((($left-goal $right-goal (CPU AndFormula ($left-tv $right-tv) $tv)) |- ($goal))
                     (union-atom $left-adds $right-adds))))
            (if (and (= $Type (Inheritance $subj $concept)) (concrete-inheritance-link? $subj $concept))
               (compile-inheritance-query $kb $subj $concept)
            (((() |- ((: (kbctx $kb) $prf $Type $tv))) (compile-query-adds (: (kbctx $kb) $prf $Type $tv)))))))))


;; Translate the external `premises |- conclusions` compiler form into the
;; single-conclusion `rules` form consumed by MORK. Facts are already
;; zero-premise conclusions and therefore need no wrapper.
(= (mm2compile $kb $stmt) (mm2stmt (compile_ $kb $stmt)))

(= (mm2stmt $stmt) (case $stmt (((() |- ($ccl)) $ccl) (($prms |- ($ccl)) (rules ($prms |- $ccl))))))

;; Some query additions arrive wrapped in an extra singleton list after
;; collapse. Unwrap that shape explicitly before applying the normal MM2 rule
;; conversion; treating it as a fact would install the list itself as a goal.
(= (compiled-add-mm2stmt $add)
   (if (== (cdr-atom $add) ())
      (let*
         (($rule (car-atom $add))
           ($prms (car-atom $rule))
           ($tail (cdr-atom $rule))
           ($ccls (car-atom (cdr-atom $tail)))
           ($ccl (car-atom $ccls)))
         (rules ($prms |- $ccl)))
      (mm2stmt $add)))

(= (query-temp-rule-premise $premise)
   (case $premise (((Compute $f $args $res) (Compute $f $args -> $res)) ($other $other))))

(= (query-compound-type? $type)
   (if (is-expr $type)
      (let $head (car-atom $type)
         (if (is-var $head) false (is-member $head (And Or LikelierThan))))
      false))

;; A temporary implication is needed only for compound children which cannot be
;; lowered by the normal adapter chain (computations or nested compounds).
;; Pure n-ary conjunctions use the direct query bundle in compileQuery instead,
;; avoiding a persistent synthetic implication for a query-local operation.
(= (query-compound-needs-temp-rule? $term)
   (if (is-expr $term) (compound-direct-query-bundle? (cdr-atom $term)) false))

(= (compound-query-temp-stmt (: $_prf $type $_tv))
   (let*
      (((cons $_head $tail) $type)
        ($premises (map-flat query-temp-rule-premise $tail)))
	      (: query-compound
	         (Implication (cons Premises $premises) (cons Conclusions ($type)))
	         (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))

;; Query assumptions with no caller-supplied TV are treated as certain. An
;; implication needs a CTV-shaped default because its positive and negative
;; support are tracked separately throughout the query compiler.
(= (default-query-assumption-tv $type $tv)
   (if (is-var $tv)
      (if (= $type (Implication (cons Premises $_premises) (cons Conclusions $_conclusions)))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))
         (STV 1.0 1.0))
      $tv))

;; An implication used as a query assumption must be executable inside its
;; fresh context, not merely stored as an inert contextual fact. Compile its
;; forward rule against the same shaped KB so it can consume sibling assumptions.
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
               (compile-implication-forward-rules $kbid $shape-kb $shape-kb $ctxprf $tv $a $b $execs $proofs $atv)))
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

;; Normalize the few structural result shapes produced by compileQuery into a
;; uniform `(compiled-query goal additions)` value. The middle case introduces
;; a fresh contextual witness when the compiler returned a rule whose premise
;; is the queried fact itself.
(= (mm2compileQuery-from-compiled $kb $stmt $compiled)
   (if (= $compiled (((() |- ($ccl)) $adds)))
      (compiled-query (internalize-proof-structure $ccl)
         (internalize-proof-structure-list (map-flat compiled-add-mm2stmt $adds)))
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
                  (cons (mm2stmt ($prms |- ($ccl))) (map-flat compiled-add-mm2stmt $adds))))
            (notsupported mm2compileQuery $kb $stmt $compiled)))))

;; MM2 query entry point. Compound queries with computed/nested children take
;; the temporary-rule route; all other statements use compileQuery and the
;; structural normalization above.
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

;; MORK indexes facts as `(type kb proof tv)`, whereas the public/compiler form
;; is `(: kb proof type tv)`. Convert recursively because these atoms may appear
;; inside generated rules and query additions, not only at the top level.
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

;; Reverse the runtime tuple layout for diagnostics and public results. Only a
;; shaped KB can be recognized safely; arbitrary four-element expressions must
;; remain untouched.
(= (externalize-query-proof $proof)
   (if (is-var $proof) $proof
      (if (= $proof (inheritance-query-result $inner))
         (externalize-query-proof $inner)
         (if (= $proof (total-implication-frontier $inner))
            (externalize-query-proof $inner)
         (if (is-expr $proof)
            (cons (externalize-query-proof (car-atom $proof))
               (map-flat externalize-query-proof (cdr-atom $proof)))
            $proof)))))

(= (externalize-proof-structure $term)
   (if (== $term ()) ()
      (if (is-var $term) $term
      (if (= $term ($type $kb $prf $tv))
         (if (and (is-expr $kb) (= $kb ($kbid $ctx $vars)))
            (: ($kbid $ctx $vars) (externalize-query-proof $prf) $type $tv)
            $term)
         (if (is-expr $term)
            (cons (externalize-proof-structure (car-atom $term))
               (externalize-proof-structure-list (cdr-atom $term)))
            $term)))))

(= (externalize-proof-structure-list $terms)
   (if (== $terms ()) ()
      (cons (externalize-proof-structure (car-atom $terms))
         (externalize-proof-structure-list (cdr-atom $terms)))))

(= (pretty (: $prf $type $tv)) (: $prf $type $tv))
(= (pretty (rules ($args |- $goal))) (pretty $goal))
(= (pretty (: $kb $prf $type $tv))
   (if (is-expr $kb)
      (if (= $kb ($kbid MAIN Nil)) (: $prf $type $tv)
         (let*
            ((($_ $idx $vars) $kb)
              ($x (map-flat (mf $kb) (collapse (match &kb ($t $kb $p $tv2) ($kb $t)))))
              ($ptype (Implication (cons Premises $x) (cons Conclusions ($type)))))
            (: $prf $ptype $tv)))
      (: $prf $type $tv)))
