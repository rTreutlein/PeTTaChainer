!(import! &self ../petta_chainer)

!(compileadd implicationPremiseKb
   (: ab_c
      (Implication
         (Implication (A) (B))
         (C))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd implicationPremiseKb
   (: a_b
      (Implication
         (A)
         (B))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 60 implicationPremiseKb
      (: $prf (Implication (A) (B))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   ())

!(test
   (query 60 implicationPremiseKb (: $prf (C) $tv))
   (: (by ab_c (total-implication (by a_b (ctx proof 2)) (by a_b (ctx proof 3)))) (C) (STV 1.0 0.999700089898053)))

!(test
   (query 60 implicationPremiseKb
      (: $prf
         (Implication
            (Not (Dog))
            (Dog))
         $tv))
   (: (total-implication (ctx proof 6) (ctx proof 7))
      (Implication (Not (Dog)) (Dog))
      (CTV (STV 0.0 1.0) (STV 1.0 1.0))))

!(test
   (query 60 implicationPremiseKb
      (: $prf
         (Implication
            (Not (Dog))
            (Not (Dog)))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   (: (total-implication (negated (ctx proof 8)) (negated (ctx proof 9)))
      (Implication (Not (Dog)) (Not (Dog)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd multiPremiseImplicationQueryKb
   (: ab_c
      (Implication
         (And
            (A)
            (B))
         (C))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 60 multiPremiseImplicationQueryKb
      (: $prf (Implication (And (A) (B)) (C)) $tv))
   (: (total-implication (by ab_c (conjunction (ctx proof 10) (ctx proof 10 1))) (by ab_c (conjunction (ctx proof 11) (ctx proof 11 1)))) (Implication (And (A) (B)) (C)) (CTV (STV 1.0 0.999700089898053) (STV 0.0 0.999800029971008))))

!(test
   (query 60 implicationPremiseKb
      (: $prf
         (Implication
            (And
               (Implication (A) (B))
               (A))
            (B))
         $tv))
   (: (total-implication
         (merge/revision
            (by a_b (ctx proof 12 1))
            (by (ctx proof 12) (ctx proof 12 1)))
         (merge/revision
            (by a_b (ctx proof 13 1))
            (by (ctx proof 13) (ctx proof 13 1))))
      (Implication
         (And (Implication (A) (B)) (A))
         (B))
      (CTV
         (STV 1.0 0.9999000099865026)
         (STV 0.5000000000036097 0.9999000099865019))))

!(set-context-polymorphic-facts kbRelativeImplicationQueryKb true)

!(compileadd kbRelativeImplicationQueryKb (: b (B) (STV 1.0 1.0)))

!(compileadd kbRelativeImplicationQueryKb
   (: ab_c
      (Implication
         (And
            (A)
            (B))
         (C))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 60 kbRelativeImplicationQueryKb
      (: $prf (Implication (A) (C))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   ())

!(test (query 10 kbRelativeImplicationQueryKb (: $prf (B) $tv))
   (: b (B) (STV 1.0 1.0)))

!(compileadd (contextualFactsKb LOCAL Nil) (: local-fact (LocalFact) (STV 1.0 1.0)))

!(test (query 10 contextualFactsKb (: $prf (LocalFact) $tv)) ())

!(test (query 10 (contextualFactsKb LOCAL Nil) (: local-fact (LocalFact) (STV 1.0 1.0)))
   (: local-fact
      (Implication (LocalFact) (LocalFact))
      (STV 1.0 1.0)))

!(compileadd biImplicationKb (: a (A) (STV 1.0 1.0)))

!(compileadd biImplicationKb
   (: a_iff_b
      (BiImplication
         (A)
         (B))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 30 biImplicationKb (: $prf (B) $tv))
   (: (by (bi-forward a_iff_b) a) (B) (STV 1.0 0.9998000399670116)))

!(compileadd biImplicationKb (: b (B2) (STV 1.0 1.0)))

!(compileadd biImplicationKb
   (: a2_iff_b2
      (BiImplication
         (A2)
         (B2))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 30 biImplicationKb (: $prf (A2) $tv))
   (: (by (bi-backward a2_iff_b2) b) (A2) (STV 1.0 0.9998000399670116)))

!(test
   (query 60 biImplicationKb
      (: $prf
         (BiImplication
            (A)
            (B))
         $tv))
   (: (bidirectional (by (bi-forward a_iff_b) (ctx proof 16)) (by (bi-backward a_iff_b) (ctx proof 17))) (BiImplication (A) (B)) (STV 1.0 0.9996001597861455)))

!(test
   (query 60 implicationPremiseKb
      (: $prf (Implication (A) (B)) (STV 1.0 1.0)))
   ())

!(compileadd negConclusionKb (: a (A) (STV 1.0 1.0)))

!(compileadd negConclusionKb
   (: a_not_b
      (Implication
         (A)
         (Not (B)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 20 negConclusionKb (: $prf (B) $tv))
   (: (negated (by a_not_b a)) (B) (STV 0.0 0.9998000399670116)))

!(test
   (query 20 negConclusionKb (: $prf (Not (B)) $tv))
   (: (negated (negated (by a_not_b a))) (Not (B)) (STV 1.0 0.9998000399670116)))

;; BiImplication already emits both directions.  Even when enough historical
;; evidence exists to calculate Bayesian inverses, each direction must remain
;; one-way instead of creating a redundant inverse of its opposite direction.
!(compileadd oneWayBiImplicationKb
   (: aIffB
      (BiImplication
         (OneWayA $x)
         (OneWayB $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd oneWayBiImplicationKb
   (: currentB (OneWayB current) (STV 1.0 1.0)))
!(compileadd oneWayBiImplicationKb
   (: h1A (OneWayA h1) (STV 1.0 1.0)))
!(compileadd oneWayBiImplicationKb
   (: h1B (OneWayB h1) (STV 1.0 1.0)))
!(compileadd oneWayBiImplicationKb
   (: h2A (OneWayA h2) (STV 0.0 1.0)))
!(compileadd oneWayBiImplicationKb
   (: h2B (OneWayB h2) (STV 0.0 1.0)))

!(test
   (query 5000 oneWayBiImplicationKb
      (: $proof (OneWayA current) $tv))
   (: (by (bi-backward aIffB) currentB)
      (OneWayA current)
      (STV 0.8 0.8999999997518513)))
