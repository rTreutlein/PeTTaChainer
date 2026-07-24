;; Compiler overview
;; -----------------
;; Statements enter through compile_ (stored facts and rules) or compileQuery
;; (temporary query goals). Source-level premises are lowered to executable
;; goals plus a combined TV and proof token. Adapter rules bridge compound or
;; computed source expressions to the simple fact shape consumed by the
;; chainer. mm2compile/mm2compileQuery then translate that external compiler
;; representation to the tuple layout used by the MORK runtime.

!(import! &self chainer_types)

(: AdapterMode Type)
(: plain AdapterMode)
(: query AdapterMode)

(: ProjectionEvidenceState Type)
(: projection-evidence-state
   (-> (List Goal)
       (List Proof) TV ProjectionEvidenceState))

(: PremiseBundle Type)
(: premise-bundle
   (-> (List Goal)
       TV Proof PremiseBundle))

(: CompiledPremise Type)
(: prem
   (-> Goal
       Expression TV Proof CompiledPremise))

(: QueryCompoundState Type)
(: query-compound-state
   (-> (List Goal)
       (List Proof) TV QueryCompoundState))

(: CompiledPremises Type)
(: compiled-premises
   (-> (List Goal)
       (List Proof) TV CompiledPremises))

(: CompiledQuery Type)
(: compiled-query
   (-> (| Goal
          (Statement KBContext Proof TV))
       (List RuntimeAddition) CompiledQuery))

(: CompiledQueryParts Type)
(: compiled-query-parts
   (-> (List Goal) Goal
       (List CompiledAddition) CompiledQueryParts))

(: CompiledOutput Type)
(: compiled-output
   (-> (List Goal)
       Proof Statement TV CompiledOutput))

(: ImplicationCTVExecutions Type)
(: implication-ctv-execs
   (-> (List Goal)
       TV ImplicationCTVExecutions))

(: ImplicationQueryTVParts Type)
(: implication-query-tv-parts
   (-> TV TV TV ImplicationQueryTVParts))

(: InheritanceLiftParts Type)
(: lift-parts
   (-> (List Expression) (List Expression) InheritanceLiftParts))

(: SpecializationJob Type)
(: compile-specialization (-> AnnotatedStatement SpecializationJob))
(: inheritance-lift-specialization
   (-> AnnotatedStatement AnnotatedStatement SpecializationJob))

(: InheritanceLiftInstanceRow Type)
(: inheritance-lift-instance-row
   (-> KB AnnotatedStatement AnnotatedStatement
       InheritanceLiftInstanceRow))

(: SpecializationTemplateRow Type)
(: specialization-template-row
   (-> KB Atom (List Expression) SpecializationJob
       SpecializationTemplateRow))

(: SpecializationDoneRow Type)
(: specialization-done-row
   (-> KB AnnotatedStatement SpecializationDoneRow))

(: NoSpecializationName Type)
(: no-specialization-name NoSpecializationName)
(: NoSpecializationStatement Type)
(: no-specialization-statement NoSpecializationStatement)
(: NoSpecializationJob Type)
(: no-specialization-job NoSpecializationJob)

(: QuerySide Type)
(: qside
   (-> KBContext Proof Statement
       (List CompiledAddition) QuerySide))

(: QueryScaffold Type)
(: query-scaffold
   (-> KBContext KBContext
       Statement
       Proof Proof (List CompiledAddition) QueryScaffold))

(: union-compiled-additions
   (-> (List CompiledAddition) (List CompiledAddition)
       (List CompiledAddition)))
(= (union-compiled-additions $left $right)
   (union-atom $left $right))

(: query-variables
   (-> (List Variable) (| NilType (List Variable))))
(= (query-variables $variables)
   (if (== $variables ()) Nil $variables))

;; Allocate a distinct context for assumptions introduced while compiling an
;; implication query. Contexts must not be shared because their assumed facts
;; are query-local.
(: nextctx (-> Number))
(= (nextctx)
   (let*
      (($mn (catch (get-state ctxid)))
        ($n (if-error-number $mn 0)))
      (progn (change-state! ctxid (+ $n 1)) $n)))

(: collect-var-step
   (-> (List Variable) Expression (List Variable)))
(= (collect-var-step $accum $arg)
   (if (is-var $arg)
      (cons (brand Variable $arg) $accum)
      $accum))

(: extract-vars (-> Expression (List Variable)))
(= (extract-vars $expr)
   (if (is-var $expr) (cons (brand Variable $expr) ())
      (if (is-expr $expr)
         (fold-nested collect-var-step () $expr)
         ())))

(: SkolemizeState (Newtype (Number Statement)))

;; Replace variables which occur only in the antecedent with stable `exists`
;; markers. In an inverted rule those variables cannot be recovered from the
;; new premise, so leaving them as ordinary variables would make unrelated
;; witnesses unify.
(: skolemize-step
   (-> Proof (List Variable) SkolemizeState Variable SkolemizeState))
(= (skolemize-step $rule $avars $state $elem)
   (let*
      (($idx (fst $state))
       ($atom (snd $state))
       ($elem (exists $rule $idx $avars)))
      (brand SkolemizeState ((+ 1 $idx) $atom))))

(: skolemize (-> Proof Statement Statement Statement))
(= (skolemize $rule $expra $exprb)
   (if (or (is-var $exprb) (is-var $expra)) $exprb
      (let*
         (($avars (list_to_set (extract-vars $expra)))
           ($bvars (list_to_set (extract-vars $exprb)))
           ($onlyb (\== $bvars $avars))
           ($state
              (sealed $onlyb
                 (fold-flat
                    (skolemize-step $rule $avars)
                    (brand SkolemizeState (0 $exprb))
                    $onlyb))))
         (snd $state))))

(: remove-index (-[det]-> Number (List $item) (List $item)))
(= (remove-index $idx $items)
   (case $items
      ((() ())
       ((cons $head $tail)
          (if (== $idx 0)
             $tail
             (cons $head (remove-index (- $idx 1) $tail)))))))

;; The singleton case deliberately preserves the element type; the multi-item
;; case builds an `And` expression.  This helper is genuinely polymorphic and
;; is not an executable-Goal boundary.
(: seq2expr (-> (List $element) $element))
(= (seq2expr (cons $head $tail)) (if (== $tail ()) $head (cons And (cons $head $tail))))

;; A projection from a compound connective can depend on the other children as
;; evidence. Preserve all their proof identities so later overlap checks see
;; the complete dependency set, while avoiding a redundant conjunction node
;; for the one-proof case.
(: projection-evidence-proof-token (-> (List Proof) Proof))
(= (projection-evidence-proof-token (cons $proof ())) $proof)
(= (projection-evidence-proof-token (cons $proof (cons $next $rest)))
   (brand Proof
      (cons conjunction (cons $proof (cons $next $rest)))))

(: projection-evidence-step
   (-> KBContext $formula ProjectionEvidenceState $element
       ProjectionEvidenceState))
(= (projection-evidence-step $kb $formula
      (projection-evidence-state $execs $proofs $acc-tv)
      $elem)
   (projection-evidence-state
      (append $execs ((: $kb $prf $elem $tv) (CPU $formula (quote ($acc-tv $tv)) $next-tv)))
      (append $proofs ($prf))
      $next-tv))

(: projection-evidence-bundle
   (-> KBContext $head (List $element) PremiseBundle))
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
(: compile-output-children
   (-[nondet]-> KBContext Statement Atom Number (List $element)
       CompiledAddition))
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

(: compile-outputs (-[nondet]-> Goal  CompiledAddition))
(= (compile-outputs (: $kb $NNprf $type $NNtv))
   (if (compound-source? $type)
      (let $head (car-atom $type)
         (if (= (configured-compound-output-mode $head) ProjectAll)
            (compile-output-children
               $kb (brand Statement $type) $head 0 (cdr-atom $type))
            (empty)))
      (empty)))

;; CPU goals normally constrain values and therefore contribute unit evidence.
;; These formulas instead compute a TV which must participate in the enclosing
;; premise TV. Aggregates opt into that behavior through their explicit tv-mode.
(: aggregate-args-tv-mode (-> $arguments AggregateTVMode))
(= (aggregate-args-tv-mode $args)
   (once
      (case $args (
         (($_kb $_pattern $_extractor $_init $_fun $_finish $tv-mode)
            $tv-mode)
         (($_gkb $_gpattern $_group $_gextractor $_ginit $_gfun
              $_gfinish $gtv-mode)
            $gtv-mode)
         ($_other unit-stv)))))

(: cpu-premise-tv
   (-> $formula $arguments $result TV))
(= (cpu-premise-tv $f $args $res)
   (if (is-member $f (FoldAllCompiled GroupedFoldAllCompiled))
      (if (== (aggregate-args-tv-mode $args) result-tv)
         $res
         (STV 1.0 1.0))
      (if (is-member $f
             (() NotFormula DistGreaterThanFormula DistGreaterThanDistFormula))
         $res
         (STV 1.0 1.0))))

(: make-kb-context (-> KB $context $variables KBContext))
(= (make-kb-context $kb $ctx $vars)
   (brand KBContext (quote ($kb $ctx $vars))))

(: source-premise-kb
   (-> KB $context $variables KBContext))
(= (source-premise-kb $kb $ctx $vars)
   (if (or (is-var $ctx) (is-var $vars))
      (kbctx $kb)
      (make-kb-context $kb $ctx $vars)))

;; Normalize one source premise to the compiler's common bundle:
;;   premise-bundle(executable goals, evidence TV, proof token).
;; Keeping this boundary uniform lets compound, computed, and ordinary fact
;; premises be combined by the same folds below.
(: leaf-source-bundle
   (-> KB $context $variables
       Statement PremiseBundle))
(= (leaf-source-bundle $kb $ctx $vars $elem)
   (let $prem-kb (source-premise-kb $kb $ctx $vars)
      (if (is-var $elem)
         (premise-bundle ((: $prem-kb $prf $elem $tv)) $tv $prf)
         (if (= $elem (CPU $f $args $res))
         (premise-bundle ((CPU $f $args $res))
            (cpu-premise-tv $f $args $res) cpu)
         (premise-bundle ((: $prem-kb $prf $elem $tv)) $tv $prf)))))

(: in_map (-> KBContext Expression CompiledPremise))
(= (in_map $kb $elem)
   (if (= $elem (CPU $f $args $res))
      (prem (CPU $f $args $res) (CPU $f $args $res)
         (cpu-premise-tv $f $args $res) cpu)
      (prem (: $kb $prf $elem $tv) $elem $tv $prf)))

