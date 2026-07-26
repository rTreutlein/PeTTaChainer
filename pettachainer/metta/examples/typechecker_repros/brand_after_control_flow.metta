(: Box (Newtype Expression))

(: choose-box (-> Bool Box))
(= (choose-box $flag)
   (brand Box
      (if $flag
         (left)
         (right))))

!(test (choose-box true) (left))
