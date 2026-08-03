!(import! &self ../petta_chainer)

!(compileadd openQueryKb (: d1 (Dog max) (STV 1.0 1.0)))

!(compileadd openQueryKb (: d2 (Dog ann) (STV 1.0 1.0)))

!(compileadd openQueryKb
   (: (no_inverse dog_to_animal) (Implication (Dog $x) (Animal $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 20 openQueryKb (: $prf (Animal $a) $tv))
   ((: ((no_inverse dog_to_animal) d1) (Animal max) (STV 1.0 0.9998000399670116)) (: ((no_inverse dog_to_animal) d2) (Animal ann) (STV 1.0 0.9998000399670116))))

!(compileadd openTimeKb (: tx1 (AtTime (FeatureX 0) 1) (STV 1.0 0.9)))

!(compileadd openTimeKb (: ty1 (AtTime (FeatureY 0) 1) (STV 1.0 0.9)))

!(compileadd openTimeKb
   (: timeAndRule
      (Implication
         (And (AtTime $x $t) (AtTime $y $t))
         (AtTime (And $x $y) $t))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 50 openTimeKb (: $prf (AtTime $f $t) $tv))
   ((: tx1 (AtTime (FeatureX 0) 1) (STV 1.0 0.9)) (: ty1 (AtTime (FeatureY 0) 1) (STV 1.0 0.9)) (: (timeAndRule (conjunction ty1 tx1)) (AtTime (And (FeatureY 0) (FeatureX 0)) 1) (STV 1.0 0.8180941841825682)) (: (timeAndRule (conjunction tx1 ty1)) (AtTime (And (FeatureX 0) (FeatureY 0)) 1) (STV 1.0 0.8180941841825682))))

!(compileadd openAndFairKb (: haveMax (Have (i max)) (STV 1.0 1.0)))

!(compileadd openAndFairKb (: haveAnn (Have (i ann)) (STV 1.0 1.0)))

!(compileadd openAndFairKb (: dogMax (Dog max) (STV 1.0 1.0)))

!(compileadd openAndFairKb (: dogAnn (Dog ann) (STV 1.0 1.0)))

!(compileadd openAndFairKb
   (: ownRule (Implication (Have (i $x)) (Own (i $x))) (CTV (STV 0.8 1.0) (STV 0.0 1.0))))

!(compileadd openAndFairKb
   (: petRule (Implication (Dog $x) (Pet $x)) (CTV (STV 0.7 1.0) (STV 0.0 1.0))))

!(compileadd openAndFairKb (: distract1 (Distract1 max) (STV 1.0 1.0)))

!(compileadd openAndFairKb (: distract2 (Distract2 max) (STV 1.0 1.0)))

!(compileadd openAndFairKb (: distract3 (Distract3 max) (STV 1.0 1.0)))

!(compileadd openAndFairKb (: distract4 (Distract4 max) (STV 1.0 1.0)))

!(compileadd openAndFairKb (: distract5 (Distract5 max) (STV 1.0 1.0)))

!(compileadd openAndFairKb (: distract6 (Distract6 max) (STV 1.0 1.0)))

!(compileadd openAndFairKb
   (: distractRule1 (Implication (Distract1 $x) (Pet $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd openAndFairKb
   (: distractRule2 (Implication (Distract2 $x) (Pet $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd openAndFairKb
   (: distractRule3 (Implication (Distract3 $x) (Pet $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd openAndFairKb
   (: distractRule4 (Implication (Distract4 $x) (Pet $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd openAndFairKb
   (: distractRule5 (Implication (Distract5 $x) (Pet $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd openAndFairKb
   (: distractRule6 (Implication (Distract6 $x) (Pet $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 30 openAndFairKb (: $prf (And (Own (i $a)) (Pet $a)) $tv))
   ((: (conjunction (ownRule haveMax) (merge/revision (merge/revision (merge/revision (merge/revision (merge/revision (merge/revision (distractRule6 distract6) (distractRule5 distract5)) (distractRule4 distract4)) (distractRule3 distract3)) (distractRule2 distract2)) (distractRule1 distract1)) (petRule dogMax))) (And (Own (i max)) (Pet max)) (STV 0.6800019996694093 0.9999093759280094)) (: (conjunction (ownRule haveAnn) (petRule dogAnn)) (And (Own (i ann)) (Pet ann)) (STV 0.5599999999999999 0.9999136351865401))))
