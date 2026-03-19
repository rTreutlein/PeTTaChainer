!(import! &self petta_chainer)

;; Minimal propositional Hilbert base encoded for the PeTTa chainer.
;; Object-language formulas are wrapped in (Provable ...).
;; All axioms and inference rules use unit STVs.
!(compileadd mathkb
   (: (no_inverse ax-mp)
      (Implication (Premises (Provable (→ $𝜑 $𝜓)) (Provable $𝜑))
         (Conclusions (Provable $𝜓)))
      (STV 1.0 1.0)))

!(compileadd mathkb (: ax-1 (Provable (→ $𝜑 (→ $𝜓 $𝜑))) (STV 1.0 1.0)))

!(compileadd mathkb
   (: ax-2 (Provable (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒)))) (STV 1.0 1.0)))

!(compileadd mathkb (: ax-3 (Provable (→ (→ (¬ $𝜑) (¬ $𝜓)) (→ $𝜓 $𝜑))) (STV 1.0 1.0)))

!(===========================================)

!(query 1000 mathkb (: $prf (Provable $a) $tv))
