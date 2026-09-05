;; Source-language analysis and premise lowering.
;;
;; Compiler overview
;; -----------------
;; Statements enter through compile_ (stored facts and rules) or compileQuery
;; (temporary query goals). Source-level premises are lowered to executable
;; goals plus a combined TV and proof token. Adapter rules bridge compound or
;; computed source expressions to the simple fact shape consumed by the
;; chainer. mm2compile/mm2compileQuery then translate that external compiler
;; representation to the tuple layout used by the MORK runtime.

;; Structural names for compiler products that cross several lowering stages.
;; They expand to positional products and add no runtime constructors.
(: CompiledPremise
   (Alias (Goal TV Proof)))
(: CompiledPremises
   (Alias ((List Goal) (List Proof) TV)))
(: CompilationPlan Type)
(: compilation-plan
   (-[det]-> Goal (List CompiledAddition) CompilationPlan))

(: atom_concat (-[det]-> Atom Atom Atom))
(: term_hash (-[det]-> $expression Number))

;; The runtime `reverse` relation has no strict-det declaration. Keep this
;; proper-list view at the compiler boundary so callers remain deterministic.
(: prepend-reversed-goals
   (-[det]-> (List Goal) (List Goal) (List Goal)))
(= (prepend-reversed-goals () $acc) $acc)
(= (prepend-reversed-goals (cons $head $tail) $acc)
   (prepend-reversed-goals $tail (cons $head $acc)))

(: prepend-reversed-proofs
   (-[det]-> (List Proof) (List Proof) (List Proof)))
(= (prepend-reversed-proofs () $acc) $acc)
(= (prepend-reversed-proofs (cons $head $tail) $acc)
   (prepend-reversed-proofs $tail (cons $head $acc)))

(: prepend-reversed-compiled-additions
   (-[det]-> (List CompiledAddition) (List CompiledAddition)
       (List CompiledAddition)))
(= (prepend-reversed-compiled-additions () $acc) $acc)
(= (prepend-reversed-compiled-additions (cons $head $tail) $acc)
   (prepend-reversed-compiled-additions
      $tail (cons $head $acc)))

(: append-goals
   (-[det]-> (List Goal) (List Goal) (List Goal)))
(= (append-goals () $right) $right)
(= (append-goals (cons $head $tail) $right)
   (cons $head (append-goals $tail $right)))

(: finish-reversed-compiled-premises
   (-[det]-> CompiledPremises CompiledPremises))
(= (finish-reversed-compiled-premises
      ($reversed-execs $reversed-proofs $tv))
   (data
      (prepend-reversed-goals $reversed-execs ())
      (prepend-reversed-proofs $reversed-proofs ())
      $tv))

(: union-compiled-additions
   (-[det]-> (List CompiledAddition) (List CompiledAddition)
       (List CompiledAddition)))
(: append-compiled-additions
   (-[det]-> (List CompiledAddition) (List CompiledAddition)
       (List CompiledAddition)))
(= (append-compiled-additions () $right) $right)
(= (append-compiled-additions (cons $head $tail) $right)
   (cons $head
      (append-compiled-additions $tail $right)))

(= (union-compiled-additions $left $right)
   (list_to_set
      (append-compiled-additions $left $right)))

(: query-variables
   (-[det]-> (List Variable) (| NilType (List Variable))))
(= (query-variables $variables)
   (if (== $variables ()) Nil $variables))

;; Allocate a distinct context for assumptions introduced while compiling an
;; implication query. Contexts must not be shared because their assumed facts
;; are query-local.
(: nextctx (-[det]-> Number))
(= (nextctx)
   (let*
      (($state-values
          (collapse (catch (get-state ctxid))))
       ($n
          (if (== $state-values ())
             0
             (if-error-number
                (car-atom $state-values) 0))))
      (progn (change-state! ctxid (+ $n 1)) $n)))

(: collect-var-step
   (-[det]-> (List Variable) Atom (List Variable)))
(= (collect-var-step $accum $arg)
   (if (is-var $arg)
      (cons (brand Variable $arg) $accum)
      $accum))

(: extract-vars (-[det]-> Atom (List Variable)))
;; Ground terms need no source walk. An open native closure remains opaque,
;; so failed groundness checks still use source-expression traversal.
(= (extract-vars $expr)
   (if (is-ground $expr) ()
      (if (is-var $expr) (cons (brand Variable $expr) ())
         (if (is-expr $expr)
            (fold-nested collect-var-step () $expr)
            ()))))

;; Source existential binders use `(Exists ($x $y ...) body)`. Keep the binder
;; explicit until rule lowering so its declared scope is available to premise
;; aggregation and conclusion witness generation.
(: explicit-exists-vars-list
   (-[semidet]-> (List Atom) (List Variable)))
(: explicit-exists-vars
   (-[semidet]-> Atom (List Variable)))
(= (explicit-exists-vars $binder)
   (if (is-expr $binder)
      (explicit-exists-vars-list
         (the (List Atom) $binder))
      (empty)))

(= (explicit-exists-vars-list ()) ())
(= (explicit-exists-vars-list (cons $var $rest))
   (if (is-var $var)
      (cons
         (brand Variable $var)
         (explicit-exists-vars-list $rest))
      (empty)))

(: head-is? (-[det]-> Atom Atom Bool))
(= (head-is? $term $expected)
   (if (== $term ()) false
      (if (is-expr $term)
         (let $head (car-atom $term)
            (if (is-var $head) false (== $head $expected)))
         false)))

(: explicit-exists-term? (-[det]-> Atom Bool))
(= (explicit-exists-term? $term)
   (head-is? $term Exists))