(: PremiseFoldState Type)
(: premise-fold-state
   (-> (List Goal) KBContext (List Proof) (List Expression) TV
       PremiseFoldState))

(: in_fold
   (-> Atom PremiseFoldState CompiledPremise PremiseFoldState))
(=
   (in_fold $formula
      (premise-fold-state
         $premises $res-kb $cclprf $ccltype $tv)
      (prem $goal $elem $tve $prfelem))
   (premise-fold-state
      (cons (CPU $formula (quote ($tv $tve)) $ntv)
         (cons $goal $premises))
      $res-kb
      (cons $prfelem $cclprf)
      (cons $elem $ccltype)
      $ntv))

(: ExistentialFold (-> Statement (List Variable) Statement))

(: exec-goal-type
   (-> Goal Expression))
(= (exec-goal-type (CPU $f $args $res)) (CPU $f $args $res))
(= (exec-goal-type (: $_kb $_prf $elem $_tv)) $elem)

(: execs-goal-type
   (-> (List Goal) Expression))
(= (execs-goal-type $execs) (seq2expr (map-flat exec-goal-type $execs)))

;; Reconstruct the source shape of a lowered connective without treating its
;; own TV-fold CPU goals as additional children. Real CPU children remain in
;; the shape; only the <Head>Formula bookkeeping inserted by the compound
;; lowering itself is removed.
(: compound-exec-source-types
   (-> Atom (List Goal) (List Expression)))
(= (compound-exec-source-types $_formula ()) ())
(= (compound-exec-source-types $formula (cons $goal $rest))
   (if (= $goal (CPU $fun $_args $_result))
      (if (== $fun $formula)
         (compound-exec-source-types $formula $rest)
         (cons (exec-goal-type $goal)
            (compound-exec-source-types $formula $rest)))
      (cons (exec-goal-type $goal)
         (compound-exec-source-types $formula $rest))))

(: compound-execs-goal-type
   (-> Atom (List Goal) Expression))
(= (compound-execs-goal-type $head $execs)
   (seq2expr
      (compound-exec-source-types
         (atom_concat $head Formula) $execs)))

;; Lower a connective whose configured premise mode is All. Every child must
;; succeed, child TVs are folded with <Head>Formula, and the proof token records
;; the conjunction of the child proofs. This is the general conjunction-
;; introduction mechanism for And premises; it is connective-generic so the
;; same machinery also serves other All-mode connectives.
(: compound-all-premise-bundle
   (-> KB $context $variables
       Atom (List $element) PremiseBundle))
(= (compound-all-premise-bundle $kb $ctx $vars $head $tail)
   (let*
      (($prem-kb (source-premise-kb $kb $ctx $vars))
        ((cons (@ $fst (prem $fstgoal $fstelem $fsttv $fstprf)) $rst) (map-flat (in_map $prem-kb) $tail))
        ($init
           (premise-fold-state
              (cons $fstgoal ())
              $prem-kb
              (cons $fstprf ())
              (cons $fstelem ())
              $fsttv))
        ($folded (fold-flat (in_fold (atom_concat $head Formula)) $init $rst))
        ((premise-fold-state
            $resNNprms $res-kb $cclprf $ccltype $ccltv)
           $folded)
        ($execs (reverse $resNNprms))
        ($rcclprf (reverse $cclprf))
        ($rccltype (reverse $ccltype))
        ($proof-token (if (= $rcclprf (cons $proof ())) $proof (cons conjunction $rcclprf))))
      (premise-bundle $execs $ccltv $proof-token)))

;; Lower one alternative of an Any-mode connective. Only one child is evidence,
;; so the proof is labelled as an introduction of the enclosing connective
;; rather than as a conjunction of all children.
(: compound-any-premise-child-bundle
   (-> KB $context $variables
       Atom $element PremiseBundle))
(= (compound-any-premise-child-bundle $kb $ctx $vars $head $elem)
   (let*
      (($prem-kb (source-premise-kb $kb $ctx $vars))
        ((prem $goal $_elem $tv $proof) (in_map $prem-kb $elem)))
      (premise-bundle ($goal) $tv ((atom_concat $head introduction) $proof))))

(: compound-any-premise-bundle
   (-[nondet]-> KB $context $variables Atom (List $element)
       PremiseBundle))
(= (compound-any-premise-bundle $_kb $_ctx $_vars $_head ()) (empty))
(= (compound-any-premise-bundle $kb $ctx $vars $head (cons $elem $rest))
   (superpose (
      (compound-any-premise-child-bundle $kb $ctx $vars $head $elem)
      (compound-any-premise-bundle $kb $ctx $vars $head $rest))))

(: compound-premise-bundle
   (-[nondet]-> KB $context $variables Atom (List $element)
       PremiseBundle))
(= (compound-premise-bundle $kb $ctx $vars $head $tail)
   (let $mode (configured-compound-premise-mode $head)
      (if (= $mode Any)
         (compound-any-premise-bundle $kb $ctx $vars $head $tail)
         (compound-all-premise-bundle $kb $ctx $vars $head $tail))))

;; Compound lowering is deliberately configuration-driven. Merely being an
;; expression is insufficient: ordinary predicates such as (Friend a b) must
;; remain fact lookups and must not be interpreted as logical connectives.
(: compound-source? (-> $type Bool))
(= (compound-source? $type)
   (if (is-expr $type)
      (let $head (car-atom $type)
         (and (not (is-var $head)) (compound-connective? $head)))
      false))

;; Query compounds need recursive lowering because a child may itself be a
;; compound or a source-level computation. A plain predicate child stays a leaf
;; lookup so it can use the normal chainer indexes.
(: query-compound-child-bundle
   (-> KB $context $variables Statement PremiseBundle))
(= (query-compound-child-bundle $kb $ctx $vars $premise)
   (if (compound-source? $premise)
      (let (cons $head $tail) $premise
         (query-compound-premise-bundle
            $kb $ctx $vars $head (the (List Expression) $tail)))
      (if (is-expr $premise)
         (let $head (car-atom $premise)
            (if (is-var $head)
               (leaf-source-bundle $kb $ctx $vars $premise)
               (if (is-member $head
                     (Compute MapDist Map2Dist AverageDist FoldAllValue FoldAll Not GreaterThan >))
                  (once (lower-source-premise $kb $ctx $vars $premise))
                  (leaf-source-bundle $kb $ctx $vars $premise))))
         (leaf-source-bundle $kb $ctx $vars $premise))))

(: query-compound-premise-state (-> PremiseBundle QueryCompoundState))
(= (query-compound-premise-state (premise-bundle $execs $tv $proof))
   (query-compound-state $execs ($proof) $tv))

;; Accumulate a direct compound-query rule in source order. Appending both goals
;; and proofs is intentional: the returned `(conjunction ...)` proof mirrors the
;; order written by the caller, while each TV fold consumes the same ordering.
(: query-compound-premise-step
   (-> KB $context $variables Atom QueryCompoundState $premise
       QueryCompoundState))
(=
   (query-compound-premise-step $kb $ctx $vars $formula
      (query-compound-state $acc-execs $acc-proofs $acc-tv)
      $premise)
   (let*
      (((premise-bundle $execs $tv $proof)
          (query-compound-child-bundle
             $kb $ctx $vars (brand Statement $premise))))
      (query-compound-state
         (append $acc-execs (append $execs ((CPU $formula (quote ($acc-tv $tv)) $next-tv))))
         (append $acc-proofs ($proof))
         $next-tv)))

(: query-compound-premise-bundle
   (-> KB $context $variables Atom (List Expression) PremiseBundle))
(= (query-compound-premise-bundle $kb $ctx $vars $head (cons $fst $rst))
   (let*
      (((query-compound-state $execs $proofs $ccltv)
           (fold-flat
              (query-compound-premise-step $kb $ctx $vars (atom_concat $head Formula))
              (query-compound-premise-state
                 (query-compound-child-bundle
                    $kb $ctx $vars (brand Statement $fst)))
              $rst))
        ($rcclprf $proofs)
        ($proof-token
           (if (= $rcclprf (cons $proof ()))
              $proof
              (brand Proof (cons conjunction $rcclprf)))))
      (premise-bundle $execs $ccltv $proof-token)))

;; A direct bundle is required when normal plain adapters cannot faithfully
;; express a child: nested compounds and computations must be lowered inside
;; the query rule rather than looked up as already materialized facts.
(: query-compound-child-needs-bundle? (-> $premise Bool))
(= (query-compound-child-needs-bundle? $premise)
   (if (compound-source? $premise)
      (query-compound-needs-bundle? $premise)
      (if (is-expr $premise)
         (let $head (car-atom $premise)
            (if (is-var $head) false
               (is-member $head
                  (Compute MapDist Map2Dist AverageDist FoldAllValue FoldAll Not GreaterThan >))))
         false)))

(: compound-direct-query-bundle? (-> (List $item) Bool))
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
(: compound-nary-query? (-> (List $item) Bool))
(= (compound-nary-query? $items)
   (case $items (
      ((cons $_a (cons $_b (cons $_c $_rest))) true)
      ($_ false))))

(: query-compound-needs-bundle? (-> $term Bool))
(= (query-compound-needs-bundle? $term)
   (if (is-expr $term)
      (let $items (cdr-atom $term)
         (or (compound-nary-query? $items) (compound-direct-query-bundle? $items)))
      false))

;; An open proof variable should be replaced by the generated bundle itself.
;; A named/structured query proof is instead retained as an outer provenance
;; label around that bundle.
(: query-compound-proof-token (-> Proof Proof Proof))
(= (query-compound-proof-token $prf $proof-token)
   (if (is-var $prf)
      $proof-token
      (brand Proof (quote ($prf $proof-token)))))

;; Build reusable adapters for source expressions found in stored rules. Each
;; adapter derives the requested compound from its lowered children. Recursing
;; on a different executable type ensures any intermediate source syntax also
;; receives an adapter, without regenerating the identical rule.
(: compile-adapter-chain
   (-[nondet]-> AdapterMode Goal  CompiledAddition))
