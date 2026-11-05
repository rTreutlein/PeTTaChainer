!(import! &self ../../pettachainer/metta/petta_chainer)

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
   (: (by sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.8642193246799066 0.02243916988834716)))

;; The structurally indexed conclusion remains reachable from an open query.
!(test
   (query 100 kb (: $prf (Friend alice $x) $tv))
   (: (by sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.8642193246799066 0.02243916988834716)))

;; The (Symmetric Friend) fact is still stored as a normal fact.
!(test (match &kb ((Symmetric $x) ($kb MAIN Nil) $p $tv) ($x $p)) (Friend tag))

;; Reverse add order: facts present before the rule is added.
!(compileadd kb2 (: tag2 (Symmetric Sibling) (STV 0.9 0.9)))
!(compileadd kb2 (: g1 (Sibling bob alice) (STV 0.9 0.9)))
!(compileadd kb2 (: sum_rel2 (Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x)) (STV 0.9 0.9)))

!(test
   (query 100 kb2 (: $prf (Sibling alice bob) $tv))
   (: (by sum_rel2 (conjunction tag2 g1)) (Sibling alice bob) (STV 0.8642193246799066 0.02243916988834716)))

;; Equal grounded rule types with distinct proof ids/TVs remain independent
;; specialization results. Deduplicating only by type used to discard alt_rel.
;; Two estimates of one condition revise; no view is selected by confidence.
;; By count (k = 800) main_rel holds 7200 observations and alt_rel 3200: the
;; revision is (0.9 * 7200 + 0.6 * 3200) / 10400 = 0.8077 at 10400, confidence
;; 0.9286. alt_rel's completion through r1 (confidence 1e-6) adds nothing.
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
   (: (merge/revision (merge/revision (by main_rel (conjunction tag3 r1)) (by alt_rel (conjunction tag3 r1))) ((antecedent-completion alt_rel 1 with cpu (prior (STV 0.5 0.0))) (conjunction tag3 r1))) (Related alice bob) (STV 0.8076565143675009 0.9285804816033009)))

!(test
   (query 100 kb3 (: (by alt_rel $prf) (Related alice bob) $tv))
   (: (by alt_rel (conjunction tag3 r1)) (Related alice bob) (STV 0.6 0.8)))

;; A specializing rule over certain structural facts.
!(compileadd kb4 (: tag4 (Symmetric Knows) (STV 1.0 1.0)))
!(compileadd kb4 (: k1 (Knows bob alice) (STV 1.0 1.0)))
!(compileadd kb4
   (: late_rel
      (Implication
         (And (Symmetric $r) ($r $x $y))
         ($r $y $x))
      (STV 0.9 0.9)))
;; The rule and its own completion read k1 as cause and as observation, a loop:
;; they revise rather than multiply, and no view is selected.
!(test (query 100 kb4 (: $prf (Knows alice bob) $tv))
   (: (merge/revision (by late_rel (conjunction tag4 k1)) ((antecedent-completion late_rel 1 with cpu (prior (STV 0.5 0.0))) (conjunction tag4 k1)))
      (Knows alice bob) (STV 0.8999423944183065 0.9000201621830276)))
