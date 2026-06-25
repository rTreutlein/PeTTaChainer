!(import! &self petta_chainer)

!(set-specializing-predicate Symmetric)

;; Rule added before any Symmetric facts: stored as a template, no rule emitted yet.
!(compileadd kb (: sum_rel (Implication (Premises (Symmetric $r) ($r $x $y)) (Conclusions ($r $y $x))) (STV 0.9 0.9)))

;; Adding (Symmetric Friend) specializes the template into a concrete-headed
;; rule (Friend $x $y) -> (Friend $y $x), keeping (Symmetric Friend) as a
;; grounded premise so its TV is threaded through.
!(compileadd kb (: tag (Symmetric Friend) (STV 0.9 0.9)))
!(compileadd kb (: f1 (Friend bob alice) (STV 0.9 0.9)))

;; Grounded computation: base rate over the real (Friend ...) facts.
!(test
   (query 100 kb (: $prf (Friend alice bob) $tv))
   (: (sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.9 0.03939074332138302)))

;; The specialized rule's conclusion head is the concrete symbol Friend, so no
;; conclusion is indexed under the `any` wildcard (which a variable head would
;; have produced).
!(test (collapse (match ccls_head_index ((fwd_trigger kb any) $_id) any)) ())

;; Because the head is concrete, an *open* backward query reaches the rule via
;; the head index -- something the generic variable-headed rule cannot do (its
;; conclusion only lives in the `any` bucket, which head-view does not scan).
!(test
   (query 100 kb (: $prf (Friend alice $x) $tv))
   (: (sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.9 0.03939074332138302)))

;; The (Symmetric Friend) fact is still stored as a normal fact.
!(test (match &kb ((Symmetric $x) ($kb MAIN Nil) $p $tv) ($x $p)) (Friend tag))

;; Reverse add order: facts present before the rule is added.
!(compileadd kb2 (: tag2 (Symmetric Sibling) (STV 0.9 0.9)))
!(compileadd kb2 (: g1 (Sibling bob alice) (STV 0.9 0.9)))
!(compileadd kb2 (: sum_rel2 (Implication (Premises (Symmetric $r) ($r $x $y)) (Conclusions ($r $y $x))) (STV 0.9 0.9)))

!(test
   (query 100 kb2 (: $prf (Sibling alice bob) $tv))
   (: (sum_rel2 (conjunction tag2 g1)) (Sibling alice bob) (STV 0.9 0.03939074332138302)))
