!(import! &self ../petta_chainer)

;; User-facing negated facts are stored canonically as the positive predicate
;; with complemented strength, so population folds see both outcomes.
!(compileadd negatedFactKb
   (: not-p (Not (P a)) (STV 0.8 0.9)))

!(test
   (query 10 negatedFactKb (: $prf (P a) $tv))
   (: not-p (P a) (STV 0.19999999999999996 0.9)))

;; The ordinary query adapter reconstructs the source-facing negation.
!(test
   (query 10 negatedFactKb (: $prf (Not (P a)) $tv))
   (: (negated not-p) (Not (P a)) (STV 0.8 0.9)))

;; Normalization retains the source proof name, so statement removal works on
;; the canonical inner fact as usual.
!(remove-compiled-statement not-p)
!(test (query 10 negatedFactKb (: $prf (P a) $tv)) ())
!(test (query 10 negatedFactKb (: $prf (Not (P a)) $tv)) ())

!(compileadd negatedBaseRateKb
   (: p_to_q
      (Implication (P $x) (Q $x))
      (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd negatedBaseRateKb (: p-pos (P old-pos) (STV 1.0 1.0)))
!(compileadd negatedBaseRateKb (: p-neg (Not (P old-neg)) (STV 1.0 1.0)))
!(compileadd negatedBaseRateKb (: q-pos (Q old-pos) (STV 1.0 1.0)))
!(compileadd negatedBaseRateKb (: q-neg (Not (Q old-neg)) (STV 1.0 1.0)))
!(compileadd negatedBaseRateKb (: q-current (Q current) (STV 1.0 1.0)))

;; Inversion now has non-degenerate P and Q marginals instead of seeing only
;; the positive observations at strength one.
!(test
   (> (length
      (query 200 negatedBaseRateKb (: $prf (P current) $tv))) 0)
   true)