(: head-is-member? (-[det]-> Atom (List Atom) Bool))
(= (head-is-member? $term $heads)
   (if (== $term ()) false
      (if (is-expr $term)
         (let $head (car-atom $term)
            (if (is-var $head) false
               (not
                  (==
                     (/==\
                        (the (List Atom) (cons $head ()))
                        $heads)
                     ()))))
         false)))

(: contains-head-list?
   (-[det]-> (-[det]-> Atom Bool) (List Atom) Bool))
(: contains-head? (-[det]-> (-[det]-> Atom Bool) Atom Bool))
(= (contains-head-list? $_predicate ()) false)
(= (contains-head-list? $predicate (cons $head $rest))
   (if (contains-head? $predicate $head)
      true
      (contains-head-list? $predicate $rest)))

(= (contains-head? $predicate $term)
   (if (== $term ()) false
      (if (is-var $term) false
         (if (is-expr $term)
            (let $head (car-atom $term)
               (if (if (is-var $head) false ($predicate $head))
                  true
                  (contains-head-list? $predicate (cdr-atom $term))))
            false))))

(: contains-explicit-exists? (-[det]-> Atom Bool))
(= (contains-explicit-exists? $term)
   (contains-head? (== Exists) $term))

;; Existentials are source forms only around one complete side of a stored
;; implication. Nested binders and quantified queries need different
;; introduction/elimination rules and must not silently compile as predicates.
(: validate-explicit-exists-term
   (-[semidet]-> Atom Atom))
(= (validate-explicit-exists-term $term)
   (if (explicit-exists-term? $term)
      (let (Exists $binder $body) $term
         (let $bound-vars (explicit-exists-vars $binder)
            (if (== $bound-vars ())
               (empty)
               (if (contains-explicit-exists? $body)
                  (empty)
                  $term))))
      (if (contains-explicit-exists? $term)
         (empty)
         $term)))

(: validate-explicit-exists-side
   (-[semidet]-> Atom Atom Atom))
(= (validate-explicit-exists-side $outside $side)
   (let $validated (validate-explicit-exists-term $side)
      (if (explicit-exists-term? $validated)
         (let (Exists $binder $_body) $validated
            (if (not
                   (==
                      (/==\
                         (explicit-exists-vars $binder)
                         (list_to_set (extract-vars $outside)))
                      ()))
               (empty)
               $validated))
         $validated)))

(: validate-explicit-exists-rule
   (-[semidet]-> Atom Atom Bool))
(= (validate-explicit-exists-rule $antecedent $consequent)
   (let* (($_antecedent-valid
              (validate-explicit-exists-side
                 $consequent $antecedent))
           ($_consequent-valid
              (validate-explicit-exists-side
                 $antecedent $consequent)))
      true))

;; Runtime rule shapes and base-rate patterns do not carry source binders.
;; Existential premises select aggregation during lowering.  Existential
;; conclusions retain a proposition-level wrapper so existence is not confused
;; with an assertion about one concrete Skolem object.
(: implication-source-term (-[det]-> Atom Atom))
(= (implication-source-term $term)
   (if (explicit-exists-term? $term)
      (ExistentialClaim
         (car-atom (cdr-atom (cdr-atom $term))))
      $term))

;; Variables bound by an existential antecedent are consumed by aggregation
;; and therefore cannot become dependencies of a generated conclusion witness.
(: implication-antecedent-free-vars
   (-[semidet]-> Atom (List Variable)))
(= (implication-antecedent-free-vars $antecedent)
   (if (head-is-member?
          $antecedent (Exists KnownExistential ExistentialResidual))
      (let ($_head $binder $body) $antecedent
         (the (List Variable)
            (\== (list_to_set (extract-vars $body))
                 (list_to_set (explicit-exists-vars $binder)))))
      (list_to_set (extract-vars $antecedent))))

(: SkolemizeState (Newtype (Number Statement)))

;; Replace variables which occur only in one direction's conclusion with
;; stable `exists` witnesses. The witness depends on the rule, its index, and
;; the variables retained from that direction's premise, so unrelated inputs
;; do not unify their existential objects.
(: skolemize-step
   (-[det]-> Proof (List Variable) SkolemizeState Variable SkolemizeState))
(= (skolemize-step $rule $avars $state $elem)
   (let*
      (($idx (fst $state))
       ($atom (snd $state))
       ($elem (exists $rule $idx $avars)))
      (brand SkolemizeState ((+ 1 $idx) $atom))))

;; ExistentialClaim bodies use canonical slots rather than Skolem terms.  Two
;; independent rules proving the same quantified body therefore meet at the
;; same proposition, while no slot can be mistaken for an ordinary object.
(: existential-slot-step
   (-[det]-> Proof (List Variable) SkolemizeState Variable SkolemizeState))
(= (existential-slot-step $_rule $_avars $state $elem)
   (let*
      (($idx (fst $state))
       ($atom (snd $state))
       ($elem (exists-slot $idx)))
      (brand SkolemizeState ((+ 1 $idx) $atom))))

(: skolemize-conclusion-vars
   (-[det]-> Proof (List Variable) Statement Statement))
(= (skolemize-conclusion-vars $rule $avars $exprb)
   (if (is-var $exprb) $exprb
      (let*
         (($bvars (list_to_set (extract-vars $exprb)))
           ($onlyb (\== $bvars $avars))
           ($state
              (if (head-is? $exprb ExistentialClaim)
                 (sealed $onlyb
                    (fold-flat
                       (existential-slot-step $rule $avars)
                       (brand SkolemizeState (0 $exprb))
                       $onlyb))
                 (sealed $onlyb
                    (fold-flat
                       (skolemize-step $rule $avars)
                       (brand SkolemizeState (0 $exprb))
                       $onlyb)))))
         (snd $state))))

