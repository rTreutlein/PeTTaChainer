;; Shared syntax and context vocabulary. No compiler or runtime policy dependencies.
;; Loaded after types and collection primitives, before configuration and policy.

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

(: head-is? (-[det]-> Atom Atom Bool))
(= (head-is? $term $expected)
   (if (== $term ()) false
      (if (is-expr $term)
         (let $head (car-atom $term)
            (if (is-var $head) false (== $head $expected)))
         false)))

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

;; A statement is stored, assumed and concluded at its canonical key: under any
;; number of negations, the statement they negate, with its value complemented
;; when the count is odd. A negation is a reading of its key, never a key.
(: canon (-[det]-> Statement (Statement Bool)))
(= (canon $statement)
   (if (head-is? $statement Not)
      (let ($key $odd) (canon (brand Statement (car-atom (cdr-atom $statement))))
         (data $key (if $odd false true)))
      (data $statement false)))

(: statement-children
   (-[det]-> Expression (List Statement)))
(= (statement-children ()) ())
(= (statement-children (cons $child $rest))
   (cons
      (brand Statement $child)
      (statement-children $rest)))

(: make-kb-context (-[det]-> KB $context $variables KBContext))
(= (make-kb-context $kb $ctx $vars)
   (brand KBContext (quote ($kb $ctx $vars))))

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

(: implication-type? (-[det]-> Statement Bool))
(= (implication-type? $type)
   (head-is? $type Implication))

;; Normalize a public KB id to its default runtime shape. Query contexts already
;; arrive shaped as `(kbid ctx vars)` and must pass through unchanged.
(: kbctx (-[det]-> Atom KBContext))
(= (kbctx $kb)
   (if (is-expr $kb)
      (brand KBContext $kb)
      (make-kb-context (brand KB $kb) MAIN Nil)))

(: contextual-cpu? (-[det]-> $formula Bool))
(= (contextual-cpu? $fun)
   (stored-list-member? $fun (ContextRule ReadRate ReadLikelihoodContext CompoundEvidence)))
