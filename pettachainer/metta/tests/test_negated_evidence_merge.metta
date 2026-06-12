!(import! &self petta_chainer)

!(test
   (evidence-negate (fact-ev (kb MAIN Nil) d (Dog)))
   (not-fact-ev (kb MAIN Nil) d (Dog)))

!(test
   (evidence-sets-overlap?
      ((fact-ev (kb MAIN Nil) d (Dog)))
      ((not-fact-ev (kb MAIN Nil) d (Dog))))
   false)

!(compileadd negEvidenceMergeKb
   (: nd_a (Implication (Premises (Not (Dog))) (Conclusions (Animal))) (CTV (STV 0.75 0.5) (STV 0.0 1.0))))

!(compileadd negEvidenceMergeKb
   (: d_a (Implication (Premises (Dog)) (Conclusions (Animal))) (CTV (STV 0.25 0.5) (STV 0.0 1.0))))

!(compileadd negEvidenceMergeKb (: d (Dog) (STV 0.5 1.0)))

!(test (query 100 negEvidenceMergeKb (: $prf (Animal) $tv))
   (: (merge/revision (d_a d) (nd_a (negated d))) (Animal) (STV 0.25 0.8571428571428571)))

!(compileadd totalMpFallbackKb (: d (Dog) (STV 0.5 1.0)))

!(compileadd totalMpFallbackKb
   (: d_a (Implication (Premises (Dog)) (Conclusions (Animal))) (CTV (STV 0.8 0.6) (STV 0.0 1.0))))

!(test (query 100 totalMpFallbackKb (: $prf (Animal) $tv))
   (: (d_a d) (Animal) (STV 0.4 0.8)))

!(compileadd totalMpNegOnlyKb (: d (Dog) (STV 0.5 1.0)))

!(compileadd totalMpNegOnlyKb
   (: nd_a (Implication (Premises (Not (Dog))) (Conclusions (Animal))) (CTV (STV 0.8 0.6) (STV 0.0 1.0))))

!(test (query 100 totalMpNegOnlyKb (: $prf (Animal) $tv))
   (: (nd_a (negated d)) (Animal) (STV 0.4 0.8)))
