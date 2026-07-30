!(import! &self (library lib_builtin_types))

(: Proof (Newtype Expression))

(: accepts-proof (-[det]-> Proof Bool))
(= (accepts-proof $_proof) true)

;; The branch data is accepted contextually by the outer brand, but the let
;; binding does not retain Proof for its consumer.
(: construct-and-use-proof (-[det]-> Number Bool))
(= (construct-and-use-proof $index)
   (let $proof
      (brand Proof
         (if (== $index 0)
            (data ctx proof)
            (data ctx proof $index)))
      (accepts-proof $proof)))
