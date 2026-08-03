!(import! &self ../petta_chainer)

!(compileadd flyingRavenMemberKb (: samRaven (Member Sam Raven) (STV 0.99 0.9)))

!(compileadd flyingRavenMemberKb (: pinguPenguin (Member Pingu Penguin) (STV 0.99 0.9)))

!(compileadd flyingRavenMemberKb
   (: penguinsDoNotFly
      (Implication
         (Member $x Penguin)
         (Not (Member $x (IntSet flies))))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd flyingRavenMemberKb (: ravenBird (Inheritance Raven Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenMemberKb (: penguinBird (Inheritance Penguin Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenMemberKb (: birdFlies (Inheritance Bird (IntSet flies)) (STV 0.99 0.9)))

!(test
   (collapse (query 100 flyingRavenMemberKb (: $prf (Member Sam (IntSet flies)) $tv)))
   ((:
      (by (no_inverse (member-inheritance-implication birdFlies))
         (by (no_inverse (member-inheritance-implication ravenBird)) samRaven))
      (Member Sam (IntSet flies))
      (STV 0.9702989999999999 0.9009039059782787))))

!(test
   (collapse (query 20 flyingRavenMemberKb (: $prf (Member Pingu (IntSet flies)) $tv)))
   ((:
      (merge/revision
         (by (no_inverse (member-inheritance-implication birdFlies))
            (by (no_inverse (member-inheritance-implication penguinBird)) pinguPenguin))
         (negated (by penguinsDoNotFly pinguPenguin)))
      (Member Pingu (IntSet flies))
      (STV 0.49259416120824195 0.9476174423845426))))
