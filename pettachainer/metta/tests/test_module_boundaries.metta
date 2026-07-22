!(import! &self ../petta_chainer)

;; Foundational insertion remains reachable through the canonical import.
!(bind! &module_boundary_tmp (new-space))
!(test (chainer-add-atom &module_boundary_tmp (Stored acyclic)) true)
!(test (match &module_boundary_tmp (Stored $x) $x) acyclic)

;; Shared fold finalization is loaded before either chainer consumes it.
!(test (finish-aggregate weighted-base-rate (BaseRateEvidence 1.0 1.0))
   (STV 1.0 1.0))

;; Query orchestration remains public at the unchanged canonical import path.
!(compileadd boundary-kb (: boundary-fact (Boundary value) (STV 0.8 0.9)))
!(test (query 10 boundary-kb (: $prf (Boundary value) $tv))
   (: boundary-fact (Boundary value) (STV 0.8 0.9)))
