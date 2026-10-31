;; Proof and truth-value term classifiers, independent of evidence policy.
;; A context assumption, or a statement a conditioned read takes as known.
(: assumption-proof? (-[det]-> Proof Bool))
(= (assumption-proof? $prf)
   (if (is-expr $prf) (let $head (car-atom $prf) (if (== $head ctx) true (== $head given))) false))

;; A certain fact, strength 0 or 1 at confidence 1, joins the same whether its
;; evidence is shared or not: P(K and X) is P(X) or 0 either way. Evidence read
;; off a proof term names the fact by its proof alone, negated under a Not.
(: certain-tvs? (-[det]-> (List TV) Bool))
(= (certain-tvs? $tvs)
   (case $tvs (
      ((cons (STV $s $c) $_rest) (if (>= $c 1.0) (if (>= $s 1.0) true (<= $s 0.0)) false))
      ($_other false))))
