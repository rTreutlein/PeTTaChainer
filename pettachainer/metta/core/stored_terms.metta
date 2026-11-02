(: typed-runtime-fact (-[det]-> Atom (Statement KBContext Proof TV)))
(= (typed-runtime-fact ($type $kb $proof $tv))
   (assemble-runtime-fact (brand Statement $type) (brand KBContext $kb) (brand Proof $proof) (checked-stored-tv $tv)))

(: typed-runtime-premise (-[semidet]-> Atom (| Goal (Statement KBContext Proof TV))))
(= (typed-runtime-premise $premise)
   (if (= $premise (CPU $formula $arguments $result))
      (CPU $formula $arguments $result)
      (typed-runtime-fact $premise)))

;; Compiler output crosses an erased-expression storage boundary here. Restore
;; each premise's nominal role while walking the list we already consume,
;; rather than reflectively checking the complete list with `(the ...)`.
(: typed-runtime-premises (-[semidet]-> Atom (List (| Goal (Statement KBContext Proof TV)))))
(= (typed-runtime-premises $premises)
   (case $premises (
      (() ())
      ((cons $premise $rest)
         (cons (typed-runtime-premise $premise) (typed-runtime-premises $rest))))))
