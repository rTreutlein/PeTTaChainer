(: Left Type)
(: left Left)

(: Right Type)
(: right Right)

; This declares the symbol Either as a value of the union. It does not define
; Either as a reusable name for the union.
(: Either (| Left Right))

(: left-as-either (-[det]-> Left Either))
(= (left-as-either $value) $value)

!(test (left-as-either left) left)