(= (compile-adapter-chain plain (: $kb $prf $type $tv))
   (if (compound-source? $type)
      (let ($kbid $ctx $vars) $kb
         (let*
            (($head (car-atom $type))
             ($tail (cdr-atom $type))
             ((premise-bundle $execs $result-tv $proof-token)
                 (compound-premise-bundle
                    (brand KB $kbid) $ctx $vars $head $tail))
              ($exec-type
                 (compound-execs-goal-type $head $execs)))
            (superpose
               (($execs |-
                    ((: $kb $proof-token $type $result-tv)))
                (if (== $exec-type $type) (empty)
                   (compile-adapter-chain plain
                      (: $kb $prfa $exec-type $atv)))))))
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
                    (let ($kbid $ctx $vars) $kb
                       (once
                          (query-compound-premise-bundle
                             (brand KB $kbid) $ctx $vars $head
                             (the (List Expression) $tail))))))
               (($execs |- ((: $kb (query-compound-proof-token $prf $proof-token) $type $result-tv)))))
            (compile-adapter-chain plain (: $kb $prf $type $tv)))
         (let*
            (((premise-bundle $execs $result-tv $proof-token)
                 (let ($kbid $ctx $vars) $kb
                    (once
                       (lower-source-premise
                          (brand KB $kbid) $ctx $vars $type))))
              ($exec-type (execs-goal-type $execs)))
            (if (and (not (is-var $type)) (not (== $exec-type $type)))
               (superpose (($execs |- ((: $kb ($prf $proof-token) $type $result-tv)))
                           (compile-adapter-chain plain (: $kb $prfa $exec-type $atv))))
               (empty))))))

;; Lower the supported source-language premise forms to executable chainer/CPU
;; goals. This function owns the semantic translation (including which TV and
;; proof token a computation contributes); callers only combine its bundles.
(: lower-source-premise-non-open
   (-[nondet]-> KB $context $variables Statement  PremiseBundle))
