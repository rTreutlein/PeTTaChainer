!(import! &self ../petta_chainer)

!(compileadd invKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd invKb (: qa (Q alice) (STV 0.9 0.8)))

!(compileadd invKb (: pb (P bob) (STV 0.7 0.8)))

; Inversion needs base rates of both P and Q, found as FoldAll aggregates over
; all proofs of each pattern. Each instance contributes a single
; confidence-weighted piece of evidence (count-confidence with K=800):
; pb -> P base rate, qa -> Q base rate. The inverted CTV is then applied to
; the witness qa via modus ponens.
!(test
   (query 200 invKb (: $prf (P alice) $tv))
   (: ((inverted r with (foldall-proof pb) (foldall-proof qa (by r pb))) qa) (P alice) (STV 0.736162240263287 0.0003604307138536469)))
