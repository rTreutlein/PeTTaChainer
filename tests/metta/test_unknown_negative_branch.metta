!(import! &self ../../pettachainer/metta/petta_chainer)

;; #83: a positive conditional alone says nothing about the complementary
;; condition. Missing rates and evidence drained by reconciliation are unknown.
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula no-evidence no-evidence (STV 0.5 0.0001)) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.5 0.0001) (STV 0.5 0.0)))
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula (STV 0.2 0.9) no-evidence (STV 0.8 0.9)) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 0.9) (STV 0.5 0.0)))
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula no-evidence (STV 0.7 0.9) (STV 0.8 0.9)) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 0.9) (STV 0.5 0.0)))
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula (STV 1 1) (STV 0.8 1) (STV 0.8 1)) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 1) (STV 0.5 0.0)))

;; The selected branch has zero evidence; the numerical confidence floor must
;; not turn it into a weak update. Either explicitly supplied branch still works.
!(test (CTVModusPonensFormula (STV 0 1) (CTV (STV 0.5 0.0001) (STV 0.5 0)))
   (STV 0.5 0.0))
!(test (CTVModusPonensFormula (STV 1 1) (CTV (STV 0.5 0) (STV 0.8 0.9)))
   (STV 0.5 0.0))
!(test (let (STV $s $c)
            (CTVModusPonensFormula (STV 0 1) (CTV (STV 0.5 0.9) (STV 0.8 0.9)))
         $s)
   0.8)
!(test (let $derived-likelihoods (ImplicationLikelihoodsFormula no-evidence no-evidence (CTV (STV 0.8 0.9) (STV 0.2 0.9))) (likelihood-read-tv $derived-likelihoods))
   (CTV (STV 0.8 0.9) (STV 0.2 0.9)))

;; Informed rates retain the total-probability estimate of the missing branch.
!(test (let (CTV $pos (STV $s $c))
            (let $derived-likelihoods (ImplicationLikelihoodsFormula (STV 0.25 0.9) (STV 0.5 0.9) (STV 0.8 0.9)) (likelihood-read-tv $derived-likelihoods))
         $c)
   0.225)
