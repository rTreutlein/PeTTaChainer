!(import! &self ../../pettachainer/metta/petta_chainer)

;; The stable facade retains the public compile-and-query contract while
;; internal module boundaries remain free to change.
!(compileadd boundary-kb (: boundary-fact (Boundary value) (STV 0.8 0.9)))
!(test (query 10 boundary-kb (: $prf (Boundary value) $tv))
   (: boundary-fact (Boundary value) (STV 0.8 0.9)))