(: remove-index (-[det]-> Number (List $item) (List $item)))
(= (remove-index $_idx ()) ())
(= (remove-index $idx (cons $head $tail))
   (if (== $idx 0)
      $tail
      (cons $head (remove-index (- $idx 1) $tail))))

;; The singleton case deliberately preserves the element type; the multi-item
;; case builds an `And` expression.  This helper is genuinely polymorphic and
;; is not an executable-Goal boundary.
(: seq2expr (-[det]-> (List $element) $element))
(= (seq2expr (cons $head $tail)) (if (== $tail ()) $head (cons And (cons $head $tail))))

;; Implication sides are expressions. Callers which need to inspect individual
;; conjuncts use this view; singleton sides remain singleton lists.
(: implication-side-conjuncts (-[det]-> Statement (List Atom)))
(= (implication-side-conjuncts $side)
   (if (head-is? $side And)
      (the (List Atom) (cdr-atom $side))
      (cons $side ())))

;; A projection from a compound connective can depend on the other children as
;; evidence. Preserve all their proof identities so later overlap checks see
;; the complete dependency set, while avoiding a redundant conjunction node
;; for the one-proof case.
(: implication-proof-token (-[det]-> (List Proof) Proof))
(= (implication-proof-token $proofs)
   (case $proofs (
      (() (brand Proof cpu))
      ((cons $proof ()) $proof)
      ((cons $proof $rest)
         (brand Proof
            (cons conjunction (cons $proof $rest)))))))

;; One lowered source premise may expand into several executable goals, but it
;; still contributes one evidence value and one proof token to its caller.
(: PremiseBundle Type)
(: premise-bundle
   (-[det]-> (List Goal) TV Proof PremiseBundle))

(: projection-evidence-step
   (-[det]-> KBContext Expression
       CompiledPremises Statement
       CompiledPremises))
(= (projection-evidence-step $kb $formula
      ($execs $proofs $acc-tv)
      $elem)
   (let ($cpu $next-tv)
      (binary-tv-cpu $formula $acc-tv (the TV $tv))
      (data
         (cons $cpu
            (cons (: $kb $prf $elem $tv) $execs))
         (cons (brand Proof $prf) $proofs)
         $next-tv)))

(: projection-evidence-bundle
   (-[det]-> KBContext Atom (List Statement) PremiseBundle))
(= (projection-evidence-bundle $kb $head (cons $fst $rst))
   (let*
      ((($reversed-execs $reversed-proofs $tv)
           (fold-flat
              (projection-evidence-step $kb (atom_concat $head Formula))
              (data
                 ((: $kb $fstprf $fst $fsttv))
                 ((brand Proof $fstprf))
                 (the TV $fsttv))
              $rst))
        ($execs (prepend-reversed-goals $reversed-execs ()))
        ($proof-token
           (implication-proof-token
              (prepend-reversed-proofs $reversed-proofs ()))))
      (premise-bundle $execs $tv $proof-token)))

;; Emit projection adapters recursively for every child of a configured
;; compound output. The strong projection uses the other children as evidence;
;; And additionally exposes a weak marginal projection so independently queried
;; conjuncts can later be pooled back to their common source.
(: statement-children
   (-[det]-> Expression (List Statement)))
(= (statement-children ()) ())
(= (statement-children (cons $child $rest))
   (cons
      (brand Statement $child)
      (statement-children $rest)))

(: compile-output-children
   (-[nondet]-> KBContext Statement Atom (List Statement)
       Number (List Statement)
       CompiledAddition))
(= (compile-output-children $kb $type $head $children
      $idx (cons $elem $rest))
   (superpose (
      (let $others (remove-index $idx $children)
         (if (== $others ())
            (brand CompiledAddition
               (((: $kb $prf $type $tvin)
                    (CPU (atom_concat $head Projection) ($tvin) $tvout)) |-
                  (: $kb (proj $idx $prf) $elem $tvout)))
            (let*
               (((premise-bundle $execs $evidence-tv $evidence-proof)
                    (projection-evidence-bundle $kb $head $others))
                 ($allargs
                    (cons (: $kb $prf $type $tvin)
                       (append-goals $execs
                             ((CPU
                                (atom_concat $head Projection)
                                ($tvin $evidence-tv) $tvout)))))
                 ($proof-token ((proj $idx $prf) $evidence-proof)))
               (brand CompiledAddition
                  ($allargs |- (: $kb $proof-token $elem $tvout))))))
      (if (== $head And)
         (brand CompiledAddition
            (((: $kb $prf $type $tvin)
                 (CPU AndMarginalProjection ($tvin) $tvout)) |-
               (: $kb (marginal-proj $idx $prf) $elem $tvout)))
         (empty))
      (compile-outputs (: $kb $childprf $elem $childtv))
      (compile-output-children
         $kb $type $head $children (+ $idx 1) $rest))))

(: compile-outputs (-[nondet]-> Goal  CompiledAddition))
(= (compile-outputs (: $kb $NNprf $type $NNtv))
   (if (compound-source? $type)
      (let*
         (($head (car-atom $type))
          ($children (statement-children (cdr-atom $type))))
         (if (= (configured-compound-output-mode $head) ProjectAll)
            (compile-output-children
               $kb $type $head $children 0 $children)
            (empty)))
      (empty)))

;; CPU goals normally constrain values and therefore contribute unit evidence.
;; These formulas instead compute a TV which must participate in the enclosing
;; premise TV. Aggregates opt into that behavior through their explicit tv-mode.
(: aggregate-args-tv-mode (-[det]-> Atom AggregateTVMode))
(= (aggregate-args-tv-mode $args)
   (once
      (case $args (
         (($_kb $_pattern $_extractor $_init $_fun $_finish $tv-mode)
            (the AggregateTVMode $tv-mode))
         (($_gkb $_gpattern $_group $_gextractor $_ginit $_gfun
              $_gfinish $gtv-mode)
            (the AggregateTVMode $gtv-mode))
         ($_other unit-stv)))))

