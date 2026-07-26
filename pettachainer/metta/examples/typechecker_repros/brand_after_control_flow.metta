(: RuntimeAddition (Newtype Expression))

(: convert-addition (-> Expression RuntimeAddition))
(= (convert-addition $stmt)
   (let*
      (($head (car-atom $stmt))
       ($tail (cdr-atom $stmt)))
      (brand RuntimeAddition
         (if (== $tail ())
            $head
            (rules $stmt)))))

!(test
   (convert-addition (fact))
   fact)

!(test
   (convert-addition (premise conclusion))
   (rules (premise conclusion)))
