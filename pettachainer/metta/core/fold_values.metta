;; Existential channels are nested propositions. Keep the stronger TV intact;
;; confidence breaks exact strength ties by evidence amount, without revision.
(: ExistentialFloor (-[det]-> STVType STVType STVType))
(= (ExistentialFloor (STV $sa $ca) (STV $sb $cb))
   (if (if (> $sb $sa) true (if (< $sb $sa) false (> $cb $ca)))
      (STV $sb $cb) (STV $sa $ca)))