(: cpu-premise-tv
   (-[det]-> Atom Atom Atom TV))
(: checked-cpu-premise-tv (-[det]-> Atom TV))
(= (checked-cpu-premise-tv $result)
   (the TV $result))

(: binary-tv-cpu (-[det]-> Atom TV TV (Goal TV)))
(= (binary-tv-cpu $formula $left $right)
   (data
      (CPU $formula (quote ($left $right)) $result)
      (the TV $result)))

(= (cpu-premise-tv $f $args $res)
   (if (head-is-member?
          (cons $f ()) (FoldAllCompiled GroupedFoldAllCompiled))
         (if (== (aggregate-args-tv-mode $args) result-tv)
            (checked-cpu-premise-tv $res)
            (STV 1.0 1.0))
      (if (head-is-member?
             (cons $f ())
             (() NotFormula DistGreaterThanFormula
                DistGreaterThanDistFormula))
         (checked-cpu-premise-tv $res)
         (STV 1.0 1.0))))

(: make-kb-context (-[det]-> KB $context $variables KBContext))
(= (make-kb-context $kb $ctx $vars)
   (brand KBContext (quote ($kb $ctx $vars))))

(: source-premise-kb
   (-[det]-> KB $context $variables KBContext))
(= (source-premise-kb $kb $ctx $vars)
   (if (or (is-var $ctx) (is-var $vars))
      (kbctx $kb)
      (make-kb-context $kb $ctx $vars)))

;; Normalize one source premise to the compiler's common bundle:
;;   premise-bundle(executable goals, evidence TV, proof token).
;; Keeping this boundary uniform lets compound, computed, and ordinary fact
;; premises be combined by the same folds below.
(: leaf-source-bundle
   (-[det]-> KB $context $variables
       Statement PremiseBundle))
(= (leaf-source-bundle $kb $ctx $vars $elem)
   (let $prem-kb (source-premise-kb $kb $ctx $vars)
      (if (is-var $elem)
         (premise-bundle ((: $prem-kb $prf $elem $tv)) $tv $prf)
         (if (= $elem (CPU $f $args $res))
         (premise-bundle ((CPU $f $args $res))
            (cpu-premise-tv $f $args $res) cpu)
         (premise-bundle ((: $prem-kb $prf $elem $tv)) $tv $prf)))))

(: in_map
   (-[det]-> KBContext Atom CompiledPremise))
(= (in_map $kb $elem)
   (if (= $elem (CPU $f $args $res))
      (data (CPU $f $args $res)
         (cpu-premise-tv $f $args $res) cpu)
      (data
         (: $kb $prf $elem $tv)
         (the TV $tv) (brand Proof $prf))))

(: in_fold
   (-[det]-> Expression
       CompiledPremises
       CompiledPremise
       CompiledPremises))
(=
   (in_fold $formula
      ($premises $proofs $tv)
      ($goal $tve $proof))
   (let ($cpu $next-tv)
      (binary-tv-cpu $formula $tv $tve)
      (data
         (cons $cpu (cons $goal $premises))
         (cons $proof $proofs)
         $next-tv)))

(: exec-goal-type
   (-[det]-> Goal Expression))
(= (exec-goal-type (CPU $f $args $res)) (CPU $f $args $res))
(= (exec-goal-type (: $_kb $_prf $elem $_tv)) $elem)

(: execs-goal-type
   (-[det]-> (List Goal) Expression))
(= (execs-goal-type $execs) (seq2expr (map-flat exec-goal-type $execs)))

;; Reconstruct the source shape of a lowered connective without treating its
;; own TV-fold CPU goals as additional children. Real CPU children remain in
;; the shape; only the <Head>Formula bookkeeping inserted by the compound
;; lowering itself is removed.
(: compound-exec-source-types
   (-[det]-> Expression (List Goal) (List Atom)))
(= (compound-exec-source-types $_formula ()) ())
(= (compound-exec-source-types $formula (cons $goal $rest))
   (if (= $goal (CPU $fun $_args $_result))
      (if (== $fun $formula)
         (compound-exec-source-types $formula $rest)
         (cons (exec-goal-type $goal)
            (compound-exec-source-types $formula $rest)))
      (cons (exec-goal-type $goal)
         (compound-exec-source-types $formula $rest))))

;; Lower a connective whose configured premise mode is All. Every child must
;; succeed, child TVs are folded with <Head>Formula, and the proof token records
;; the conjunction of the child proofs. This is the general conjunction-
;; introduction mechanism for And premises; it is connective-generic so the
;; same machinery also serves other All-mode connectives.
(: compound-all-premise-bundle
   (-[nondet]-> KB $context $variables
       Atom Atom PremiseBundle))

(: compound-premise-items
   (-[nondet]-> KBContext Atom
       (List CompiledPremise)))
(= (compound-premise-items $kb $items)
   (case $items (
      (() ())
      ((cons $item $rest)
         (cons
            (in_map $kb (brand Statement $item))
            (compound-premise-items $kb $rest))))))

(= (compound-all-premise-bundle $kb $ctx $vars $head $tail)
   (let*
      (($prem-kb (source-premise-kb $kb $ctx $vars))
        ((cons ($fstgoal $fsttv $fstprf) $rst)
           (compound-premise-items $prem-kb $tail))
        ($init
           (data
              (cons $fstgoal ())
              (cons $fstprf ())
              $fsttv))
        (($reversed-execs $reversed-proofs $ccltv)
           (fold-flat
              (in_fold (atom_concat $head Formula))
              (the CompiledPremises $init)
              $rst))
        ($execs (prepend-reversed-goals $reversed-execs ()))
        ($proof-token
           (implication-proof-token
              (prepend-reversed-proofs $reversed-proofs ()))))
      (premise-bundle $execs $ccltv $proof-token)))

