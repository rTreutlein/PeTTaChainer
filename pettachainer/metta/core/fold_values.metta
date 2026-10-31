;; Existential channels are nested propositions. Keep the stronger TV intact;
;; confidence breaks exact strength ties by evidence amount, without revision.
(: ExistentialFloor (-[det]-> STVType STVType STVType))
(= (ExistentialFloor (STV $sa $ca) (STV $sb $cb))
   (if (if (> $sb $sa) true (if (< $sb $sa) false (> $cb $ca)))
      (STV $sb $cb) (STV $sa $ca)))

(: fa-instance-acc (-[det]-> $a InstanceEvidenceState))
(= (fa-instance-acc $a)(the InstanceEvidenceState $a))

(: base-rate-entry-tv (-[det]-> BaseRateEntry TV))
(= (base-rate-entry-tv (base-rate $_kbid $_stored $tv $_source $_mode)) $tv)

(: base-rate-entry-user? (-[det]-> BaseRateEntry Bool))
(= (base-rate-entry-user? (base-rate $_kbid $_stored $_tv $source $_mode)) (== $source user))
