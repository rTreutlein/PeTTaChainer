!(import! &self ../petta_chainer)

!(compileadd directKb
   (: fathersFatherGrandfather
      (Implication
         (And (Father $a $b) (Father $b $c))
         (Grandfather $a $c))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd directKb
   (: fathersMotherGrandfather
      (Implication
         (And (Father $a $b) (Mother $b $c))
         (Grandfather $a $c))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd directKb
   (: grandfatherOld
      (Implication
         (Exists ($x) (Grandfather $a $x))
         (Old $a))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd directKb (: fatherAB (Father a b) (STV 1.0 0.9)))

!(compileadd directKb (: fatherBC (Father b c) (STV 1.0 0.9)))

!(compileadd directKb (: fatherAY (Father a y) (STV 1.0 0.9)))

!(compileadd directKb (: motherYC (Mother y c) (STV 0.0 0.9)))

!(test
   (query 50 directKb (: $prf (Grandfather a c) $tv))
   (: (merge/revision
         (fathersMotherGrandfather (conjunction fatherAY motherYC))
         (fathersFatherGrandfather (conjunction fatherAB fatherBC)))
      (Grandfather a c)
      (STV 0.2501166485375841 0.9230240565975534)))

!(test
   (query 50 directKb (: $prf (Grandfather $who c) $tv))
   (: (merge/revision
         (fathersMotherGrandfather (conjunction fatherAY motherYC))
         (fathersFatherGrandfather (conjunction fatherAB fatherBC)))
      (Grandfather a c)
      (STV 0.2501166485375841 0.9230240565975534)))

!(test
   (query 50 directKb (: $prf (Old $who) $tv))
   (: (grandfatherOld
         (disjunction
            (merge/revision
               (fathersMotherGrandfather (conjunction fatherAY motherYC))
               (fathersFatherGrandfather (conjunction fatherAB fatherBC)))))
      (Old a)
      (STV 0.2501166485375841 0.9230240245003262)))
