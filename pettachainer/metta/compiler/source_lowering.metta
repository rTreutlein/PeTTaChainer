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

;; The strict determinism checker rejects the library folds over a semidet
;; step; these are their semidet forms, shared by the compiler and runtime.
(: fold-semidet (-[semidet]-> (-[semidet]-> $acc $item $acc) $acc (List $item) $acc))
(= (fold-semidet $_fun $acc ()) $acc)
(= (fold-semidet $fun $acc (cons $item $rest)) (fold-semidet $fun ($fun $acc $item) $rest))

(: map-semidet (-[semidet]-> (-[semidet]-> $input $output) (List $input) (List $output)))
(= (map-semidet $_fun ()) ())
(= (map-semidet $fun (cons $item $rest)) (cons ($fun $item) (map-semidet $fun $rest)))

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

;; The variables of an expression's elements, nested ones included, consed
;; onto the accumulator in the order they occur. A det walk commits to its
;; clause; the library fold-nested is effect-polymorphic, so each walk through
;; it left a choice point that kept its caller's frames alive.
(: collect-vars
   (-[det]-> (List Variable) Expression (List Variable)))
(= (collect-vars $accum ()) $accum)
(= (collect-vars $accum (cons $arg $rest))
   (collect-vars
      (if (is-expr $arg) (collect-vars $accum $arg)
         (if (is-var $arg) (cons (brand Variable $arg) $accum) $accum))
      $rest))