(= (lower-source-premise-non-open $kb $ctx $vars $premise)
   (if (compound-source? $premise)
      (let*
         (($head (car-atom $premise))
          ($tail (cdr-atom $premise)))
         (compound-premise-bundle $kb $ctx $vars $head $tail))
      (case $premise (
           ((Implication (cons Premises $_premises) (cons Conclusions $_conclusions))
              (leaf-source-bundle $kb $ctx $vars $premise))
           ((Compute $f $args -> $res)
              (premise-bundle ((CPU $f $args $res))
                 (cpu-premise-tv $f $args $res) cpu))
           ((Compute $f $args $res)
              (premise-bundle ((CPU $f $args $res))
                 (cpu-premise-tv $f $args $res) cpu))
           ((MapDist $fun $a $value -> $out)
              (premise-bundle
                 ((: (make-kb-context $kb $ctx $vars)
                      $prfa $a $tv_a)
                  (CPU DistMapFormula ($fun $value) $out))
                 (STV 1.0 1.0)
                 $prfa))
           ((Map2Dist $fun $a $valuea $b $valueb -> $out)
              (premise-bundle
                 ((: (make-kb-context $kb $ctx $vars)
                      $prfa $a $tv_a)
                  (: (make-kb-context $kb $ctx $vars)
                      $prfb $b $tv_b)
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
                 (premise-bundle
                    ((: (make-kb-context $kb $ctx $vars)
                         $prf ($rel $a $b) $tv))
                    $tv $prf)))
           ($other
              (premise-bundle
                 ((: (make-kb-context $kb $ctx $vars)
                      $prf $other $tv))
                 $tv $prf))))))

;; Variable-headed expressions require the generic fact path. Dispatching them
;; through the structural cases above would mistake an unknown predicate head
;; for compiler syntax and could specialize the query incorrectly.
(: lower-source-premise
   (-[nondet]-> KB $context $variables Statement  PremiseBundle))
(= (lower-source-premise $kb $ctx $vars $premise)
   (if (and (is-expr $premise) (is-var (car-atom $premise)))
      (if (== (cdr-atom $premise) ())
         (leaf-source-bundle $kb $ctx $vars (car-atom $premise))
         (leaf-source-bundle $kb $ctx $vars $premise))
      (lower-source-premise-non-open $kb $ctx $vars $premise)))

;; Combine premise bundles left-to-right. AndFormula is inserted only between
;; non-empty bundles so the first premise supplies the initial TV and no fake
;; unit-evidence proof is introduced.
(: append-premise-bundle
   (-> CompiledPremises PremiseBundle CompiledPremises))
(=
   (append-premise-bundle (compiled-premises $current-execs $current-proofs $current-tv)
      (premise-bundle $execs $tv $proof))
   (if (== $current-execs ()) (compiled-premises $execs ($proof) $tv)
      (compiled-premises
         (append $current-execs (append $execs ((CPU AndFormula (quote ($current-tv $tv)) $next-tv))))
         (append $current-proofs ($proof))
         $next-tv)))

(: compile-same-var-in-list? (-> Variable (List Variable) Bool))
(= (compile-same-var-in-list? $_var ()) false)
(= (compile-same-var-in-list? $var (cons $head $tail))
   (or (== $var $head) (compile-same-var-in-list? $var $tail)))

(: compile-var-list-subtract
   (-> (List Variable) (List Variable) (List Variable)))
(= (compile-var-list-subtract () $_exclude) ())
(= (compile-var-list-subtract (cons $var $rest) $exclude)
   (if (compile-same-var-in-list? $var $exclude)
      (compile-var-list-subtract $rest $exclude)
      (cons $var (compile-var-list-subtract $rest $exclude))))

(: compile-has-vars? (-> (List Variable) Bool))
(= (compile-has-vars? $vars) (not (== $vars ())))

;; A premise-local variable denotes existential evidence, not a variable which
;; should escape into the compiled rule. Collapse all matching witnesses with
;; OrFormula; retain group variables when the premise is correlated with the
;; conclusion or another premise so each binding gets its own aggregate.
(: fold-existential-premise-bundle
   (-> KB $context $variables Statement (List Variable) PremiseBundle))
(= (fold-existential-premise-bundle $kb $ctx $vars $premise $group-vars)
   (let $prem-kb (source-premise-kb $kb $ctx $vars)
      (if (== $group-vars ())
         (premise-bundle
            ((CPU FoldAllCompiled
                 (quote ($prem-kb $premise extract-tv (STV 0.0 1.0) OrFormula identity result-tv))
                 $fold-tv))
            $fold-tv
            cpu)
         (premise-bundle
            ((CPU GroupedFoldAllCompiled
                 (quote ($prem-kb $premise $group-vars extract-tv (STV 0.0 1.0) OrFormula identity result-tv))
                 $fold-tv))
            $fold-tv
            cpu))))

;; Only ordinary fact-like premises are safe to rewrite as existential folds.
;; Compiler forms and computations have their own lowering and binding rules;
;; folding them as database patterns would change their meaning.
(: existential-foldable-premise? (-> Statement Bool))
(= (existential-foldable-premise? $premise)
   (if (is-expr $premise)
      (let $head (car-atom $premise)
         (if (is-var $head) true
            (not
               (is-member $head
                  (Implication Compute MapDist Map2Dist AverageDist FoldAllValue FoldAll Not GreaterThan >)))))
      true))

(: lower-source-premise-with-existentials
   (-[nondet]-> KB $context $variables Statement  PremiseBundle))
(= (lower-source-premise-with-existentials $kb $ctx $vars $premise)
   (if
      (and (is-expr $premise)
         (let $head (car-atom $premise)
            (and (not (is-var $head)) (== $head ExistentialFold))))
      (let (ExistentialFold $fold-premise $group-vars) $premise
         (fold-existential-premise-bundle
            $kb $ctx $vars $fold-premise $group-vars))
      (lower-source-premise $kb $ctx $vars $premise)))

(: compile-premise-local-vars
   (-> (List Variable) (List Variable) Statement (List Variable)))
(= (compile-premise-local-vars $conclusion-vars $other-vars $premise)
   (let $premise-vars (list_to_set (extract-vars $premise))
      (compile-var-list-subtract (compile-var-list-subtract $premise-vars $conclusion-vars) $other-vars)))

(: compile-premise-has-existentials?
   (-> (List Variable) (List Variable) Statement Bool))
(= (compile-premise-has-existentials? $conclusion-vars $other-vars $premise)
   (let $local-vars (compile-premise-local-vars $conclusion-vars $other-vars $premise)
      (and (existential-foldable-premise? $premise) (compile-has-vars? $local-vars))))

(: compile-premise-group-vars
   (-> (List Variable) (List Variable) Statement (List Variable)))
(= (compile-premise-group-vars $conclusion-vars $other-vars $premise)
   (let*
      (($premise-vars (list_to_set (extract-vars $premise)))
        ($local-vars (compile-premise-local-vars $conclusion-vars $other-vars $premise)))
      (compile-var-list-subtract $premise-vars $local-vars)))

;; Partition before lowering so existential-only premises run after normal
;; premises. This lets variables shared with other premises be bound first and
;; correctly distinguishes genuinely local variables from correlated ones.
(: partition-existential-premises-walk
   (-> (List Variable) (List Variable)
       (List Expression) (List Expression) (List Expression)
       ((List Expression) (List Expression))))
(= (partition-existential-premises-walk $_conclusion-vars $_prior-vars $normal $folded ())
   ($normal $folded))
(= (partition-existential-premises-walk $conclusion-vars $prior-vars $normal $folded (cons $premise $rest))
   (let*
      (($premise-vars (list_to_set (extract-vars $premise)))
        ($rest-vars (list_to_set (extract-vars $rest)))
        ($other-vars (append $prior-vars $rest-vars))
        ($nprior (append $prior-vars $premise-vars)))
      (if (compile-premise-has-existentials?
             $conclusion-vars $other-vars
             (brand Statement $premise))
         (let $group-vars
            (compile-premise-group-vars
               $conclusion-vars $other-vars
               (brand Statement $premise))
            (partition-existential-premises-walk $conclusion-vars $nprior $normal
               (append $folded
                  (cons
                     (ExistentialFold
                        (brand Statement $premise) $group-vars)
                     ()))
               $rest))
         (partition-existential-premises-walk $conclusion-vars $nprior
            (append $normal (the (List Expression) ($premise)))
            $folded $rest))))

(: partition-existential-premises
   (-> (List Variable) (List Expression) (List Expression)))
(= (partition-existential-premises $conclusion-vars $premises)
   (let*
      (($partitioned
          (partition-existential-premises-walk $conclusion-vars () () () $premises))
        ($normal (fst $partitioned))
        ($folded (snd $partitioned)))
      (append $normal $folded)))

(: lower-source-premises-step
   (-[nondet]-> KB $context $variables CompiledPremises Statement
       CompiledPremises))
(= (lower-source-premises-step $kb $ctx $vars $acc $premise)
   (append-premise-bundle $acc
      (lower-source-premise-with-existentials $kb $ctx $vars $premise)))

(: lower-source-premises-list
   (-[nondet]-> KB $context $variables (List Expression)
       CompiledPremises))
(= (lower-source-premises-list $kb $ctx $vars $premises)
   (lower-source-premises-list-acc
      $kb $ctx $vars
      (compiled-premises () () (STV 1.0 1.0))
      $premises))

(: lower-source-premises-list-acc
   (-[nondet]-> KB $context $variables CompiledPremises (List Expression)
       CompiledPremises))
(= (lower-source-premises-list-acc $_kb $_ctx $_vars $acc ()) $acc)
(= (lower-source-premises-list-acc $kb $ctx $vars $acc (cons $premise $rest))
   (lower-source-premises-list-acc
      $kb $ctx $vars
      (lower-source-premises-step
         $kb $ctx $vars $acc (brand Statement $premise))
      $rest))

(: lower-source-premises
   (-[nondet]-> KB $context $variables (List Expression) (List Expression)
       CompiledPremises))
(= (lower-source-premises $kb $ctx $vars $premises $conclusions)
   (let*
      (($conclusion-vars (list_to_set (extract-vars $conclusions)))
        ($ordered-premises (partition-existential-premises $conclusion-vars $premises)))
      (lower-source-premises-list $kb $ctx $vars $ordered-premises)))

;; Premises of an implication *query* are temporary assumptions. A positive
;; `(Not A)` assumption is represented by an A-shaped contextual fact with
;; strength zero, allowing ordinary fact matching while preserving its logical
;; truth through the bundle TV.
(: lower-query-assumption-premise
   (-[nondet]-> KB $context $variables Statement  PremiseBundle))
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

(: lower-query-assumption-premises-step
   (-[nondet]-> KB $context $variables CompiledPremises Statement
       CompiledPremises))
(= (lower-query-assumption-premises-step $kb $ctx $vars $acc $premise)
   (append-premise-bundle $acc (lower-query-assumption-premise $kb $ctx $vars $premise)))

(: lower-query-assumption-premises
   (-[nondet]-> KB $context $variables (List Expression)
       CompiledPremises))
(= (lower-query-assumption-premises $kb $ctx $vars $premises)
   (lower-query-assumption-premises-acc
      $kb $ctx $vars
      (compiled-premises () () (STV 1.0 1.0))
      $premises))

(: lower-query-assumption-premises-acc
   (-[nondet]-> KB $context $variables CompiledPremises (List Expression)
       CompiledPremises))
(= (lower-query-assumption-premises-acc $_kb $_ctx $_vars $acc ()) $acc)
(= (lower-query-assumption-premises-acc $kb $ctx $vars $acc (cons $premise $rest))
   (lower-query-assumption-premises-acc
      $kb $ctx $vars
      (lower-query-assumption-premises-step
         $kb $ctx $vars $acc (brand Statement $premise))
      $rest))

;; Construct the refuting side of a total-implication query: the first premise
;; is assumed false and all remaining premises true. This is the counterexample
;; condition used to compute the negative component of the implication CTV.
(: lower-query-assumption-premise-false
   (-> KB $context $variables Statement PremiseBundle))
(= (lower-query-assumption-premise-false $kb $ctx $vars $premise)
   (if (and (is-expr $premise) (not (is-var (car-atom $premise))))
      (let $head (car-atom $premise)
         (if (== $head Not)
            (let $prem-kb (source-premise-kb $kb $ctx $vars)
               (premise-bundle ((: $prem-kb $prf (car-atom (cdr-atom $premise)) (STV 1.0 1.0))) (STV 0.0 1.0) (negated $prf)))
            (if (== $head Implication)
               (premise-bundle
                  ((: (make-kb-context $kb $ctx $vars)
                       $prf $premise
                       (CTV (STV 0.0 1.0) (STV 1.0 1.0))))
                  (CTV (STV 0.0 1.0) (STV 1.0 1.0))
                  $prf)
               (premise-bundle
                  ((: (make-kb-context $kb $ctx $vars)
                       $prf $premise (STV 0.0 1.0)))
                  (STV 0.0 1.0) $prf))))
      (premise-bundle
         ((: (make-kb-context $kb $ctx $vars)
              $prf $premise (STV 0.0 1.0)))
         (STV 0.0 1.0) $prf)))

(: lower-query-assumption-premises-negative
   (-[nondet]-> KB $context $variables (List Expression)
       CompiledPremises))
(= (lower-query-assumption-premises-negative $kb $ctx $vars ())
   (compiled-premises () () (STV 0.0 1.0)))
(= (lower-query-assumption-premises-negative $kb $ctx $vars (cons $premise $rest))
   (lower-query-assumption-premises-acc $kb $ctx $vars
      (append-premise-bundle
         (compiled-premises () () (STV 1.0 1.0))
         (lower-query-assumption-premise-false
            $kb $ctx $vars (brand Statement $premise)))
      $rest))

(: bidirectional-implication-type? (-> Statement Bool))
(= (bidirectional-implication-type? $Type)
   (if (is-expr $Type)
      (let $head (car-atom $Type)
         (and (not (is-var $head)) (bidirectional-implication-form? $head)))
      false))

(: compile-query-adds (-> Goal (List CompiledAddition)))
(= (compile-query-adds (: $kb $prf $type $tv))
   (collapse (compile-adapter-chain query (: $kb $prf $type $tv))))


;; Normalize a public KB id to its default runtime shape. Query contexts already
;; arrive shaped as `(kbid ctx vars)` and must pass through unchanged.
(: existing-kb-context (-> Expression KBContext))
(= (existing-kb-context $kb)
   (brand KBContext $kb))

(: default-kb-context (-> Expression KBContext))
(= (default-kb-context $kb)
   (make-kb-context (brand KB $kb) MAIN Nil))

(: kbctx (-> Expression KBContext))
(= (kbctx $kb)
   (if (is-expr $kb)
      (existing-kb-context $kb)
      (default-kb-context $kb)))

(: context-polymorphic-facts-key (-> KB Atom))
(= (context-polymorphic-facts-key $kb) (atom_concat context_polymorphic_facts_ $kb))

(: set-context-polymorphic-facts (-> KB Bool Bool))
(= (set-context-polymorphic-facts $kb $enabled)
   (change-state! (context-polymorphic-facts-key $kb) $enabled))

(: context-polymorphic-facts? (-> KB Bool))
(= (context-polymorphic-facts? $kb)
   (let $menabled (catch (get-state (context-polymorphic-facts-key $kb)))
      (if-error-bool $menabled false)))

(: compile-fact-kb-from-id (-> Expression KBContext))
(= (compile-fact-kb-from-id $kb)
   (let $kbid (brand KB $kb)
      (if (context-polymorphic-facts? $kbid)
         (make-kb-context $kbid $ctx $vars)
         (make-kb-context $kbid MAIN Nil))))

(: compile-fact-kb (-> Expression KBContext))
(= (compile-fact-kb $kb)
   (if (is-expr $kb)
      (existing-kb-context $kb)
      (compile-fact-kb-from-id $kb)))

(: map-nested2 (-> (-> $term $term) $term $term))
(= (map-nested2 $f ()) ())
(= (map-nested2 $f (cons $x $xs))
   (if (is-expr $x) ($f (cons (map-nested2 $f $x) (map-nested2 $f $xs)))
      ($f (cons ($f $x) (map-nested2 $f $xs)))))

(: toQuery (-> $term $term))
(= (toQuery $elem) (if (=? $elem (exists $_1 $_2 $_3)) $var $elem))

(: contains-cpu? (-> $term Bool))
(= (contains-cpu? $term)
   (if (is-var $term) false
      (if (is-expr $term)
         (or (== (car-atom $term) CPU)
            (fold-flat (|-> ($acc $elem) (or $acc (contains-cpu? $elem))) false (cdr-atom $term)))
         false)))

(: disable-inversion-proof-id? (-> Proof Bool))
(= (disable-inversion-proof-id? $prf) (= $prf (no_inverse $_)))

;; Preserve the dependency shape of a rule application. Zero-premise rules are
;; CPU-derived, one premise needs no wrapper, and multiple premises must retain
;; an explicit conjunction for overlap detection and proof rendering.
(: implication-proof-token (-> (List Proof) Proof))
(= (implication-proof-token $proofs)
   (case $proofs (
      (() cpu)
      ((cons $proof ()) $proof)
      ((cons $proof $rest)
         (brand Proof
            (cons conjunction (cons $proof $rest)))))))

;; Rules stored with an STV need a CTV derived from antecedent/consequent base
;; rates before modus ponens can use them. An explicit CTV already carries both
;; directions and therefore needs no runtime base-rate scans.
(: compile-implication-ctv-execs
   (-> KB Statement Statement TV ImplicationCTVExecutions))
(= (compile-implication-ctv-execs $_kb $_a $_b (CTV $pos $neg))
   (implication-ctv-execs () (CTV $pos $neg)))
(= (compile-implication-ctv-execs $kb $a $b (STV $s $c))
   (let*
      (($a1 (copy_term (map-nested2 toQuery $a)))
        ($b1 (copy_term (map-nested2 toQuery $b))))
      (implication-ctv-execs
          ((base-rate-premise $kb $a1 $rule-atv)
           (base-rate-premise $kb $b1 $rule-btv)
           (CPU ImplicationCTVFormula
              (quote ($rule-atv $rule-btv (STV $s $c)))
              $rule-ctv))
         $rule-ctv)))

;; A negated conclusion is stored as positive evidence for its inner expression
;; with a negated proof and transformed TV. Keeping the runtime type positive
;; lets it share the ordinary fact indexes.
(: compile-implication-output
   (-> Proof Proof Statement TV CompiledOutput))
(= (compile-implication-output $prf $proof-token $b $btv)
   (case $b (
      ((Not $inner)
         (compiled-output
            ((CPU NotFormula ($btv) $out-tv))
            (negated (quote ($prf $proof-token)))
            $inner
            $out-tv))
      ($other
         (compiled-output () (quote ($prf $proof-token)) $other $btv)))))

;; Emit the forward rule plus the adapters needed on both sides. The shape KB is
;; context-sensitive for assumption queries, while adapter-kb controls where
;; reusable source-shape adapters are indexed.
(: compile-implication-forward-rules
   (-[nondet]-> KB KBContext KBContext Proof TV Statement Statement
       (List Goal)
       (List Proof) TV  CompiledAddition))
(= (compile-implication-forward-rules $kb $shape-kb $adapter-kb $prf $tv $a $b $execs $proofs $atv)
   (superpose (
      (once
         (let*
            (($proof-token (implication-proof-token $proofs))
              ((implication-ctv-execs $ctv-execs $rule-ctv)
                 (compile-implication-ctv-execs $kb $a $b $tv))
              ((compiled-output $out-execs $out-prf $out-type $out-tv)
                 (compile-implication-output
                    $prf $proof-token $b (the TV $btv)))
              ($allargs
                 (append
                    (the (List Goal) $execs)
                    (append
                       (the (List Goal) $ctv-execs)
                       (append
                          (the (List Goal)
                             ((CPU CTVModusPonensFormula ($atv $rule-ctv) $btv)))
                          (the (List Goal)
                             $out-execs))))))
            ($allargs |- ((: $shape-kb $out-prf $out-type $out-tv)))))
      (if (is-var $b) (empty) (compile-outputs (: $adapter-kb ($prf $prfb) $b $btv2)))
      (if (is-var $a) (empty) (compile-adapter-chain plain (: $adapter-kb $prfa $a $atv))))))

(: rule-evidence-base-name (-> Proof Proof))
(= (rule-evidence-base-name $prf)
   (if (= $prf (bi-forward $fwd)) $fwd
      (if (= $prf (bi-backward $bwd)) $bwd
         (if (= $prf (no_inverse $inner)) $inner
            $prf))))

(: rule-evidence-registered? (-> KB Proof Bool))
(= (rule-evidence-registered? $kbid $name)
   (not (== (collapse (once (match &rule_evidence_names ($kbid $name) true))) ())))

(: register-rule-evidence!
   (-> KB Proof (| Bool (List $no-result))))
(= (register-rule-evidence! $kb $prf)
   (let $name (rule-evidence-base-name $prf)
      (if (is-expr $name) ()
         (if (logic-rule? $name) ()
            (if (rule-evidence-registered? $kb $name) ()
               (once
                  (add-atom &rule_evidence_names ($kb $name))))))))

;; Estimate the base rate required to reinterpret an STV rule as a CTV. Open
;; inheritance antecedents use universe-aware weighted evidence; ordinary
;; patterns use the generic evidence accumulator.
(: base-rate-premise-default
   (-> KB Statement $truth-value Goal))
(= (base-rate-premise-default $kb $pattern $brtv)
   (if (and (= $pattern (Inheritance $x $_concept)) (is-var $x))
      (CPU FoldAllCompiled
         (quote
            ($kb $pattern (extract-inheritance-tv $kb $pattern) (BaseRateEvidence 0.0 0.0)
               WeightedBaseRateAcc (weighted-base-rate-in-universe $kb) result-tv))
         $brtv)
      (CPU FoldAllCompiled
         (quote
            ($kb $pattern extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv))
         $brtv)))

;; A concrete inheritance target may have a configured/dynamic concept prior.
;; Seed its fold with that prior so sparse observations revise the prior instead
;; of silently behaving like an uninformative generic predicate.
(: base-rate-premise
   (-> KB Statement $truth-value Goal))
(= (base-rate-premise $kb $pattern $brtv)
   (if (and (= $pattern (Inheritance $x $subj)) (and (is-var $x) (not (is-var $subj))))
      (let*
         (($prior-runtime
             (ConceptNodePriorRuntime $kb $subj))
          ($prior
             (brand BaseRatePrior $prior-runtime)))
         (CPU FoldAllCompiled
            (quote
               ($kb $pattern (extract-inheritance-tv $kb $pattern)
                  (BaseRateEvidenceWithPrior
                     $prior
                     (BaseRateEvidence 0.0 0.0))
                  WeightedBaseRateWithPriorAcc
                  (weighted-base-rate-with-prior-in-universe $kb)
                  result-tv))
            $brtv))
      (base-rate-premise-default $kb $pattern $brtv)))

;; Compile the backward use of an implication by deriving its CTV, applying TV
;; inversion, and then using the observed consequent as modus-ponens evidence.
;; This is emitted only when the main compiler has proved the antecedent is
;; invertible (no CPU goals and no explicit no_inverse marker).
(: inverse-implication
   (-> KB Proof Statement Statement TV CompiledAddition))
(= (inverse-implication $kb $prf $a $b $itv)
   (let*
      (($a1 (copy_term (map-nested2 toQuery $a)))
        ($b1 (copy_term (map-nested2 toQuery $b))))
      (((: (make-kb-context $kb $ctx $vars) $prfb_wit $b $btv_wit)
            (base-rate-premise $kb $a1 $atv)
            (base-rate-premise $kb $b1 $btv)
            (CPU ImplicationCTVFormula (quote ($atv $btv $itv)) $rule-ctv)
            (CPU CTVInversionFormula (quote ($atv $btv $rule-ctv)) $iitv)
            (CPU CTVModusPonensFormula (quote ($btv_wit $iitv)) $mp-tv))
         |-
         ((: (make-kb-context $kb $ctx $vars)
              ((inverted $prf with cpu cpu) $prfb_wit) $a $mp-tv)))))

;; Concrete Inheritance assertions also act as implication-like rules over
;; members. Materializing these views once at compile time lets ordinary rule
;; indexing and inference handle inheritance without a separate chainer path.
(: concrete-inheritance-link? (-> $subject $concept Bool))
(= (concrete-inheritance-link? $subj $concept)
   (and (not (is-var $subj)) (not (is-var $concept))))

(: compile-derived-inheritance-views
   (-[nondet]-> KB Proof Term Term TV  CompiledAddition))
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
(: inheritance-context-premise? (-> $premise $subject Bool))
(= (inheritance-context-premise? $premise $subj)
   (if (= $premise (Inheritance $premise-subj $_concept))
      (== $premise-subj $subj)
      false))

(: inheritance-lift-auxiliary-premises
   (-> (List Expression) $subject (List Expression)))
(= (inheritance-lift-auxiliary-premises () $_subj) ())
(= (inheritance-lift-auxiliary-premises (cons $premise $rest) $subj)
   (if (inheritance-context-premise? $premise $subj)
      (inheritance-lift-auxiliary-premises $rest $subj)
      (cons $premise (inheritance-lift-auxiliary-premises $rest $subj))))

;; Pair a grounded rule instance with its original template. Contextual
;; Inheritance premises keep their grounded concept but replace the concrete
;; subject with the query's hypothetical instance; auxiliary premises remain
;; grounded MAIN facts.
(: inheritance-lift-parts
   (-> (List Expression) (List Expression) $subject $instance
       InheritanceLiftParts))
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
(: inheritance-lift-ctv (-> TV TV))
(= (inheritance-lift-ctv (CTV $pos $neg)) (CTV $pos $neg))
(= (inheritance-lift-ctv (STV $s $c))
   (CTV (STV $s $c) (STV 0.0 1.0)))

(: compile-inheritance-lift-instance
   (-> KB KBContext AnnotatedStatement AnnotatedStatement
       CompiledAddition))
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
      (($kb (car-atom $lift-kb))
       ($ctx (car-atom (cdr-atom $lift-kb)))
       ($vars (car-atom (cdr-atom (cdr-atom $lift-kb))))
       ((lift-parts $contextual-premises $auxiliary-premises)
          (inheritance-lift-parts
             (the (List Expression) $ground-premises)
             (the (List Expression) $source-premises)
             $source-subj $instance))
       ($lift-premises
          (if (== $contextual-premises ())
             (the (List Expression)
                ((Inheritance $instance $ground-subj)))
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
          (CPU AndFormula (quote ($main-atv $context-atv)) $all-atv))
       ($rule-ctv (inheritance-lift-ctv (the TV $tv)))
       ($modus-ponens
          (CPU CTVModusPonensFormula (quote ($all-atv $rule-ctv)) $out-tv))
       ($out
          (: $lift-kb
             ((inheritance-rule-lift $prf) $source-proof $context-proof)
             (Inheritance $instance $ground-concept) $out-tv)))
      ((append
          (the (List Goal)
             $main-execs)
          (the (List Goal)
             (append
                (the (List Goal)
                   $context-execs)
                (the (List Goal) (quote ($all-evidence $modus-ponens))))))
        |- ($out))))

