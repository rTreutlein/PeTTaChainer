!(import! &self ../../pettachainer/metta/petta_chainer)

;; One full-weight observation carries one unit
;; of evidence: confidence is 1 / (1 + 800), never min(1, 1).
!(test
   (finish-aggregate fallbackCalibrationKb
      (weighted-base-rate-in-universe fallbackCalibrationKb)
      (BaseRateEvidence 1.0 1.0))
   (STV 1.0 0.0012484394506866417))

!(compileadd brKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd brKb (: qa (Q alice) (STV 0.9 0.8)))

!(compileadd brKb (: pb (P bob) (STV 0.7 0.8)))

; First query computes the base rates by folding over all instances and
; harvests them into the cache afterwards.
!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.7361612357845151 0.0003604274173100072)))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.6999999999999998 0.0009990009990009992))

; Second query reuses the fold snapshots the first query left current (their
; STVs are also in the cache): the inverted proof keeps its modus ponens TV
; and reads the same base rates, with no fold expansion.
!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.7361612357845151 0.0003604274173100072)))

; A stored fact counts in the base rates observing it when it is added.
!(compileadd brKb (: pc (P carol) (STV 0.3 0.8)))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.49999999999999994 0.0019960079840319364))

!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu)
       qa)
      (P alice)
      (STV 0.6327756330204969 0.00038353389027774137)))

!(test
   (cached-base-rate brKb (P $x))
   ((STV 0.49999999999999994 0.0019960079840319364)))

; User-provided base rates override the cache and feed inversion directly.
!(set-base-rate brKb (P $x) (STV 0.5 0.5))
!(set-base-rate brKb (Q $x) (STV 0.9 0.5))

!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.5 0.5691658648147646)))

; Monotonic additions also leave explicit user estimates unchanged.
!(compileadd brKb (: pd (P dave) (STV 0.6 0.8)))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.5 0.5))

; Adding a rule likewise preserves computed snapshots. The rule only enlarges
; the proof search space; it does not retract any evidence behind the cache.
!(store-produced-base-rate! ruleAddCacheKb (P $x) (STV 0.4 0.2) base-rate)

