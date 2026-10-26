!(import! &self ../../pettachainer/metta/petta_chainer)

!(set-base-rate robotKb (Member $x toy) (STV 0.5 0.9))
!(set-base-rate robotKb (Member $x see) (STV 0.5 0.9))
!(set-base-rate robotKb (Member $x bring) (STV 0.5 0.9))
!(set-base-rate robotKb (Member $x round) (STV 0.5 0.9))
!(set-base-rate robotKb (And (Member $x toy) (Member $x see)) (STV 0.25 0.9))
!(set-base-rate robotKb
   (And
      (Member $obj $property)
      (Member $prototype $property)
      (Member $prototype $category))
   (STV 0.125 0.9))
!(set-base-rate robotKb
   (And
      (Member $obj $property)
      (Member $prototype $property)
      (Member $prototype toy)
      (Member $obj see))
   (STV 0.0625 0.9))

!(compileadd robotKb
   (: toySeenBring
      (Implication
         (And (Member $x toy) (Member $x see))
         (Member $x bring))
      (STV 0.99 0.99)))

!(compileadd robotKb (: frisbeeToy (Member frisbee toy) (STV 0.99 0.99)))

!(compileadd robotKb (: sportsballToy (Member sportsball toy) (STV 0.99 0.99)))

!(compileadd robotKb (: orangeRound (Member orange round) (STV 0.99 0.99)))

!(compileadd robotKb (: sportsballRound (Member sportsball round) (STV 0.99 0.99)))

!(mark-logic-rule sharedPropertyCategory)

!(compileadd robotKb
   (: sharedPropertyCategory
      (Implication
         (And
            (Member $obj $property)
            (Member $prototype $property)
            (Member $prototype $category))
         (Member $obj $category))
      (STV 0.99 0.99)))

!(mark-logic-rule sharedPropertySeenBring)

!(compileadd robotKb
   (: sharedPropertySeenBring
      (Implication
         (And
            (Member $obj $property)
            (Member $prototype $property)
            (Member $prototype toy)
            (Member $obj see))
         (Member $obj bring))
      (STV 0.99 0.99)))

!(compileadd robotKb (: seenFrisbee (Member frisbee see) (STV 0.99 0.99)))

!(compileadd robotKb (: seenSelfRobot (Member selfRobot see) (STV 0.99 0.99)))

!(compileadd robotKb (: seenPerson (Member person see) (STV 0.99 0.99)))

!(compileadd robotKb (: seenOrange (Member orange see) (STV 0.99 0.99)))

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
         (let (: $_prf (Member $label $category) (STV $s $c))
            (query 80 robotKb (: $_prf (Member $label $category) (STV $s $c)))
            (highConfidenceObjectResult (: $_prf (Member $label $category) (STV $s $c)))))
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
