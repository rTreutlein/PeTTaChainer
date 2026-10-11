!(import! &self ../../pettachainer/metta/petta_chainer)

;; Minimal repros of three failure families the ProbLog differential fuzzer
;; found (docs/metta/fuzzing.md, scripts/fuzz_vs_problog.py), each with
;; ProbLog's exact answer.

!(set-evidence-confidence-k 5)

;; F1. A closed read pins the reading conclusion false to cut its circular
;; support; an inversion of the reading rule must not read the pin as an
;; observation. Loop C <- (Or A D), D <- C, complete, A observed at 0.68:
;; exact P(D) = 0.9 * 0.21 * 0.68 = 0.12852 (before: 0.0147).
!(set-complete-predicate f1loop C)
!(set-complete-predicate f1loop D)
!(compileadd f1loop (: rC (Implication (Or (A $x) (D $x)) (C $x)) (CTV (STV 0.21 1) (STV 0 1))))
!(compileadd f1loop (: rD (Implication (C $x) (D $x)) (CTV (STV 0.9 1) (STV 0 1))))
!(compileadd f1loop (: obs-A-a (A a) (STV 0.68 1)))
!(set-base-rate f1loop (A $x) (STV 0.49 1.0))
!(set-base-rate f1loop (C $x) (STV 0.1029 1.0))
!(set-base-rate f1loop (D $x) (STV 0.09261 1.0))
!(test (query 2000 f1loop (: $prf (D a) $tv))
   (: (by rD (by rC (conjunction obs-A-a unfounded))) (D a) (STV 0.12852000000000002 0.9999359466218718)))

;; The same pin in a plain chain A -> B -> C over complete B, C, with A an
;; unobserved root: the inversion of rC read C's pin and answered 0.054
;; (exact 0.2195). A derivation reads no population prior, so C has no
;; answer (the documented latent-premise gap).
!(set-complete-predicate f1chain B)
!(set-complete-predicate f1chain C)
!(compileadd f1chain (: rB (Implication (A $x) (B $x)) (CTV (STV 0.7 1) (STV 0 1))))
!(compileadd f1chain (: rC (Implication (B $x) (C $x)) (CTV (STV 0.64 1) (STV 0 1))))
;; A fully observed history of 15 individuals gives B and C their base rates.
!(compileadd f1chain (: hist-A-h0 (A h0) (STV 1 1)))
!(compileadd f1chain (: hist-B-h0 (B h0) (STV 0 1)))
!(compileadd f1chain (: hist-C-h0 (C h0) (STV 0 1)))
!(compileadd f1chain (: hist-A-h1 (A h1) (STV 0 1)))
!(compileadd f1chain (: hist-B-h1 (B h1) (STV 0 1)))
!(compileadd f1chain (: hist-C-h1 (C h1) (STV 0 1)))
!(compileadd f1chain (: hist-A-h2 (A h2) (STV 0 1)))
!(compileadd f1chain (: hist-B-h2 (B h2) (STV 0 1)))
!(compileadd f1chain (: hist-C-h2 (C h2) (STV 0 1)))
!(compileadd f1chain (: hist-A-h3 (A h3) (STV 0 1)))
!(compileadd f1chain (: hist-B-h3 (B h3) (STV 0 1)))
!(compileadd f1chain (: hist-C-h3 (C h3) (STV 0 1)))
!(compileadd f1chain (: hist-A-h4 (A h4) (STV 0 1)))
!(compileadd f1chain (: hist-B-h4 (B h4) (STV 0 1)))
!(compileadd f1chain (: hist-C-h4 (C h4) (STV 0 1)))
!(compileadd f1chain (: hist-A-h5 (A h5) (STV 0 1)))
!(compileadd f1chain (: hist-B-h5 (B h5) (STV 0 1)))
!(compileadd f1chain (: hist-C-h5 (C h5) (STV 0 1)))
!(compileadd f1chain (: hist-A-h6 (A h6) (STV 1 1)))
!(compileadd f1chain (: hist-B-h6 (B h6) (STV 0 1)))
!(compileadd f1chain (: hist-C-h6 (C h6) (STV 0 1)))
!(compileadd f1chain (: hist-A-h7 (A h7) (STV 0 1)))
!(compileadd f1chain (: hist-B-h7 (B h7) (STV 0 1)))
!(compileadd f1chain (: hist-C-h7 (C h7) (STV 0 1)))
!(compileadd f1chain (: hist-A-h8 (A h8) (STV 1 1)))
!(compileadd f1chain (: hist-B-h8 (B h8) (STV 1 1)))
!(compileadd f1chain (: hist-C-h8 (C h8) (STV 1 1)))
!(compileadd f1chain (: hist-A-h9 (A h9) (STV 1 1)))
!(compileadd f1chain (: hist-B-h9 (B h9) (STV 0 1)))
!(compileadd f1chain (: hist-C-h9 (C h9) (STV 0 1)))
!(compileadd f1chain (: hist-A-h10 (A h10) (STV 0 1)))
!(compileadd f1chain (: hist-B-h10 (B h10) (STV 0 1)))
!(compileadd f1chain (: hist-C-h10 (C h10) (STV 0 1)))
!(compileadd f1chain (: hist-A-h11 (A h11) (STV 1 1)))
!(compileadd f1chain (: hist-B-h11 (B h11) (STV 1 1)))
!(compileadd f1chain (: hist-C-h11 (C h11) (STV 0 1)))
!(compileadd f1chain (: hist-A-h12 (A h12) (STV 0 1)))
!(compileadd f1chain (: hist-B-h12 (B h12) (STV 0 1)))
!(compileadd f1chain (: hist-C-h12 (C h12) (STV 0 1)))
!(compileadd f1chain (: hist-A-h13 (A h13) (STV 1 1)))
!(compileadd f1chain (: hist-B-h13 (B h13) (STV 1 1)))
!(compileadd f1chain (: hist-C-h13 (C h13) (STV 0 1)))
!(compileadd f1chain (: hist-A-h14 (A h14) (STV 0 1)))
!(compileadd f1chain (: hist-B-h14 (B h14) (STV 0 1)))
!(compileadd f1chain (: hist-C-h14 (C h14) (STV 0 1)))
!(set-base-rate f1chain (A $x) (STV 0.49 1.0))
!(test (query 2000 f1chain (: $prf (C a) $tv))
   ())

