!(import! &self ../../pettachainer/metta/petta_chainer)
!(set-bayes-prior-count 0)
!(set-base-rate populationKb (Bird $x) (STV 0.2 1))
;; The STV source's antecedent is Not Bird; rate caches key exact patterns.
!(set-base-rate populationKb (Not (Bird $x)) (STV 0.8 1))
!(set-base-rate populationKb (Fly $x) (STV 0.5 1))
!(compileadd populationKb (: nonbirds (Implication (Not (Bird $x)) (Fly $x)) (STV 0.4 1)))
;; No birds are counted. Total probability supplies (0.5 - 0.8*0.4)/0.2.
!(test (collapse (let (: $p $type (STV $s $c))
   (query 1000 populationKb (: $q (Implication (Bird $x) (Fly $x)) $tv))
   (and (<= (abs-math (- $s 0.9)) 1e-12) (> $c 0)))) (true))
;; A ground hypothetical false antecedent supplies no population evidence.
!(test (collapse (let (: $p $type (STV $_s $c))
   (query 1000 populationKb (: $q (Implication (Bird tweety) (Fly tweety)) $tv)) $c)) (0.0))
