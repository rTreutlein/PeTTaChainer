!(import! &self ../../pettachainer/metta/petta_chainer)

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
