;; Classify compiled fold descriptors without reading or changing state.

(datatype BaseRateAggregateKey (base-rate-aggregate-key-value KB Statement $mode))
(datatype NoBaseRateAggregateKey no-base-rate-aggregate-key)

(: base-rate-finish? (-[det]-> $finish Bool))
(= (base-rate-finish? $finish) (== $finish base-rate))

(: base-rate-aggregate-key (-[det]-> $arguments (| BaseRateAggregateKey NoBaseRateAggregateKey)))
(= (base-rate-aggregate-key $args)
   (case $args (
      (($kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
         (if (base-rate-finish? $finish)
            (base-rate-aggregate-key-value (brand KB $kbid) (brand Statement $pattern) $finish)
            no-base-rate-aggregate-key))
      ($_other no-base-rate-aggregate-key))))

(: sk-instance-fold? (-[det]-> Atom Bool))
(= (sk-instance-fold? ($_kb $_pattern $_extractor $_init $_function $finish $_mode))
   (== $finish implication-instance-ctv))

(: sk-instance-fold-key? (-[det]-> SkeletonKey Bool))
(= (sk-instance-fold-key? $key)
   (case $key (((sk-fold $args) (sk-instance-fold? $args)) ($_other false))))

(: sk-rate-fold? (-[det]-> SkeletonKey Bool))
(= (sk-rate-fold? $key)
   (if (sk-instance-fold-key? $key) true
      (case $key (
         ((sk-fold ($_kb $_pattern $_extractor $_init $_function $finish $_mode)) (base-rate-finish? $finish))
         ($_other false)))))

(: sk-existential-fold? (-[det]-> Atom Bool))
(= (sk-existential-fold? $fold)
   (let* (($args (case $fold (
                    ((sk-fold $scalar) $scalar)
                    ((sk-group $grouped) $grouped)
                    ((CPU $_kind $spec $_result) $spec)
                    ($_other ()))))
          ($function (case $args (
                        (($_kb $_body $_extract $_initial $f $_finish $_mode) $f)
                        (($_kb2 $_body2 $_group $_extract2 $_initial2 $g $_finish2 $_mode2) $g)
                        ($_other-args none)))))
      (if (== $function OrFormula) true (== $function ExistentialFloor))))

(: aggregate-fold-function? (-[det]-> $function Bool))
(= (aggregate-fold-function? $function)
   (stored-list-member? $function (FoldAllCompiled GroupedFoldAllCompiled CompoundRate)))