;; A grounded lift is one specialization job. The common specialization engine
;; below handles template indexing and late facts for both ordinary compiler
;; specialization and these Inheritance views.
(: emit-specialization
   (-[nondet]-> KB SpecializationJob  CompiledAddition))
(= (emit-specialization $kb
      (inheritance-lift-specialization $stmt $source-stmt))
   (let $stored
      (collapse
         (once
            (match &inheritance_lift_instance
               (inheritance-lift-instance-row
                  $kb $candidate $_source)
               (if (=alpha $candidate $stmt) true (empty)))))
      (if (not (== $stored ())) (empty)
         (let*
            (($stmt-copy (copy_term $stmt))
             ($source-copy (copy_term $source-stmt))
             ($_instance
                (add-atom &inheritance_lift_instance
                   (inheritance-lift-instance-row
                      $kb $stmt-copy $source-copy))))
            (empty)))))

(: compile-inheritance-lifts-for-context
   (-[nondet]-> KB KBContext  CompiledAddition))
(= (compile-inheritance-lifts-for-context $kb $lift-kb)
   (match &inheritance_lift_instance
      (inheritance-lift-instance-row
         $kb $ground-stmt $source-stmt)
      (let* (($ground-copy (copy_term $ground-stmt))
             ($source-copy (copy_term $source-stmt)))
         (compile-inheritance-lift-instance
            $kb $lift-kb $ground-copy $source-copy))))

;; On rule addition, emit every instance already supported by stored facts and
;; retain the template for facts added later. No open lifted rule enters the KB.
(: compile-inheritance-rule-lifts
   (-[nondet]-> KB AnnotatedStatement (List Expression) (List Expression)
       CompiledAddition))
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

(: specialization-trigger? (-> Statement Bool))
(= (specialization-trigger? $premise)
   (if (is-expr $premise)
      (let $head (car-atom $premise)
         (if (is-var $head) false
            (and (specializing-predicate? $head)
               (not (== (extract-vars $premise) ())))))
      false))

