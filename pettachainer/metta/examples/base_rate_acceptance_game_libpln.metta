!(import! &self ../../../repos/PLN/lib_pln.metta)

; libPLN prior baseline for the acceptance game.
; Run from pettachainer/metta with:
;   petta examples/base_rate_acceptance_game_libpln.metta
;
; This mirrors the PeTTaChainer file's downstream question:
;   should the system accept this contract?
; The difference is that libPLN receives fixed Good(contract) priors and keeps
; them fixed. It then derives AcceptContract through libPLN's own Modus Ponens
; rule via PLN.Query.

(= (FixedGoodTV) (stv 0.5 0.01))
(= (UniformGoodTV) (stv (/ 1.0 6.0) 0.01))
(= (AcceptRuleTV) (stv 1.0 1.0))

(= (fixed-kb)
   ((Sentence ((ReliableGood contractReliable) (FixedGoodTV)) (fixedReliableGood))
    (Sentence ((FastGood contractFast) (FixedGoodTV)) (fixedFastGood))
    (Sentence ((CheapGood contractCheap) (FixedGoodTV)) (fixedCheapGood))
    (Sentence ((LocalGood contractLocal) (FixedGoodTV)) (fixedLocalGood))
    (Sentence ((HighVolumeGood contractHighVolume) (FixedGoodTV)) (fixedHighVolumeGood))
    (Sentence ((FragileGood contractFragile) (FixedGoodTV)) (fixedFragileGood))

    (Sentence ((Implication (ReliableGood contractReliable) (AcceptContract contractReliable)) (AcceptRuleTV))
              (fixedReliableAcceptRule))
    (Sentence ((Implication (FastGood contractFast) (AcceptContract contractFast)) (AcceptRuleTV))
              (fixedFastAcceptRule))
    (Sentence ((Implication (CheapGood contractCheap) (AcceptContract contractCheap)) (AcceptRuleTV))
              (fixedCheapAcceptRule))
    (Sentence ((Implication (LocalGood contractLocal) (AcceptContract contractLocal)) (AcceptRuleTV))
              (fixedLocalAcceptRule))
    (Sentence ((Implication (HighVolumeGood contractHighVolume) (AcceptContract contractHighVolume)) (AcceptRuleTV))
              (fixedHighVolumeAcceptRule))
    (Sentence ((Implication (FragileGood contractFragile) (AcceptContract contractFragile)) (AcceptRuleTV))
              (fixedFragileAcceptRule))))

(= (uniform-kb)
   ((Sentence ((ReliableGood contractReliable) (UniformGoodTV)) (uniformReliableGood))
    (Sentence ((FastGood contractFast) (UniformGoodTV)) (uniformFastGood))
    (Sentence ((CheapGood contractCheap) (UniformGoodTV)) (uniformCheapGood))
    (Sentence ((LocalGood contractLocal) (UniformGoodTV)) (uniformLocalGood))
    (Sentence ((HighVolumeGood contractHighVolume) (UniformGoodTV)) (uniformHighVolumeGood))
    (Sentence ((FragileGood contractFragile) (UniformGoodTV)) (uniformFragileGood))

    (Sentence ((Implication (ReliableGood contractReliable) (AcceptContract contractReliable)) (AcceptRuleTV))
              (uniformReliableAcceptRule))
    (Sentence ((Implication (FastGood contractFast) (AcceptContract contractFast)) (AcceptRuleTV))
              (uniformFastAcceptRule))
    (Sentence ((Implication (CheapGood contractCheap) (AcceptContract contractCheap)) (AcceptRuleTV))
              (uniformCheapAcceptRule))
    (Sentence ((Implication (LocalGood contractLocal) (AcceptContract contractLocal)) (AcceptRuleTV))
              (uniformLocalAcceptRule))
    (Sentence ((Implication (HighVolumeGood contractHighVolume) (AcceptContract contractHighVolume)) (AcceptRuleTV))
              (uniformHighVolumeAcceptRule))
    (Sentence ((Implication (FragileGood contractFragile) (AcceptContract contractFragile)) (AcceptRuleTV))
              (uniformFragileAcceptRule))))

(= (accept-tv $query-result)
   (case $query-result
      (((cons (stv $s $c) $_stamp) (stv $s $c))
       ($_ (stv 0.0 0.0)))))

(= (FixedAcceptQuery $contract)
   (PLN.Query (fixed-kb) (AcceptContract $contract) 80 80 200))

(= (UniformAcceptQuery $contract)
   (PLN.Query (uniform-kb) (AcceptContract $contract) 80 80 200))

(= (FixedAcceptTV $contract)
   (accept-tv (FixedAcceptQuery $contract)))

(= (UniformAcceptTV $contract)
   (accept-tv (UniformAcceptQuery $contract)))

(= (break-even-threshold contractReliable) (/ (+ 25.0 20.0) (+ 70.0 25.0)))
(= (break-even-threshold contractFast) (/ (+ 20.0 15.0) (+ 95.0 20.0)))
(= (break-even-threshold contractCheap) (/ (+ 15.0 12.0) (+ 60.0 15.0)))
(= (break-even-threshold contractLocal) (/ (+ 12.0 10.0) (+ 65.0 12.0)))
(= (break-even-threshold contractHighVolume) (/ (+ 35.0 18.0) (+ 50.0 35.0)))
(= (break-even-threshold contractFragile) (/ (+ 35.0 20.0) (+ 140.0 35.0)))

(= (Accepted? $contract $tv)
   (let (stv $s $_c) $tv
      (>= $s (break-even-threshold $contract))))

!(FixedAcceptQuery contractReliable)
!(UniformAcceptQuery contractReliable)

!(test (FixedAcceptTV contractReliable) (stv 0.51 0.01))
!(test (FixedAcceptTV contractHighVolume) (stv 0.51 0.01))
!(test (UniformAcceptTV contractReliable) (stv 0.18333333333333332 0.01))
!(test (UniformAcceptTV contractHighVolume) (stv 0.18333333333333332 0.01))
!(test (Accepted? contractReliable (FixedAcceptTV contractReliable)) true)
!(test (Accepted? contractHighVolume (FixedAcceptTV contractHighVolume)) false)
!(test (Accepted? contractFragile (FixedAcceptTV contractFragile)) true)
!(test (Accepted? contractReliable (UniformAcceptTV contractReliable)) false)
