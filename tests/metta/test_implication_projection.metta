!(import! &self ../../pettachainer/metta/petta_chainer)

;; An implication query proves its consequent under the positive assumption
;; of its antecedent, returning an STV. For a rule S -> (A and B and C),
;; projection adapters run in that context. The stored positive branch is 0.9
;; at confidence 0.9; MP propagates its variance, then marginal projection
;; gives c' = s*c / (s*c + 1 - c) = 0.81/0.91 = 0.8901098901.
;; Parts of one source pool, so querying (And A B), either part, or reordered
;; parts returns the same positive strength and confidence. The negative
;; branch remains in internal rule storage for modus ponens.

!(compileadd ctvKb (: r (Implication S (And A B C)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (query 100 ctvKb (: $prf (Implication S (And A B)) $tv))
   (:
      (conditional-implication
         (conjunction (marginal-proj 0 (by r (ctx proof 0))) (marginal-proj 1 (by r (ctx proof 0)))))
      (Implication S (And A B))
      (STV 0.9 0.8901098896304337)))

;; The query's truth-value pattern, a single part and the parts in another
;; order give the same values.
!(test
   (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S (And A B)) $pos)) $tv)
   (STV 0.9 0.8901098896304337))

!(test
   (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S A) $tv)) $tv)
   (STV 0.9 0.8901098896304337))

!(test
   (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S (And B A)) $tv)) $tv)
   (STV 0.9 0.8901098896304337))

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
   (STV 0.9 0.8901098893173621))

!(test
   (let (: $_prf $_type $tv) (query 100 stvKb (: $prf (Implication (S $y) (And (A $y) (B $y))) $tv)) $tv)
   (STV 0.9 0.8901098893173621))

;; A nested conclusion, S -> (A and (B and C)). B and C are parts of one
;; source and pool; A and B are parts of different sources, (A and (B and C))
;; and (B and C), which both rest on the rule's one conclusion. Conjoined
;; they are conditioned on it (docs/metta/overlap_conditioning.md,
;; "Entangled premises"): 0.9 and 0.2, the rule's own branches (before:
;; 0.9 * 0.9 and 0.2 * 0.2, multiplied as independent).
!(compileadd nestedKb (: r (Implication S (And A (And B C))) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (let (: $_prf $_type $tv) (query 100 nestedKb (: $prf (Implication S (And B C)) $tv)) $tv)
   (STV 0.9 0.8901098896304337))

!(test
   (let (: $_prf $_type $tv) (query 100 nestedKb (: $prf (Implication S (And A B)) $tv)) $tv)
   (STV 0.9 0.8999278939280647))

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