(: rule-trigger-premises (-> (List Expression) (List Expression)))
(= (rule-trigger-premises ()) ())
(= (rule-trigger-premises (cons $prem $rest))
   (if (specialization-trigger? (brand Statement $prem))
      (cons $prem (rule-trigger-premises $rest))
      (rule-trigger-premises $rest)))

(: impl-premises
   (-> Statement (List Expression)))
(= (impl-premises (Implication (cons Premises $premises) (cons Conclusions $_conclusions)))
   (the (List Expression) $premises))
(: impl-conclusions
   (-> Statement (List Expression)))
(= (impl-conclusions (Implication (cons Premises $_premises) (cons Conclusions $conclusions)))
   (the (List Expression) $conclusions))

(: fact-head (-> Statement Atom))
(= (fact-head $type) (if (is-expr $type) (car-atom $type) $type))

;; Both structural rules and Inheritance lifts use the same indexed template
;; store. A job carries the emitter to run after its trigger list is grounded.
;; Keeping the triggers with the job lets a newly added fact use this one path
;; regardless of which compiler feature requested specialization.
(: specialization-template-registered?
   (-> KB Atom SpecializationJob Bool))
(= (specialization-template-registered? $kb $head $job)
   (not (== (collapse
      (match &spec_template
         (specialization-template-row
            $kb $head $_triggers $stored-job)
         (if (=alpha $stored-job $job) true (empty)))) ())))

(: register-specialization-templates!
   (-> KB (List Expression) (List Expression) SpecializationJob
       (| Bool (List $no-result))))
(= (register-specialization-templates! $_kb () $_triggers $_job) ())
(= (register-specialization-templates! $kb (cons $trigger $rest) $triggers $job)
   (let $head (fact-head (brand Statement $trigger))
      (let $_register
         (if (specialization-template-registered? $kb $head $job) ()
            (let*
               ((($triggers-copy $job-copy)
                   (copy_term (quote ($triggers $job)))))
               (once
                  (add-atom &spec_template
                     (specialization-template-row
                        $kb $head $triggers-copy $job-copy)))))
         (register-specialization-templates! $kb $rest $triggers $job))))

;; Idempotency is per grounded statement, not merely per rule type: distinct
;; proof ids or TVs are independent evidence even when their types coincide.
;; The rule-add and fact-add paths may discover the same statement, so retain
;; the full statement as the stable deduplication key.
(: spec-done? (-> KB AnnotatedStatement Bool))
(= (spec-done? $kb $gstmt)
   (not
      (== (collapse
             (match &spec_done
                (specialization-done-row $kb $stored)
                (if (=alpha $stored $gstmt) true (empty))))
          ())))

(: mark-spec-done! (-> KB AnnotatedStatement Bool))
(= (mark-spec-done! $kb $gstmt)
   (let $copy (copy_term $gstmt)
      (once
         (add-atom &spec_done
            (specialization-done-row $kb $copy)))))

;; Compiler backends may contribute additional fact providers for structural
;; specialization. PeTTaChainer's default provider reads its native KB; MM2
;; adds a provider that reads compiler metadata directly from MORK.
(: compiler-specialization-fact
   (-[nondet]-> KB Statement  Statement))
(= (compiler-specialization-fact $kb $trigger)
   (match &kb ($candidate ($kb $_ctx $_vars) $_prf $_tv)
      (let $typed-candidate (brand Statement $candidate)
         (let $trigger $typed-candidate
            $typed-candidate))))

;; Bind the trigger variables by matching each remaining trigger against the
;; compiler-visible fact providers; $body shares those variables, so it comes
;; out ground.
(: ground-triggers
   (-[nondet]-> KB (List Expression) SpecializationJob
       SpecializationJob))
(= (ground-triggers $_kb () $body) $body)
(= (ground-triggers $kb (cons $trigger $rest) $body)
   (let $candidate
      (compiler-specialization-fact $kb (brand Statement $trigger))
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
(: specialize-rule-add
   (-[nondet]-> KB (List Expression) SpecializationJob
       CompiledAddition))
(= (specialize-rule-add $kb $triggers $job)
   (let $_register
      (register-specialization-templates! $kb $triggers $triggers $job)
      (emit-specialization $kb (ground-triggers $kb $triggers $job))))

;; Fact-add: the new fact is not in &kb yet, so pin the trigger it satisfies
;; directly in each compatible position, then resolve the remaining triggers
;; against the store.
(: ground-specialization-with-fact
   (-[nondet]-> KB Statement (List Expression) (List Expression) SpecializationJob
       SpecializationJob))
(= (ground-specialization-with-fact $_kb $_fact () $_before $_job) (empty))
(= (ground-specialization-with-fact $kb $fact
      (cons $trigger $rest) $before $job)
   (superpose
      ((let $_ (let $trigger $fact ok)
          (ground-triggers $kb (append $before $rest) $job))
       (ground-specialization-with-fact $kb $fact $rest
          (append $before ($trigger)) $job))))

(: compile-specialization-fact-triggers
   (-[nondet]-> KB Statement  CompiledAddition))
(= (compile-specialization-fact-triggers $kb $type)
   (let $head (fact-head $type)
      (match &spec_template
         (specialization-template-row
            $kb $head $stored-triggers $stored-job)
         (let
            ($triggers $job)
            (copy_term
               (quote ($stored-triggers $stored-job)))
            (emit-specialization $kb
               (ground-specialization-with-fact
                  $kb $type $triggers ()
                  $job))))))

;; Retraction support for the unified specialization store. Templates and
;; grounded completion markers must disappear with their source statement;
;; otherwise a later fact can resurrect a removed rule, and a clean re-add can
;; be suppressed by stale idempotency state.
(: specialization-statement-name
   (-> (| AnnotatedStatement NoSpecializationStatement)
       (| Proof NoSpecializationName)))
(= (specialization-statement-name $stmt)
   (case $stmt (((: $name $_type $_tv) $name) ($_other no-specialization-name))))

(: specialization-job-name
   (-> (| SpecializationJob NoSpecializationJob)
       (| Proof NoSpecializationName)))
(= (specialization-job-name $job)
   (case $job (
      ((compile-specialization $stmt) (specialization-statement-name $stmt))
      ((inheritance-lift-specialization $_ground $source) (specialization-statement-name $source))
      ($_other no-specialization-name))))

(: remove-specialization-state! (-> Proof (List $none)))
(= (remove-specialization-state! $name)
   (let*
      (($_templates
          (collapse
             (match &spec_template
                (specialization-template-row
                   $kb $head $triggers $job)
                (if (== (specialization-job-name
                           $job)
                        $name)
                   (remove-atom &spec_template
                      (specialization-template-row
                         $kb $head $triggers $job))
                   (empty)))))
       ($_done
          (collapse
             (match &spec_done
                (specialization-done-row $kb $stmt)
                (if (== (specialization-statement-name $stmt) $name)
                   (remove-atom &spec_done
                      (specialization-done-row $kb $stmt))
                   (empty)))))
       ($_lifts
          (collapse
             (match &inheritance_lift_instance
                (inheritance-lift-instance-row
                   $kb $stmt $source)
                (if (== (specialization-statement-name $source) $name)
                   (remove-atom &inheritance_lift_instance
                      (inheritance-lift-instance-row
                         $kb $stmt $source))
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
(: compile_ (-[nondet]-> KB AnnotatedStatement  CompiledAddition))
(= (compile_ $kb (: $prf $Type $tv))
   (if (is-var $Type) (empty)
      (if (= $Type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
       (let $triggers
          (rule-trigger-premises (the (List Expression) $premises))
        (if (not (== $triggers ()))
         (specialize-rule-add $kb $triggers
            (compile-specialization (: $prf $Type $tv)))
         (let*
            (($_evidence-reg (register-rule-evidence! $kb $prf))
             ((compiled-premises $execs $proofs $atv)
                (once
                   (lower-source-premises $kb $ctx $vars
                      (the (List Expression) $premises)
                      (the (List Expression) $conclusions))))
             ($shape-kb (make-kb-context $kb $ctx $vars))
             ($adapter-kb (kbctx $kb))
             ($a (brand Statement (seq2expr $premises)))
             ($b (brand Statement (seq2expr $conclusions)))
             ($na (skolemize $prf $b $a))
             ;; Guard inversion on the *lowered* premises: a premise that lowers to a
             ;; CPU computation (FoldAll, Compute, ...) cannot be inverted. $a is the
             ;; clean antecedent expression for base-rate patterns and never carries a
             ;; CPU head, so the check must look at $execs, not $a.
             ($skip-inverse (or (disable-inversion-proof-id? $prf) (contains-cpu? (execs-goal-type $execs)))))
	            (superpose (
	                 (compile-implication-forward-rules
	                    $kb $shape-kb $adapter-kb $prf (the TV $tv)
	                    $a $b $execs $proofs $atv)
	                 (if (not $skip-inverse)
	                    (inverse-implication
	                       $kb $prf $na $b (the TV $tv))
	                    (empty))
	                 (if (or $skip-inverse (is-var $na)) (empty)
	                    (compile-outputs
	                       (: $adapter-kb
	                          ((inverted $prf $w $pa1 $pa2) $pb2)
	                          $na $natv)))
	                 (if (or $skip-inverse (is-var $b)) (empty)
	                    (compile-adapter-chain plain
	                       (: $adapter-kb $pb2 $b $btv2)))
	                 (compile-inheritance-rule-lifts $kb (: $prf $Type $tv)
	                    (the (List Expression) $premises)
	                    (the (List Expression) $conclusions)))))))
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
                           $kb $prf
                           (brand Term $subj) (brand Term $concept)
                           (the TV $tv))
                        (empty))
                     (compile-specialization-fact-triggers $kb $Type)
                     (compile-outputs (: $fact-kb $prf $Type $tv))))
                  (superpose ((() |- ((: $fact-kb $prf $Type $tv)))
                              (compile-specialization-fact-triggers $kb $Type)
                              (compile-outputs (: $fact-kb $prf $Type $tv)))))))))))


(: implication-query-known-tv-parts
   (-> TV ImplicationQueryTVParts))
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
(: query-side
   (-> KB (| NilType (List Variable)) Bool
       (List Expression) (List Expression) QuerySide))
(= (query-side $kb $mvars $negative? $premises $conclusion-side)
   (let*
      (($ctx (nextctx))
       ($shape-kb (make-kb-context $kb $ctx $mvars))
       ((compiled-premises $execs $_proofs $_atv)
          (once (if $negative?
                   (lower-query-assumption-premises-negative $kb $ctx $mvars $premises)
                   (lower-query-assumption-premises $kb $ctx $mvars $premises))))
       ($goal-expr (brand Statement (seq2expr $conclusion-side)))
       ($adds
          (union-atom
             (query-context-premise-adds $kb $ctx $mvars $execs)
             (collapse (compile-adapter-chain query (: $shape-kb $prf $goal-expr $adapter-tv))))))
      (qside $shape-kb $prf $goal-expr $adds)))

;; The two sides of a total-implication query share one conclusion $b and differ
;; only in polarity. Returns the ground shape-kbs, $b, the fresh pos/neg proof
;; vars (used by the caller in its known goals and proof token), and all adds.
(: query-pos-neg-scaffold
   (-> KB (| NilType (List Variable))
       (List Expression) (List Expression) QueryScaffold))
(= (query-pos-neg-scaffold $kb $mvars $premises $conclusions)
   (let*
      (((qside $pos-shape-kb $pos-prf $b $pos-adds)
          (query-side $kb $mvars false $premises $conclusions))
       ((qside $neg-shape-kb $neg-prf $_b $neg-adds)
          (query-side $kb $mvars true $premises $conclusions)))
      (query-scaffold $pos-shape-kb $neg-shape-kb $b $pos-prf $neg-prf
         (union-atom $pos-adds $neg-adds))))

(: compile-inheritance-query
   (-> KB Term Term
       CompiledQueryParts))
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
                 (quote
                    ($kb
                       $member-sample-pattern
                       (extract-value $member-sample-pattern
                          (WeightedTv $member-atv $member-btv))
                       (BaseRateEvidence 0.0 0.0)
                       WeightedBaseRateAcc
                       (member-inheritance $kb)
                       result-tv))
                 $member-fold-tv)
            (CPU MemberInheritanceEvidenceFormula
               ($member-fold-tv) $member-tv))
             |- ($member-goal)))
       ($member-adds
          (cons (brand CompiledAddition $member-sample-rule)
             (cons (brand CompiledAddition $member-rule) ())))
       ($premises ((Inheritance $x $subj)))
       ($conclusions ((Inheritance $x $concept)))
       ($mvars (cons (brand Variable $x) ()))
       ((query-scaffold $pos-shape-kb $neg-shape-kb $b $pos-prf $neg-prf $all-adds)
          (query-pos-neg-scaffold $kb $mvars
             (the (List Expression) $premises)
             (the (List Expression) $conclusions)))
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
      ($induction-rule
         (brand CompiledAddition
            ((quote ($known-pos-goal $known-neg-goal)) |- ($induction-goal)))))
      (compiled-query-parts
         ()
         $goal
         (union-compiled-additions $member-adds
            (union-compiled-additions $all-adds
               (union-compiled-additions $lift-adds ($induction-rule)))))))

