!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd flyingRavenKb (: samRaven (Member Sam Raven) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: pinguPenguin (Member Pingu Penguin) (STV 0.99 0.9)))

!(compileadd flyingRavenKb
   (: penguinsDoNotFly
      (Implication
         (Member $x Penguin)
         (Not (Member $x flies)))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd flyingRavenKb (: ravenBird (Inheritance Raven Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: penguinBird (Inheritance Penguin Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: birdFlies (Inheritance Bird flies) (STV 0.99 0.9)))

;; Sam is a raven, so a bird, so flies. The class links are rules whose
;; negative branches come from the base rates, which no member informs here:
;; a non-raven Sam is unknown, which bounds the confidence.
!(test
   (collapse (query 200 flyingRavenKb (: $prf (Member Sam flies) $tv)))
   ((: (by birdFlies (by ravenBird samRaven)) (Member Sam flies) (STV 0.982699 0.4787214132400715))))

;; Pingu is a penguin: the penguin rule and the bird route revise.
!(test
   (collapse (query 60 flyingRavenKb (: $prf (Member Pingu flies) $tv)))
   ((: (merge/revision (negated (by penguinsDoNotFly pinguPenguin)) (by birdFlies (by penguinBird pinguPenguin)))
       (Member Pingu flies) (STV 0.10007216199275315 0.9084036784088747))))

!(test
   (collapse (query 200 flyingRavenKb (: $prf (Member Pingu flies) $tv)))
   ((: (merge/revision (negated (by penguinsDoNotFly pinguPenguin)) (by birdFlies (by penguinBird pinguPenguin)))
       (Member Pingu flies) (STV 0.10007216199275315 0.9084036784088747))))
