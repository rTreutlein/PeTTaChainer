!(import! &self ../../pettachainer/metta/petta_chainer)

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
;; from NoOutput(press), automatic implication inversion reconstructs the OR,
;; and the completion of the rule onto the local defect conditions on the
;; known upstream alternative.

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

;; The inverse is Bayes' rule over the antecedent's base rate. The rule is
;; deterministic both ways, so the inverted OR is the observation's 0.82
;; whatever the prior.
!(set-base-rate machineInverseKb
   (Or (Defective $machine) (UpstreamFailure $machine))
   (STV 0.82 0.99))

!(test
   (query 300 machineInverseKb
      (: $proof
         (Or
            (Defective press)
            (UpstreamFailure press))
         $tv))
   (: ((inverted failureStopsOutput with cpu (prior (STV 0.8199991919212325 0.99)))
          observedPressStopped)
      (Or (Defective press) (UpstreamFailure press))
      (STV 0.82 0.8999999996128824)))

;; Bayes' rule over the press's defect rate (0.418, from one stored fact, so
;; the answer carries little confidence) with P(NoOutput | defect) = 1 and
;; P(NoOutput | no defect) = P(UpstreamFailure) = 0.4, the observation read as
;; a likelihood ratio: Jeffrey's rule, 0.82 P(defect | NoOutput) = 0.527.
!(test
   (query 300 machineInverseKb
      (: $proof (Defective press) $tv))
   (: ((antecedent-completion failureStopsOutput 0 with cpu (prior (STV 0.5 0.0)))
          (conjunction
             (by propagateUpstreamFailure (conjunction feederFeedsPress feederDefect))
             observedPressStopped))
      (Defective press)
      (STV 0.5857142857142857 0.006822439134954615)))
