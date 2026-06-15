!(import! &self petta_chainer)

;; ===========================================================================
;; Lifting-merge prototype (design validation, not wired into the engine yet)
;;
;; Problem: two proofs of B that share a premise `a:A` cannot be revision-merged
;; at the conclusion (they overlap on `a`), so the engine dominates and discards
;; one branch's contribution. The correct answer pools the derivations at the
;; IMPLICATION level (A->B), where they are independent, then applies `a` once.
;;
;; This prototype computes that pooled answer directly from the proof terms plus
;; the kb truth values, with no change to the live merge, to validate the math.
;;
;; Technique: residual extraction by a 2-point probe of the shared antecedent.
;; A modus-ponens / deduction / conjunction proof tree is linear in the shared
;; antecedent's strength, so evaluating the proof with the antecedent at
;; strength 1 and at strength 0 recovers the residual implication's positive and
;; negative conditional TVs. Revise the residuals (they are independent), then
;; apply the real `a` once. The real antecedent's confidence therefore enters
;; exactly once -- no double counting.
;; ===========================================================================

;; --- stand-in kb (would be read from &kb and the compiled rules) ---
(= (leaf-tv a)  (STV 1.0 1.0))
(= (leaf-tv xx) (STV 1.0 1.0))
(= (leaf-tv yy) (STV 1.0 1.0))
(= (rule-ctv ab1) (CTV (STV 0.6 0.9) (STV 0.0 1.0)))
(= (rule-ctv ab2) (CTV (STV 0.6 0.9) (STV 0.0 1.0)))
(= (rule-ctv ax)  (CTV (STV 0.7 0.9) (STV 0.0 1.0)))
(= (rule-ctv xb)  (CTV (STV 0.8 0.9) (STV 0.0 1.0)))
(= (rule-ctv r1)  (CTV (STV 0.6 0.9) (STV 0.0 1.0)))
(= (rule-ctv r2)  (CTV (STV 0.6 0.9) (STV 0.0 1.0)))

