!(import! &self ../petta_chainer)

!(set-base-rate robotKb (Inheritance $x toy) (STV 0.5 0.9))
!(set-base-rate robotKb (Inheritance $x see) (STV 0.5 0.9))
!(set-base-rate robotKb (Inheritance $x bring) (STV 0.5 0.9))
!(set-base-rate robotKb (Inheritance $x round) (STV 0.5 0.9))
!(set-base-rate robotKb (And (Inheritance $x toy) (Inheritance $x see)) (STV 0.25 0.9))
!(set-base-rate robotKb
   (And
      (Inheritance $obj $property)
      (Inheritance $prototype $property)
      (Inheritance $prototype $category))
   (STV 0.125 0.9))
!(set-base-rate robotKb
   (And
      (Inheritance $obj $property)
      (Inheritance $prototype $property)
      (Inheritance $prototype toy)
      (Inheritance $obj see))
   (STV 0.0625 0.9))

!(compileadd robotKb
   (: toySeenBring
      (Implication
         (And (Inheritance $x toy) (Inheritance $x see))
         (Inheritance $x bring))
      (STV 0.99 0.99)))

!(compileadd robotKb (: frisbeeToy (Inheritance frisbee toy) (STV 0.99 0.99)))

!(compileadd robotKb (: sportsballToy (Inheritance sportsball toy) (STV 0.99 0.99)))

!(compileadd robotKb (: orangeRound (Inheritance orange round) (STV 0.99 0.99)))

!(compileadd robotKb (: sportsballRound (Inheritance sportsball round) (STV 0.99 0.99)))

!(mark-logic-rule sharedPropertyCategory)

!(compileadd robotKb
   (: sharedPropertyCategory
      (Implication
         (And
            (Inheritance $obj $property)
            (Inheritance $prototype $property)
            (Inheritance $prototype $category))
         (Inheritance $obj $category))
      (STV 0.99 0.99)))

!(mark-logic-rule sharedPropertySeenBring)

!(compileadd robotKb
   (: sharedPropertySeenBring
      (Implication
         (And
            (Inheritance $obj $property)
            (Inheritance $prototype $property)
            (Inheritance $prototype toy)
            (Inheritance $obj see))
         (Inheritance $obj bring))
      (STV 0.99 0.99)))

!(compileadd robotKb (: seenFrisbee (Inheritance frisbee see) (STV 0.99 0.99)))

!(compileadd robotKb (: seenSelfRobot (Inheritance selfRobot see) (STV 0.99 0.99)))

!(compileadd robotKb (: seenPerson (Inheritance person see) (STV 0.99 0.99)))

!(compileadd robotKb (: seenOrange (Inheritance orange see) (STV 0.99 0.99)))

(= (highConfidenceObjectResult (: $_prf $_type (STV $s $c)))
   (and (> $s 0.8) (> $c 0.8)))
(= (containsTrue $items)
   (case $items (
      ((cons true $_rest) true)
      ((cons $_head $rest) (containsTrue $rest))
      ($_ false))))

(= (hasHighConfidenceObject $label $category)
   (let $matches
      (collapse
         (let (: $_prf (Inheritance $label $category) (STV $s $c))
            (query 80 robotKb (: $_prf (Inheritance $label $category) (STV $s $c)))
            (highConfidenceObjectResult (: $_prf (Inheritance $label $category) (STV $s $c)))))
      (containsTrue $matches)))

(= (PLNobjectsOfCategoryHelper () $_category) ())
(= (PLNobjectsOfCategoryHelper (cons (detection $label $coord) $rest) $category)
   (if (hasHighConfidenceObject $label $category)
      (cons (detection $label $coord)
         (PLNobjectsOfCategoryHelper $rest $category))
      (PLNobjectsOfCategoryHelper $rest $category)))

(= (PLNobjectsOfCategory $objects $category)
   (unique-atom (PLNobjectsOfCategoryHelper $objects $category)))

!(test
   (PLNobjectsOfCategory
      ((detection frisbee someCoords1)
       (detection selfRobot someCoords2)
       (detection person someCoords3)
       (detection orange someCoords4))
      bring)
   ((detection frisbee someCoords1) (detection orange someCoords4)))
