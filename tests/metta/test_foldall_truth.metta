!(import! &self ../../pettachainer/metta/petta_chainer)

;; FoldAllTruth folds members' truth values as data: the rule folds every
;; Leak belief and reads one Leak again without an evidence clash, and a
;; variable rule truth turns the folded value into the conclusion's belief.
!(compileadd kb (: l1 (Leak u1) (STV 0.2 0.9)))
!(compileadd kb (: l2 (Leak u2) (STV 0.6 0.8)))
!(compileadd kb
   (: share
      (Implication
         (And (FoldAllTruth (Leak $v) (STV $s $_c) $s 0.0
                 (|-> ($acc $elem) (+ $acc $elem)) -> $total)
              (Leak $u)
              (FoldAllTruth (Leak $u) (STV $su $_cu) $su 0.0
                 (|-> ($acc $elem) $elem) -> $mine)
              (Compute / ($mine $total) -> $p))
         (Share $u))
      (CTV (STV $p 1.0) (STV $p 1.0))))

!(test
   (let (: $_proof (Share u1) (STV $s $_c))
      (car-atom (collapse (query 100 kb (: $prf (Share u1) $tv))))
      (and (> $s 0.2499) (< $s 0.2501)))
   true)

!(test
   (let (: $_proof (Share u2) (STV $s $_c))
      (car-atom (collapse (query 100 kb (: $prf (Share u2) $tv))))
      (and (> $s 0.7499) (< $s 0.7501)))
   true)
