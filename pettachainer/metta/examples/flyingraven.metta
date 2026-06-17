!(import! &self petta_chainer)

!(compileadd flyingRavenKb (: samRaven (Inheritance Sam Raven) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: pinguPenguin (Inheritance Pingu Penguin) (STV 0.99 0.9)))

!(compileadd flyingRavenKb
   (: penguinsDoNotFly
      (Implication
         (Premises (Inheritance $x Penguin))
         (Conclusions (Not (Inheritance $x (IntSet flies)))))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd flyingRavenKb (: ravenBird (Inheritance Raven Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: penguinBird (Inheritance Penguin Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: birdFlies (Inheritance Bird (IntSet flies)) (STV 0.99 0.9)))

!(test
   (query 100 flyingRavenKb (: $prf (Inheritance Sam (IntSet flies)) $tv))
   (: ((inheritance-implication birdFlies)
         ((inheritance-implication ravenBird) samRaven))
      (Inheritance Sam (IntSet flies))
      (STV 0.99 0.9000930956748517)))

!(test
   (query 100 flyingRavenKb (: $prf (Inheritance Pingu (IntSet flies)) $tv))
   (: ((inheritance-implication birdFlies)
         ((inheritance-implication penguinBird) pinguPenguin))
      (Inheritance Pingu (IntSet flies))
      (STV 0.99 0.8995312826106832)))

!(test
   (query 100 flyingRavenKb (: $prf (Not (Inheritance Pingu (IntSet flies))) $tv))
   (: (merge/revision
         (penguinsDoNotFly pinguPenguin)
         (negated
            ((inheritance-implication birdFlies)
               ((inheritance-implication penguinBird) pinguPenguin))))
      (Not (Inheritance Pingu (IntSet flies)))
      (STV 0.5012490433490503 0.9472363895486416)))
