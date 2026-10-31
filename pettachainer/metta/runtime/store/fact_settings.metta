;; Indexed declaration and authoritative base-rate reads.
;; No installation, compiler plans, proof semantics or inference.
(: complete-predicate? (-[det]-> KB Atom Bool))
(= (complete-predicate? $kb $head)
   (not (== (collapse (once (match &complete_predicates ($kb $head) true))) ())))
(: positive-only-pattern? (-[det]-> KB Statement Bool))
(= (positive-only-pattern? $kb $pattern)
   (fold-flat (positive-only-conjunct? $kb) false (implication-side-conjuncts $pattern)))
(: positive-only-conjunct? (-[det]-> KB Bool Atom Bool))
(= (positive-only-conjunct? $kb $seen $conjunct)
   (if $seen true
      (let* ((($statement $_odd) (canon (brand Statement $conjunct)))
             ($head (if (is-expr $statement) (car-atom $statement) $statement)))
         (not (== (collapse (once (match &positive_only_predicates ($kb $head) true))) ())))))

(: user-base-rate? (-[det]-> KB Statement Bool))
(= (user-base-rate? $kb $pattern)
   (let $hash (index-hash (quote ($kb $pattern)))
      (not (== (collapse (once (match &ctx_base_rate_cache
         ($hash (base-rate $kb $stored $_tv user any))
         (if (=alpha $stored $pattern) true (empty))))) ()))))
