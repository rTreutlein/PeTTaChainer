!(import! &self ../petta_chainer)

!(set-specializing-predicate Symmetric)

;; Rule added before any Symmetric facts: stored as a template, no rule emitted yet.
!(compileadd kb (: sum_rel (Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x)) (STV 0.9 0.9)))

;; Adding (Symmetric Friend) specializes the template into a concrete-headed
;; rule (Friend $x $y) -> (Friend $y $x), keeping (Symmetric Friend) as a
;; grounded premise so its TV is threaded through.
!(compileadd kb (: tag (Symmetric Friend) (STV 0.9 0.9)))
!(compileadd kb (: f1 (Friend bob alice) (STV 0.9 0.9)))

;; Grounded computation: base rate over the real (Friend ...) facts.
!(test
   (query 100 kb (: $prf (Friend alice bob) $tv))
   (: (sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.9 0.03939074332138302)))

;; The structurally indexed conclusion remains reachable from an open query.
!(test
   (query 100 kb (: $prf (Friend alice $x) $tv))
   (: (sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.9 0.03939074332138302)))

;; The (Symmetric Friend) fact is still stored as a normal fact.
!(test (match &kb ((Symmetric $x) ($kb MAIN Nil) $p $tv) ($x $p)) (Friend tag))

;; Reverse add order: facts present before the rule is added.
!(compileadd kb2 (: tag2 (Symmetric Sibling) (STV 0.9 0.9)))
!(compileadd kb2 (: g1 (Sibling bob alice) (STV 0.9 0.9)))
!(compileadd kb2 (: sum_rel2 (Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x)) (STV 0.9 0.9)))

!(test
   (query 100 kb2 (: $prf (Sibling alice bob) $tv))
   (: (sum_rel2 (conjunction tag2 g1)) (Sibling alice bob) (STV 0.9 0.03939074332138302)))

;; Equal grounded rule types with distinct proof ids/TVs remain independent
;; specialization results. Deduplicating only by type used to discard alt_rel.
!(compileadd kb3 (: tag3 (Symmetric Related) (STV 1.0 1.0)))
!(compileadd kb3 (: r1 (Related bob alice) (STV 1.0 1.0)))
!(compileadd kb3
   (: main_rel
      (Implication
         (And (Symmetric $r) ($r $x $y))
         ($r $y $x))
      (STV 0.9 0.9)))
!(compileadd kb3
   (: alt_rel
      (Implication
         (And (Symmetric $r) ($r $x $y))
         ($r $y $x))
      (STV 0.6 0.8)))

!(test
   (query 100 kb3 (: $prf (Related alice bob) $tv))
   (: (merge/revision (main_rel (conjunction tag3 r1))
                      (alt_rel (conjunction tag3 r1)))
      (Related alice bob) (STV 0.8076923077136262 0.9285714285102494)))

;; Removing a specializing rule also removes its deferred template. A later
;; structural fact must not resurrect it, and re-adding it must work normally.
!(compileadd kb4
   (: removable_rel
      (Implication
         (And (Symmetric $r) ($r $x $y))
         ($r $y $x))
      (STV 0.9 0.9)))
!(remove-compiled-statement removable_rel)
!(compileadd kb4 (: tag4 (Symmetric Knows) (STV 1.0 1.0)))
!(compileadd kb4 (: k1 (Knows bob alice) (STV 1.0 1.0)))
!(test (query 100 kb4 (: $prf (Knows alice bob) $tv)) ())

!(compileadd kb4
   (: removable_rel
      (Implication
         (And (Symmetric $r) ($r $x $y))
         ($r $y $x))
      (STV 0.9 0.9)))
!(test (query 100 kb4 (: $prf (Knows alice bob) $tv))
   (: (removable_rel (conjunction tag4 k1))
      (Knows alice bob) (STV 0.9 0.8999999999819711)))
