!(import! &self petta_chainer)

!(compileadd robotKb
   (: toySeenBring
      (Implication
         (Premises (Inheritance $x toy) (Inheritance $x see))
         (Conclusions (Inheritance $x bring)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

!(compileadd robotKb (: frisbeeToy (Inheritance frisbee toy) (STV 0.99 0.99)))

!(compileadd robotKb (: sportsballToy (Inheritance sportsball toy) (STV 0.99 0.99)))

!(compileadd robotKb (: orangeRound (Inheritance orange round) (STV 0.99 0.99)))

!(compileadd robotKb (: sportsballRound (Inheritance sportsball round) (STV 0.99 0.99)))

!(mark-logic-rule sharedPropertyCategory)

!(compileadd robotKb
   (: sharedPropertyCategory
      (Implication
         (Premises
            (Inheritance $obj $property)
            (Inheritance $prototype $property)
            (Inheritance $prototype $category))
         (Conclusions (Inheritance $obj $category)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

!(mark-logic-rule sharedPropertySeenBring)

!(compileadd robotKb
   (: sharedPropertySeenBring
      (Implication
         (Premises
            (Inheritance $obj $property)
            (Inheritance $prototype $property)
            (Inheritance $prototype toy)
            (Inheritance $obj see))
         (Conclusions (Inheritance $obj bring)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

(= (addSeenObservation $label)
   (compileadd robotKb (: (seen $label) (Inheritance $label see) (STV 0.99 0.99))))

(= (PLNobjectsOfCategoryHelper () $_category) ())
(= (PLNobjectsOfCategoryHelper (cons (detection $label $coord) $rest) $category)
   (let $_seen (collapse (addSeenObservation $label))
         (let $hits (collapse (query 300 robotKb (: $prf (Inheritance $label $category) $tv)))
         (if (== $hits ())
            (PLNobjectsOfCategoryHelper $rest $category)
            (cons (detection $label $coord)
               (PLNobjectsOfCategoryHelper $rest $category))))))

(= (PLNobjectsOfCategory $objects $category)
   (unique-atom (PLNobjectsOfCategoryHelper $objects $category)))

!(test
   (PLNobjectsOfCategory
      ((detection frisbee someCoords1)
       (detection {SELF} someCoords2)
       (detection person someCoords3)
       (detection orange someCoords4))
      bring)
   ((detection frisbee someCoords1) (detection orange someCoords4)))
