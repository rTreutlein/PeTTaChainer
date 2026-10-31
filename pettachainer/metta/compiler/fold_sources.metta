;; Decode lowered existential sources and filter empty instance judgments.

(: existential-fold-source (-[nondet]-> Atom SkPattern))
(= (existential-fold-source $premise)
   (case $premise (
      ((CPU $fun $args $_res)
         (if (if (== $fun FoldAllCompiled) true (== $fun GroupedFoldAllCompiled))
            (let $pattern (car-atom (cdr-atom $args))
               (if (head-is? $pattern ExistentialAlternatives)
                  (let* (((ExistentialAlternatives $claim $_channel) $pattern)
                         ($scope (car-atom $args))
                         ((Exists $_binder $body) (existential-source $claim))
                         ($sources (cons $claim (implication-side-conjuncts (brand Statement $body))))
                         ($source (superpose $sources)))
                     (assemble-stored-runtime-fact $source $scope $_proof $_tv))
                  (empty)))
            (empty)))
      ($_other (empty)))))

(: InstanceEvidenceFormula (-[nondet]-> Bool TV TV))
(= (InstanceEvidenceFormula $full? $tv)
   (if (== $tv no-evidence) (empty)
      (if $full? $tv
         (let (STV $s $c)
            (case $tv (((CTV $positive $_negative) $positive) ($_stv $tv)))
            (if (> $c 0.0) (STV $s $c) (empty))))))
