!(import! &self ../../pettachainer/metta/petta_chainer)

!(test
   (evidence-entries (evidence-negated (evidence-set ((fact-ev (kb MAIN Nil) d (Dog)) (not-fact-ev (kb MAIN Nil) e (Cat)) e))))
   ((not-fact-ev (kb MAIN Nil) d (Dog)) (fact-ev (kb MAIN Nil) e (Cat)) (not-ev e)))

!(test
   (evidence-overlap?
      (evidence-set ((fact-ev (kb MAIN Nil) d (Dog))))
      (evidence-set ((not-fact-ev (kb MAIN Nil) d (Dog)))))
   false)

!(compileadd negEvidenceMergeKb
   (: nd_a (Implication (Not (Dog)) (Animal)) (CTV (STV 0.75 0.5) (STV 0.0 1.0))))

!(compileadd negEvidenceMergeKb
   (: d_a (Implication (Dog) (Animal)) (CTV (STV 0.25 0.5) (STV 0.0 1.0))))

!(compileadd negEvidenceMergeKb (: d (Dog) (STV 0.5 1.0)))

!(test (query 100 negEvidenceMergeKb (: $prf (Animal) $tv))
   (: (merge/revision (by nd_a (negated d)) (by d_a d)) (Animal) (STV 0.29547002724795635 0.8800959232613909)))

!(compileadd totalMpFallbackKb (: d (Dog) (STV 0.5 1.0)))

!(compileadd totalMpFallbackKb
   (: d_a (Implication (Dog) (Animal)) (CTV (STV 0.8 0.6) (STV 0.0 1.0))))

!(test (query 100 totalMpFallbackKb (: $prf (Animal) $tv))
   (: (by d_a d) (Animal) (STV 0.4 0.9000624609618988)))

!(compileadd totalMpNegOnlyKb (: d (Dog) (STV 0.5 1.0)))

!(compileadd totalMpNegOnlyKb
   (: nd_a (Implication (Not (Dog)) (Animal)) (CTV (STV 0.8 0.6) (STV 0.0 1.0))))

!(test (query 100 totalMpNegOnlyKb (: $prf (Animal) $tv))
   (: (by nd_a (negated d)) (Animal) (STV 0.4 0.9000624609618988)))