;; Compile a public query into one goal rule plus temporary additions.
;; Implication queries require positive and refuting assumption contexts;
;; bidirectional queries require one context per direction. A concrete
;; Inheritance query accepts only the total-implication producer plus the
;; explicitly separate Member producer; ordinary direct proofs cannot answer
;; its constrained root goal.
;; Ordinary queries remain a direct known goal with only the adapters their
;; source syntax requires.
(: compileQuery
   (-[nondet]-> KB AnnotatedStatement  CompiledQueryParts))
(= (compileQuery $kb (: $prf $Type $tv))
   (if (is-var $Type)
      (compiled-query-parts
         ()
         (: (kbctx $kb) $prf $Type $tv)
         ())
      (if (= $Type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (($vars (extract-vars $Type))
             ($mvars (query-variables $vars))
             ((query-scaffold $pos-shape-kb $neg-shape-kb $b $pos-prf $neg-prf $all-adds)
                (query-pos-neg-scaffold $kb $mvars
                   (the (List Expression) $premises)
                   (the (List Expression) $conclusions)))
             ((implication-query-tv-parts $known-pos-tv $known-neg-tv $known-tv)
                (implication-query-known-tv-parts (the TV $tv)))
             ($known-pos-goal (: $pos-shape-kb $pos-prf $b $known-pos-tv))
             ($known-neg-goal (: $neg-shape-kb $neg-prf $b $known-neg-tv))
             ;; The two contextual answers are alternative evaluations of one
             ;; conditional, not independent conjuncts. Mark their combining
             ;; frontier so shared source facts remain admissible.
             ($known-goal (: (kbctx $kb)
                (total-implication-frontier
                   (total-implication $pos-prf $neg-prf))
                $Type $known-tv)))
            (compiled-query-parts
               ($known-pos-goal $known-neg-goal)
               $known-goal
               $all-adds))
         (if (bidirectional-implication-type? $Type)
            (let ($_head (cons Premises $left) (cons Conclusions $right)) $Type
               (let*
                  (($vars (extract-vars $Type))
                    ($mvars (query-variables $vars))
                    ((qside $left-shape-kb $left-prf $left-goal-expr $left-adds)
                       (query-side $kb $mvars false
                          (the (List Expression) $left)
                          (the (List Expression) $right)))
                    ((qside $right-shape-kb $right-prf $right-goal-expr $right-adds)
                       (query-side $kb $mvars false
                          (the (List Expression) $right)
                          (the (List Expression) $left)))
                    ($left-goal (: $left-shape-kb $left-prf $left-goal-expr $left-tv))
                    ($right-goal (: $right-shape-kb $right-prf $right-goal-expr $right-tv))
                    ($goal (: (kbctx $kb) (bidirectional $left-prf $right-prf) $Type $tv)))
                  (compiled-query-parts
                     ($left-goal $right-goal
                        (CPU AndFormula ($left-tv $right-tv) $tv))
                     $goal
                     (union-compiled-additions $left-adds $right-adds))))
            (if (and (= $Type (Inheritance $subj $concept)) (concrete-inheritance-link? $subj $concept))
               (compile-inheritance-query
                  $kb (brand Term $subj) (brand Term $concept))
               (compiled-query-parts
                  ()
                  (: (kbctx $kb) $prf $Type $tv)
                  (compile-query-adds
                     (: (kbctx $kb) $prf $Type $tv))))))))


;; Translate the external `premises |- conclusions` compiler form into the
;; single-conclusion `rules` form consumed by MORK. Facts are already
;; zero-premise conclusions and therefore need no wrapper.
(: mm2compile
   (-[nondet]-> KB AnnotatedStatement  RuntimeAddition))
(= (mm2compile $kb $stmt)
   (let $compiled (compile_ $kb $stmt)
      (mm2stmt $compiled)))

(: mm2stmt (-> CompiledAddition RuntimeAddition))
(= (mm2stmt $stmt)
   (let*
      (($prms (car-atom $stmt))
       ($ccl (car-atom (car-atom (cdr-atom (cdr-atom $stmt))))))
      (brand RuntimeAddition
         (if (== $prms ())
            $ccl
            (rules (quote ($prms |- $ccl)))))))

;; Some query additions arrive wrapped in an extra singleton list after
;; collapse. Unwrap that shape explicitly before applying the normal MM2 rule
;; conversion; treating it as a fact would install the list itself as a goal.
(: compiled-add-mm2stmt
   (-> CompiledAddition RuntimeAddition))
(= (compiled-add-mm2stmt $add)
   (if (== (cdr-atom $add) ())
      (let*
         (($rule (car-atom $add))
           ($prms (car-atom $rule))
           ($tail (cdr-atom $rule))
           ($ccls (car-atom (cdr-atom $tail)))
           ($ccl (car-atom $ccls)))
         (rules (quote ($prms |- $ccl))))
      (mm2stmt $add)))

(: compiled-adds-mm2stmts
   (-> (List CompiledAddition) (List RuntimeAddition)))
(= (compiled-adds-mm2stmts $adds)
   (map-flat compiled-add-mm2stmt $adds))

(: adds-mm2stmts
   (-> (List CompiledAddition) (List RuntimeAddition)))
(= (adds-mm2stmts $adds) (map-flat mm2stmt $adds))

(: query-temp-rule-premise (-[det]-> Statement Statement))
(= (query-temp-rule-premise $premise)
   (case $premise (((Compute $f $args $res) (Compute $f $args -> $res)) ($other $other))))

(: query-compound-type? (-> Statement Bool))
(= (query-compound-type? $type)
   (if (is-expr $type)
      (let $head (car-atom $type)
         (if (is-var $head) false (is-member $head (And Or LikelierThan))))
      false))

;; A temporary implication is needed only for compound children which cannot be
;; lowered by the normal adapter chain (computations or nested compounds).
;; Pure n-ary conjunctions use the direct query bundle in compileQuery instead,
;; avoiding a persistent synthetic implication for a query-local operation.
(: query-compound-needs-temp-rule? (-> Statement Bool))
(= (query-compound-needs-temp-rule? $term)
   (if (is-expr $term) (compound-direct-query-bundle? (cdr-atom $term)) false))

(: compound-query-temp-stmt (-> AnnotatedStatement AnnotatedStatement))
(= (compound-query-temp-stmt (: $_prf $type $_tv))
	(let $premises (map-flat query-temp-rule-premise (cdr-atom $type))
	      (: query-compound
	         (Implication (cons Premises $premises) (cons Conclusions ($type)))
	         (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))

;; Query assumptions with no caller-supplied TV are treated as certain. An
;; implication needs a CTV-shaped default because its positive and negative
;; support are tracked separately throughout the query compiler.
(: default-query-assumption-tv (-> Statement TV TV))
(= (default-query-assumption-tv $type $tv)
   (if (is-var $tv)
      (if (= $type (Implication (cons Premises $_premises) (cons Conclusions $_conclusions)))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))
         (STV 1.0 1.0))
      $tv))

;; An implication used as a query assumption must be executable inside its
;; fresh context, not merely stored as an inert contextual fact. Compile its
;; forward rule against the same shaped KB so it can consume sibling assumptions.
(: query-context-assumed-implication-rules
   (-> KB $context $variables Proof Statement TV
       (List CompiledAddition)))
