;; Conversion between compiler products and the MORK runtime tuple layout.
;; Translate the external `premises |- conclusions` compiler form into the
;; single-conclusion `rules` form consumed by MORK. Facts are already
;; zero-premise conclusions and therefore need no wrapper.
(: mm2stmt (-[det]-> CompiledAddition RuntimeAddition))
(= (mm2stmt ($premises |- $conclusion))
   (if (== $premises ())
      (brand RuntimeAddition $conclusion)
      (brand RuntimeAddition
         (rules (quote ($premises |- $conclusion))))))

;; Some query additions arrive wrapped in an extra singleton list after
;; collapse. Unwrap that shape explicitly before applying the normal MM2 rule
;; conversion; treating it as a fact would install the list itself as a goal.
(: compiled-add-mm2stmt
   (-[det]-> CompiledAddition RuntimeAddition))
(= (compiled-add-mm2stmt $add)
   (if (== (cdr-atom $add) ())
      (let*
         (($rule (car-atom $add))
           ($prms (car-atom $rule))
           ($tail (cdr-atom $rule))
           ($ccls (car-atom (cdr-atom $tail)))
           ($ccl (car-atom $ccls)))
         (brand RuntimeAddition
            (rules (quote ($prms |- $ccl)))))
      (mm2stmt $add)))

(: compiled-adds-mm2stmts
   (-[det]-> (List CompiledAddition) (List RuntimeAddition)))
(= (compiled-adds-mm2stmts $adds)
   (map-flat compiled-add-mm2stmt $adds))

;; MORK indexes facts as `(type kb proof tv)`, whereas the public/compiler form
;; is `(: kb proof type tv)`. Convert recursively because these atoms may appear
;; inside generated rules and query additions, not only at the top level.
(: internalize-proof-structure
   (-[semidet]-> Goal
       (Statement KBContext Proof TV)))
(= (internalize-proof-structure (: $kb $proof $statement $truth-value))
   (quote ($statement $kb $proof $truth-value)))

(: compile-internalize-runtime-addition
   (-[det]-> RuntimeAddition RuntimeAddition))
(= (compile-internalize-runtime-addition $addition)
   (brand RuntimeAddition
      (the Expression
         (internalize-proof-structure-any $addition))))

(: internalize-proof-structure-any
   (-[det]-> Expression Atom))
(= (internalize-proof-structure-any $term)
   (if (== $term ()) ()
      (if (is-var $term) $term
      (if (= $term (: $kb $prf $type $tv)) (quote ($type $kb $prf $tv))
         (if (is-expr $term)
            (cons
               (internalize-proof-structure-any (car-atom $term))
               (map-flat internalize-proof-structure-any
                  (cdr-atom $term)))
            $term)))))

;; Reverse the runtime tuple layout for diagnostics and public results. Only a
;; shaped KB can be recognized safely; arbitrary four-element expressions must
;; remain untouched.
(: externalize-query-proof (-[nondet]-> Proof Proof))
(= (externalize-query-proof $proof)
   (if (is-var $proof) $proof
      (if (= $proof (inheritance-query-result $inner))
         (externalize-query-proof (brand Proof $inner))
         (if (= $proof (total-implication-frontier $inner))
            (externalize-query-proof (brand Proof $inner))
         (if (is-expr $proof)
            (brand Proof
               (cons
                  (externalize-query-proof-child
                     (car-atom $proof))
                  (externalize-query-proof-children
                     (cdr-atom $proof))))
            $proof)))))

(: externalize-query-proof-child
   (-[nondet]-> Expression Proof))
(= (externalize-query-proof-child $child)
   (externalize-query-proof (brand Proof $child)))

(: externalize-query-proof-children
   (-[nondet]-> (List Atom) (List Proof)))
(= (externalize-query-proof-children ())
   ())
(= (externalize-query-proof-children
      (cons $child $rest))
   (cons
      (externalize-query-proof-child $child)
      (externalize-query-proof-children $rest)))

(: externalize-proof-structure-list-core
   (-[nondet]-> (List Atom) (List Atom)))
(= (externalize-proof-structure-list-core $terms)
   (if (== $terms ()) ()
      (cons (externalize-proof-structure (car-atom $terms))
         (externalize-proof-structure-list-core (cdr-atom $terms)))))

;; Inspect the second field without unifying it with a KB-context pattern.
;; A direct `= ($type ($kbid $ctx $vars) ...)` test can otherwise turn an
;; unbound domain argument into a three-field KB context while merely trying
;; to decide whether an arbitrary four-element expression is a runtime fact.
(: runtime-fact-kb-shaped? (-[det]-> Atom Bool))
(= (runtime-fact-kb-shaped? $term)
   (if (is-expr $term)
      (let $tail (cdr-atom $term)
         (if (== $tail ()) false
            (is-expr (car-atom $tail))))
      false))

(: externalize-proof-structure (-[nondet]-> Expression Atom))
(= (externalize-proof-structure $term)
   (once
      (if (is-var $term) $term
         (if (== $term ()) ()
            (if (runtime-fact-kb-shaped? $term)
               (if (= $term ($type ($kbid $ctx $vars) $prf $tv))
                  (: ($kbid $ctx $vars)
                     (externalize-query-proof (brand Proof $prf))
                     $type $tv)
                  (cons
                     (externalize-proof-structure (car-atom $term))
                     (externalize-proof-structure-list-core
                        (cdr-atom $term))))
               (if (is-expr $term)
                  (cons
                     (externalize-proof-structure (car-atom $term))
                     (externalize-proof-structure-list-core
                        (cdr-atom $term)))
                  $term))))))

(: pretty (-[semidet]-> Atom AnnotatedStatement))
(= (pretty (: $prf $type $tv)) (: $prf $type $tv))
(= (pretty (rules ($args |- $goal))) (pretty $goal))
(= (pretty (: $kb $prf $type $tv))
   (once
      (if (is-expr $kb)
         (if (= $kb ($kbid MAIN Nil)) (: $prf $type $tv)
            (let*
                 (($idx (car-atom (cdr-atom $kb)))
                 ($vars (car-atom (cdr-atom (cdr-atom $kb))))
                 ($x
                    (collapse
                       (match &kb
                          ($t $kb $_proof $_truth-value)
                          $t)))
                 ($ptype (Implication (seq2expr $x) $type)))
               (: $prf $ptype $tv)))
         (: $prf $type $tv))))