(: extract-vars (-[det]-> Atom (List Variable)))
;; Ground terms need no source walk. An open native closure remains opaque,
;; so failed groundness checks still use source-expression traversal.
(= (extract-vars $expr)
   (if (is-ground $expr) ()
      (if (is-var $expr) (cons (brand Variable $expr) ())
         (if (is-expr $expr)
            (collect-vars () $expr)
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
;; implication, or a bare query. Nested binders need further
;; introduction/elimination rules and must not silently compile as predicates.
(: validate-explicit-exists-term
   (-[semidet]-> Atom Atom))
(= (validate-explicit-exists-term $term)
   (if (explicit-exists-term? $term)
      (let (Exists $binder $body) $term
         (let $bound-vars (explicit-exists-vars $binder)
            (if (if (== $bound-vars ()) true
                   (not (== (\== $bound-vars (extract-vars $body)) ())))
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
                         (implication-antecedent-free-vars $outside))
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

;; The antecedents of the implications among a conclusion's conjuncts,
;; through nested implications: their variables are universal, bound by the
;; implication that reads them, never existential witnesses.
(: implication-binders (-[det]-> (List Atom) (List Atom) (List Atom)))
(= (implication-binders () $later) $later)
(= (implication-binders (cons $part $rest) $later)
   (let $after (implication-binders $rest $later)
      (if (head-is? $part Implication)
         (case $part (
            ((Implication $x $y) (cons $x (implication-binders (implication-side-conjuncts (brand Statement $y)) $after)))
            ($_other $after)))
         $after)))

(: skolemize-conclusion-vars
   (-[det]-> Proof (List Variable) Statement Statement))
(= (skolemize-conclusion-vars $rule $avars $exprb)
   (if (is-var $exprb) $exprb
      (let*
         (($bvars (list_to_set (extract-vars $exprb)))
           ($kept (implication-binders (implication-side-conjuncts $exprb) $avars))
           ($onlyb (\== $bvars (extract-vars $kept)))
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

(: vars-covered? (-[det]-> Atom (List Variable) Bool))
(= (vars-covered? $term $known)
   (== (\== (list_to_set (extract-vars $term)) $known) ()))

;; Implication sides are expressions. Callers which need to inspect individual
;; conjuncts use this view, through nested conjunctions: (And (And a b) c) has
;; the conjuncts of (And a b c). Singleton sides remain singleton lists.
(: conjunct-leaves (-[det]-> (List Atom) (List Atom) (List Atom)))
(= (conjunct-leaves () $later) $later)
(= (conjunct-leaves (cons $part $rest) $later)
   (let $after (conjunct-leaves $rest $later)
      (if (head-is? $part And) (conjunct-leaves (the (List Atom) (cdr-atom $part)) $after) (cons $part $after))))
(: implication-side-conjuncts (-[det]-> Statement (List Atom)))
(= (implication-side-conjuncts $side)
   (if (head-is? $side And)
      (conjunct-leaves (the (List Atom) (cdr-atom $side)) ())
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

;; A statement is stored, assumed and concluded at its canonical key: under any
;; number of negations, the statement they negate, with its value complemented
;; when the count is odd. A negation is a reading of its key, never a key.
(: canon (-[det]-> Statement (Statement Bool)))
(= (canon $statement)
   (if (head-is? $statement Not)
      (let ($key $odd) (canon (brand Statement (car-atom (cdr-atom $statement))))
         (data $key (if $odd false true)))
      (data $statement false)))

;; An addition concluding a statement concludes its canonical key: a negated
;; conclusion complements its value and negates its proof.
(: canonical-addition
   (-[det]-> KBContext (List Goal) Proof Statement Atom CompiledAddition))
(= (canonical-addition $kb $premises $proof $statement $tv)
   (let ($key $odd) (canon $statement)
      (if $odd
         (brand CompiledAddition
            ((append-goals $premises ((CPU NotFormula ($tv) $not-tv)))
               |- (: $kb (brand Proof (negated $proof)) $key $not-tv)))
         (brand CompiledAddition ($premises |- (: $kb $proof $key $tv))))))

;; One lowered source premise may expand into several executable goals, but it
;; still contributes one evidence value and one proof token to its caller.
(: PremiseBundle Type)
(: premise-bundle
   (-[det]-> (List Goal) TV Proof PremiseBundle))

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

(: lower (-[semidet]-> KBContext Statement PremiseBundle))
(: lower-all (-[semidet]-> (-[semidet]-> KBContext Statement PremiseBundle) KBContext Atom
   (List Statement) PremiseBundle))

(: compile-output-children
   (-[nondet]-> KBContext Statement Atom (List Statement)
       Number (List Statement)
       CompiledAddition))
(= (compile-output-children $kb $type $head $children
      $idx (cons $elem $rest))
   (superpose (
      (let $others (remove-index $idx $children)
         (if (== $others ())
            (canonical-addition $kb
               ((: $kb $prf $type $tvin) (CPU (atom_concat $head Projection) ($tvin) $tvout))
               (brand Proof (proj $idx $prf)) $elem $tvout)
            (let (premise-bundle $execs $evidence-tv $evidence-proof)
                 (lower-all lower $kb $head $others)
               (canonical-addition $kb
                  (cons (: $kb $prf $type $tvin)
                     (append-goals $execs
                        ((CPU (atom_concat $head Projection) ($tvin $evidence-tv) $tvout))))
                  (brand Proof ((proj $idx $prf) $evidence-proof)) $elem $tvout))))
      (if (== $head And)
         (canonical-addition $kb
            ((: $kb $prf $type $tvin) (CPU AndMarginalProjection ($tvin) $tvout))
            (brand Proof (marginal-proj $idx $prf)) $elem $tvout)
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

;; A rule's conclusion and its statement premises share one context pattern,
;; with two exceptions compiled at MAIN while that context is open, which the
;; chainer routes into a hypothetical scope by their pattern
;; (contextualize-rule-premise): a fold, and a premise whose predicate is a
;; variable. Read in a private context, a variable predicate would unify with
;; the context's internal keys, such as RuleTruth.
(: fold-scope (-[det]-> KBContext KBContext))
(= (fold-scope ($kbid $ctx $vars))
   (if (or (is-var $ctx) (is-var $vars)) (kbctx (brand KB $kbid)) (make-kb-context (brand KB $kbid) $ctx $vars)))

(: exec-goal-type
   (-[det]-> Goal Expression))
(= (exec-goal-type (CPU $f $args $res)) (CPU $f $args $res))
(= (exec-goal-type (: $_kb $_prf $elem $_tv)) $elem)

(: execs-goal-type
   (-[det]-> (List Goal) Expression))
(= (execs-goal-type $execs) (seq2expr (map-flat exec-goal-type $execs)))

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

;; Source-level computations lower to CPU goals rather than key reads.
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
      (FoldAllTruth true)
      (Not true)
      (GreaterThan true)
      (> true)
      ($_other false))))

;; How a premise reads a statement: one bundle of goals, its truth value and
;; its proof. A negation reads its statement and complements it; an
;; existential reads the floor of its claim and its witnesses; a computation
;; lowers to CPU goals; every other statement, a compound included, is a key
;; read, and the compound's producers give that key its value. Statement reads
;; share the reader's context; folds take `fold-scope`.
(= (lower $kc $premise)
   (once (if (head-is? $premise Not)
      (let (premise-bundle $goals $tv $proof) (lower $kc (brand Statement (car-atom (cdr-atom $premise))))
         (premise-bundle (append-goals $goals ((CPU NotFormula ($tv) $not-tv))) $not-tv (negated $proof)))
   (if (explicit-exists-term? $premise)
      (fold-existential-premise-bundle (fold-scope $kc)
         (brand Statement (ExistentialAlternatives (canonical-existential-side $premise) $channel))
         (implication-antecedent-free-vars $premise) ExistentialFloor (STV 0 0))
   ;; A variable or variable-headed premise is a fact read in `fold-scope`:
   ;; dispatching it through the cases below would mistake an unknown head for
   ;; compiler syntax.
   (if (if (is-var $premise) true (if (is-expr $premise) (is-var (car-atom $premise)) false))
      (let $read (if (is-var $premise) $premise (if (== (cdr-atom $premise) ()) (car-atom $premise) $premise))
         (premise-bundle ((: (fold-scope $kc) $prf $read $tv)) $tv $prf))
   (let ($kb $_ctx $_vars) $kc
      (case $premise (
         ((CPU $f $args $res)
            (premise-bundle ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu))
         ((KnownExistential $binder $body)
            (let $bound-vars (list_to_set (explicit-exists-vars $binder))
               (if (== $bound-vars ())
                  (empty)
                  (fold-existential-premise-bundle (fold-scope $kc) (brand Statement $body)
                     (\== (list_to_set (extract-vars $body)) $bound-vars) OrFormula (STV 0 0)))))
         ((ExistentialResidual $binder $body)
            (existential-residual-premise-bundle $kc $binder $body))
         ((Compute $f $args -> $res)
            (premise-bundle ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu))
         ((Compute $f $args $res)
            (premise-bundle ((CPU $f $args $res)) (cpu-premise-tv $f $args $res) cpu))
         ((MapDist $fun $a $value -> $out)
            (premise-bundle
               ((: $kc $prfa $a $tv_a) (CPU DistMapFormula (quote ($fun $value)) $out))
               (STV 1.0 1.0) $prfa))
         ((Map2Dist $fun $a $valuea $b $valueb -> $out)
            (premise-bundle
               ((: $kc $prfa $a $tv_a) (: $kc $prfb $b $tv_b)
                (CPU DistMap2Formula (quote ($fun $valuea $valueb)) $out))
               (STV 1.0 1.0) (conjunction $prfa $prfb)))
         ((AverageDist $pattern $value -> $out)
            (premise-bundle
               ((CPU FoldAllCompiled
                   ($kb $pattern (extract-value $pattern $value) (SumCount (PointMass 0.0) 0)
                      DistSumCountAcc dist-average unit-stv)
                   $out))
               (STV 1.0 1.0) cpu))
         ((FoldAllValue $pattern $init $fun -> $out)
            (premise-bundle
               ((CPU FoldAllCompiled ($kb $pattern extract-tv $init $fun identity unit-stv) $out))
               (STV 1.0 1.0) cpu))
         ;; Like FoldAll, with each member's truth value matched against
         ;; `$truth` so `$value` can use it.
         ((FoldAllTruth $pattern $truth $value $init $fun -> $out)
            (premise-bundle
               ((CPU FoldAllCompiled
                   ($kb $pattern (extract-with-truth $pattern $truth $value) $init $fun identity unit-stv)
                   $out))
               (STV 1.0 1.0) cpu))
         ((FoldAll $pattern $value $init $fun -> $out)
            (premise-bundle
               ((CPU FoldAllCompiled
                   ($kb $pattern (extract-value $pattern $value) $init $fun identity unit-stv)
                   $out))
               (STV 1.0 1.0) cpu))
         (($rel $a $b)
            (if (is-member $rel (GreaterThan >))
               (if (is-var $b) (premise-bundle ((CPU DistGreaterThanDistFormula ($a $b) $tv)) $tv cpu)
                  (premise-bundle ((CPU DistGreaterThanFormula ($a $b) $tv)) $tv cpu))
               (premise-bundle ((: $kc $prf ($rel $a $b) $tv)) $tv $prf)))
         ($other
            (premise-bundle ((: $kc $prf $other $tv)) $tv $prf))))))))))

;; A connective's part. Its formula reads an implication part at the
;; implication's probability, which the chainer judges in the implication's
;; query scaffold. A rule's own conclusion is never read so: its projections
;; would take a part judged from the same rule as evidence for its siblings
;; (see compile-output-children).
(: lower-part (-[semidet]-> KBContext Statement PremiseBundle))
(= (lower-part $kc $part)
   (if (implication-type? $part)
      (premise-bundle ((: $kc $prf $part (STV $s $c))) (STV $s $c) $prf)
      (lower $kc $part)))

;; A connective over parts read by `$read`: their goals in source order, their
;; values folded by <Head>Formula, the conjunction of their proofs.
(: lower-all-step
   (-[semidet]-> (-[semidet]-> KBContext Statement PremiseBundle) KBContext Expression
       CompiledPremises Statement CompiledPremises))
(= (lower-all-step $read $kc $formula ($goals $proofs $tv) $part)
   (let* (((premise-bundle $part-goals $part-tv $part-proof) ($read $kc $part))
          (($cpu $next-tv) (binary-tv-cpu $formula $tv $part-tv)))
      (data (cons $cpu (prepend-reversed-goals $part-goals $goals)) (cons $part-proof $proofs) $next-tv)))

(= (lower-all $read $kc $head (cons $first $rest))
   (let* (((premise-bundle $goals $tv $proof) ($read $kc $first))
          (($reversed-goals $reversed-proofs $all-tv)
             (fold-semidet (lower-all-step $read $kc (atom_concat $head Formula))
                (data (prepend-reversed-goals $goals ()) ($proof) $tv) $rest)))
      (premise-bundle (prepend-reversed-goals $reversed-goals ())
         $all-tv (implication-proof-token (prepend-reversed-proofs $reversed-proofs ())))))

;; Compound settling: a part known with certainty at its connective's settling
;; value (`set-compound-settling`) decides the compound without the other
;; parts, so a part with no proof does not block it. The settled reading reads
;; the part alone, checks its value (SettlesFormula), and carries the settling
;; value. A part that already carries a value settles only with that value.
;; Only a part binding all the compound's variables settles it: one leaving a
;; variable open would decide a single instance of a variable the other parts
;; range over.
(: settled-reading (-[det]-> Statement Statement PremiseBundle (List PremiseBundle)))
(= (settled-reading $compound $part (premise-bundle $goals $tv $proof))
   (case (let $head (car-atom $compound) (collapse (match &logic_config (compound-settling $head $setting) $setting))) (
      ((cons $value $_none)
         (if (vars-covered? $compound (list_to_set (extract-vars $part)))
            (if (is-var $tv)
               (cons (premise-bundle
                        (append-goals $goals ((CPU SettlesFormula (quote ($tv $value)) $value)))
                        $value (settled $proof))
                  ())
               (if (== $tv $value) (cons (premise-bundle $goals $value (settled $proof)) ()) ()))
            ()))
      (() ()))))

;; The settling readings of a compound's parts, in source order. This and the
;; antecedent recursions below prepend onto their later results: the
;; determinism checker accepts `append` only onto a constructed list, and a
;; semidet fold's type-variable result would leave a runtime type check.
(: settlings (-[semidet]-> KBContext Statement (List Statement) (List PremiseBundle)))
(= (settlings $_kc $_compound ()) ())
(= (settlings $kc $compound (cons $part $rest))
   (append (settled-reading $compound $part (lower-part $kc $part)) (settlings $kc $compound $rest)))

;; An Any-mode compound is introduced by any one of its parts.
(: any-reading (-[semidet]-> KBContext Atom Statement PremiseBundle))
(= (any-reading $kc $head $part)
   (let (premise-bundle $goals $tv $proof) (lower-part $kc $part)
      (premise-bundle $goals $tv ((atom_concat $head introduction) $proof))))

;; The readings of a compound: in All mode its complete bundle, then the
;; bundle of each part that settles it alone; in Any mode one per part.
(: compound-readings (-[semidet]-> KBContext Statement (List PremiseBundle)))
(= (compound-readings $kc $compound)
   (let* (($head (car-atom $compound)) ($parts (statement-children (cdr-atom $compound))))
      (if (== (configured-compound-premise-mode $head) Any)
         (map-semidet (any-reading $kc $head) $parts)
         (cons (lower-all lower-part $kc $head $parts) (settlings $kc $compound $parts)))))

;; The rules that give a compound key its value: one per reading, concluding
;; the compound in the reader's context, and those of every compound key the
;; readings read, through negations too. They live with their reader: a rule
;; emits those of the keys it reads, and the chainer installs a query's for
;; its lifetime (install-producers!) (#142).
(: reading-addition (-[det]-> KBContext Statement PremiseBundle CompiledAddition))
(= (reading-addition $kc $compound (premise-bundle $goals $tv $proof))
   (brand CompiledAddition ($goals |- (: $kc $proof $compound $tv))))

(: producers (-[semidet]-> KBContext Statement (List CompiledAddition)))
(: child-producers-step
   (-[semidet]-> KBContext (List CompiledAddition) Statement (List CompiledAddition)))
(= (child-producers-step $kc $acc $child)
   (append-compiled-additions $acc (producers $kc $child)))
(= (producers $kc $statement)
   (let ($key $_odd) (canon $statement)
      (if (compound-source? $key)
         (fold-semidet (child-producers-step $kc)
            (map-flat (reading-addition $kc $key) (compound-readings $kc $key))
            (statement-children (cdr-atom $key)))
         ())))

;; The readings of a top-level premise: a compound is read inline through its
;; readings, any other statement through `lower`.
(: premise-readings (-[semidet]-> KBContext Statement (List PremiseBundle)))
(= (premise-readings $kc $premise)
   (if (compound-source? $premise)
      (compound-readings $kc $premise)
      (cons (lower $kc $premise) ())))

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

(: extend-step
   (-[det]-> CompiledPremises PremiseBundle (List CompiledPremises) (List CompiledPremises)))
(= (extend-step $partial $reading $kept) (cons (append-premise-bundle $partial $reading) $kept))
(: extend-partials-step
   (-[det]-> (List PremiseBundle) CompiledPremises (List CompiledPremises) (List CompiledPremises)))
(= (extend-partials-step $readings $partial $kept) (foldr-flat (extend-step $partial) $kept $readings))
;; Every combination of the conjuncts' readings, the last conjunct varying
;; fastest, as reversed partial lowerings.
(: conjunct-combinations
   (-[semidet]-> KBContext (List CompiledPremises) (List Atom) (List CompiledPremises)))
(= (conjunct-combinations $_kc $partials ()) $partials)
(= (conjunct-combinations $kc $partials (cons $conjunct $rest))
   (conjunct-combinations $kc
      (foldr-flat (extend-partials-step (premise-readings $kc (brand Statement $conjunct))) () $partials)
      $rest))

;; The lowerings of a conjunctive antecedent that one conjunct settles alone,
;; one per reading of the conjunct, in source order. `antecedent-settlings`
;; keeps the And test in a function body: as an argument, an `if` with an
;; empty-list branch leaves a runtime type check.
(: reading-settlings
   (-[det]-> Statement Statement (List PremiseBundle) (List CompiledPremises) (List CompiledPremises)))
(= (reading-settlings $_antecedent $_conjunct () $later) $later)
(= (reading-settlings $antecedent $conjunct (cons $reading $rest) $later)
   (let $after (reading-settlings $antecedent $conjunct $rest $later)
      (case (settled-reading $antecedent $conjunct $reading) (
         ((cons (premise-bundle $goals $tv $proof) $_none) (cons (data $goals (cons $proof ()) $tv) $after))
         ($_unsettled $after)))))
(: conjunct-settlings (-[semidet]-> KBContext Statement (List Atom) (List CompiledPremises)))
(= (conjunct-settlings $_kc $_antecedent ()) ())
(= (conjunct-settlings $kc $antecedent (cons $conjunct $rest))
   (let $part (brand Statement $conjunct)
      (reading-settlings $antecedent $part (premise-readings $kc $part)
         (conjunct-settlings $kc $antecedent $rest))))
(: antecedent-settlings (-[semidet]-> KBContext Statement (List CompiledPremises)))
(= (antecedent-settlings $kc $antecedent)
   (if (head-is? $antecedent And)
      (conjunct-settlings $kc $antecedent (implication-side-conjuncts $antecedent))
      ()))

;; Every lowering of a rule's antecedent, the complete one first: each conjunct
;; is read through each of its readings, and a conjunct that settles a
;; conjunctive antecedent alone adds a lowering of its own.
(: antecedent-lowerings (-[semidet]-> KBContext Statement (List CompiledPremises)))
(: finished-lowerings (-[det]-> (List CompiledPremises) (List CompiledPremises) (List CompiledPremises)))
(= (finished-lowerings () $later) $later)
(= (finished-lowerings (cons $partial $rest) $later)
   (cons (finish-reversed-compiled-premises $partial) (finished-lowerings $rest $later)))
(= (antecedent-lowerings $kc $antecedent)
   (let* (($conjuncts (implication-side-conjuncts $antecedent))
          ($combinations (conjunct-combinations $kc ((data () () (STV 1.0 1.0))) $conjuncts)))
      (finished-lowerings $combinations (antecedent-settlings $kc $antecedent))))

;; The complete lowering of a statement read as an antecedent.
(: complete-lowering (-[semidet]-> KBContext Statement CompiledPremises))
(= (complete-lowering $kc $statement)
   (case (antecedent-lowerings $kc $statement) (((cons $complete $_others) $complete))))

;; The query-local rule a goal reading a statement as a whole needs: a negation
;; is read through a view of its statement, whose proof is negated so its
;; evidence is the statement's as written, and which is never stored; a
;; computation is bridged when its goals differ from the goal shape. A compound
;; goal reads its key, whose producers the chainer installs.
(: root-adapters (-[nondet]-> Goal CompiledAddition))
(= (root-adapters (: $kb $prf $type $tv))
   (if (compound-source? $type) (empty)
      (let (premise-bundle $execs $result-tv $proof-token) (lower $kb $type)
         (if (head-is? $type Not)
            (brand CompiledAddition ($execs |- (: $kb $proof-token $type $result-tv)))
            (if (if (is-var $type) false (not (== (execs-goal-type $execs) $type)))
               (brand CompiledAddition ($execs |- (: $kb ($prf $proof-token) $type $result-tv)))
               (empty))))))

;; Build the canonical direct-claim statement corresponding to a source
;; binder/body pair. Free variables remain available for grouping; only bound
;; witness positions become slots.
(: existential-claim-statement
   (-[semidet]-> Atom Atom Statement))
(= (existential-claim-statement $binder $body)
   (let* (($bound-vars (list_to_set (explicit-exists-vars $binder)))
          ($state (sealed $bound-vars
             (fold-flat (existential-slot-step existential-claim ())
                (brand SkolemizeState (0 (ExistentialClaim $body))) $bound-vars))))
      (snd $state)))

;; An explicit existential premise collapses all matching witnesses with
;; OrFormula. Free variables form independent groups, while variables named by
;; the binder do not escape into the compiled rule.
(: fold-existential-premise-bundle
   (-[det]-> KBContext Statement (List Variable) (-[det]-> STVType STVType STVType) STVType PremiseBundle))
(= (fold-existential-premise-bundle $scope $premise $group-vars $function $empty-tv)
   (if (== $group-vars ())
      (premise-bundle
         ((CPU FoldAllCompiled
              (quote ($scope $premise extract-tv $empty-tv $function identity result-tv))
              $fold-tv))
         $fold-tv
         cpu)
      (premise-bundle
         ((CPU GroupedFoldAllCompiled
              (quote ($scope $premise $group-vars extract-tv $empty-tv $function identity result-tv))
              $fold-tv))
         $fold-tv
         cpu)))

;; Existential channels are nested propositions. Keep the stronger TV intact;
;; confidence breaks exact strength ties by evidence amount, without revision.
(: ExistentialFloor (-[det]-> STVType STVType STVType))
(= (ExistentialFloor (STV $sa $ca) (STV $sb $cb))
   (if (if (> $sb $sa) true (if (< $sb $sa) false (> $cb $ca)))
      (STV $sb $cb) (STV $sa $ca)))

;; One normalization for source rules and query lookup. Each complete side's
;; bound variables become local rigid slots; free variables remain shared.
(: canonical-existential-side (-[semidet]-> Statement Statement))
(= (canonical-existential-side $side)
   (let $valid (validate-explicit-exists-term $side)
      (if (explicit-exists-term? $valid)
         (let (Exists $binder $body) $valid
            (existential-claim-statement $binder $body))
         (brand Statement $valid))))

;; Compare the direct existential proposition with the OR of the witnesses
;; currently enumerable from the body. The direct proposition uses canonical
;; slots, so matching it cannot bind the witness variable and accidentally
;; restrict the following fold to one object. The direct premise binds outer
;; arguments before the scalar fold, including groups without witnesses. Only
;; the residual requests the empty disjunction identity (0,1).
(: existential-residual-premise-bundle
   (-[nondet]-> KBContext Atom Atom PremiseBundle))
(= (existential-residual-premise-bundle $kc $binder $body)
   (let*
      (($bound-vars (list_to_set (explicit-exists-vars $binder)))
       ($claim (existential-claim-statement $binder $body))
       ($scope (fold-scope $kc))
       ((premise-bundle $fold-execs $known-tv $_fold-proof)
          (fold-existential-premise-bundle $scope (brand Statement $body) () OrFormula (STV 0 1))))
      (if (== $bound-vars ())
         (empty)
         (premise-bundle
            (cons
               (: $scope $direct-proof $claim $direct-tv)
               (append-goals
                  $fold-execs
                  ((CPU ExistentialResidualFormula
                       ($direct-tv $known-tv) $residual-tv))))
            $residual-tv
            (conjunction $direct-proof cpu)))))

;; Probability reads retain the written event's key; connective evaluation
;; uses De Morgan expansion. Do not descend into predicate arguments
;; or binders, which are terms rather than Boolean statement children.
(: query-assumption-nnf (-[det]-> Statement Statement))
(= (query-assumption-nnf $source)
   (let ($key $odd) (canon $source)
      (if (head-is-member? $key (And Or))
         (if $odd
            (brand Statement (cons (if (head-is? $key And) Or And)
               (map-flat (|-> ($child) (query-assumption-nnf (brand Statement (Not $child))))
                  (statement-children (cdr-atom $key)))))
            (brand Statement (cons (car-atom $key)
               (map-flat query-assumption-nnf (statement-children (cdr-atom $key))))))
         (if $odd (brand Statement (Not $key)) $key))))

(: lower-query-assumption-premise
   (-[nondet]-> KB $context $variables Statement  PremiseBundle))
;; Antecedents of an implication *query* are temporary assumptions, asserted at
;; their canonical key (an existential at its claim): an assumed negation is
;; its statement at strength zero. An assumed compound asserts the keys of one
;; of its readings, each reading a world of its own, since rules read a
;; compound antecedent through its parts.
(= (lower-query-assumption-premise $kb $ctx $vars $source)
   (let* ((($statement $odd) (canon $source))
          ($premise (if (contains-explicit-exists? $statement) (canonical-existential-side $statement) $statement))
          ($kc (make-kb-context $kb $ctx $vars)))
      (if $odd
         (premise-bundle ((: $kc $prf $premise (STV 0.0 1.0))) (STV 1.0 1.0) $prf)
         (let $readings (premise-readings $kc $premise) (superpose $readings)))))

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
(= (lower-query-assumption-premise-false $kb $ctx $vars $source)
   (let ($premise $odd) (canon $source)
      (if $odd
         (premise-bundle ((: (make-kb-context $kb $ctx $vars) $prf $premise (STV 1.0 1.0))) (STV 0.0 1.0) (negated $prf))
         (if (head-is? $premise Implication)
            (premise-bundle
               ((: (make-kb-context $kb $ctx $vars)
                    $prf $premise
                    (CTV (STV 0.0 1.0) (STV 1.0 1.0))))
               (CTV (STV 0.0 1.0) (STV 1.0 1.0))
               $prf)
            (premise-bundle
               ((: (make-kb-context $kb $ctx $vars)
                    $prf $premise (STV 0.0 1.0)))
               (STV 0.0 1.0) $prf)))))

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
;; compiler-generated existential witnesses with query variables, one per
;; distinct witness: conjuncts that share a witness, as a skolemized variable
;; shared, stay joined in the scan. Traverse expression nodes, never their list
;; suffixes: matching a suffix against an `exists` pattern would unify ordinary
;; variable-headed terms into open conses. The walk threads the witnesses seen
;; so far, each paired with its query variable.
(: RuleQueryState Type)
(: rule-query-state (-[det]-> $term (List WitnessVar) RuleQueryState))
(: WitnessVar Type)
(: witness-var (-[det]-> Atom Variable WitnessVar))

(: witness-query-var (-[det]-> Atom (List WitnessVar) Atom))
(= (witness-query-var $_witness ()) ())
(= (witness-query-var $witness (cons (witness-var $stored $var) $rest))
   (if (== $witness $stored) $var (witness-query-var $witness $rest)))

(: rule-query-walk-list (-[det]-> (List $term) (List WitnessVar) RuleQueryState))

(: rule-query-walk (-[det]-> $term (List WitnessVar) RuleQueryState))
(= (rule-query-walk $term $witnesses)
   (if (== $term ()) (rule-query-state () $witnesses)
      (if (is-var $term) (rule-query-state $term $witnesses)
         (if (is-expr $term)
            (if (== (car-atom $term) exists)
               (case (cdr-atom $term) (
                  ((cons $_rule (cons $_idx (cons $_vars ())))
                     (let $known (witness-query-var $term $witnesses)
                        (if (== $known ())
                           (rule-query-state $query-var (cons (witness-var $term $query-var) $witnesses))
                           (rule-query-state $known $witnesses))))
                  ($_other (rule-query-walk-list $term $witnesses))))
               (rule-query-walk-list $term $witnesses))
            (rule-query-state $term $witnesses)))))

(= (rule-query-walk-list () $witnesses) (rule-query-state () $witnesses))
(= (rule-query-walk-list (cons $head $rest) $witnesses)
   (let* (((rule-query-state $new-head $after-head) (rule-query-walk $head $witnesses))
          ((rule-query-state $new-rest $after-rest) (rule-query-walk-list $rest $after-head))
          ($list (cons $new-head $new-rest)))
      (rule-query-state $list $after-rest)))

(: rule-query-pattern (-[det]-> $term $term))
(= (rule-query-pattern $term)
   (let (rule-query-state $pattern $_witnesses) (rule-query-walk $term ()) $pattern))

(: contains-cpu? (-[det]-> Expression Bool))
(= (contains-cpu? $term)
   (contains-head? (== CPU) $term))