;; F2. D true settles (Or B D) and leaves B undetermined: the projection gives
;; no value, so B keeps its population prior, exact 0.73 (before: a
;; confidence-0 projection answered 0).
!(compileadd f2settled (: rE (Implication (Or (B $x) (D $x)) (E $x)) (CTV (STV 0.58 1) (STV 0.21 1))))
!(compileadd f2settled (: obs-D-b (D b) (STV 1 1)))
!(set-base-rate f2settled (B $x) (STV 0.73 1.0))
!(set-base-rate f2settled (D $x) (STV 0.62768 1.0))
!(set-base-rate f2settled (E $x) (STV 0.542805262 1.0))
!(test (query 2000 f2settled (: $prf (B b) $tv))
   (: (population-prior (B $_0)) (B b) (STV 0.73 1.0)))

;; A known disjunct conditions the completion of an Or antecedent: with
;; A = 0, P(B | C) is Bayes' rule over B's prior, exact 0.0178 (before: the
;; inverted Or projected under its unconditioned prior, 0.120).
!(compileadd f2known (: rC (Implication (Or (B $x) (A $x)) (C $x)) (CTV (STV 0.07 1) (STV 0.89 1))))
!(compileadd f2known (: hist-A-h0 (A h0) (STV 0 1)))
!(compileadd f2known (: hist-B-h0 (B h0) (STV 0 1)))
!(compileadd f2known (: hist-C-h0 (C h0) (STV 1 1)))
!(compileadd f2known (: hist-A-h1 (A h1) (STV 1 1)))
!(compileadd f2known (: hist-B-h1 (B h1) (STV 0 1)))
!(compileadd f2known (: hist-C-h1 (C h1) (STV 0 1)))
!(compileadd f2known (: hist-A-h2 (A h2) (STV 0 1)))
!(compileadd f2known (: hist-B-h2 (B h2) (STV 0 1)))
!(compileadd f2known (: hist-C-h2 (C h2) (STV 1 1)))
!(compileadd f2known (: hist-A-h3 (A h3) (STV 1 1)))
!(compileadd f2known (: hist-B-h3 (B h3) (STV 0 1)))
!(compileadd f2known (: hist-C-h3 (C h3) (STV 0 1)))
!(compileadd f2known (: hist-A-h4 (A h4) (STV 1 1)))
!(compileadd f2known (: hist-B-h4 (B h4) (STV 0 1)))
!(compileadd f2known (: hist-C-h4 (C h4) (STV 0 1)))
!(compileadd f2known (: hist-A-h5 (A h5) (STV 0 1)))
!(compileadd f2known (: hist-B-h5 (B h5) (STV 0 1)))
!(compileadd f2known (: hist-C-h5 (C h5) (STV 1 1)))
!(compileadd f2known (: hist-A-h6 (A h6) (STV 1 1)))
!(compileadd f2known (: hist-B-h6 (B h6) (STV 0 1)))
!(compileadd f2known (: hist-C-h6 (C h6) (STV 0 1)))
!(compileadd f2known (: hist-A-h7 (A h7) (STV 0 1)))
!(compileadd f2known (: hist-B-h7 (B h7) (STV 1 1)))
!(compileadd f2known (: hist-C-h7 (C h7) (STV 0 1)))
!(compileadd f2known (: hist-A-h8 (A h8) (STV 1 1)))
!(compileadd f2known (: hist-B-h8 (B h8) (STV 0 1)))
!(compileadd f2known (: hist-C-h8 (C h8) (STV 0 1)))
!(compileadd f2known (: hist-A-h9 (A h9) (STV 0 1)))
!(compileadd f2known (: hist-B-h9 (B h9) (STV 1 1)))
!(compileadd f2known (: hist-C-h9 (C h9) (STV 0 1)))
!(compileadd f2known (: hist-A-h10 (A h10) (STV 0 1)))
!(compileadd f2known (: hist-B-h10 (B h10) (STV 0 1)))
!(compileadd f2known (: hist-C-h10 (C h10) (STV 1 1)))
!(compileadd f2known (: obs-A-b (A b) (STV 0 1)))
!(compileadd f2known (: obs-C-b (C b) (STV 1 1)))
!(test (query 2000 f2known (: $prf (B b) $tv))
   (: ((antecedent-completion rC 0 with cpu (prior (STV 0.18750000000000003 0.6875))) (conjunction obs-A-b obs-C-b)) (B b) (STV 0.017826825127334467 0.9538571899944228)))

