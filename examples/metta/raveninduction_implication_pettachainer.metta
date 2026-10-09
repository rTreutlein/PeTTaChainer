!(import! &self ../../pettachainer/metta/petta_chainer)

!(set-base-rate ravenInductionImplicationKb (Rv1 $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Rv2 $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Raven $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Black $x) (STV 0.25 0.9))

!(compileadd ravenInductionImplicationKb
   (: rv1ImpliesRaven
      (Implication (Rv1 $x) (Raven $x))
      (STV 0.9 0.9)))

!(compileadd ravenInductionImplicationKb
   (: rv2ImpliesRaven
      (Implication (Rv2 $x) (Raven $x))
      (STV 0.9 0.9)))

!(compileadd ravenInductionImplicationKb
   (: rv1ImpliesBlack
      (Implication (Rv1 $x) (Black $x))
      (STV 0.8 0.9)))

!(compileadd ravenInductionImplicationKb
   (: rv2ImpliesBlack
      (Implication (Rv2 $x) (Black $x))
      (STV 0.0 0.9)))

!(test
   (query 100 ravenInductionImplicationKb
      (: $prf
         (Implication (Raven $x) (Black $x))
         $tv))
   (:
      (total-implication
         (merge/revision
            (by rv1ImpliesBlack
               ((inverted rv1ImpliesRaven with cpu (prior (STV 0.25000694425154857 0.9))) (ctx proof 0)))
            (by rv2ImpliesBlack
               ((inverted rv2ImpliesRaven with cpu (prior (STV 0.25000694425154857 0.9))) (ctx proof 0))))
         (merge/revision
            (by rv1ImpliesBlack
               ((inverted rv1ImpliesRaven with cpu (prior (STV 0.25000694425154857 0.9))) (ctx proof 1)))
            (by rv2ImpliesBlack
               ((inverted rv2ImpliesRaven with cpu (prior (STV 0.25000694425154857 0.9))) (ctx proof 1)))))
      (Implication (Raven $x) (Black $x))
      (CTV
         (STV 0.4337885433384649 0.5234740322165239)
         (STV 0.18944376904514637 0.41780567700414095))))
