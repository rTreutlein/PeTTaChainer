;; MORK indexes facts as `(type kb proof tv)`, whereas the public/compiler form
;; is `(: kb proof type tv)`. Convert recursively because these atoms may appear
;; inside generated rules and query additions, not only at the top level.
(: internalize-proof-structure
   (-[semidet]-> (| Goal QueryScope)
       (Statement KBContext Proof TV)))
(= (internalize-proof-structure (: $kb $proof $statement $truth-value))
   (quote ($statement $kb $proof $truth-value)))

(: internalize-proof-structure-any
   (-[det]-> Expression Atom))
(= (internalize-proof-structure-any $term)
   (if (== $term ()) ()
      (if (is-var $term) $term
      (if (if (head-is? $term :) (= $term (: $kb $prf $type $tv)) false) (quote ($type $kb $prf $tv))
         (if (is-expr $term)
            (cons
               (internalize-proof-structure-any (car-atom $term))
               (map-flat internalize-proof-structure-any
                  (cdr-atom $term)))
            $term)))))

;; Every compiler addition has one premise list and one conclusion. Encode
;; that product directly; no external RuntimeAddition is exposed to consumers.
(: mm2stmt (-[det]-> CompiledAddition RuntimeAddition))
(= (mm2stmt $addition)
   (let* ((($source $role $priors $premises $conclusion)
              (source-plan-parts $addition))
          ($runtime (internalize-proof-structure-any
             (if (== $premises ()) $conclusion (rules (quote ($premises |- $conclusion)))))))
      (compile-source-plan $source $role $priors $runtime)))

;; Reverse the runtime tuple layout for diagnostics and public results. Only a
;; shaped KB can be recognized safely; arbitrary four-element expressions must
;; remain untouched.
(: externalize-query-proof (-[nondet]-> Proof Proof))
(= (externalize-query-proof $proof)
   (if (is-var $proof) $proof
      (if (= $proof (total-implication-frontier $inner))
         (externalize-query-proof (brand Proof $inner))
         (if (is-expr $proof)
            (brand Proof
               (cons
                  (externalize-query-proof-child
                     (car-atom $proof))
                  (map-flat externalize-query-proof-child
                     (cdr-atom $proof))))
            $proof))))

(: externalize-query-proof-child
   (-[nondet]-> Expression Proof))
(= (externalize-query-proof-child $child)
   (externalize-query-proof (brand Proof $child)))

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
      (if (head-is? $term source-plan)
         (let (source-plan $_source $_role $_priors $_parents $addition) $term (externalize-proof-structure $addition))
         (if (is-var $term) $term
         (if (== $term ()) ()
            (if (runtime-fact-kb-shaped? $term)
               (if (= $term ($type ($kbid $ctx $vars) $prf $tv))
                  (: ($kbid $ctx $vars)
                     (externalize-query-proof (brand Proof $prf))
                     $type $tv)
                  (cons
                     (externalize-proof-structure (car-atom $term))
                     (map-flat externalize-proof-structure (cdr-atom $term))))
               (if (is-expr $term)
                  (cons
                     (externalize-proof-structure (car-atom $term))
                     (map-flat externalize-proof-structure (cdr-atom $term)))
                  $term)))))))

(: pretty (-[semidet]-> Atom AnnotatedStatement))
(= (pretty (: $prf $type $tv)) (: $prf $type $tv))
(= (pretty (rules ($args |- $goal))) (pretty $goal))
(= (pretty (: $kb $prf $type $tv))
   (once
      (if (is-expr $kb)
         (if (= $kb ($kbid MAIN Nil)) (: $prf $type $tv)
            (let*
                 (($x
                    (collapse
                       (match &kb
                          ($t $kb $_proof $_truth-value)
                          $t)))
                 ($ptype (Implication (seq2expr $x) $type)))
               (: $prf $ptype $tv)))
         (: $prf $type $tv))))
