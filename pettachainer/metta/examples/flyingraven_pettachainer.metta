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

!(mark-logic-rule inheritanceDeduction)

!(compileadd flyingRavenKb
   (: inheritanceDeduction
      (Implication
         (Premises (Inheritance $a $b) (Inheritance $b $c))
         (Conclusions (Inheritance $a $c)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 flyingRavenKb (: $prf (Inheritance Sam (IntSet flies)) $tv))
   (: (inheritanceDeduction
         (conjunction
            (inheritanceDeduction (conjunction samRaven ravenBird))
            birdFlies))
      (Inheritance Sam (IntSet flies))
      (STV 0.9702989999999999 0.9)))

!(test
   (query 100 flyingRavenKb (: $prf (Inheritance Pingu (IntSet flies)) $tv))
   (: (inheritanceDeduction
         (conjunction
            (inheritanceDeduction (conjunction pinguPenguin penguinBird))
            birdFlies))
      (Inheritance Pingu (IntSet flies))
      (STV 0.9702989999999999 0.9)))

!(test
   (query 100 flyingRavenKb (: $prf (Not (Inheritance Pingu (IntSet flies))) $tv))
   (: (merge/revision
         (penguinsDoNotFly pinguPenguin)
         (negated
            (inheritanceDeduction
               (conjunction
                  (inheritanceDeduction (conjunction pinguPenguin penguinBird))
                  birdFlies))))
      (Not (Inheritance Pingu (IntSet flies)))
      (STV 0.5098505000000001 0.9473684210526316)))
