!(import! &self petta_chainer)

!(compileadd implicationPremiseKb
   (: ab_c
      (Implication
         (Premises
            (Implication (Premises (A)) (Conclusions (B))))
         (Conclusions
            (C)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd implicationPremiseKb
   (: a_b
      (Implication
         (Premises
            (A))
         (Conclusions
            (B)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 60 implicationPremiseKb
      (: $prf (Implication (Premises (A)) (Conclusions (B)))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   (: (total-implication (a_b (ctx proof 0)) (a_b (ctx proof 1)))
      (Implication (Premises (A)) (Conclusions (B)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 60 implicationPremiseKb (: $prf (C) $tv))
   (: (ab_c (total-implication (a_b (ctx proof 2)) (a_b (ctx proof 3))))
      (C)
      (STV 1.0 1.0)))

!(test
   (query 60 implicationPremiseKb
      (: $prf
         (Implication
            (Premises (Not (Dog)))
            (Conclusions (Dog)))
         $tv))
   (: (total-implication (ctx proof 6) (ctx proof 7))
      (Implication (Premises (Not (Dog))) (Conclusions (Dog)))
      (CTV (STV 0.0 1.0) (STV 1.0 1.0))))

!(test
   (query 60 implicationPremiseKb
      (: $prf
         (Implication
            (Premises (Not (Dog)))
            (Conclusions (Not (Dog))))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   (: (total-implication (negated (ctx proof 8)) (negated (ctx proof 9)))
      (Implication (Premises (Not (Dog))) (Conclusions (Not (Dog))))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd multiPremiseImplicationQueryKb
   (: ab_c
      (Implication
         (Premises
            (A)
            (B))
         (Conclusions
            (C)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 60 multiPremiseImplicationQueryKb
      (: $prf (Implication (Premises (A) (B)) (Conclusions (C))) $tv))
   (: (total-implication
        (ab_c (conjunction (ctx proof 10) (ctx proof 10 1)))
        (ab_c (conjunction (ctx proof 11) (ctx proof 11 1))))
      (Implication (Premises (A) (B)) (Conclusions (C)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 60 implicationPremiseKb
      (: $prf
         (Implication
            (Premises
               (Implication (Premises (A)) (Conclusions (B)))
               (A))
            (Conclusions (B)))
         $tv))
   (: (total-implication (a_b (ctx proof 12 1)) (a_b (ctx proof 13 1)))
      (Implication
         (Premises
            (Implication (Premises (A)) (Conclusions (B)))
            (A))
         (Conclusions (B)))
      (CTV (STV 1.0 1.0) (STV 1.0 1.0))))

!(set-context-polymorphic-facts kbRelativeImplicationQueryKb true)

!(compileadd kbRelativeImplicationQueryKb (: b (B) (STV 1.0 1.0)))

!(compileadd kbRelativeImplicationQueryKb
   (: ab_c
      (Implication
         (Premises
            (A)
            (B))
         (Conclusions
            (C)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 60 kbRelativeImplicationQueryKb
      (: $prf (Implication (Premises (A)) (Conclusions (C)))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   (: (total-implication
        (ab_c (conjunction (ctx proof 14) b))
        (ab_c (conjunction (ctx proof 15) b)))
      (Implication (Premises (A)) (Conclusions (C)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 10 kbRelativeImplicationQueryKb (: $prf (B) $tv))
   (: b (B) (STV 1.0 1.0)))

!(compileadd (contextualFactsKb LOCAL Nil) (: local-fact (LocalFact) (STV 1.0 1.0)))

!(test (query 10 contextualFactsKb (: $prf (LocalFact) $tv)) ())

!(test (query 10 (contextualFactsKb LOCAL Nil) (: local-fact (LocalFact) (STV 1.0 1.0)))
   (: local-fact
      (Implication (Premises (LocalFact)) (Conclusions (LocalFact)))
      (STV 1.0 1.0)))

!(compileadd biImplicationKb (: a (A) (STV 1.0 1.0)))

!(compileadd biImplicationKb
   (: a_iff_b
      (BiImplication
         (Premises (A))
         (Conclusions (B)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 30 biImplicationKb (: $prf (B) $tv))
   (: ((bi-forward a_iff_b) a) (B) (STV 1.0 1.0)))

!(compileadd biImplicationKb (: b (B2) (STV 1.0 1.0)))

!(compileadd biImplicationKb
   (: a2_iff_b2
      (BiImplication
         (Premises (A2))
         (Conclusions (B2)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 30 biImplicationKb (: $prf (A2) $tv))
   (: ((bi-backward a2_iff_b2) b) (A2) (STV 1.0 1.0)))

!(test
   (query 60 biImplicationKb
      (: $prf
         (BiImplication
            (Premises (A))
            (Conclusions (B)))
         $tv))
   (: (bidirectional
        ((bi-forward a_iff_b) (ctx proof 16))
        ((bi-backward a_iff_b) (ctx proof 17)))
      (BiImplication (Premises (A)) (Conclusions (B)))
      (STV 1.0 1.0)))
