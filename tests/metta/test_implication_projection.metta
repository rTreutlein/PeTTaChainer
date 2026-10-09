!(import! &self ../../pettachainer/metta/petta_chainer)

;; An implication query proves its consequent in hypothetical contexts where
;; the antecedent is assumed, true in the positive one and false in the
;; refuting one. A rule concluding a conjunction, S -> (A and B and C), is
;; projected onto its parts there as in the main context: its projection
;; adapters are compiled in the rule's context, not the main one only.
;;
;; Values by hand. The rule's CTV is (0.9, 0.2) at confidence 0.9. With S
;; certain, modus ponens gives the conjunction 0.9 in the positive context
;; and 0.2 in the refuting one, at confidence 0.9 (0.89999999956 and
;; 0.89999999975: the idealized variance of modus ponens). A part's marginal
;; projection keeps the strength and scales the count by it, c' = s c / (s c
;; + 1 - c): 0.81 / 0.91 = 0.8901098901 and 0.18 / 0.28 = 0.6428571429. Parts
;; of one source pool back into it, so A and B, two of three parts, read the
;; first part's marginal: P(A and B | S) = 0.9, P(A and B | not S) = 0.2.

!(compileadd ctvKb (: r (Implication S (And A B C)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (query 100 ctvKb (: $prf (Implication S (And A B)) $tv))
   (: (total-implication
         (conjunction (marginal-proj 0 (by r (ctx proof 0))) (marginal-proj 1 (by r (ctx proof 0))))
         (conjunction (marginal-proj 0 (by r (ctx proof 1))) (marginal-proj 1 (by r (ctx proof 1)))))
      (Implication S (And A B))
      (CTV (STV 0.9 0.8901098896304337) (STV 0.2 0.6428571422241105))))

;; The query's truth-value pattern, a single part and the parts in another
;; order give the same values.
!(test
   (let (: $_prf $_type $tv)
      (query 100 ctvKb (: $prf (Implication S (And A B)) (CTV $pos $neg)))
      $tv)
   (CTV (STV 0.9 0.8901098896304337) (STV 0.2 0.6428571422241105)))

!(test
   (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S A) $tv)) $tv)
   (CTV (STV 0.9 0.8901098896304337) (STV 0.2 0.6428571422241105)))

!(test
   (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S (And B A)) $tv)) $tv)
   (CTV (STV 0.9 0.8901098896304337) (STV 0.2 0.6428571422241105)))

;; An STV query asks for the positive side, which equals the Assuming query.
!(test
   (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S (And A B)) (STV $s $c))) $tv)
   (STV 0.9 0.8901098896304337))

!(test
   (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Assuming S (And A B)) $tv)) $tv)
   (STV 0.9 0.8901098896304337))

;; An STV rule over a variable. Its negative branch comes from the base rates
;; of both sides, which no fact here observes, so the refuting side has no
;; evidence. The ground query and the open one, over a hypothetical
;; individual, agree.
!(compileadd stvKb (: r (Implication (S $x) (And (A $x) (B $x) (C $x))) (STV 0.9 0.9)))

!(test
   (let (: $_prf $_type $tv) (query 100 stvKb (: $prf (Implication (S x) (And (A x) (B x))) $tv)) $tv)
   (CTV (STV 0.9 0.8901098893173621) (STV 0.0 0.0)))

!(test
   (let (: $_prf $_type $tv) (query 100 stvKb (: $prf (Implication (S $y) (And (A $y) (B $y))) $tv)) $tv)
   (CTV (STV 0.9 0.8901098893173621) (STV 0.0 0.0)))

;; A nested conclusion, S -> (A and (B and C)). B and C are parts of one
;; source and pool; A and B are parts of different sources, (A and (B and C))
;; and (B and C), and multiply as independent conjuncts: 0.9 * 0.9 and
;; 0.2 * 0.2 (limit: nested sources are not flattened into one pool).
!(compileadd nestedKb (: r (Implication S (And A (And B C))) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (let (: $_prf $_type $tv) (query 100 nestedKb (: $prf (Implication S (And B C)) $tv)) $tv)
   (CTV (STV 0.9 0.8901098896304337) (STV 0.2 0.6428571422241105)))

!(test
   (let (: $_prf $_type $tv) (query 100 nestedKb (: $prf (Implication S (And A B)) $tv)) $tv)
   (CTV (STV 0.81 0.8901098896304337) (STV 0.04000000000000001 0.6428571422241105)))

;; A part's projection that reads the other parts as evidence divides the
;; source by them, P(A) = P(ABC) / P(BC). The other parts' marginals read off
;; the same source would make that 0.9 / 0.9 = 1: they are not evidence apart
;; from it, so the projection does not read them. A certain fact S shares no
;; evidence, so the shared-evidence check does not stop them either.
;; A part's marginal projection keeps the strength and scales the count by
;; it, c' = s c / (s c + 1 - c): 0.81 / 0.91 = 0.8901098901 from the
;; conjunction's 0.9 at confidence 0.89999999956 (modus ponens).
!(compileadd mainKb (: s S (STV 1.0 1.0)))
!(compileadd mainKb (: r (Implication S (And A B C)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (query 100 mainKb (: $prf A $tv))
   (: (marginal-proj 0 (by r s)) A (STV 0.9 0.8901098896304337)))

!(test
   (query 100 mainKb (: $prf (And A B) $tv))
   (: (conjunction (marginal-proj 0 (by r s)) (marginal-proj 1 (by r s))) (And A B) (STV 0.9 0.8901098896304337)))

;; Other parts known apart from the source are evidence: with B and C stored,
;; P(A) = P(ABC) / P(BC) = 0.9 / (0.95 * 0.95), at the smaller confidence.
!(compileadd evidenceKb (: s S (STV 1.0 1.0)))
!(compileadd evidenceKb (: b B (STV 0.95 0.9)))
!(compileadd evidenceKb (: c C (STV 0.95 0.9)))
!(compileadd evidenceKb (: r (Implication S (And A B C)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (query 100 evidenceKb (: $prf A $tv))
   (: ((proj 0 (by r s)) (conjunction b c)) A (STV 0.997229916897507 0.8999999995588468)))
