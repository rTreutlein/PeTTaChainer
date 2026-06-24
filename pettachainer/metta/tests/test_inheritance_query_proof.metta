!(import! &self petta_chainer)

;; Characterization test for the inheritance-query branch of compileQuery
;; (the "block C" derived-implication path). It pins the proof token
;; (inheritance-query (total-implication POS NEG)) where POS/NEG carry the
;; (ctx proof 0)/(ctx proof 1) tokens produced by sharing $pos-prf/$neg-prf
;; between the adapter adds and the rule's known goals. If a refactor of the
;; shared pos/neg adds machinery severs that variable identity, this query
;; either stops resolving (empty) or emits a different proof, so this guards
;; the dedup of the duplicated pos/neg blocks in compileQuery.

!(compileadd inheritanceQueryKb (: i1 (Inheritance a Bird) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i2 (Inheritance a Flier) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i3 (Inheritance b Bird) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i4 (Inheritance b Flier) (STV 1.0 0.9)))

!(test
   (collapse (query 80 inheritanceQueryKb (: $prf (Inheritance Bird Flier) $tv)))
   ((: (inheritance-query (total-implication ((inheritance-implication i4) ((inverted (inheritance-implication i3) with (foldall-proof ((inverted (inheritance-implication i4) with cpu (foldall-proof i2 i4)) i2) ((inverted (inheritance-implication i4) with (foldall-proof i2 i4) (foldall-proof i2 i4)) i4)) (foldall-proof i1 i3)) (ctx proof 0))) ((inheritance-implication i4) ((inverted (inheritance-implication i3) with (foldall-proof ((inverted (inheritance-implication i4) with cpu (foldall-proof i2 i4)) i2) ((inverted (inheritance-implication i4) with (foldall-proof i2 i4) (foldall-proof i2 i4)) i4)) (foldall-proof i1 i3)) (ctx proof 1))))) (Inheritance Bird Flier) (STV 0.9995836610860238 0.0018662506673711578))))
