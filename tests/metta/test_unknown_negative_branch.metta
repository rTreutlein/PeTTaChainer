!(import! &self ../../pettachainer/metta/petta_chainer)

;; #83: a positive conditional alone says nothing about the complementary
;; condition. Missing rates and evidence drained by reconciliation are unknown.
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula no-evidence no-evidence (STV 0.5 0.0001) 0.5) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.5 0.0001) (STV 0.5 0.0)))
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula (STV 0.2 0.9) no-evidence (STV 0.8 0.9) 0.5) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 0.9) (STV 0.5 0.0)))
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula no-evidence (STV 0.7 0.9) (STV 0.8 0.9) 0.5) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 0.9) (STV 0.5 0.0)))
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula (STV 1 1) (STV 0.8 1) (STV 0.8 1) 0.5) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 1) (STV 0.5 0.0)))
;; A complete conclusion centres the unknown branch at false.
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula no-evidence no-evidence (STV 0.8 0.9) 0.0) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 0.9) (STV 0.0 0.0)))

;; The selected branch has zero evidence; the numerical confidence floor must
;; not turn it into a weak update. Either explicitly supplied branch still works.
!(test (CTVModusPonensFormula (STV 0 1) (CTV (STV 0.5 0.0001) (STV 0.5 0)))
   (STV 0.5 0.0))
!(test (CTVModusPonensFormula (STV 1 1) (CTV (STV 0.5 0) (STV 0.8 0.9)))
   (STV 0.5 0.0))
!(test (CTVModusPonensFormula (STV 0 1) (CTV (STV 1 1) (STV 0.0 0)))
   (STV 0.0 0.0))
!(test (let (STV $s $c)
            (CTVModusPonensFormula (STV 0 1) (CTV (STV 0.5 0.9) (STV 0.8 0.9)))
         $s)
   0.8)
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula no-evidence no-evidence (CTV (STV 0.8 0.9) (STV 0.2 0.9)) 0.5) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 0.9) (STV 0.2 0.9)))

;; Informed rates retain the total-probability estimate of the missing branch.
!(test (let (CTV $pos (STV $s $c))
            (let $derived-likelihoods (ImplicationLikelihoodsFormula (STV 0.25 0.9) (STV 0.5 0.9) (STV 0.8 0.9) 0.5) (likelihood-read-tv $derived-likelihoods))
         $c)
   0.225)

(= (close? $x $y) (< (abs-math (- $x $y)) 0.0001))

;; An unknown branch has the uniform prior's variance 1/12. Its share of a
;; conclusion's variance is weighted by the square of its mass, (1 - 0.95)^2.
!(test (ideal-var 0.5 0.0) 0.08333333333333333)
!(test (let (STV $s $c) (CTVModusPonensFormula (STV 0.95 0.9) (CTV (STV 0.98 0.9) (STV 0.5 0.0)))
         (and (close? $s 0.956) (close? $c 0.19728)))
   true)

;; A member chain through STV rules whose negative branches no rate informs:
;; tom is a Cat, so the first link's negative branch carries no mass; the
;; second's carries P(not Mammal) = 0.05.
!(compileadd chainKb (: ab (Implication (Cat $x) (Mammal $x)) (STV 0.95 0.9)))
!(compileadd chainKb (: bc (Implication (Mammal $x) (Animal $x)) (STV 0.98 0.9)))
!(compileadd chainKb (: db (Implication (Dog $x) (Mammal $x)) (STV 0.95 0.9)))
!(compileadd chainKb (: m1 (Cat tom) (STV 1.0 0.9)))
!(compileadd chainKb (: m2 (Dog rex) (STV 1.0 0.9)))
!(compileadd chainKb (: m3 (Mammal eve) (STV 1.0 0.9)))
!(test (let (: $p (Mammal tom) (STV $s $c)) (query 100 chainKb (: $p (Mammal tom) $tv))
         (and (close? $s 0.95) (close? $c 0.9)))
   true)
!(test (let (: $p (Animal tom) (STV $s $c)) (query 100 chainKb (: $p (Animal tom) $tv))
         (and (close? $s 0.956) (close? $c 0.19728)))
   true)

;; One step: a certain antecedent selects the positive branch alone; an
;; antecedent at 0.95 gives the unknown branch mass 0.05.
!(compileadd oneKb (: bc (Implication (Mammal $x) (Animal $x)) (STV 0.98 0.9)))
!(compileadd oneKb (: m1 (Mammal tom) (STV 1.0 1.0)))
!(compileadd oneKb (: m2 (Mammal ann) (STV 0.95 0.9)))
!(test (let (: $p (Animal tom) (STV $s $c)) (query 100 oneKb (: $p (Animal tom) $tv))
         (and (close? $s 0.98) (close? $c 0.9)))
   true)
!(test (let (: $p (Animal ann) (STV $s $c)) (query 100 oneKb (: $p (Animal ann) $tv))
         (and (close? $s 0.956) (close? $c 0.19728)))
   true)

;; Three steps: each link's unknown branch adds its mass-weighted variance.
!(compileadd threeKb (: ab (Implication (Cat $x) (Mammal $x)) (STV 0.95 0.9)))
!(compileadd threeKb (: bc (Implication (Mammal $x) (Vert $x)) (STV 0.98 0.9)))
!(compileadd threeKb (: cd (Implication (Vert $x) (Animal $x)) (STV 0.99 0.9)))
!(compileadd threeKb (: m1 (Cat tom) (STV 1.0 0.9)))
!(test (let (: $p (Animal tom) (STV $s $c)) (query 100 threeKb (: $p (Animal tom) $tv))
         (and (close? $s 0.96844) (close? $c 0.14077)))
   true)
