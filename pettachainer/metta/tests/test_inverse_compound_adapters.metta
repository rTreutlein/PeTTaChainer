!(import! &self ../petta_chainer)

!(compileadd inverseCompoundKb
   (: p_qr
      (Implication
         (P $x)
         (And (Q $x) (R $x)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

;; Supply observations for the compound antecedent and consequent so inversion
;; can estimate both base rates.
!(compileadd inverseCompoundKb (: p-bob (P bob) (STV 0.7 0.8)))
!(compileadd inverseCompoundKb (: q-alice (Q alice) (STV 0.9 0.8)))
!(compileadd inverseCompoundKb (: r-alice (R alice) (STV 0.8 0.8)))

;; The compiler-generated adapter first reconstructs the compound consequent
;; from its children, allowing inversion to derive P. The base-rate scan keeps
;; the shared `$x`, so it counts only valid same-entity conjunctions.
!(test
   (query 300 inverseCompoundKb (: $prf (P alice) $tv))
   (: ((inverted p_qr with
          (foldall-proof p-bob)
          (foldall-proof
             (conjunction q-alice r-alice)
             (by p_qr p-bob)))
       (conjunction q-alice r-alice))
      (P alice)
      (STV 0.730644992235394 0.0020226270843351274)))
