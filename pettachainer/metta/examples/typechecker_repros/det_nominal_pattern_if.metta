(: Context (Newtype Expression))

(: has-context-shape (-[det]-> Context Bool))
(= (has-context-shape $value)
   (if (= $value ($name $index $vars))
      true
      false))

!(test
   (has-context-shape
      (brand Context (main 0 ())))
   true)
