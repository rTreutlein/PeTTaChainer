!(import! &self petta_chainer)

!(set-base-rate ravenInductionImplicationKb (Rv1 $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Rv2 $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Raven $x) (STV 0.25 0.9))
!(set-base-rate ravenInductionImplicationKb (Black $x) (STV 0.25 0.9))

!(compileadd ravenInductionImplicationKb
   (: rv1ImpliesRaven
      (Implication (Premises (Rv1 $x)) (Conclusions (Raven $x)))
      (STV 0.9 0.9)))

!(compileadd ravenInductionImplicationKb
   (: rv2ImpliesRaven
      (Implication (Premises (Rv2 $x)) (Conclusions (Raven $x)))
      (STV 0.9 0.9)))

!(compileadd ravenInductionImplicationKb
   (: rv1ImpliesBlack
      (Implication (Premises (Rv1 $x)) (Conclusions (Black $x)))
      (STV 0.8 0.9)))

!(compileadd ravenInductionImplicationKb
   (: rv2ImpliesBlack
      (Implication (Premises (Rv2 $x)) (Conclusions (Black $x)))
      (STV 0.0 0.9)))

!(test
   (query 100 ravenInductionImplicationKb
      (: $prf
         (Implication (Premises (Raven $x)) (Conclusions (Black $x)))
         $tv))
   (:
      (total-implication
         (merge/revision
            (rv1ImpliesBlack
               ((inverted rv1ImpliesRaven with cpu cpu) (ctx proof 0)))
            (rv2ImpliesBlack
               ((inverted rv2ImpliesRaven with cpu cpu) (ctx proof 0))))
         (merge/revision
            (rv1ImpliesBlack
               ((inverted rv1ImpliesRaven with cpu cpu) (ctx proof 1)))
            (rv2ImpliesBlack
               ((inverted rv2ImpliesRaven with cpu cpu) (ctx proof 1)))))
      (Implication (Premises (Raven $x)) (Conclusions (Black $x)))
      (CTV
         (STV 0.43377973868275976 0.5234813517279882)
         (STV 0.1894448281191785 0.4177956832421612))))
