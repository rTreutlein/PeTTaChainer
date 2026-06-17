!(import! &self petta_chainer)

; --- Unit checks for the uniform 1/N node prior ----------------------------

; Distinct subjects are deduped before counting.
!(test (list-len (list_to_set (cons rv1 (cons rv2 (cons rv1 ()))))) 2)

; Two distinct subjects -> prior 1/2, confidence count-confidence(2).
!(test (UniformPriorTv (cons rv1 (cons rv2 (cons rv1 ())))) (STV 0.5 0.0024937655860349127))

; Empty observation set -> no evidence (no division by zero).
!(test (UniformPriorTv ()) no-evidence)

; --- Integration: induction with every base rate derived from the facts ----
; No set-base-rate anywhere. P(raven)=0.9 and P(black)=0.4 are folded from the
; instances; the subject prior is folded as 1/N=0.5 over the distinct observed
; ravens. The uniform-prior fold runs through the chainer as a rule premise.

!(compileadd urKb (: rv1Raven (Inheritance rv1 raven) (STV 0.9 0.9)))
!(compileadd urKb (: rv2Raven (Inheritance rv2 raven) (STV 0.9 0.9)))
!(compileadd urKb (: rv1Black (Inheritance rv1 (IntSet black)) (STV 0.8 0.9)))
!(compileadd urKb (: rv2NotBlack (Inheritance rv2 (IntSet black)) (STV 0.0 0.9)))

!(register-inheritance-induction! urKb)

!(test
   (query 100 urKb (: $prf (Inheritance raven (IntSet black)) $tv))
   (: (merge/revision
         (inheritanceInduction rv1Raven rv1Black)
         (inheritanceInduction rv2Raven rv2NotBlack))
      (Inheritance raven (IntSet black))
      (STV 0.5 0.3932038834951457)))
