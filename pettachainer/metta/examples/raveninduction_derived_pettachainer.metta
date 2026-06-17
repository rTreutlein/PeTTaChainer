!(import! &self petta_chainer)

; Raven induction with inheritance represented through ordinary implication
; machinery. There is no set-base-rate and no inheritanceInduction rule here.
;
; Direct inheritance observations register rv1 and rv2 as KB subjects. When
; inversion needs the singleton priors for (Inheritance $x rv1) or
; (Inheritance $x rv2), the runtime now supplies a KB-global concept-node
; prior, 1/N over currently registered inheritance endpoint nodes.
;
; The compiler derives implication views from the direct inheritance
; observations. When modus ponens or inversion needs a full CTV, the compiled
; rule estimates the negative branch from current base rates at calculation time.

!(compileadd ravenDerivedKb (: rv1RavenObserved (Inheritance rv1 raven) (STV 0.9 0.9)))
!(compileadd ravenDerivedKb (: rv2RavenObserved (Inheritance rv2 raven) (STV 0.9 0.9)))
!(compileadd ravenDerivedKb (: rv1BlackObserved (Inheritance rv1 (IntSet black)) (STV 0.8 0.9)))
!(compileadd ravenDerivedKb (: rv2BlackObserved (Inheritance rv2 (IntSet black)) (STV 0.0 0.9)))

!(test
   (query 300 ravenDerivedKb
      (: $prf
         (Inheritance raven (IntSet black))
         $tv))
   (:
      (inheritance-query
         (total-implication
            ((inheritance-implication rv2BlackObserved)
               ((inverted (inheritance-implication rv2RavenObserved)
                   with
                   (foldall-proof
                      ((inverted (inheritance-implication rv2BlackObserved)
                          with
                          cpu
                          (foldall-proof rv1BlackObserved rv2BlackObserved))
                       rv2BlackObserved)
                      ((inverted (inheritance-implication rv2BlackObserved)
                          with
                          (foldall-proof rv1BlackObserved rv2BlackObserved)
                          (foldall-proof rv1BlackObserved rv2BlackObserved))
                       rv1BlackObserved))
                   (foldall-proof rv1RavenObserved rv2RavenObserved))
                (ctx proof 0)))
            ((inheritance-implication rv2BlackObserved)
               ((inverted (inheritance-implication rv2RavenObserved)
                   with
                   (foldall-proof
                      ((inverted (inheritance-implication rv2BlackObserved)
                          with
                          cpu
                          (foldall-proof rv1BlackObserved rv2BlackObserved))
                       rv2BlackObserved)
                      ((inverted (inheritance-implication rv2BlackObserved)
                          with
                          (foldall-proof rv1BlackObserved rv2BlackObserved)
                          (foldall-proof rv1BlackObserved rv2BlackObserved))
                       rv1BlackObserved))
                   (foldall-proof rv1RavenObserved rv2RavenObserved))
                (ctx proof 1)))))
      (Inheritance raven (IntSet black))
      (STV 0.4758369798846596 0.001770086372769075)))
