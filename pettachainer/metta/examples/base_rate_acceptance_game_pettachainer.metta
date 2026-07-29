!(import! &self ../petta_chainer)

; End-to-end base-rate acceptance game.
; Run from pettachainer/metta with:
;   petta examples/base_rate_acceptance_game_pettachainer.metta
;
; There is no LikelierThan comparison here. Each query asks whether the system
; accepts a concrete contract:
;   (AcceptContract contractReliable)
; The proof has to pass through the raw Good/Bad observations, the inverted
; signal rule, and then the AcceptContract rule.

!(compileadd baseRateAcceptanceKb
   (: signalRule_Reliable
      (Implication
         (Premises (ReliableGood $supplier))
         (Conclusions (ReliableProbePaysOff $supplier)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd baseRateAcceptanceKb (: signal_Reliable (ReliableProbePaysOff contractReliable) (STV 0.9 0.8)))
!(compileadd baseRateAcceptanceKb
   (: acceptRule_Reliable
      (Implication
         (Premises (ReliableGood contractReliable))
         (Conclusions (AcceptContract contractReliable)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd baseRateAcceptanceKb
   (: signalRule_Fast
      (Implication
         (Premises (FastGood $supplier))
         (Conclusions (FastProbePaysOff $supplier)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd baseRateAcceptanceKb (: signal_Fast (FastProbePaysOff contractFast) (STV 0.9 0.8)))
!(compileadd baseRateAcceptanceKb
   (: acceptRule_Fast
      (Implication
         (Premises (FastGood contractFast))
         (Conclusions (AcceptContract contractFast)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd baseRateAcceptanceKb
   (: signalRule_Cheap
      (Implication
         (Premises (CheapGood $supplier))
         (Conclusions (CheapProbePaysOff $supplier)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd baseRateAcceptanceKb (: signal_Cheap (CheapProbePaysOff contractCheap) (STV 0.9 0.8)))
!(compileadd baseRateAcceptanceKb
   (: acceptRule_Cheap
      (Implication
         (Premises (CheapGood contractCheap))
         (Conclusions (AcceptContract contractCheap)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd baseRateAcceptanceKb
   (: signalRule_Local
      (Implication
         (Premises (LocalGood $supplier))
         (Conclusions (LocalProbePaysOff $supplier)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd baseRateAcceptanceKb (: signal_Local (LocalProbePaysOff contractLocal) (STV 0.9 0.8)))
!(compileadd baseRateAcceptanceKb
   (: acceptRule_Local
      (Implication
         (Premises (LocalGood contractLocal))
         (Conclusions (AcceptContract contractLocal)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd baseRateAcceptanceKb
   (: signalRule_HighVolume
      (Implication
         (Premises (HighVolumeGood $supplier))
         (Conclusions (HighVolumeProbePaysOff $supplier)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd baseRateAcceptanceKb (: signal_HighVolume (HighVolumeProbePaysOff contractHighVolume) (STV 0.9 0.8)))
!(compileadd baseRateAcceptanceKb
   (: acceptRule_HighVolume
      (Implication
         (Premises (HighVolumeGood contractHighVolume))
         (Conclusions (AcceptContract contractHighVolume)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd baseRateAcceptanceKb
   (: signalRule_Fragile
      (Implication
         (Premises (FragileGood $supplier))
         (Conclusions (FragileProbePaysOff $supplier)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd baseRateAcceptanceKb (: signal_Fragile (FragileProbePaysOff contractFragile) (STV 0.9 0.8)))
!(compileadd baseRateAcceptanceKb
   (: acceptRule_Fragile
      (Implication
         (Premises (FragileGood contractFragile))
         (Conclusions (AcceptContract contractFragile)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

; Ten deterministic samples for each supplier type.
!(compileadd baseRateAcceptanceKb (: reliableObs1 (ReliableGood supplierReliable1) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs2 (ReliableGood supplierReliable2) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs3 (ReliableGood supplierReliable3) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs4 (ReliableGood supplierReliable4) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs5 (ReliableGood supplierReliable5) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs6 (ReliableGood supplierReliable6) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs7 (ReliableGood supplierReliable7) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs8 (ReliableGood supplierReliable8) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs9 (ReliableGood supplierReliable9) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: reliableObs10 (ReliableGood supplierReliable10) (STV 0.0 1.0)))

!(compileadd baseRateAcceptanceKb (: fastObs1 (FastGood supplierFast1) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs2 (FastGood supplierFast2) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs3 (FastGood supplierFast3) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs4 (FastGood supplierFast4) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs5 (FastGood supplierFast5) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs6 (FastGood supplierFast6) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs7 (FastGood supplierFast7) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs8 (FastGood supplierFast8) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs9 (FastGood supplierFast9) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fastObs10 (FastGood supplierFast10) (STV 0.0 1.0)))

!(compileadd baseRateAcceptanceKb (: cheapObs1 (CheapGood supplierCheap1) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs2 (CheapGood supplierCheap2) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs3 (CheapGood supplierCheap3) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs4 (CheapGood supplierCheap4) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs5 (CheapGood supplierCheap5) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs6 (CheapGood supplierCheap6) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs7 (CheapGood supplierCheap7) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs8 (CheapGood supplierCheap8) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs9 (CheapGood supplierCheap9) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: cheapObs10 (CheapGood supplierCheap10) (STV 0.0 1.0)))

!(compileadd baseRateAcceptanceKb (: localObs1 (LocalGood supplierLocal1) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs2 (LocalGood supplierLocal2) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs3 (LocalGood supplierLocal3) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs4 (LocalGood supplierLocal4) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs5 (LocalGood supplierLocal5) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs6 (LocalGood supplierLocal6) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs7 (LocalGood supplierLocal7) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs8 (LocalGood supplierLocal8) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs9 (LocalGood supplierLocal9) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: localObs10 (LocalGood supplierLocal10) (STV 0.0 1.0)))

!(compileadd baseRateAcceptanceKb (: highVolumeObs1 (HighVolumeGood supplierHighVolume1) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs2 (HighVolumeGood supplierHighVolume2) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs3 (HighVolumeGood supplierHighVolume3) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs4 (HighVolumeGood supplierHighVolume4) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs5 (HighVolumeGood supplierHighVolume5) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs6 (HighVolumeGood supplierHighVolume6) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs7 (HighVolumeGood supplierHighVolume7) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs8 (HighVolumeGood supplierHighVolume8) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs9 (HighVolumeGood supplierHighVolume9) (STV 1.0 1.0)))
!(compileadd baseRateAcceptanceKb (: highVolumeObs10 (HighVolumeGood supplierHighVolume10) (STV 1.0 1.0)))

!(compileadd baseRateAcceptanceKb (: fragileObs1 (FragileGood supplierFragile1) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs2 (FragileGood supplierFragile2) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs3 (FragileGood supplierFragile3) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs4 (FragileGood supplierFragile4) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs5 (FragileGood supplierFragile5) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs6 (FragileGood supplierFragile6) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs7 (FragileGood supplierFragile7) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs8 (FragileGood supplierFragile8) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs9 (FragileGood supplierFragile9) (STV 0.0 1.0)))
!(compileadd baseRateAcceptanceKb (: fragileObs10 (FragileGood supplierFragile10) (STV 0.0 1.0)))

(= (accept-tv $contract)
   (let (: $_prf (AcceptContract $contract) $tv)
      (query 800 baseRateAcceptanceKb (: $_prf (AcceptContract $contract) $tv))
      $tv))

(= (break-even-threshold contractReliable) (/ (+ 25.0 20.0) (+ 70.0 25.0)))
(= (break-even-threshold contractFast) (/ (+ 20.0 15.0) (+ 95.0 20.0)))
(= (break-even-threshold contractCheap) (/ (+ 15.0 12.0) (+ 60.0 15.0)))
(= (break-even-threshold contractLocal) (/ (+ 12.0 10.0) (+ 65.0 12.0)))
(= (break-even-threshold contractHighVolume) (/ (+ 35.0 18.0) (+ 50.0 35.0)))
(= (break-even-threshold contractFragile) (/ (+ 35.0 20.0) (+ 140.0 35.0)))

(= (accepted? $contract)
   (let (STV $s $_c) (accept-tv $contract)
      (>= $s (break-even-threshold $contract))))

!(test (accepted? contractReliable) true)
!(test (accepted? contractCheap) true)
!(test (accepted? contractHighVolume) true)
!(test (accepted? contractFast) true)
!(test (accepted? contractLocal) true)
!(test (accepted? contractFragile) false)