(: compound-any-premise-bundle
   (-[nondet]-> KB $context $variables Atom Atom
       PremiseBundle))
(= (compound-any-premise-bundle $kb $ctx $vars $head (cons $elem $rest))
   (superpose (
      (let*
         (($prem-kb (source-premise-kb $kb $ctx $vars))
           (($goal $tv $proof) (in_map $prem-kb $elem)))
         (premise-bundle
            ($goal) $tv ((atom_concat $head introduction) $proof)))
      (compound-any-premise-bundle $kb $ctx $vars $head $rest))))

(: compound-premise-bundle
   (-[nondet]-> KB $context $variables Atom Atom
       PremiseBundle))
(= (compound-premise-bundle $kb $ctx $vars $head $tail)
   (let $mode (configured-compound-premise-mode $head)
      (if (= $mode Any)
         (compound-any-premise-bundle $kb $ctx $vars $head $tail)
         (compound-all-premise-bundle $kb $ctx $vars $head $tail))))

;; Compound lowering is deliberately configuration-driven. Merely being an
;; expression is insufficient: ordinary predicates such as (Friend a b) must
;; remain fact lookups and must not be interpreted as logical connectives.
(: compound-source? (-[det]-> Statement Bool))
(= (compound-source? $type)
   (if (is-expr $type)
      (let $head (car-atom $type)
         (if (is-var $head)
            false
            (compound-connective? $head)))
      false))

;; Query compounds need recursive lowering because a child may itself be a
;; compound or a source-level computation. A plain predicate child stays a leaf
;; lookup so it can use the normal chainer indexes.
(: source-computation-head? (-[det]-> Atom Bool))
(= (source-computation-head? $head)
   (case $head (
      (Compute true)
      (KnownExistential true)
      (ExistentialResidual true)
      (MapDist true)
      (Map2Dist true)
      (AverageDist true)
      (FoldAllValue true)
      (FoldAll true)
      (Not true)
      (GreaterThan true)
      (> true)
      ($_other false))))

;; Forward declarations for the mutually recursive compound/source lowering
;; group.  Their implementations remain below.
(: query-compound-premise-bundle
   (-[semidet]-> KB $context $variables Atom
       (List Statement) PremiseBundle))
(: lower-source-premise
   (-[nondet]-> KB $context $variables Statement  PremiseBundle))

(: query-compound-child-bundle
   (-[semidet]-> KB $context $variables Statement PremiseBundle))
(= (query-compound-child-bundle $kb $ctx $vars $premise)
   (if (compound-source? $premise)
      (let (cons $head $tail) $premise
         (query-compound-premise-bundle
            $kb $ctx $vars $head
            (statement-children $tail)))
      (if (is-expr $premise)
         (let $head (car-atom $premise)
            (if (is-var $head)
               (leaf-source-bundle $kb $ctx $vars $premise)
               (if (source-computation-head? $head)
                  (once (lower-source-premise $kb $ctx $vars $premise))
                  (leaf-source-bundle $kb $ctx $vars $premise))))
         (leaf-source-bundle $kb $ctx $vars $premise))))

;; Accumulate a direct compound-query rule in source order. Appending both goals
;; and proofs is intentional: the returned `(conjunction ...)` proof mirrors the
;; order written by the caller, while each TV fold consumes the same ordering.
(: query-compound-premise-step
   (-[semidet]-> KB $context $variables Expression
       CompiledPremises
       Statement
       CompiledPremises))
(=
   (query-compound-premise-step $kb $ctx $vars $formula
      ($acc-execs $acc-proofs $acc-tv)
      $premise)
   (let*
      (((premise-bundle $execs $tv $proof)
          (query-compound-child-bundle
             $kb $ctx $vars
             $premise))
       (($cpu $next-tv)
          (binary-tv-cpu $formula $acc-tv $tv)))
      (data
         (cons $cpu
            (prepend-reversed-goals $execs $acc-execs))
         (cons $proof $acc-proofs)
         $next-tv)))

(= (query-compound-premise-bundle $kb $ctx $vars $head (cons $fst $rst))
   (let*
      ((($reversed-execs $reversed-proofs $ccltv)
           (fold-flat
              (query-compound-premise-step
                 $kb $ctx $vars (atom_concat $head Formula))
              (let (premise-bundle $first-execs $first-tv $first-proof)
                 (query-compound-child-bundle $kb $ctx $vars $fst)
                 (data
                    (prepend-reversed-goals $first-execs ())
                    ($first-proof) $first-tv))
              $rst))
        ($execs (prepend-reversed-goals $reversed-execs ()))
        ($proof-token
           (implication-proof-token
              (prepend-reversed-proofs $reversed-proofs ()))))
      (premise-bundle $execs $ccltv $proof-token)))

;; A direct bundle is required when normal plain adapters cannot faithfully
;; express a child: nested compounds and computations must be lowered inside
;; the query rule rather than looked up as already materialized facts.
(: query-compound-child-needs-bundle? (-[det]-> Statement Bool))
(= (query-compound-child-needs-bundle? $premise)
   (if (compound-source? $premise)
      (query-compound-needs-bundle? $premise)
      (if (is-expr $premise)
         (let $head (car-atom $premise)
            (if (is-var $head) false
               (source-computation-head? $head)))
         false)))

(: compound-direct-query-bundle? (-[det]-> (List Statement) Bool))
(= (compound-direct-query-bundle? $items)
   (if (== $items ()) false
      (case $items (
         ((cons $item $rest)
            (if (query-compound-child-needs-bundle? $item)
               true
               (compound-direct-query-bundle? $rest)))))))

