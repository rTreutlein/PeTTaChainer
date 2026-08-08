!(import! &self ../petta_chainer)

;; -------------------------------------------------------------------------
;; Forward direction: distinct failure events combine as a probabilistic OR.
;; The press has a 0.7 local-defect estimate. Its feeder has a 0.4 defect
;; estimate, propagated into the press as an upstream failure event.

!(compileadd machineForwardKb
   (: feederFeedsPress (Feeds feeder press) (STV 1.0 1.0)))
!(compileadd machineForwardKb
   (: feederDefect (Defective feeder) (STV 0.4 0.9)))
!(compileadd machineForwardKb
   (: pressDefect (Defective press) (STV 0.7 0.9)))

!(compileadd machineForwardKb
   (: propagateUpstreamFailure
      (Implication
         (And
            (Feeds $upstream $machine)
            (Defective $upstream))
         (UpstreamFailure $machine))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd machineForwardKb
   (: failureStopsOutput
      (Implication
         (Or
            (Defective $machine)
            (UpstreamFailure $machine))
         (NoOutput $machine))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; 0.7 OR 0.4 = 0.82, not an evidence-weighted merge of the two causes.
!(test
   (query 100 machineForwardKb
      (: $proof
         (Or
            (Defective press)
            (UpstreamFailure press))
         $tv))
   (: (conjunction
          pressDefect
          (by propagateUpstreamFailure
             (conjunction feederFeedsPress feederDefect)))
      (Or (Defective press) (UpstreamFailure press))
      (STV 0.8200000000000001 0.9318166197352297)))

!(test
   (query 150 machineForwardKb
      (: $proof (NoOutput press) $tv))
   (: (by failureStopsOutput
          (conjunction
             pressDefect
             (by propagateUpstreamFailure
                (conjunction feederFeedsPress feederDefect))))
      (NoOutput press)
      (STV 0.8200000000000001 0.9318166193205277)))

;; -------------------------------------------------------------------------
;; Reverse direction: the local press defect is deliberately absent. Starting
;; from NoOutput(press), automatic implication inversion reconstructs the OR;
;; the ordinary Or projection then subtracts the known upstream alternative.

!(compileadd machineInverseKb
   (: feederFeedsPress (Feeds feeder press) (STV 1.0 1.0)))
!(compileadd machineInverseKb
   (: feederDefect (Defective feeder) (STV 0.4 0.9)))
!(compileadd machineInverseKb
   (: observedPressStopped
      (NoOutput press) (STV 0.82 0.9)))

!(compileadd machineInverseKb
   (: propagateUpstreamFailure
      (Implication
         (And
            (Feeds $upstream $machine)
            (Defective $upstream))
         (UpstreamFailure $machine))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd machineInverseKb
   (: failureStopsOutput
      (Implication
         (Or
            (Defective $machine)
            (UpstreamFailure $machine))
         (NoOutput $machine))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; The inverse is Bayesian and therefore needs base rates. Equal 0.82 rates
;; express the modeled equivalence between "some modeled failure" and no output.
!(set-base-rate machineInverseKb
   (Or (Defective $machine) (UpstreamFailure $machine))
   (STV 0.82 0.99))
!(set-base-rate machineInverseKb
   (NoOutput $machine)
   (STV 0.82 0.99))

;; Expected strength: (0.82 - 0.4) / (1 - 0.4) = 0.7.
!(test
   (query 300 machineInverseKb
      (: $proof
         (Or
            (Defective press)
            (UpstreamFailure press))
         $tv))
   (: ((inverted failureStopsOutput with cpu cpu)
          observedPressStopped)
      (Or (Defective press) (UpstreamFailure press))
      (STV 0.82 0.8970590810311)))

!(test
   (query 300 machineInverseKb
      (: $proof (Defective press) $tv))
   (: ((proj 0
          ((inverted failureStopsOutput with cpu cpu)
             observedPressStopped))
         (by propagateUpstreamFailure
            (conjunction feederFeedsPress feederDefect)))
      (Defective press)
      (STV 0.7 0.7962833508893552)))
