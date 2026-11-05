!(import! &self ../../pettachainer/metta/petta_chainer)

;; A row whose rule is deterministic and whose premises are certain is
;; determined: its conclusion is certain, so it is computed when built,
;; whoever needs it, and its key changes as a stored fact's would
;; (runtime_design_assumptions.md, "Determined rows"). An outcome the rule
;; (C $x) -> (B $x), stated with (CTV (STV 0 1) (STV 1 1)), derives from a
;; stored (C $x) therefore reaches the instance tally of the hypothesis
;; (A $x) -> (B $x) and the population of (B $x) at the next query, whatever
;; it asks, as a stored (B $x) would.

!(set-evidence-confidence-k 1)
!(set-backward-query-metrics true)

(: truth (-[semidet]-> KB Atom))
(= (truth $kb)
   (case (sk-key-value (sk-key (RuleTruth (Implication (A $x) (B $x))) ($kb MAIN Nil))) (
      ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps) $tv)
      ($_none none))))

!(set-rule-refinement givenKb true)
!(set-positive-only-predicate givenKb A)
!(compileadd givenKb (: complement (Implication (C $x) (B $x)) (CTV (STV 0 1) (STV 1 1))))
!(compileadd givenKb (: h (Implication (A $x) (B $x)) (STV 0.5 0.01)))
!(compileadd givenKb (: a1 (A i1) (STV 1 1)))
!(compileadd givenKb (: c1 (C i1) (STV 0 1)))
!(compileadd givenKb (: a2 (A i2) (STV 1 1)))
!(compileadd givenKb (: c2 (C i2) (STV 0 1)))
!(compileadd givenKb (: a3 (A i3) (STV 1 1)))
!(compileadd givenKb (: c3 (C i3) (STV 1 1)))

;; The first review folds the three instances, deriving their outcomes: two
;; positive, one negative.
!(test (let (: $p $t $tv) (query 50 givenKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) $tv)
   (STV 0.6661073825503356 0.7506297229219142))

;; A positive instance whose outcome only the rule tells. A query with no
;; budget about something else takes it into the tally and the population, at
;; the cost of the rows it changes.
!(compileadd givenKb (: anew (A new) (STV 1 1)))
!(compileadd givenKb (: cnew (C new) (STV 0 1)))
!(begin-backward-query-metrics!)
!(test (query 0 givenKb (: $p (A i1) $tv)) (: a1 (A i1) (STV 1 1)))
!(test (query_metric_value row-computes) 7)
!(test (truth givenKb) (STV 0.7493702770780857 0.8004032258064516))
!(test (query 0 givenKb (: $p (B other) $tv))
   (: (population-prior (B $_0)) (B other) (STV 0.7380952380952381 0.8)))

;; A hypothesis about the complement learns from the same outcomes: (C $x) is
;; stored where (B $x) is derived, and the other way round. Applied to a new
;; case, h's view of (C case), through the inverted rule, is the same
;; estimate as hc's, not more evidence: the two views are sample twins and the
;; merge keeps one (overlap_conditioning.md, "Sample twins"). Revised as
;; independent, they gave (STV 0.2397 0.8012) through a factored revision.
!(compileadd givenKb (: hc (Implication (A $x) (C $x)) (STV 0.5 0.01)))
!(compileadd givenKb (: acase (A case) (STV 1 1)))
!(test (let (: $p $t $tv) (query 50 givenKb (: $p (RuleTruth (Implication (A $x) (C $x))) $tv)) $tv)
   (STV 0.2506297229219143 0.8004032258064516))
!(test (query 50 givenKb (: $p (C case) $tv))
   (: ((inverted complement with cpu (prior (STV 0.2619047619047619 0.8))) (by h acase)) (C case) (STV 0.2506297229219143 0.8004032258064516)))
