!(import! &self ../../pettachainer/metta/petta_chainer)

;; Idealized confidence: second-order uncertainty propagation. Confidence follows
;; the variance of the conclusion's strength, propagated exactly through each
;; formula and converted back to a count. Verified against Monte-Carlo.

;; --- Modus ponens ---
;; symmetric implication (both branches confident): confidence is high and tracks
;; how well the marginal is pinned down.
!(test (CTVModusPonensFormula (STV 0.5 0.9) (CTV (STV 0.8 0.9) (STV 0.2 0.9)))
   (STV 0.5 0.9297507003411903))
;; same implication, unsure antecedent: confidence drops.
!(test (CTVModusPonensFormula (STV 0.5 0.3) (CTV (STV 0.8 0.9) (STV 0.2 0.9)))
   (STV 0.5 0.533570866460099))

;; One-sided implication (the realistic case): confident on the positive branch,
;; unsure on the negative (P(B | not A) is hard to estimate). Confidence then
;; depends on which branch we lean on:
;;   antecedent likely TRUE  -> lean on the known positive branch -> higher
;;   antecedent likely FALSE -> forced onto the unknown negative  -> lower
!(test (CTVModusPonensFormula (STV 0.9 0.9) (CTV (STV 0.8 0.9) (STV 0.5 0.1)))
   (STV 0.77 0.8249273772285918))
!(test (CTVModusPonensFormula (STV 0.5 0.9) (CTV (STV 0.8 0.9) (STV 0.5 0.1)))
   (STV 0.65 0.2870618096418617))
!(test (CTVModusPonensFormula (STV 0.1 0.9) (CTV (STV 0.8 0.9) (STV 0.5 0.1)))
   (STV 0.53 0.12040223903159016))

;; --- Conjunction / disjunction (exact product variance) ---
!(test (AndFormula (STV 0.5 0.9) (STV 0.5 0.9)) (STV 0.25 0.9310329967103845))
!(test (AndFormula (STV 0.8 0.9) (STV 0.3 0.5)) (STV 0.24 0.572930511571637))
!(test (OrFormula (STV 0.5 0.9) (STV 0.5 0.9)) (STV 0.75 0.9310329967103845))

;; --- Inversion (Bayes ratio) ---
;; Well-supported base rates: variance propagates through P(A|B)=sb_a*sa/sb by the
;; delta method (validated against Monte-Carlo).
!(test (CTVInversionFormula (STV 0.3 0.9) (STV 0.5 0.9) (CTV (STV 0.7 0.9) (STV 0.0 1.0)))
   (CTV (STV 0.4199966700913868 0.7676062411488879) (STV 0.1800033299086132 0.8785665683836059)))
;; Frechet-inconsistent inputs: P(A)=0.7 and P(B)=0.9 force P(B|A) >= (0.7+0.9-1)/0.7
;; = 0.857, but the rule asserts P(B|A)=0.8. The least evidence that restores the
;; bound is dropped first; the weakly supported base rates give way, not the rule,
;; and the inversion holds at the confidence what remains supports.
!(test (CTVInversionFormula (STV 0.7 0.001) (STV 0.9 0.001) (CTV (STV 0.8 0.9) (STV 0.1 0.9)))
   (CTV (STV 0.5991684764483071 0.0007907267437587532) (STV 1.0 1.0e-06)))

;; The reconciliation itself. Over the upper bound P(B)/P(A) = 0.5 < 0.99, the
;; counts are drained until P(A) P(B|A) = P(B); a base rate of 1.0 from one
;; observation cannot move by draining, so it loses its evidence instead of
;; overriding a well-supported rule; nothing changes when the bounds hold.
!(test (ConsistentTriple (STV 0.4 0.9) (STV 0.2 0.9) (STV 0.99 0.9))
   (stv-triple (STV 0.21911294900796238 0.8736610061711604) (STV 0.2169183962662314 0.8924505836885637) (STV 0.9899843767715834 0.8998594129084929)))
!(test (ConsistentTriple (STV 1.0 0.00224) (STV 1.0 0.00112) (STV 0.8 0.9))
   (stv-triple (STV 1.0 0.00224) (STV 1.0 0.0) (STV 0.8 0.9)))
!(test (ConsistentTriple (STV 0.3 0.9) (STV 0.5 0.9) (STV 0.7 0.9))
   (stv-triple (STV 0.3 0.9) (STV 0.5 0.9) (STV 0.7 0.9)))

;; --- End-to-end realistic example ---
;; Diagnostic-style inference with one-sided rules and uncertain evidence.
!(compileadd med (: fever (Fever p) (STV 1.0 0.8)))
!(compileadd med (: cough (Cough p) (STV 0.6 0.7)))
!(compileadd med
   (: fluRule (Implication (And (Fever $x) (Cough $x)) (Flu $x))
      (CTV (STV 0.7 0.85) (STV 0.5 0.15))))
!(compileadd med
   (: tiredRule (Implication (Flu $x) (Tired $x))
      (CTV (STV 0.9 0.9) (STV 0.5 0.1))))

;; Flu from And(Fever, Cough) through the one-sided fluRule.
!(test (query 40 med (: $prf (Flu p) $tv))
   (: (by fluRule (conjunction fever cough)) (Flu p) (STV 0.62 0.49224732166420715)))

;; Tired chains one more one-sided step; confidence erodes further down the chain.
!(test (query 60 med (: $prf (Tired p) $tv))
   (: (by tiredRule (by fluRule (conjunction fever cough))) (Tired p) (STV 0.748 0.3402330502780622)))

;; With no Bayes prior, a likelihood without evidence is read as it is:
;; 0.9 * 0.5 / (0.9 * 0.5 + 0.2 * 0.5).
!(set-bayes-prior-count 0.0)
!(test (CTVBayesFormula (STV 0.5 0.9) (CTV (STV 0.9 0.0) (STV 0.2 0.9)))
   (CTV (STV 0.8181818181818181 0.06857724870583486) (STV 0.11111111111111108 0.00015613340650492377)))
!(set-bayes-prior-count 0.2)
