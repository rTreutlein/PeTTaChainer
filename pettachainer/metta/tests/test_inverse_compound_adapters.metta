!(import! &self petta_chainer)

!(compileadd inverseCompoundKb
   (: p_qr
      (Implication
         (Premises (P $x))
         (Conclusions (And (Q $x) (R $x))))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

;; Supply observations for the compound antecedent and consequent so inversion
;; can estimate both base rates.
!(compileadd inverseCompoundKb (: p-bob (P bob) (STV 0.7 0.8)))
!(compileadd inverseCompoundKb (: q-alice (Q alice) (STV 0.9 0.8)))
!(compileadd inverseCompoundKb (: r-alice (R alice) (STV 0.8 0.8)))

;; The compiler-generated adapter first reconstructs the compound consequent
;; from its children, allowing inversion to derive P.
!(test
   (query 300 inverseCompoundKb (: $prf (P alice) $tv))
   (: ((inverted p_qr with
          (foldall-proof p-bob)
          (foldall-proof
             (conjunction q-alice r-alice)
             (p_qr p-bob)
             (conjunction (marginal-proj 0 (p_qr p-bob)) r-alice)
             (conjunction q-alice (marginal-proj 1 (p_qr p-bob)))))
       (conjunction q-alice r-alice))
      (P alice)
      (STV 0.7905396295087841 0.008823683939600556)))
