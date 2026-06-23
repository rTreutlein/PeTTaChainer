!(import! &self petta_chainer)

; Same setup as raveninduction.metta, but object-level observations use Member.
; Member observations stay in the Member relation; compileadd also exposes each
; object as its own singleton member class and derives member-level implication
; views. The class-level Inheritance query can therefore compare the extensional
; member path against the legacy inheritance-only example.

!(compileadd ravenMemberKb (: rv1RavenObserved (Member rv1 raven) (STV 0.9 0.9)))
!(compileadd ravenMemberKb (: rv2RavenObserved (Member rv2 raven) (STV 0.9 0.9)))
!(compileadd ravenMemberKb (: rv1BlackObserved (Member rv1 (IntSet black)) (STV 0.8 0.9)))
!(compileadd ravenMemberKb (: rv2BlackObserved (Member rv2 (IntSet black)) (STV 0.0 0.9)))

!(test
   (query 300 ravenMemberKb
      (: $prf
         (Inheritance raven (IntSet black))
         $tv))
   (:
      (member-inheritance-fold cpu)
      (Inheritance raven (IntSet black))
      (STV 0.39999999999999997 0.001819184536182807)))
