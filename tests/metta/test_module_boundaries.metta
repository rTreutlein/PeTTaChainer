!(import! &self ../../pettachainer/metta/petta_chainer)

;; Shared safe insertion remains reachable through the canonical import.
!(bind! &module_boundary_tmp (new-space))
!(test (chainer-add-atom &module_boundary_tmp (Stored acyclic)) true)
!(test (match &module_boundary_tmp (Stored $x) $x) acyclic)

;; Backward aggregate finalization remains reachable through the canonical import.
!(test (finish-aggregate weighted-base-rate (BaseRateEvidence 1.0 1.0))
   (STV 1.0 1.0))

;; Query orchestration remains public at the unchanged canonical import path.
!(compileadd boundary-kb (: boundary-fact (Boundary value) (STV 0.8 0.9)))
!(test (query 10 boundary-kb (: $prf (Boundary value) $tv))
   (: boundary-fact (Boundary value) (STV 0.8 0.9)))
