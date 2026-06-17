!(import! &self petta_chainer)

; Raven induction with inheritance represented through ordinary implication
; machinery. There is no set-base-rate and no inheritanceInduction rule here.
;
; Direct inheritance observations register rv1 and rv2 as KB subjects. When
; inversion needs the singleton priors for (Inheritance $x rv1) or
; (Inheritance $x rv2), the runtime now supplies a KB-global concept-node
; prior, 1/N over currently registered inheritance endpoint nodes.
;
; The generated implications carry only the observed positive STV. When modus
; ponens or inversion needs a full CTV, the compiled rule estimates the negative
; branch from current base rates at calculation time.

!(compileadd ravenDerivedKb (: rv1RavenObserved (Inheritance rv1 raven) (STV 0.9 0.9)))
!(compileadd ravenDerivedKb (: rv2RavenObserved (Inheritance rv2 raven) (STV 0.9 0.9)))
!(compileadd ravenDerivedKb (: rv1BlackObserved (Inheritance rv1 (IntSet black)) (STV 0.8 0.9)))
!(compileadd ravenDerivedKb (: rv2BlackObserved (Inheritance rv2 (IntSet black)) (STV 0.0 0.9)))

!(compileadd ravenDerivedKb
   (: rv1ImpliesRaven
      (Implication
         (Premises (Inheritance $x rv1))
         (Conclusions (Inheritance $x raven)))
      (STV 0.9 0.9)))

!(compileadd ravenDerivedKb
   (: rv2ImpliesRaven
      (Implication
         (Premises (Inheritance $x rv2))
         (Conclusions (Inheritance $x raven)))
      (STV 0.9 0.9)))

!(compileadd ravenDerivedKb
   (: rv1ImpliesBlack
      (Implication
         (Premises (Inheritance $x rv1))
         (Conclusions (Inheritance $x (IntSet black))))
      (STV 0.8 0.9)))

!(compileadd ravenDerivedKb
   (: rv2ImpliesBlack
      (Implication
         (Premises (Inheritance $x rv2))
         (Conclusions (Inheritance $x (IntSet black))))
      (STV 0.0 0.9)))

!(test
   (query 300 ravenDerivedKb
      (: $prf
         (Implication
            (Premises (Inheritance $x raven))
            (Conclusions (Inheritance $x (IntSet black))))
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
      (Implication
         (Premises (Inheritance $q raven))
         (Conclusions (Inheritance $q (IntSet black))))
      (CTV
         (STV 0.6188715468989251 0.004210957006189564)
         (STV 0.17850910059853156 0.003610318196153512))))
