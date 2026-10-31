;; Shared runtime term constructors, scalar adapters and counters.
;; Schema-less proof/result stores erase nominal roles. Reconstruct a fact only
;; at those boundaries and validate the truth-value payload whose numeric
;; fields affect inference. Typed &kb reads do not pass through this adapter.
(: assemble-stored-runtime-fact (-[det]-> Atom Atom Atom Atom (Statement KBContext Proof TV)))
(= (assemble-stored-runtime-fact $type $kb $proof $tv)
   (data (brand Statement $type) (brand KBContext $kb) (brand Proof $proof) (the TV $tv)))

;; Scalar ids recovered from erased spaces are checked individually at their
;; lookup boundary, avoiding a traversal of the collected list.
(: stored-number (-[det]-> Atom Number))
(= (stored-number $value) (the Number $value))

(: chainer-first-or (-[det]-> $value (List $value) $value))
(= (chainer-first-or $fallback ()) $fallback)
(= (chainer-first-or $_fallback (cons $value $_rest)) $value)

(: chainer-acyclic-term? (-[det]-> $term Bool))
(= (chainer-acyclic-term? $term) (== (collapse (callPredicate (Predicate (cyclic_term $term)))) ()))

(: chainer-add-atom (-[semidet]-> $space $expression (| Bool (List $no-result))))
(= (chainer-add-atom $space $expr)
   (if (chainer-acyclic-term? $expr) (add-space-atom! $space (brand SpaceAtom $expr)) (empty)))

;; Build erased, raw atom-space rows without letting a variable first field be
;; interpreted as a function head.  The nominal result also proves to
;; add-atom that the row is bound and nonempty.
(: make-space-pair (-[det]-> $left $right SpaceAtom))
(= (make-space-pair $left $right) (brand SpaceAtom (cons $left (cons $right ()))))

(: make-space-row3 (-[det]-> $first $second $third SpaceAtom))
(= (make-space-row3 $first $second $third)
   (brand SpaceAtom (cons $first (cons $second (cons $third ())))))

(: make-space-row4 (-[det]-> $first $second $third $fourth SpaceAtom))
(= (make-space-row4 $first $second $third $fourth)
   (brand SpaceAtom (cons $first (cons $second (cons $third (cons $fourth ()))))))

(: next-search-id (-[det]-> CounterKey Number))
(= (next-search-id $key) (let $n (search-id-value $key) (progn (change-state! $key (+ $n 1)) $n)))

(: cpu-call (-[nondet]-> Number $formula $arguments  $result))
(= (cpu-call $_steps $fun $args) (reduce (reduce (cons $fun $args))))


(: assemble-runtime-fact (-[det]-> Statement KBContext Proof TV (Statement KBContext Proof TV)))
(= (assemble-runtime-fact $type $kb $proof $tv) (data $type $kb $proof $tv))
