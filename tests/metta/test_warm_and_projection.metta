!(import! &self ../../pettachainer/metta/petta_chainer)


;; A connective containing an implication is not a connective over only user
;; predicates. Its member compiler needs the original shape, including the
;; metadata child; abstracting that child to a variable lets it become CPU.
!(test
   (pattern-shape (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
!(test
   (pattern-shape (Or (Metadata S) (Implication (A $x) (C $x))))
   (Or (Metadata S) (Implication (A $x) (C $x))))
!(test
   (pattern-shape (Not (And (Metadata S) (Implication (A $x) (C $x)))))
   (Not (And (Metadata S) (Implication (A $x) (C $x)))))

;; Compare the complete proof and both TV components with a fresh KB, and the
;; strength with the expected one. A singleton is required: an empty result
;; must fail, not skip the assertion. A rule's consequent C reads .8; a part C
;; of a predicted And(B, C) at .8 moves from its uniform prior by probability
;; kinematics, B unknown: the parts' 1/4 at their exact variance 7/144 (n =
;; 20/7) revised with the prediction to P*, and C = P* + (1 - P*)/3: .8658 at
;; the rule's confidence .6, .8656 at the wrapped rule's .5455.
(: warm-stale-matches? (-[semidet]-> Number Number KB KB Statement Bool))
(= (warm-stale-matches? $strength $steps $warm $cold $statement)
   (let* (((cons (: $proof $_type (STV $s $c)) ())
              (collapse (query $steps $warm (: $p $statement $tv))))
          ((cons (: $fresh-proof $_fresh-type (STV $fresh-s $fresh-c)) ())
              (collapse (query 300 $cold (: $q $statement $value)))))
      (and (=alpha $proof $fresh-proof)
         (and (< (abs-math (- $s $strength)) 1e-9)
            (and (> $c 0)
               (and (< (abs-math (- $s $fresh-s)) 1e-9)
                    (< (abs-math (- $c $fresh-c)) 1e-8)))))))

;; flat: failed query before the first input arrives.
!(compileadd flatfailedWarmKb (: rule (Implication (A $x) (And (B $x) (C $x))) (STV 0.8 0.6)))
!(compileadd flatfailedColdKb (: rule (Implication (A $x) (And (B $x) (C $x))) (STV 0.8 0.6)))
!(test (collapse (query 300 flatfailedWarmKb (: $p (C a) $tv))) ())
!(compileadd flatfailedWarmKb (: a (A a) (STV 1 1)))
!(compileadd flatfailedColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8657957244653 300 flatfailedWarmKb flatfailedColdKb (C a)) true)
!(test (warm-stale-matches? 0.8657957244653 0 flatfailedWarmKb flatfailedColdKb (C a)) true)

;; flat: implication query before the first input arrives.
!(compileadd flatimplicationWarmKb (: rule (Implication (A $x) (And (B $x) (C $x))) (STV 0.8 0.6)))
!(compileadd flatimplicationColdKb (: rule (Implication (A $x) (And (B $x) (C $x))) (STV 0.8 0.6)))
!(collapse (query 300 flatimplicationWarmKb (: $p (Implication (A $x) (C $x)) $tv)))
!(compileadd flatimplicationWarmKb (: a (A a) (STV 1 1)))
!(compileadd flatimplicationColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8657957244653 300 flatimplicationWarmKb flatimplicationColdKb (C a)) true)
!(test (warm-stale-matches? 0.8657957244653 0 flatimplicationWarmKb flatimplicationColdKb (C a)) true)

;; nested: failed query before the first input arrives.
!(compileadd nestedfailedWarmKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd nestedfailedWarmKb (: rule (Implication (AcceptSource S) (Implication (A $x) (And (B $x) (C $x)))) (STV 0.8 0.6)))
!(compileadd nestedfailedColdKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd nestedfailedColdKb (: rule (Implication (AcceptSource S) (Implication (A $x) (And (B $x) (C $x)))) (STV 0.8 0.6)))
!(test (collapse (query 300 nestedfailedWarmKb (: $p (C a) $tv))) ())
!(compileadd nestedfailedWarmKb (: a (A a) (STV 1 1)))
!(compileadd nestedfailedColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8657957244653 300 nestedfailedWarmKb nestedfailedColdKb (C a)) true)
!(test (warm-stale-matches? 0.8657957244653 0 nestedfailedWarmKb nestedfailedColdKb (C a)) true)

;; nested: implication query before the first input arrives.
!(compileadd nestedimplicationWarmKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd nestedimplicationWarmKb (: rule (Implication (AcceptSource S) (Implication (A $x) (And (B $x) (C $x)))) (STV 0.8 0.6)))
!(compileadd nestedimplicationColdKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd nestedimplicationColdKb (: rule (Implication (AcceptSource S) (Implication (A $x) (And (B $x) (C $x)))) (STV 0.8 0.6)))
!(collapse (query 300 nestedimplicationWarmKb (: $p (Implication (A $x) (C $x)) $tv)))
!(compileadd nestedimplicationWarmKb (: a (A a) (STV 1 1)))
!(compileadd nestedimplicationColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8657957244653 300 nestedimplicationWarmKb nestedimplicationColdKb (C a)) true)
!(test (warm-stale-matches? 0.8657957244653 0 nestedimplicationWarmKb nestedimplicationColdKb (C a)) true)

