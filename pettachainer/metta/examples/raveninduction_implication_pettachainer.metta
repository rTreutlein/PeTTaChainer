!(import! &self petta_chainer)

!(set-base-rate ravenInductionImplicationKb (Rv1 $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Rv2 $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Raven $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Black $x) (STV 0.25 0.9))

!(compileadd ravenInductionImplicationKb
   (: rv1ImpliesRaven
      (Implication (Premises (Rv1 $x)) (Conclusions (Raven $x)))
      (CTV (STV 0.9 0.9) (STV 0.0 1.0))))

!(compileadd ravenInductionImplicationKb
   (: rv2ImpliesRaven
      (Implication (Premises (Rv2 $x)) (Conclusions (Raven $x)))
      (CTV (STV 0.9 0.9) (STV 0.0 1.0))))

!(compileadd ravenInductionImplicationKb
   (: rv1ImpliesBlack
      (Implication (Premises (Rv1 $x)) (Conclusions (Black $x)))
      (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

!(compileadd ravenInductionImplicationKb
   (: rv2ImpliesBlack
      (Implication (Premises (Rv2 $x)) (Conclusions (Black $x)))
      (CTV (STV 0.0 0.9) (STV 0.0 1.0))))

!(test
   (let
      (: $prf
         (Implication (Premises (Raven $x)) (Conclusions (Black $x)))
         $tv)
      (query 100 ravenInductionImplicationKb
         (: $prf
            (Implication (Premises (Raven $x)) (Conclusions (Black $x)))
            $tv))
      $tv)
   (CTV
      (STV 0.36000000000000004 0.8950276243093923)
      (STV 0.01333333333333333 0.8950276243093923)))
