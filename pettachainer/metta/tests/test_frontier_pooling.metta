!(import! &self ../petta_chainer)

;; Frontier pooling of same-source projections: conjunction queries whose
;; conjuncts are marginal projections of one stored or derived (And ...) source
;; are answered by pooling the projections back into that source instead of
;; being rejected by the evidence-overlap guard.

;; --- reordering a stored bundle returns the source TV verbatim --------------
!(compileadd kb1 (: bc (And (M e1 cook) (A e1 bob) (P e1 dinner)) (STV 0.9 0.99)))

!(test (query 100 kb1 (: $prf (And (A $e bob) (P $e dinner) (M $e cook)) $tv))
       (: (conjunction (marginal-proj 1 bc) (marginal-proj 2 bc) (marginal-proj 0 bc))
          (And (A e1 bob) (P e1 dinner) (M e1 cook)) (STV 0.9 0.99)))

;; --- a strict subset gets the marginal projection TV ------------------------
!(test (query 100 kb1 (: $prf (And (A $e bob) (M $e cook)) $tv))
       (: (conjunction (marginal-proj 1 bc) (marginal-proj 0 bc))
          (And (A e1 bob) (M e1 cook)) (STV 0.9 0.9889012208657048)))

;; --- negated bundle: reorder keeps strength 0 at full confidence ------------
!(compileadd kb2 (: neg (And (M e2 leave) (A e2 rex) (Permitted e2)) (STV 0.0 0.99)))

!(test (query 100 kb2 (: $prf (And (Permitted $e) (M $e leave) (A $e rex)) $tv))
       (: (conjunction (marginal-proj 2 neg) (marginal-proj 0 neg) (marginal-proj 1 neg))
          (And (Permitted e2) (M e2 leave) (A e2 rex)) (STV 0.0 0.99)))

;; --- mixed query: independent fact conjunct + a full bundle -----------------
!(compileadd kb2 (: nm (Name rex "Rex") (STV 1.0 0.99)))

!(test (query 100 kb2 (: $prf (And (Name $r "Rex") (M $e leave) (A $e $r) (Permitted $e)) $tv))
       (: (conjunction nm (marginal-proj 0 neg) (marginal-proj 1 neg) (marginal-proj 2 neg))
          (And (Name rex "Rex") (M e2 leave) (A e2 rex) (Permitted e2)) (STV 0.0 0.989999999999875)))

;; --- rule-derived bundle: reorder returns the derived TV verbatim -----------
!(compileadd kb3 (: r (Implication (PartOf $x g) (And (M (sk $x) bark) (A (sk $x) $x) (Past (sk $x)))) (STV 1.0 0.9)))
!(compileadd kb3 (: fp (PartOf fido g) (STV 1.0 0.99)))

!(test (query 100 kb3 (: $prf (And (Past $e) (M $e bark) (A $e fido)) $tv))
       (: (conjunction (marginal-proj 2 (by r fp)) (marginal-proj 0 (by r fp)) (marginal-proj 1 (by r fp)))
          (And (Past (sk fido)) (M (sk fido) bark) (A (sk fido) fido)) (STV 1.0 0.8918896517282313)))

;; --- regression: independent sources still combine via AndFormula -----------
!(compileadd kb4 (: b1 (And (P e4) (Q e4)) (STV 0.9 0.99)))
!(compileadd kb4 (: b2 (And (R e4) (S e4)) (STV 0.9 0.99)))

!(test (query 100 kb4 (: $prf (And (P $e) (R $e)) $tv))
       (: (conjunction (marginal-proj 0 b1) (marginal-proj 0 b2))
          (And (P e4) (R e4)) (STV 0.81 0.9894792210353621)))