;; wrapped: failed query before the first input arrives.
!(compileadd wrappedfailedWarmKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd wrappedfailedWarmKb (: rule (Implication (AcceptSource S) (And (Metadata S) (Implication (A $x) (And (B $x) (C $x))))) (STV 0.8 0.6)))
!(compileadd wrappedfailedColdKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd wrappedfailedColdKb (: rule (Implication (AcceptSource S) (And (Metadata S) (Implication (A $x) (And (B $x) (C $x))))) (STV 0.8 0.6)))
!(test (collapse (query 300 wrappedfailedWarmKb (: $p (C a) $tv))) ())
!(compileadd wrappedfailedWarmKb (: a (A a) (STV 1 1)))
!(compileadd wrappedfailedColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8655786350146 300 wrappedfailedWarmKb wrappedfailedColdKb (C a)) true)
!(test (warm-stale-matches? 0.8655786350146 0 wrappedfailedWarmKb wrappedfailedColdKb (C a)) true)

;; A second expanded instance must recover independently, while the
;; first keeps its proof.
!(test (collapse (query 300 wrappedfailedWarmKb (: $p (C b) $tv))) ())
!(compileadd wrappedfailedWarmKb (: b (A b) (STV 1 1)))
!(compileadd wrappedfailedColdKb (: b (A b) (STV 1 1)))
!(test (warm-stale-matches? 0.8655786350146 300 wrappedfailedWarmKb wrappedfailedColdKb (C b)) true)
!(test (warm-stale-matches? 0.8655786350146 0 wrappedfailedWarmKb wrappedfailedColdKb (C a)) true)

;; wrapped: implication query before the first input arrives.
!(compileadd wrappedimplicationWarmKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd wrappedimplicationWarmKb (: rule (Implication (AcceptSource S) (And (Metadata S) (Implication (A $x) (And (B $x) (C $x))))) (STV 0.8 0.6)))
!(compileadd wrappedimplicationColdKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd wrappedimplicationColdKb (: rule (Implication (AcceptSource S) (And (Metadata S) (Implication (A $x) (And (B $x) (C $x))))) (STV 0.8 0.6)))
!(collapse (query 300 wrappedimplicationWarmKb (: $p (Implication (A $x) (C $x)) $tv)))
!(compileadd wrappedimplicationWarmKb (: a (A a) (STV 1 1)))
!(compileadd wrappedimplicationColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8655786350146 300 wrappedimplicationWarmKb wrappedimplicationColdKb (C a)) true)
!(test (warm-stale-matches? 0.8655786350146 0 wrappedimplicationWarmKb wrappedimplicationColdKb (C a)) true)

;; plain: failed query before the first input arrives.
!(compileadd plainfailedWarmKb (: rule (Implication (A $x) (C $x)) (STV 0.8 0.6)))
!(compileadd plainfailedColdKb (: rule (Implication (A $x) (C $x)) (STV 0.8 0.6)))
!(test (collapse (query 300 plainfailedWarmKb (: $p (C a) $tv))) ())
!(compileadd plainfailedWarmKb (: a (A a) (STV 1 1)))
!(compileadd plainfailedColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8 300 plainfailedWarmKb plainfailedColdKb (C a)) true)
!(test (warm-stale-matches? 0.8 0 plainfailedWarmKb plainfailedColdKb (C a)) true)

;; plain: implication query before the first input arrives.
!(compileadd plainimplicationWarmKb (: rule (Implication (A $x) (C $x)) (STV 0.8 0.6)))
!(compileadd plainimplicationColdKb (: rule (Implication (A $x) (C $x)) (STV 0.8 0.6)))
!(collapse (query 300 plainimplicationWarmKb (: $p (Implication (A $x) (C $x)) $tv)))
!(compileadd plainimplicationWarmKb (: a (A a) (STV 1 1)))
!(compileadd plainimplicationColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8 300 plainimplicationWarmKb plainimplicationColdKb (C a)) true)
!(test (warm-stale-matches? 0.8 0 plainimplicationWarmKb plainimplicationColdKb (C a)) true)

;; nestedPlain: failed query before the first input arrives.
!(compileadd nestedPlainfailedWarmKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd nestedPlainfailedWarmKb (: rule (Implication (AcceptSource S) (Implication (A $x) (C $x))) (STV 0.8 0.6)))
!(compileadd nestedPlainfailedColdKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd nestedPlainfailedColdKb (: rule (Implication (AcceptSource S) (Implication (A $x) (C $x))) (STV 0.8 0.6)))
!(test (collapse (query 300 nestedPlainfailedWarmKb (: $p (C a) $tv))) ())
!(compileadd nestedPlainfailedWarmKb (: a (A a) (STV 1 1)))
!(compileadd nestedPlainfailedColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8 300 nestedPlainfailedWarmKb nestedPlainfailedColdKb (C a)) true)
!(test (warm-stale-matches? 0.8 0 nestedPlainfailedWarmKb nestedPlainfailedColdKb (C a)) true)

;; nestedPlain: implication query before the first input arrives.
!(compileadd nestedPlainimplicationWarmKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd nestedPlainimplicationWarmKb (: rule (Implication (AcceptSource S) (Implication (A $x) (C $x))) (STV 0.8 0.6)))
!(compileadd nestedPlainimplicationColdKb (: s (AcceptSource S) (STV 1 1)))
!(compileadd nestedPlainimplicationColdKb (: rule (Implication (AcceptSource S) (Implication (A $x) (C $x))) (STV 0.8 0.6)))
!(collapse (query 300 nestedPlainimplicationWarmKb (: $p (Implication (A $x) (C $x)) $tv)))
!(compileadd nestedPlainimplicationWarmKb (: a (A a) (STV 1 1)))
!(compileadd nestedPlainimplicationColdKb (: a (A a) (STV 1 1)))
!(test (warm-stale-matches? 0.8 300 nestedPlainimplicationWarmKb nestedPlainimplicationColdKb (C a)) true)
!(test (warm-stale-matches? 0.8 0 nestedPlainimplicationWarmKb nestedPlainimplicationColdKb (C a)) true)