;; F3. An observation of C informs the conjuncts of (And A B) -> C; the
;; completion onto A reads the unobserved B at its population prior, and E
;; follows from A: exact 0.5592 (before: no answer).
!(compileadd f3and (: rC (Implication (And (A $x) (B $x)) (C $x)) (CTV (STV 0.85 1) (STV 0.7 1))))
!(compileadd f3and (: rE (Implication (A $x) (E $x)) (CTV (STV 0.94 1) (STV 0.29 1))))
!(compileadd f3and (: obs-C-a (C a) (STV 0 1)))
!(set-base-rate f3and (A $x) (STV 0.44 1.0))
!(set-base-rate f3and (B $x) (STV 0.2 1.0))
!(test (query 2000 f3and (: $prf (E a) $tv))
   (: (by rE ((antecedent-completion rC 0 with cpu (prior (STV 0.44 1.0))) (conjunction (population-prior (B $_0)) obs-C-a))) (E a) (STV 0.5592468833317317 0.9998831101258783)))

;; The same for an Or: (Or A B) -> D, deterministic, D = 0, so A is certainly
;; false, exact 0 (before: no answer).
!(set-complete-predicate f3or D)
!(compileadd f3or (: rD (Implication (Or (A $x) (B $x)) (D $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd f3or (: obs-D-a (D a) (STV 0 1)))
!(set-base-rate f3or (A $x) (STV 0.18 1.0))
!(set-base-rate f3or (B $x) (STV 0.0846 1.0))
!(set-base-rate f3or (D $x) (STV 0.249372 1.0))
!(test (query 2000 f3or (: $prf (A a) $tv))
   (: ((antecedent-completion rD 0 with cpu (prior (STV 0.18 1.0))) (conjunction (population-prior (B $_0)) obs-D-a)) (A a) (STV 0.0 0.9999421512249334)))

;; F5. In a loop of complete predicates, C <- (Or B D) and D <- C, the rule
;; application of C reads the observed D = 0 as a cause and the inversion of
;; rD observes it as C's effect; a premise is both only in a loop through C.
;; A false disjunct adds nothing to B's cause, so P(C | B) = 0.47 times D's
;; likelihood ratio 0.06 / 1 is exact: 0.0505 (before: the forward view's
;; evidence contained the inversion's, and 0.47 was kept).
!(set-complete-predicate f5loop C)
!(set-complete-predicate f5loop D)
!(compileadd f5loop (: rC (Implication (Or (B $x) (D $x)) (C $x)) (CTV (STV 0.47 1) (STV 0 1))))
!(compileadd f5loop (: rD (Implication (C $x) (D $x)) (CTV (STV 0.94 1) (STV 0 1))))
!(compileadd f5loop (: obs-B-a (B a) (STV 1 1)))
!(compileadd f5loop (: obs-D-a (D a) (STV 0 1)))
!(set-base-rate f5loop (B $x) (STV 0.781 1.0))
!(set-base-rate f5loop (C $x) (STV 0.36707 1.0))
!(test (query 2000 f5loop (: $prf (C a) $tv))
   (: (factored-revision (by rC (conjunction obs-B-a obs-D-a)) (prior (STV 0.47 0.9999000099103349)) (((inverted rD with cpu (prior (STV 0.36707 1.0))) obs-D-a))) (C a) (STV 0.050519527051236156 0.9999055997327737)))