;; --- proof term representation (matches the engine's proof tokens) ---
;; A proof term is one of:
;;   leaf atom             a fact's proof token, e.g. `a` is the proof of (A i)
;;   (implName argProof)   modus ponens: implication `implName` applied to the
;;                         proof of its premise, e.g. `(ab1 a)` proves (B i)
;;   (conjunction p1 p2)   the two premise PROOFS p1, p2 conjoined
;; So in `(rr (conjunction (pr a) (qr a)))`, the conjuncts are the proofs
;; `(pr a)` of (P i) and `(qr a)` of (Q i) -- both built from the same leaf
;; proof `a`. That is a PROOF term, not a type; the heads pr/qr/rr/ab1 are
;; implication proof tokens, the leaves a/xx/yy are fact proof tokens.

;; --- evaluate a proof term to its TV, overriding one leaf fact ---
(= (env-or-leaf (over $oname $otv) $name)
   (if (== $oname $name) $otv (leaf-tv $name)))

(= (eval-proof $env $term)
   (if (is-expr $term)
      (let $head (car-atom $term)
         (if (== $head conjunction)
            (AndFormula
               (eval-proof $env (car-atom (cdr-atom $term)))
               (eval-proof $env (car-atom (cdr-atom (cdr-atom $term)))))
            (CTVFormula (eval-proof $env (car-atom (cdr-atom $term))) (rule-ctv $head))))
      (env-or-leaf $env $term)))

;; --- residual implication of a path w.r.t. the shared antecedent ---
(= (residual-ctv $proof $shared)
   (CTV (eval-proof (over $shared (STV 1.0 1.0)) $proof)
        (eval-proof (over $shared (STV 0.0 1.0)) $proof)))

(= (revise-ctv (CTV $p1 $n1) (CTV $p2 $n2))
   (CTV (mergetvs $p1 $p2) (mergetvs $n1 $n2)))

;; --- factor the shared antecedent, revise the residuals, re-apply once ---
(= (factor-merge $proof1 $proof2 $shared $real-tv)
   (CTVFormula $real-tv
      (revise-ctv (residual-ctv $proof1 $shared) (residual-ctv $proof2 $shared))))

;; Case 1: two implications A->B, sharing premise a.
;; direct-B query dominates to (STV 0.6 0.9); pooled is (STV 0.6 0.947).
!(test (factor-merge (ab1 a) (ab2 a) a (STV 1.0 1.0))
   (STV 0.6 0.9473684210526316))

;; Case 2: direct A->B vs deduction chain A->X->B, sharing premise a.
;; pooled (STV 0.58 0.947) matches the engine's own implication query.
!(test (factor-merge (ab1 a) (xb (ax a)) a (STV 1.0 1.0))
   (STV 0.58 0.9473684210526316))

;; Case 3: A,X->B / A,Y->B, sharing only A. The engine's implication query
;; cannot express this (mixed assumed/real conjunctive premise), so factoring
;; is the only route to the pooled answer.
!(test (factor-merge (r1 (conjunction a xx)) (r2 (conjunction a yy)) a (STV 1.0 1.0))
   (STV 0.6 0.9473684210526316))

;; No overcounting: with an uncertain shared premise a=(1.0 0.5), the residual is
;; probed at confidence 1 and the real a applied once, so a's confidence caps the
;; result exactly once. Naively revising the two conclusions would wrongly inflate
;; the confidence to ~0.667.
!(test (factor-merge (ab1 a) (ab2 a) a (STV 1.0 0.5))
   (STV 0.6 0.5))

;; ===========================================================================
;; Boundary: factoring is exact iff the factored leaf appears ONCE on the path
;;
;; AndFormula (s1*s2), OrFormula (s1+s2-s1*s2), and CTVFormula are each LINEAR
;; in any single argument. So factoring out a leaf proof that occurs once on a
;; path is exact -- that is every case above, including the deduction chain and
;; the conjunction with a distinct second premise.
;;
;; The decisive question is not "is there a conjunction" but "does the factored
;; leaf occur more than once on the path." Contrast two proofs of (B i), both
;; of shape (pqToB (conjunction _ _)):
;; ===========================================================================

;; pa, qa : independent stored facts (P i), (Q i).
(= (leaf-tv pa) (STV 0.6 1.0))
(= (leaf-tv qa) (STV 0.5 1.0))
;; aToP, aToQ : derive (P i), (Q i) from the SAME fact a:(A i). pqToB : P,Q -> B.
(= (rule-ctv aToP)  (CTV (STV 1.0 1.0) (STV 0.0 1.0)))
(= (rule-ctv aToQ)  (CTV (STV 1.0 1.0) (STV 0.0 1.0)))
(= (rule-ctv pqToB) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))

;; factored single-path value: probe-extract the residual, then apply real leaf.
(= (residual-then-apply $proof $shared $real-tv)
   (CTVFormula $real-tv (residual-ctv $proof $shared)))

;; LINEAR -- your (conjunction pa qa): the conjuncts are independent fact proofs,
;; so factoring out pa (which occurs once) round-trips to the true value exactly.
!(test
   (residual-then-apply (pqToB (conjunction pa qa)) pa (STV 0.6 1.0))
   (STV 0.3 1.0))
!(test
   (eval-proof (over pa (STV 0.6 1.0)) (pqToB (conjunction pa qa)))
   (STV 0.3 1.0))

;; NONLINEAR -- the conjuncts are PROOFS (aToP a) and (aToQ a), both derived from
;; the shared leaf a, so a occurs twice and B = A AND A (true strength 0.5*0.5 =
;; 0.25). The 2-point probe sees strength 1 at a=1 and 0 at a=0, reconstructs the
;; identity implication, and applies real a=0.5 to get 0.5 -- it misses the
;; quadratic shrinkage. Factored 0.5 vs true 0.25.
!(test
   (residual-then-apply (pqToB (conjunction (aToP a) (aToQ a))) a (STV 0.5 1.0))
   (STV 0.5 1.0))
!(test
   (eval-proof (over a (STV 0.5 1.0)) (pqToB (conjunction (aToP a) (aToQ a))))
   (STV 0.25 1.0))

;; So the live guard is "factor only leaves that occur once on the path" -- a
;; walk over the proof term, not a property of the formulas. (Piecewise formulas
;; like LikelierThanFormula's max(0, s_a - s_b) kink break linearity even for a
;; single occurrence, and would also fall back to dominance.)