;; Three-or-more-child compound queries are also lowered directly. The ordinary
;; adapter path was designed around binary rule shapes; forcing an n-ary query
;; through it can lose the complete ordered proof bundle. This is the explicit
;; specialization which makes `(And A B C ...)` synthesize one query-local
;; conjunction-introduction rule with proof `(conjunction a b c ...)`.
(: compound-nary-query? (-[det]-> (List Statement) Bool))
(= (compound-nary-query? $items)
   (case $items (
      ((cons $_a (cons $_b (cons $_c $_rest))) true)
      ($_ false))))

(: query-compound-needs-bundle? (-[det]-> Statement Bool))
(= (query-compound-needs-bundle? $term)
   (if (is-expr $term)
      (let $items
         (statement-children (cdr-atom $term))
         (if (compound-nary-query? $items)
            true
            (compound-direct-query-bundle? $items)))
      false))

;; An open proof variable should be replaced by the generated bundle itself.
;; A named/structured query proof is instead retained as an outer provenance
;; label around that bundle.
(: query-compound-proof-token (-[det]-> Proof Proof Proof))
(= (query-compound-proof-token $prf $proof-token)
   (if (is-var $prf)
      $proof-token
      (brand Proof (quote ($prf $proof-token)))))

;; Build reusable adapters for source expressions found in stored rules. Each
;; adapter derives the requested compound from its lowered children. Recursing
;; on a different executable type ensures any intermediate source syntax also
;; receives an adapter, without regenerating the identical rule.
(: AdapterMode Type)
(: plain AdapterMode)
(: query AdapterMode)

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
                    $kbid $ctx $vars $head $tail))
              ($exec-type
                 (seq2expr
                    (compound-exec-source-types
                       (atom_concat $head Formula) $execs))))
            (superpose
               ((brand CompiledAddition
                    ($execs |-
                       (: $kb $proof-token $type $result-tv)))
                (if (== $exec-type $type) (empty)
                   (compile-adapter-chain plain
                      (: $kb $prfa $exec-type $atv)))))))
      (empty)))

