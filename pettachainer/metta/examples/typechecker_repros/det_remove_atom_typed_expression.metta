(: Entry Type)
(: entry (-> Number Entry))

(: remove-entry (-[det]-> Entry Bool))
(= (remove-entry $value)
   (remove-atom &self $value))

!(add-atom &self (entry 1))
!(test (remove-entry (entry 1)) true)
