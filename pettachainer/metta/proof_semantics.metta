;; Fold finalization is shared by forward base-rate accumulation and backward
;; aggregate proofs.  Keep it below both consumers rather than making either
;; chainer own the other one's semantics.
(= (aggregate-finish identity $acc) $acc)
(= (aggregate-finish dist-average $acc) (reduce (reduce (DistAverageFromSumCount $acc))))
(= (aggregate-finish base-rate $acc) (BaseRateTv $acc))
(= (aggregate-finish weighted-base-rate $acc) (WeightedBaseRateTv $acc))
(= (aggregate-finish weighted-base-rate-with-prior $acc) (WeightedBaseRateWithPriorTv $acc))
(= (aggregate-finish (member-inheritance $kbid) $acc)
   (member-inheritance-tv $kbid $acc))
(= (aggregate-finish (weighted-base-rate-in-universe $kbid) $acc)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedBaseRateTv $acc)
         (WeightedUniverseBaseRateTv $universe-size $acc))))
(= (aggregate-finish (weighted-base-rate-with-prior-in-universe $kbid) (BaseRateEvidenceWithPrior $prior $ev))
   (let $universe-size (kb-universe-size $kbid)
      (BaseRateWithPriorFormula
         (resolve-base-rate-prior $prior)
         (if (== $universe-size no-universe-size)
            (WeightedBaseRateTv $ev)
            (WeightedUniverseBaseRateTv $universe-size $ev)))))
(= (aggregate-finish uniform-prior $acc) (UniformPriorTv $acc))
(= (aggregate-finish uniform-prior-known $acc) (UniformPriorKnownTv $acc))