(= (query-context-assumed-implication-rules $kbid $ctx $mvars $ctxprf $type $tv)
   (if (is-var $type) ()
      (if (= $type (Implication (cons Premises $premises) (cons Conclusions $conclusions)))
         (let*
            (((compiled-premises $execs $proofs $atv)
                 (once
                    (lower-source-premises $kbid $ctx $mvars
                       (the (List Expression) $premises)
                       (the (List Expression) $conclusions))))
              ($shape-kb (make-kb-context $kbid $ctx $mvars))
              ($a (brand Statement (execs-goal-type $execs)))
              ($b (brand Statement (seq2expr $conclusions))))
            (collapse
               (compile-implication-forward-rules $kbid $shape-kb $shape-kb $ctxprf $tv $a $b $execs $proofs $atv)))
         ())))

(: query-context-premise-assumption-adds
   (-> KB $context $variables Proof Statement TV
       (List CompiledAddition)))
(= (query-context-premise-assumption-adds $kbid $ctx $mvars $ctxprf $type $tv)
   (append
      ((brand CompiledAddition
          (() |- ((: (make-kb-context $kbid $ctx $mvars)
                     $ctxprf $type $tv)))))
      (query-context-assumed-implication-rules $kbid $ctx $mvars $ctxprf $type $tv)))

(: query-context-premise-adds-step
   (-> KB $context $variables
       (Number (List CompiledAddition))
       Goal
       (Number (List CompiledAddition))))
(= (query-context-premise-adds-step $kbid $ctx $mvars ($idx $adds) $premise)
   (let $ctxprf
      (brand Proof
         (if (== $idx 0) (ctx proof $ctx) (ctx proof $ctx $idx)))
      (case $premise
         (((CPU $_fun $_args $_res) ($idx $adds))
          ((: $_kb $_prf $type $tv)
             ((+ $idx 1)
                (append $adds
                   (query-context-premise-assumption-adds $kbid $ctx $mvars $ctxprf $type
                      (default-query-assumption-tv $type $tv)))))
          ($_other ($idx $adds))))))

(: query-context-premise-adds
   (-> KB $context $variables
       (List Goal)
       (List CompiledAddition)))
(= (query-context-premise-adds $kbid $ctx $mvars $premises)
   (let*
      (($state (fold-flat (query-context-premise-adds-step $kbid $ctx $mvars) (0 ()) $premises)))
      (snd $state)))

;; Normalize the few structural result shapes produced by compileQuery into a
;; uniform `(compiled-query goal additions)` value. The middle case introduces
;; a fresh contextual witness when the compiler returned a rule whose premise
;; is the queried fact itself.
(: mm2compileQuery-from-direct
   (-> KB AnnotatedStatement (List Goal) Goal
       (List CompiledAddition) CompiledQuery))
(= (mm2compileQuery-from-direct $kb $_stmt $premises $conclusion $adds)
   (case ($premises $conclusion)
      (((((: ($kbid $_ctx $_vars) $prf $type $tv))
          (: ($kbid $_ctx $_vars) $prf1 $type1 $tv1))
         (let*
            (($vars (extract-vars $type))
             ($mvars (query-variables $vars))
             ($ctx (nextctx))
             ($ctxatom
                (: (make-kb-context (brand KB $kbid) $ctx $mvars)
                   (brand Proof (ctx proof $ctx))
                   (brand Statement $type) $tv))
             ($goal
                (: (make-kb-context (brand KB $kbid) $ctx $mvars)
                   (brand Proof $prf1) (brand Statement $type1) $tv1))
             ($all-adds
                (cons
                   (internalize-goal-addition $ctxatom)
                   (map-flat compile-internalize-runtime-addition
                      (adds-mm2stmts $adds)))))
            (compiled-query
               (internalize-proof-structure $goal)
               $all-adds)))
       ($_other
          (mm2compileQuery-from-direct-default
             $premises $conclusion $adds)))))

(: mm2compileQuery-from-direct-default
   (-> (List Goal) Goal
       (List CompiledAddition) CompiledQuery))
(= (mm2compileQuery-from-direct-default $premises $conclusion $adds)
   (compiled-query
      (internalize-proof-structure $conclusion)
      (map-flat compile-internalize-runtime-addition
         (if (== $premises ())
            (compiled-adds-mm2stmts $adds)
            (let $rule
               (brand CompiledAddition
                  (quote ($premises |- ($conclusion))))
               (cons
                  (mm2stmt $rule)
                  (compiled-adds-mm2stmts $adds)))))))

(: mm2compileQuery-from-compiled
   (-> KB AnnotatedStatement CompiledQueryParts CompiledQuery))
(= (mm2compileQuery-from-compiled
      $kb $stmt
      (compiled-query-parts $premises $conclusion $adds))
   (mm2compileQuery-from-direct
      $kb $stmt $premises $conclusion $adds))

;; MM2 query entry point. Compound queries with computed/nested children take
;; the temporary-rule route; all other statements use compileQuery and the
;; structural normalization above.
(: mm2compileQuery (-[nondet]-> KB AnnotatedStatement  CompiledQuery))
(= (mm2compileQuery $kb $stmt)
   (case $stmt (
      ((: $prf $type $tv)
         (if (query-compound-type? $type)
            (if (query-compound-needs-temp-rule? $type)
               (compiled-query
                  (internalize-proof-structure
                     (: (kbctx $kb) $prf $type $tv))
                  (map-flat compile-internalize-runtime-addition
                     (collapse (mm2compile $kb (compound-query-temp-stmt $stmt)))))
               (mm2compileQuery-from-compiled $kb $stmt (compileQuery $kb $stmt)))
            (mm2compileQuery-from-compiled $kb $stmt (compileQuery $kb $stmt))))
      ($_ (mm2compileQuery-from-compiled $kb $stmt (compileQuery $kb $stmt))))))

(: mf
   (-> KBContext (KBContext Statement) Statement))
(= (mf $kb ($kb $t)) $t)

;; MORK indexes facts as `(type kb proof tv)`, whereas the public/compiler form
;; is `(: kb proof type tv)`. Convert recursively because these atoms may appear
;; inside generated rules and query additions, not only at the top level.
(: internalize-proof-structure
   (-> Goal
       (Statement KBContext Proof TV)))
(= (internalize-proof-structure (: $kb $proof $statement $truth-value))
   (internalize-proof-fields $kb $proof $statement $truth-value))

(: internalize-proof-fields
   (-> KBContext Proof Statement TV
       (Statement KBContext Proof TV)))
(= (internalize-proof-fields $kb $proof $statement $truth-value)
   (quote ($statement $kb $proof $truth-value)))

(: internalize-goal-addition
   (-> Goal RuntimeAddition))
(= (internalize-goal-addition $goal)
   (brand RuntimeAddition
      (internalize-proof-structure $goal)))

(: compile-internalize-runtime-addition
   (-> RuntimeAddition RuntimeAddition))
(= (compile-internalize-runtime-addition $addition)
   (brand RuntimeAddition
      (internalize-proof-structure-any $addition)))

(: internalize-proof-structure-any
   (-> (| Atom Expression) (| Atom Expression)))
(= (internalize-proof-structure-any $term)
   (if (== $term ()) ()
      (if (is-var $term) $term
      (if (= $term (: $kb $prf $type $tv)) (quote ($type $kb $prf $tv))
         (if (is-expr $term)
            (cons
               (internalize-proof-structure-any
                  (the (| Atom Expression) (car-atom $term)))
               (internalize-proof-structure-list
                  (the (List (| Atom Expression)) (cdr-atom $term))))
            $term)))))

(: internalize-proof-structure-list
   (-> (List (| Atom Expression)) (List (| Atom Expression))))
(= (internalize-proof-structure-list ()) ())
(= (internalize-proof-structure-list (cons $head $rest))
   (cons
      (internalize-proof-structure-any $head)
      (internalize-proof-structure-list $rest)))

;; Reverse the runtime tuple layout for diagnostics and public results. Only a
;; shaped KB can be recognized safely; arbitrary four-element expressions must
;; remain untouched.
(: externalize-query-proof (-> Proof Proof))
(= (externalize-query-proof $proof)
   (if (is-var $proof) (brand Proof $proof)
      (if (= $proof (inheritance-query-result $inner))
         (externalize-query-proof (brand Proof $inner))
         (if (= $proof (total-implication-frontier $inner))
            (externalize-query-proof (brand Proof $inner))
         (if (is-expr $proof)
            (brand Proof
               (cons
                  (externalize-query-proof-child
                     (car-atom $proof))
                  (map-flat externalize-query-proof-child
                     (cdr-atom $proof))))
            (brand Proof $proof))))))

(: externalize-query-proof-child (-> $child Proof))
(= (externalize-query-proof-child $child)
   (externalize-query-proof (brand Proof $child)))

(: externalize-proof-structure-core (-> $term $term))
(= (externalize-proof-structure-core $term)
   (once
      (if (== $term ()) ()
         (if (is-var $term) $term
         (if (= $term ($type $kb $prf $tv))
            (if (and (is-expr $kb) (= $kb ($kbid $ctx $vars)))
               (: ($kbid $ctx $vars)
                  (externalize-query-proof (brand Proof $prf))
                  $type $tv)
               $term)
            (if (is-expr $term)
               (cons (externalize-proof-structure-core (car-atom $term))
                  (externalize-proof-structure-list-core (cdr-atom $term)))
               $term))))))

(: externalize-proof-structure-list-core
   (-> (List $term) (List $term)))
(= (externalize-proof-structure-list-core $terms)
   (if (== $terms ()) ()
      (cons (externalize-proof-structure-core (car-atom $terms))
         (externalize-proof-structure-list-core (cdr-atom $terms)))))

(: externalize-proof-structure (-> Expression Expression))
(= (externalize-proof-structure $term)
   (externalize-proof-structure-core $term))

(: pretty (-> Expression AnnotatedStatement))
(= (pretty (: $prf $type $tv)) (: $prf $type $tv))
(= (pretty (rules ($args |- $goal))) (pretty $goal))
(= (pretty (: $kb $prf $type $tv))
   (once
      (if (is-expr $kb)
         (if (= $kb ($kbid MAIN Nil)) (: $prf $type $tv)
            (let*
               (($idx (car-atom (cdr-atom $kb)))
                 ($vars (car-atom (cdr-atom (cdr-atom $kb))))
                 ($x (map-flat (mf $kb) (collapse (match &kb ($t $kb $p $tv2) ($kb $t)))))
                 ($ptype (Implication (cons Premises $x) (cons Conclusions ($type)))))
               (: $prf $ptype $tv)))
         (: $prf $type $tv))))