;; Query adapters differ from stored-rule adapters in three places:
;; 1. Not is exposed as an explicit negated proof;
;; 2. complex/n-ary compounds get one query-local direct bundle; and
;; 3. other computed source forms are lowered and bridged only when their
;;    executable goal shape differs from the requested source expression.
(= (compile-adapter-chain query (: $kb $prf $type $tv))
   (if (head-is? $type Not)
      (let $a (car-atom (cdr-atom $type))
         (brand CompiledAddition
            (((: $kb $inner-prf $a $inner-tv)
                 (CPU NotFormula ($inner-tv) $tv))
               |-
               (: $kb (negated $inner-prf) $type $tv))))
      (if (compound-source? $type)
         (if (query-compound-needs-bundle? $type)
            (let*
               (((cons $head $tail) $type)
                 ((premise-bundle $execs $result-tv $proof-token)
                    (let ($kbid $ctx $vars) $kb
                       (once
                          (query-compound-premise-bundle
                             $kbid $ctx $vars $head
                             (statement-children $tail))))))
               (brand CompiledAddition
                  ($execs |-
                     (: $kb
                         (query-compound-proof-token $prf $proof-token)
                         $type $result-tv))))
            (compile-adapter-chain plain (: $kb $prf $type $tv)))
         (let*
            (((premise-bundle $execs $result-tv $proof-token)
                 (let ($kbid $ctx $vars) $kb
                    (once
                       (lower-source-premise
                          $kbid $ctx $vars $type))))
              ($exec-type (execs-goal-type $execs)))
            (if (if (is-var $type)
                   false
                   (not (== $exec-type $type)))
               (superpose ((brand CompiledAddition
                              ($execs |-
                                 (: $kb ($prf $proof-token) $type $result-tv)))
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
           ((Implication $_antecedent $_consequent)
              (leaf-source-bundle $kb $ctx $vars $premise))
           ((KnownExistential $binder $body)
              (let $bound-vars
                 (list_to_set (explicit-exists-vars $binder))
                 (if (== $bound-vars ())
                    (empty)
                    (fold-existential-premise-bundle
                       $kb $ctx $vars (brand Statement $body)
                       (\==
                          (list_to_set (extract-vars $body))
                          $bound-vars)))))
           ((ExistentialResidual $binder $body)
              (existential-residual-premise-bundle
                 $kb $ctx $vars $binder $body))
           ((Compute $f $args -> $res)
              (premise-bundle ((CPU $f $args $res))
                 (cpu-premise-tv $f $args $res) cpu))
           ((Compute $f $args $res)
              (lower-source-premise-non-open
                 $kb $ctx $vars
                 (brand Statement (Compute $f $args -> $res))))
           ((MapDist $fun $a $value -> $out)
              (premise-bundle
                 ((: (make-kb-context $kb $ctx $vars)
                      $prfa $a $tv_a)
                  (CPU DistMapFormula (quote ($fun $value)) $out))
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
                          unit-stv)
                       $out))
                 (STV 1.0 1.0)
                 cpu))
           ((FoldAllValue $pattern $init $fun -> $out)
              (premise-bundle
                 ((CPU FoldAllCompiled
                       ($kb $pattern extract-tv $init $fun identity unit-stv)
                       $out))
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
(= (lower-source-premise $kb $ctx $vars $premise)
   (if (if (is-expr $premise)
          (is-var (car-atom $premise))
          false)
      (if (== (cdr-atom $premise) ())
         (leaf-source-bundle
            $kb $ctx $vars
            (brand Statement (car-atom $premise)))
         (leaf-source-bundle $kb $ctx $vars $premise))
      (lower-source-premise-non-open $kb $ctx $vars $premise)))

;; Combine premise bundles left-to-right. AndFormula is inserted only between
;; non-empty bundles so the first premise supplies the initial TV and no fake
;; unit-evidence proof is introduced.
(: append-premise-bundle
   (-[det]-> CompiledPremises PremiseBundle CompiledPremises))
(=
   (append-premise-bundle
      ($current-execs $current-proofs $current-tv)
      (premise-bundle $execs $tv $proof))
   (if (== $current-execs ())
      (data
         (prepend-reversed-goals $execs ())
         (cons $proof ()) $tv)
      (let ($cpu $next-tv)
         (binary-tv-cpu AndFormula $current-tv $tv)
         (data
            (cons $cpu
               (prepend-reversed-goals $execs $current-execs))
            (cons $proof $current-proofs)
            $next-tv))))

;; Build the canonical direct-claim statement corresponding to a source
;; binder/body pair. Free variables remain available for grouping; only bound
;; witness positions become slots.
(: existential-claim-statement
   (-[semidet]-> Atom Atom Statement))
(= (existential-claim-statement $binder $body)
   (let*
      (($bound-vars (list_to_set (explicit-exists-vars $binder)))
       ($body-vars (list_to_set (extract-vars $body)))
       ($free-vars (\== $body-vars $bound-vars)))
      (skolemize-conclusion-vars
         existential-claim $free-vars
         (brand Statement (ExistentialClaim $body)))))

;; An explicit existential premise collapses all matching witnesses with
;; OrFormula. Free variables form independent groups, while variables named by
;; the binder do not escape into the compiled rule.
(: fold-existential-premise-bundle
   (-[det]-> KB $context $variables Statement (List Variable) PremiseBundle))
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

;; A direct proposition-level existential is a second proof path for `Exists`,
;; distinct from the enumerable-witness fold. Compiling both paths lets a
;; downstream existential premise consume non-constructive existence without
;; equating its TV with the partial witness disjunction.
(: direct-existential-premise-bundle
   (-[semidet]-> KB $context $variables Atom Atom PremiseBundle))
(= (direct-existential-premise-bundle $kb $ctx $vars $binder $body)
   (let $prem-kb (source-premise-kb $kb $ctx $vars)
      (premise-bundle
         ((: $prem-kb $proof
              (existential-claim-statement $binder $body) $tv))
         $tv
         $proof)))

;; Compare the direct existential proposition with the OR of the witnesses
;; currently enumerable from the body. The direct proposition uses canonical
;; slots, so matching it cannot bind the witness variable and accidentally
;; restrict the following fold to one object.
(: existential-residual-premise-bundle
   (-[nondet]-> KB $context $variables Atom Atom PremiseBundle))
(= (existential-residual-premise-bundle $kb $ctx $vars $binder $body)
   (let*
      (($bound-vars (list_to_set (explicit-exists-vars $binder)))
       ($body-vars (list_to_set (extract-vars $body)))
       ($group-vars (\== $body-vars $bound-vars))
       ($claim (existential-claim-statement $binder $body))
       ((premise-bundle $fold-execs $known-tv $_fold-proof)
          (fold-existential-premise-bundle
             $kb $ctx $vars (brand Statement $body) $group-vars))
       ($prem-kb (source-premise-kb $kb $ctx $vars)))
      (if (== $bound-vars ())
         (empty)
         (premise-bundle
            (cons
               (: $prem-kb $direct-proof $claim $direct-tv)
               (append-goals
                  $fold-execs
                  ((CPU ExistentialResidualFormula
                       ($direct-tv $known-tv) $residual-tv))))
            $residual-tv
            (conjunction $direct-proof cpu)))))

(: lower-source-premise-with-existentials
   (-[nondet]-> KB $context $variables Statement  PremiseBundle))
(= (lower-source-premise-with-existentials $kb $ctx $vars $premise)
   (if (explicit-exists-term? $premise)
      (let* (((Exists $binder $body) $premise)
             ($bound-vars
                (list_to_set (explicit-exists-vars $binder)))
             ($body-vars
                (list_to_set (extract-vars $body)))
             ($group-vars (\== $body-vars $bound-vars)))
         (superpose
            ((direct-existential-premise-bundle
                $kb $ctx $vars $binder $body)
             (fold-existential-premise-bundle
                $kb $ctx $vars (brand Statement $body) $group-vars))))
      (lower-source-premise $kb $ctx $vars $premise)))

(: lower-implication-antecedent
   (-[nondet]-> KB $context $variables Statement CompiledPremises))
(: lower-implication-conjunct-step
   (-[nondet]-> KB $context $variables CompiledPremises Atom
       CompiledPremises))
(= (lower-implication-conjunct-step $kb $ctx $vars $acc $conjunct)
   (append-premise-bundle $acc
      (lower-source-premise
         $kb $ctx $vars (brand Statement $conjunct))))

(= (lower-implication-antecedent $kb $ctx $vars $antecedent)
   (if (head-is? $antecedent And)
      (finish-reversed-compiled-premises
         (fold-flat
            (lower-implication-conjunct-step $kb $ctx $vars)
            (data () () (STV 1.0 1.0))
            (the (List Atom) (cdr-atom $antecedent))))
      (let (premise-bundle $execs $tv $proof)
         (lower-source-premise-with-existentials
            $kb $ctx $vars $antecedent)
         (data $execs (cons $proof ()) $tv))))

;; Antecedents of an implication *query* are temporary assumptions. A positive
;; `(Not A)` assumption is represented by an A-shaped contextual fact with
;; strength zero, allowing ordinary fact matching while preserving its logical
;; truth through the bundle TV.
(: lower-query-assumption-premise
   (-[nondet]-> KB $context $variables Statement  PremiseBundle))
(= (lower-query-assumption-premise $kb $ctx $vars $premise)
   (if (if (is-expr $premise)
          (if (is-var (car-atom $premise)) false true)
          false)
      (let $head (car-atom $premise)
         (if (== $head Implication)
            (leaf-source-bundle $kb $ctx $vars $premise)
            (if (== $head Not)
               (let $prem-kb (source-premise-kb $kb $ctx $vars)
                  (premise-bundle ((: $prem-kb $prf (car-atom (cdr-atom $premise)) (STV 0.0 1.0))) (STV 1.0 1.0) $prf))
               (lower-source-premise $kb $ctx $vars $premise))))
      (lower-source-premise $kb $ctx $vars $premise)))

(: lower-query-assumption-premises
   (-[nondet]-> KB $context $variables (List Atom)
       CompiledPremises))

;; Keep the Atom-to-Statement boundary named: the strict checker otherwise
;; specializes fold-flat's input to `(List Statement)` and leaves a runtime
;; type check on callers' source `(List Atom)`.
(: lower-query-assumption-premises-step
   (-[nondet]-> KB $context $variables CompiledPremises Atom
       CompiledPremises))
(= (lower-query-assumption-premises-step $kb $ctx $vars $acc $premise)
   (append-premise-bundle $acc
      (lower-query-assumption-premise
         $kb $ctx $vars (brand Statement $premise))))

(= (lower-query-assumption-premises $kb $ctx $vars $premises)
   (finish-reversed-compiled-premises
      (fold-flat
         (lower-query-assumption-premises-step $kb $ctx $vars)
         (data () () (STV 1.0 1.0))
         $premises)))

;; Construct the refuting side of a total-implication query: the first premise
;; is assumed false and all remaining premises true. This is the counterexample
;; condition used to compute the negative component of the implication CTV.
(: lower-query-assumption-premise-false
   (-[det]-> KB $context $variables Statement PremiseBundle))
(= (lower-query-assumption-premise-false $kb $ctx $vars $premise)
   (if (if (is-expr $premise)
          (if (is-var (car-atom $premise)) false true)
          false)
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
   (-[nondet]-> KB $context $variables (List Atom)
       CompiledPremises))
(= (lower-query-assumption-premises-negative $kb $ctx $vars ())
   (data () () (STV 0.0 1.0)))
(= (lower-query-assumption-premises-negative $kb $ctx $vars (cons $premise $rest))
   (finish-reversed-compiled-premises
      (fold-flat
         (lower-query-assumption-premises-step $kb $ctx $vars)
         (append-premise-bundle
            (data () () (STV 1.0 1.0))
            (lower-query-assumption-premise-false
               $kb $ctx $vars (brand Statement $premise)))
         $rest)))

(: bidirectional-implication-type? (-[det]-> Statement Bool))
(: implication-type? (-[det]-> Statement Bool))
(= (implication-type? $type)
   (head-is? $type Implication))

(= (bidirectional-implication-type? $Type)
   (if (is-expr $Type)
      (let $head (car-atom $Type)
         (if (is-var $head)
            false
            (bidirectional-implication-form? $head)))
      false))

;; Normalize a public KB id to its default runtime shape. Query contexts already
;; arrive shaped as `(kbid ctx vars)` and must pass through unchanged.
(: existing-kb-context (-[det]-> Atom KBContext))
(= (existing-kb-context $kb)
   (brand KBContext $kb))

(: kbctx (-[det]-> Atom KBContext))
(= (kbctx $kb)
   (if (is-expr $kb)
      (existing-kb-context $kb)
      (make-kb-context (brand KB $kb) MAIN Nil)))

(: set-context-polymorphic-facts (-[det]-> KB Bool Bool))
(= (set-context-polymorphic-facts $kb $enabled)
   (let $_old
      (collapse
         (match &context_polymorphic_facts
            ($kb $stored)
            (remove-atom &context_polymorphic_facts ($kb $stored))))
      (let $_added
         (collapse
            (once
               (add-atom &context_polymorphic_facts
                  ($kb $enabled))))
         $enabled)))

(: context-polymorphic-facts? (-[det]-> KB Bool))
(= (context-polymorphic-facts? $kb)
   (not
      (==
         (collapse
            (once
               (match &context_polymorphic_facts
                  ($kb true) true)))
         ())))

;; Base-rate scans must leave ordinary open expressions intact while replacing
;; compiler-generated existential witnesses with query variables. Traverse
;; expression nodes, never their list suffixes: matching a suffix against an
;; `exists` pattern would unify ordinary variable-headed terms into open conses.
(: rule-query-pattern-list
   (-[det]-> (List $term) (List $term)))
(= (rule-query-pattern-list ()) ())
(= (rule-query-pattern-list (cons $head $rest))
   (cons
      (rule-query-pattern $head)
      (rule-query-pattern-list $rest)))

(: rule-query-pattern (-[det]-> $term $term))
(= (rule-query-pattern $term)
   (if (== $term ()) ()
   (if (is-var $term) $term
      (if (is-expr $term)
         (let*
            (($head (car-atom $term))
             ($rest (cdr-atom $term)))
            (if (== $head exists)
               (case $rest (
                  ((cons $_rule (cons $_idx (cons $_vars ()))) $query-var)
                  ($_other
                     (cons
                        (rule-query-pattern $head)
                        (rule-query-pattern-list $rest)))))
               (cons
                  (rule-query-pattern $head)
                  (rule-query-pattern-list $rest))))
         $term))))

(: contains-cpu? (-[det]-> Expression Bool))
(= (contains-cpu? $term)
   (contains-head? (== CPU) $term))