!(compileadd ruleAddCacheKb
   (: rToP
      (Implication (R $x) (P $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(test
   (cached-base-rate ruleAddCacheKb (P $x))
   ((STV 0.4 0.2)))

!(clear-base-rate brKb (P $x))
!(clear-base-rate brKb (Q $x))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   no-cache-entry)

; Compound patterns containing Inheritance are stored and cleared directly.
!(set-base-rate inheritancePatternKb
   (And (Inheritance $x madeOfPlastic) (Operation $x opLighter))
   (STV 0.25 0.9))

!(test
   (cached-base-rate inheritancePatternKb
      (And (Inheritance $x madeOfPlastic) (Operation $x opLighter)))
   ((STV 0.25 0.9)))

!(clear-base-rate inheritancePatternKb
   (And (Inheritance $x madeOfPlastic) (Operation $x opLighter)))

!(test
   (cached-base-rate inheritancePatternKb
      (And (Inheritance $x madeOfPlastic) (Operation $x opLighter)))
   ())

; --- Refinement of computed cache entries ---

!(compileadd brKb2 (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd brKb2 (: qa (Q alice) (STV 0.9 0.8)))

!(compileadd brKb2 (: pb (P bob) (STV 0.7 0.8)))

; A cached estimate the aggregate did not produce is replaced once a fold takes
; its members into the aggregate, however confident it was: partial work may be
; confidently wrong. The conclusion uses the aggregate's estimate, which is
; written back to the cache.
!(store-produced-base-rate! brKb2 (P $x) (STV 0.5 0.9) base-rate)

!(test
   (query 200 brKb2 (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.7361612357845151 0.0003604274173100072)))

!(test
   (let $cached (cached-base-rate brKb2 (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.6999999999999998 0.0009990009990009992))

; A base rate set or cleared elsewhere leaves unrelated derived answers alone:
; only the folds over the changed pattern recompute.
!(compileadd unrelatedRateKb (: a (A x) (STV 1.0 0.9)))
!(compileadd unrelatedRateKb
   (: ab (Implication (A $v) (B $v)) (CTV (STV 0.9 0.9) (STV 0.1 0.9))))

!(test
   (query 20 unrelatedRateKb (: $prf (B x) $tv))
   (: (by ab a) (B x) (STV 0.9 0.8999993598872059)))

!(set-base-rate unrelatedRateOtherKb (Z $y) (STV 0.5 0.5))

!(test
   (query 20 unrelatedRateKb (: $prf (B x) $tv))
   (: (by ab a) (B x) (STV 0.9 0.8999993598872059)))

!(clear-base-rate unrelatedRateOtherKb (Z $y))

!(test
   (query 20 unrelatedRateKb (: $prf (B x) $tv))
   (: (by ab a) (B x) (STV 0.9 0.8999993598872059)))

; A base rate follows its members incrementally and may lag. A second proof of
; P(bob) changes Q(bob), but no query needs Q(bob), so the Q base rate keeps its
; old contribution and the inversion reads the lagging rate. Once a query
; recomputes Q(bob), the next one replaces its contribution: the rate and the
; inversion then equal, up to rounding, those of a KB that had both proofs from
; the start (P(alice) 0.4840541797751332, Q rate 0.6221923233199902).
!(compileadd revisedRateKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd revisedRateKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd revisedRateKb (: pb (P bob) (STV 0.7 0.8)))

!(test
   (query 200 revisedRateKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.7361612357845151 0.0003604274173100072)))

!(compileadd revisedRateKb (: pb2 (P bob) (STV 0.1 0.8)))

!(test
   (query 200 revisedRateKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.4206635633054373 0.000882872802661841)))

!(test
   (cached-base-rate revisedRateKb (Q $x))
   ((STV 0.7382770346341803 0.0020863193128742123)))

!(test
   (query 200 revisedRateKb (: $prf (Q bob) $tv))
   (: (by r (merge/revision pb2 pb)) (Q bob) (STV 0.38 0.9176432113844136)))

!(test
   (query 200 revisedRateKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.4840518450016611 0.0002891856455941174)))

!(test
   (cached-base-rate revisedRateKb (Q $x))
   ((STV 0.6221923233199901 0.0021424540496628843)))

; An inheritance base rate weights each member by the subject mass, which falls
; as the universe gains subjects. New subjects elsewhere rescale the rate kept
; from before them, so it equals that of a KB that had them from the start.
!(compileadd grownUniverseKb
   (: bf (Implication (Inheritance $x Bird) (Inheritance $x Flyer)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd grownUniverseKb (: tweetyBird (Inheritance tweety Bird) (STV 1.0 0.9)))
!(compileadd grownUniverseKb (: pinguFlyer (Inheritance pingu Flyer) (STV 0.3 0.9)))

!(test
   (let $_answers (collapse (query 200 grownUniverseKb (: $prf (Inheritance pingu Bird) $tv)))
      (cached-base-rate grownUniverseKb (Inheritance $x Bird)))
   ((STV 0.998669031501917 0.0005631826475775279)))

!(compileadd grownUniverseKb (: samCat (Inheritance sam Cat) (STV 1.0 0.9)))
!(compileadd grownUniverseKb (: rexDog (Inheritance rex Dog) (STV 1.0 0.9)))

!(test
   (let $_answers (collapse (query 200 grownUniverseKb (: $prf (Inheritance pingu Bird) $tv)))
      (cached-base-rate grownUniverseKb (Inheritance $x Bird)))
   ((STV 0.998669031501917 0.0005631826475775279)))

; A member derived through its own base rate (the inverted sensor concludes
; Leak q with the Leak rate as its prior) changes whenever the rate moves. The
; rate does not count that version, so such a change does not mark the member
; to be taken again: otherwise every past belief read through the rate would be
; needed and recomputed each time the rate moved.
!(compileadd rateEchoKb (: sensor (Implication (Leak $u) (Alarm $u)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd rateEchoKb (: l1 (Leak u1) (STV 1.0 1.0)))
!(compileadd rateEchoKb (: l2 (Leak u2) (STV 0.0 1.0)))
!(compileadd rateEchoKb (: aq (Alarm q) (STV 1.0 1.0)))
!(collapse (query 200 rateEchoKb (: $p (Leak q) $tv)))
!(compileadd rateEchoKb (: l3 (Leak u3) (STV 0.0 1.0)))
!(collapse (query 200 rateEchoKb (: $p (Leak q) $tv)))
!(test (collapse (match &sk_rate_dirty ($_hash $_fold (sk-key (Leak q) $_kbctx)) true)) ())
