!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd openQueryKb (: d1 (Dog max) (STV 1.0 1.0)))

!(compileadd openQueryKb (: d2 (Dog ann) (STV 1.0 1.0)))

!(compileadd openQueryKb
   (: (no_inverse dog_to_animal) (Implication (Dog $x) (Animal $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 20 openQueryKb (: $prf (Animal $a) $tv))
   ((: (by (no_inverse dog_to_animal) d1) (Animal max) (STV 1.0 0.9998000399670116)) (: (by (no_inverse dog_to_animal) d2) (Animal ann) (STV 1.0 0.9998000399670116))))

!(compileadd openTimeKb (: tx1 (AtTime (FeatureX 0) 1) (STV 1.0 0.9)))

!(compileadd openTimeKb (: ty1 (AtTime (FeatureY 0) 1) (STV 1.0 0.9)))

!(compileadd openTimeKb
   (: timeAndRule
      (Implication
         (And (AtTime $x $t) (AtTime $y $t))
         (AtTime (And $x $y) $t))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; The rule builds terms from its own conclusions, (And X (And X Y)) among
;; them; only the budget bounds how many.
!(test
   (query 50 openTimeKb (: $prf (AtTime $f $t) $tv))
   ((: tx1 (AtTime (FeatureX 0) 1) (STV 1.0 0.9)) (: ty1 (AtTime (FeatureY 0) 1) (STV 1.0 0.9)) (: (by timeAndRule (conjunction ty1 tx1)) (AtTime (And (FeatureY 0) (FeatureX 0)) 1) (STV 1.0 0.8180941841825682)) (: (by timeAndRule (conjunction tx1 ty1)) (AtTime (And (FeatureX 0) (FeatureY 0)) 1) (STV 1.0 0.8180941841825682)) (: (conditioned tx1 (by timeAndRule (conjunction (given true) (by timeAndRule (conjunction (given true) ty1)))) (by timeAndRule (conjunction (given false) (by timeAndRule (conjunction (given false) ty1))))) (AtTime (And (FeatureX 0) (And (FeatureX 0) (FeatureY 0))) 1) (STV 1.0 0.8178933383970609)) (: (conditioned ty1 (by timeAndRule (conjunction (given true) (by timeAndRule (conjunction tx1 (given true))))) (by timeAndRule (conjunction (given false) (by timeAndRule (conjunction tx1 (given false)))))) (AtTime (And (FeatureY 0) (And (FeatureX 0) (FeatureY 0))) 1) (STV 1.0 0.8178933383970609)) (: (conditioned tx1 (by timeAndRule (conjunction (given true) (by timeAndRule (conjunction ty1 (given true))))) (by timeAndRule (conjunction (given false) (by timeAndRule (conjunction ty1 (given false)))))) (AtTime (And (FeatureX 0) (And (FeatureY 0) (FeatureX 0))) 1) (STV 1.0 0.8178933383970609)) (: (conditioned ty1 (by timeAndRule (conjunction (given true) (by timeAndRule (conjunction (given true) tx1)))) (by timeAndRule (conjunction (given false) (by timeAndRule (conjunction (given false) tx1))))) (AtTime (And (FeatureY 0) (And (FeatureY 0) (FeatureX 0))) 1) (STV 1.0 0.8178933383970609)) (: (conditioned tx1 (by timeAndRule (conjunction (given true) (conditioned ty1 (by timeAndRule (conjunction (given true) (by timeAndRule (conjunction (given true) (given true))))) (by timeAndRule (conjunction (given false) (by timeAndRule (conjunction (given true) (given false)))))))) (by timeAndRule (conjunction (given false) (conditioned ty1 (by timeAndRule (conjunction (given true) (by timeAndRule (conjunction (given false) (given true))))) (by timeAndRule (conjunction (given false) (by timeAndRule (conjunction (given false) (given false))))))))) (AtTime (And (FeatureX 0) (And (FeatureY 0) (And (FeatureX 0) (FeatureY 0)))) 1) (STV 1.0 0.8176925910538717)) (: (conditioned ty1 (by timeAndRule (conjunction (given true) (by timeAndRule (conjunction (given true) (by timeAndRule (conjunction tx1 (given true))))))) (by timeAndRule (conjunction (given false) (by timeAndRule (conjunction (given false) (by timeAndRule (conjunction tx1 (given false)))))))) (AtTime (And (FeatureY 0) (And (FeatureY 0) (And (FeatureX 0) (FeatureY 0)))) 1) (STV 1.0 0.8177594959013654))))

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
   ((: (conjunction (by ownRule haveMax) (merge/revision (merge/revision (merge/revision (merge/revision (merge/revision (merge/revision (by petRule dogMax) (by distractRule1 distract1)) (by distractRule2 distract2)) (by distractRule3 distract3)) (by distractRule4 distract4)) (by distractRule5 distract5)) (by distractRule6 distract6))) (And (Own (i max)) (Pet max)) (STV 0.7400000993747873 0.9999230825234057)) (: (conjunction (by ownRule haveAnn) (by petRule dogAnn)) (And (Own (i ann)) (Pet ann)) (STV 0.5599999999999999 0.9999136435669362))))

;; An open query keeps a stored fact (ONA threelegdog, ChainerGame
;; benchmarks/ona/repros/open_query_drops_fact.metta). The member rule applied
;; with x = c = Dog reads (HasLeg Dog 4) to conclude it again; its view's
;; evidence contained the fact's, so it replaced the fact: 0.20 for the open
;; query against 0.9 for the ground one. Such an instance builds no row now.
!(compileadd legKb (: f1 (Member fido Dog) (STV 1.0 0.9)))
!(compileadd legKb (: f2 (Member snoopy Dog) (STV 1.0 0.9)))
!(compileadd legKb (: f3 (Inheritance Dog Animal) (STV 1.0 0.9)))
!(compileadd legKb (: f4 (HasLeg Dog 4) (STV 1.0 0.9)))
!(compileadd legKb (: f5 (HasLeg fido 3) (STV 1.0 0.9)))
!(compileadd legKb (: f6 (HasLeg Chicken 2) (STV 1.0 0.9)))
!(compileadd legKb (: f7 (Inheritance Chicken Animal) (STV 1.0 0.9)))
!(compileadd legKb (: r1 (Implication (And (Member $x $c) (HasLeg $c $n)) (HasLeg $x $n)) (STV 1.0 0.9)))
!(test (query 100 legKb (: $p (HasLeg Dog 4) $tv)) (: f4 (HasLeg Dog 4) (STV 1.0 0.9)))
!(test (let (: $p (HasLeg Dog 4) $tv) (query 100 legKb (: $p (HasLeg Dog $n) $tv)) ($p $tv)) (f4 (STV 1.0 0.9)))

;; A rule that grows its terms ((Num $x) -> (Num (succ $x)), ONA
;; reasoningbench, benchmarks/ona/repros/term_growing_rule.metta) inverts into
;; an unbounded chain of ever larger statements. Demand walks the keys a query
;; reaches breadth first, once each; walked depth first, a key reached again
;; more closely walked everything below it again (budget 100: over 55 s, now
;; about 4 s).
!(compileadd numKb (: r9 (Implication (Num $x) (Num (succ $x))) (STV 1.0 0.9)))
!(compileadd numKb (: f10 (Num 1) (STV 1.0 0.9)))
!(test (query 100 numKb (: $p (Num (succ 1)) $tv)) (: (by r9 f10) (Num (succ 1)) (STV 1.0 0.8181610802590104)))
