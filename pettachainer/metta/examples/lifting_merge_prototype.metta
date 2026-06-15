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

(= (eval-binary $env $op $term)
   ($op (eval-proof $env (car-atom (cdr-atom $term)))
        (eval-proof $env (car-atom (cdr-atom (cdr-atom $term))))))

(= (eval-proof $env $term)
   (if (is-expr $term)
      (let $head (car-atom $term)
         (if (== $head conjunction)  (eval-binary $env AndFormula $term)
         (if (== $head likelier)     (eval-binary $env LikelierThanFormula $term)
         (if (== $head old-likelier) (eval-binary $env ClampedLikelierFormula $term)
            (CTVFormula (eval-proof $env (car-atom (cdr-atom $term))) (rule-ctv $head))))))
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
;; Boundary: the probe is exact on every proof the engine actually builds
;;
;; AndFormula (s1*s2), OrFormula (s1+s2-s1*s2), and CTVFormula are each LINEAR
;; in any single argument, so factoring a leaf that occurs ONCE on a path is
;; exact -- every case above, including the deduction chain and the conjunction
;; with a distinct second premise.
;;
;; A leaf can only occur twice on a path by being shared across the conjuncts of
;; a conjunction. The frontier conjunction guard forbids exactly that: conjuncts
;; must have disjoint fact evidence. So a "diamond" -- deriving P and Q both from
;; the same a, then conjoining for B -- is rejected, and querying B yields NO
;; proof, whereas the same rule over independent facts P,Q does build. Hence
;; every proof reaching the merge has each fact leaf at most once, and the
;; 2-point probe is exact; no fact-reuse case ever arises.
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

;; A buildable proof -- (conjunction pa qa), independent conjuncts. Factoring pa
;; (occurs once) round-trips to the true value exactly.
!(test
   (residual-then-apply (pqToB (conjunction pa qa)) pa (STV 0.6 1.0))
   (STV 0.3 1.0))
!(test
   (eval-proof (over pa (STV 0.6 1.0)) (pqToB (conjunction pa qa)))
   (STV 0.3 1.0))

;; The diamond proof (conjunction (aToP a) (aToQ a)) reuses a, so AndFormula
;; double-counts it: B = A AND A at a=(0.5 1.0) collapses to 0.5*0.5 = 0.25 by
;; falsely assuming the two copies of A are independent. That artifact is why the
;; engine's conjunction guard rejects this proof outright (a direct query for B
;; returns nothing), so it never reaches the merge in the first place.
!(test
   (eval-proof (over a (STV 0.5 1.0)) (pqToB (conjunction (aToP a) (aToQ a))))
   (STV 0.25 1.0))

;; The only single-occurrence nonlinearity was a piecewise formula -- the old
;; LikelierThanFormula's max(0, s_a - s_b) kink. That has been made multilinear
;; (see the next section), so the probe is now exact on every engine proof.

;; ===========================================================================
;; Why LikelierThanFormula was made multilinear
;;
;; The old form (max 0 (- s_a s_b)) was piecewise-linear: a kink at s_a = s_b.
;; Probing only at s_a=0 and s_a=1 fits a straight line that cannot see the kink,
;; so factoring a leaf that flowed through it was wrong between the probe points.
;; LikelierThanFormula is now s_a * (1 - s_b) -- P(A and not B) under independence
;; -- which is multilinear and factors exactly.
;; ===========================================================================

(= (leaf-tv w) (STV 0.6 1.0))
(= (rule-ctv lrule) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))

;; The old clamped form, kept here only to show the problem it caused.
(= (ClampedLikelierFormula (STV $sa $ca) (STV $sb $cb))
   (STV (max 0.0 (- $sa $sb)) (min $ca $cb)))

;; Old clamped LikelierThan, real a=(0.3 1.0). The probe line is 0.4 * s_a (fit
;; through s_a=0 ->0 and s_a=1 ->0.4), giving 0.12. But 0.3 is below the kink at
;; s_b=0.6, so the true value is (max 0 (- 0.3 0.6)) = 0. Factored 0.12 vs true 0.
!(test
   (residual-then-apply (lrule (old-likelier a w)) a (STV 0.3 1.0))
   (STV 0.12 1.0))
!(test
   (eval-proof (over a (STV 0.3 1.0)) (lrule (old-likelier a w)))
   (STV 0.0 1.0))

;; The current multilinear LikelierThanFormula: same probe line (0.12), but now
;; it IS the truth -- 0.3 * (1 - 0.6) = 0.12 both ways.
!(test
   (residual-then-apply (lrule (likelier a w)) a (STV 0.3 1.0))
   (STV 0.12 1.0))
!(test
   (eval-proof (over a (STV 0.3 1.0)) (lrule (likelier a w)))
   (STV 0.12 1.0))
