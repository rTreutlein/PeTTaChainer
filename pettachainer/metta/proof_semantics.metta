;; Fold finalization is shared by forward base-rate accumulation and backward
;; aggregate proofs.  Keep it below both consumers rather than making either
;; chainer own the other one's semantics.
(: IdentityFinish Type)
(: identity IdentityFinish)
(: DistAverageFinish Type)
(: dist-average DistAverageFinish)
(: BaseRateFinish Type)
(: base-rate BaseRateFinish)
(: WeightedBaseRateFinish Type)
(: weighted-base-rate WeightedBaseRateFinish)
(: WeightedBaseRateWithPriorFinish Type)
(: weighted-base-rate-with-prior WeightedBaseRateWithPriorFinish)
(: MemberInheritanceFinish Type)
(: member-inheritance (-[det]-> $kb MemberInheritanceFinish))
(: WeightedBaseRateInUniverseFinish Type)
(: weighted-base-rate-in-universe
   (-[det]-> $kb WeightedBaseRateInUniverseFinish))
(: WeightedBaseRateWithPriorInUniverseFinish Type)
(: weighted-base-rate-with-prior-in-universe
   (-[det]-> $kb WeightedBaseRateWithPriorInUniverseFinish))
(: UniformPriorFinish Type)
(: uniform-prior UniformPriorFinish)
(: UniformPriorKnownFinish Type)
(: uniform-prior-known UniformPriorKnownFinish)

(: aggregate-finish (-[det]-> IdentityFinish $acc $acc))
(: aggregate-finish
   (-[det]-> DistAverageFinish DistributionSumCount Distribution))
(: aggregate-finish (-[det]-> BaseRateFinish BaseRateEvidenceState TV))
(: aggregate-finish
   (-[det]-> WeightedBaseRateFinish BaseRateEvidenceState TV))
(: aggregate-finish
   (-[det]-> WeightedBaseRateWithPriorFinish BaseRateEvidenceWithPriorState TV))
(: aggregate-finish
   (-[det]-> MemberInheritanceFinish BaseRateEvidenceState TV))
(: aggregate-finish
   (-[det]-> WeightedBaseRateInUniverseFinish BaseRateEvidenceState TV))
(: aggregate-finish
   (-[det]-> WeightedBaseRateWithPriorInUniverseFinish BaseRateEvidenceWithPriorState TV))
(: aggregate-finish
   (-[det]-> UniformPriorFinish (List $subject) TV))
(: aggregate-finish
   (-[det]-> UniformPriorKnownFinish (List $subject) TV))
(= (aggregate-finish identity $acc) $acc)
(= (aggregate-finish dist-average $acc)
   (the Distribution
      (reduce (reduce (DistAverageFromSumCount $acc)))))
(= (aggregate-finish base-rate $acc) (BaseRateTv $acc))
(= (aggregate-finish weighted-base-rate $acc) (WeightedBaseRateTv $acc))
(= (aggregate-finish weighted-base-rate-with-prior $acc) (WeightedBaseRateWithPriorTv $acc))
(= (aggregate-finish (member-inheritance $kbid) $acc)
   (member-inheritance-tv $kbid $acc))
(= (aggregate-finish (weighted-base-rate-in-universe $kbid) $acc)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedBaseRateTv $acc)
         (WeightedUniverseBaseRateTv
            (the Number $universe-size) $acc))))
(= (aggregate-finish (weighted-base-rate-with-prior-in-universe $kbid) (BaseRateEvidenceWithPrior $prior $ev))
   (let $universe-size (kb-universe-size $kbid)
      (BaseRateWithPriorFormula
         (resolve-base-rate-prior $prior)
         (if (== $universe-size no-universe-size)
            (WeightedBaseRateTv $ev)
            (WeightedUniverseBaseRateTv
               (the Number $universe-size) $ev)))))
(= (aggregate-finish uniform-prior $acc) (UniformPriorTv $acc))
(= (aggregate-finish uniform-prior-known $acc) (UniformPriorKnownTv $acc))
