!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd inverseCompoundKb
   (: p_qr
      (Implication
         (P $x)
         (And (Q $x) (R $x)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

;; Supply observations for the compound consequent and for the antecedent's
;; base rate, the prior the inversion reads.
!(compileadd inverseCompoundKb (: p-bob (P bob) (STV 0.7 0.8)))
!(compileadd inverseCompoundKb (: q-alice (Q alice) (STV 0.9 0.8)))
!(compileadd inverseCompoundKb (: r-alice (R alice) (STV 0.8 0.8)))

;; The compiler-generated adapter first reconstructs the compound consequent
;; from its children, allowing inversion to derive P: the conjunction 0.72
;; weighs P(P | Q and R) = 0.8 * 0.7 / (0.8 * 0.7 + 0.1 * 0.3) and
;; P(P | not (Q and R)) = 0.2 * 0.7 / (0.2 * 0.7 + 0.9 * 0.3).
!(test
   (query 300 inverseCompoundKb (: $prf (P alice) $tv))
   (: ((inverted p_qr with cpu (prior (STV 0.6599999999999998 0.0009990009990009992))) (conjunction q-alice r-alice)) (P alice) (STV 0.760823053647666 0.016270192255568902)))

;; A rule stated with an STV is inverted over the base rates of both sides.
;; The compound consequent's base-rate scan keeps the shared `$x`, so it
;; counts only valid same-entity conjunctions: alice's, not carol's Q with
;; alice's R. The inversion excludes Alice's own observation: no independent
;; consequent remains, so it returns the population prior rather than
;; increasing confidence with its own evidence.
!(compileadd inverseCompoundStvKb
   (: p_qr
      (Implication
         (P $x)
         (And (Q $x) (R $x)))
      (STV 0.8 0.9)))
!(compileadd inverseCompoundStvKb (: p-bob (P bob) (STV 0.7 0.8)))
!(compileadd inverseCompoundStvKb (: q-alice (Q alice) (STV 0.9 0.8)))
!(compileadd inverseCompoundStvKb (: r-alice (R alice) (STV 0.8 0.8)))
!(compileadd inverseCompoundStvKb (: q-carol (Q carol) (STV 0.9 0.8)))

!(test
   (query 300 inverseCompoundStvKb (: $prf (P alice) $tv))
   (: (population-prior (P $x)) (P alice) (STV 0.6599999999999998 0.0009990009990009992)))
!(test
   (cached-base-rate inverseCompoundStvKb (And (Q $x) (R $x)))
   ((STV 0.7200000000000002 0.0010134642737165396)))
