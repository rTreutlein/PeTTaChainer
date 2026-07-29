!(import! &self ../petta_chainer)

; --- Unit checks for the uniform 1/N node prior ----------------------------

; Distinct subjects are deduped before counting.
!(test (list-len (list_to_set (cons rv1 (cons rv2 (cons rv1 ()))))) 2)

; Two distinct subjects -> prior 1/2, confidence count-confidence(2).
!(test (UniformPriorTv (cons rv1 (cons rv2 (cons rv1 ())))) (STV 0.5 0.0024937655860349127))

; Empty observation set -> no evidence (no division by zero).
!(test (UniformPriorTv ()) no-evidence)

; Concept-node prior strength stays dynamic over the currently known inheritance
; endpoint nodes, but its confidence is a tiny synthetic default unless a KB
; explicitly opts into a stronger example prior.
!(compileadd dynConceptPriorKb (: rv1Raven (Inheritance rv1 raven) (STV 0.9 0.9)))
!(compileadd dynConceptPriorKb (: rv2Black (Inheritance rv2 (IntSet black)) (STV 0.0 0.9)))

!(test (concept-node-prior-tv dynConceptPriorKb rv1) (STV 0.25 0.000001))

!(set-concept-prior-confidence dynConceptPriorKb 0.9)

!(test (concept-node-prior-tv dynConceptPriorKb rv1) (STV 0.25 0.9))

!(test
   (BaseRateWithPriorFormula
      (concept-node-prior-tv dynConceptPriorKb raven)
      (STV 0.9 0.9))
   (STV 0.575 0.9473684210526316))

!(compileadd dynConceptPriorKb (: ravenBird (Inheritance raven bird) (STV 0.9 0.9)))

!(test (concept-node-prior-tv dynConceptPriorKb rv1) (STV 0.2 0.9))

!(clear-concept-prior-confidence dynConceptPriorKb)

!(test (concept-node-prior-tv dynConceptPriorKb rv1) (STV 0.2 0.000001))
