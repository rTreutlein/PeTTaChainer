!(import! &self ../../pettachainer/metta/petta_chainer)

; Raven induction: the class link raven -> black is the implication between
; the two classes, (raven $x) -> (black $x), estimated from the members as
; its instance fold. Each member is one sample, weighted by how surely it is
; a raven; there is no set-base-rate and no induction rule here.

!(compileadd ravenDerivedKb (: rv1RavenObserved (Member rv1 raven) (STV 0.9 0.9)))
!(compileadd ravenDerivedKb (: rv2RavenObserved (Member rv2 raven) (STV 0.9 0.9)))
!(compileadd ravenDerivedKb (: rv1BlackObserved (Member rv1 black) (STV 0.8 0.9)))
!(compileadd ravenDerivedKb (: rv2BlackObserved (Member rv2 black) (STV 0.0 0.9)))

!(test
   (collapse
      (query 300 ravenDerivedKb
         (: $prf (Inheritance raven black) $tv)))
   ((: (implication-instance-fold cpu) (Inheritance raven black) (STV 0.39999999999999997 0.001819184536182807))))
