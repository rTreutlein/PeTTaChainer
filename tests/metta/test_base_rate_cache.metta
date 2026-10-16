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
   (: ((inverted r with cpu (prior (STV 0.6599999999999998 0.0009990009990009992))) qa) (P alice) (STV 0.8756842458979404 0.016392040302468155)))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.6999999999999998 0.0009990009990009992))

; Second query reuses the fold snapshots the first query left current (their
; STVs are also in the cache): the inverted proof keeps its modus ponens TV
; and reads the same base rates, with no fold expansion.
!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu (prior (STV 0.6599999999999998 0.0009990009990009992))) qa) (P alice) (STV 0.8756842458979404 0.016392040302468155)))

; A stored fact counts in the base rates observing it when it is added.
!(compileadd brKb (: pc (P carol) (STV 0.3 0.8)))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.49999999999999994 0.0019960079840319364))

!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu (prior (STV 0.49999999999999994 0.0019960079840319364)))
       qa)
      (P alice)
      (STV 0.8181729844617551 0.013415651820819992)))

!(test
   (cached-base-rate brKb (P $x))
   ((STV 0.49999999999999994 0.0019960079840319364)))

; User-provided base rates override the cache and feed inversion directly.
; The rule states both branches, so the inversion reads only the rate of P.
!(set-base-rate brKb (P $x) (STV 0.5 0.5))
!(set-base-rate brKb (Q $x) (STV 0.9 0.5))

!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu (prior (STV 0.5 0.5))) qa) (P alice) (STV 0.8181729844617551 0.7411849338953941)))

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
   (: ((inverted r with cpu (prior (STV 0.6599999999999998 0.0009990009990009992))) qa) (P alice) (STV 0.8756842458979404 0.016392040302468155)))

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
; old contribution and the rule s, stated with an STV, reads the lagging rate
; to derive its negative branch. Once a query recomputes Q(bob), the next one
; replaces its contribution: the rate and S(alice) then equal, up to rounding,
; those of a KB that had both proofs from the start.
!(compileadd revisedRateKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd revisedRateKb (: s (Implication (Q $x) (S $x)) (STV 0.5 0.9)))
!(compileadd revisedRateKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd revisedRateKb (: sc (S carol) (STV 0.4 0.8)))
!(compileadd revisedRateKb (: pb (P bob) (STV 0.7 0.8)))

!(test
   (query 200 revisedRateKb (: $prf (S alice) $tv))
   (: (by s qa) (S alice) (STV 0.4617916601776897 0.25559483954767565)))

!(compileadd revisedRateKb (: pb2 (P bob) (STV 0.1 0.8)))

!(test
   (query 200 revisedRateKb (: $prf (S alice) $tv))
   (: (by s qa) (S alice) (STV 0.4617916601776897 0.25559483954767565)))

!(test
   (cached-base-rate revisedRateKb (Q $x))
   ((STV 0.7382770346341803 0.0020863193128742123)))

!(test
   (query 200 revisedRateKb (: $prf (Q bob) $tv))
   (: (by r (merge/revision pb2 pb)) (Q bob) (STV 0.38 0.9176432113844136)))

!(test
   (query 200 revisedRateKb (: $prf (S alice) $tv))
   (: (by s qa) (S alice) (STV 0.4735315065911971 0.1679794416874766)))

!(test
   (cached-base-rate revisedRateKb (Q $x))
   ((STV 0.6221923233199901 0.0021424540496628843)))

!(compileadd startRateKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd startRateKb (: s (Implication (Q $x) (S $x)) (STV 0.5 0.9)))
!(compileadd startRateKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd startRateKb (: sc (S carol) (STV 0.4 0.8)))
!(compileadd startRateKb (: pb (P bob) (STV 0.7 0.8)))
!(compileadd startRateKb (: pb2 (P bob) (STV 0.1 0.8)))
!(test (query 200 startRateKb (: $prf (S alice) $tv))
   (: (by s qa) (S alice) (STV 0.4735315065911971 0.1679794416874766)))
!(test (cached-base-rate startRateKb (Q $x))
   ((STV 0.6221923233199902 0.0021424540496628843)))

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
!(test (collapse (match &sk_rate_dirty ($_hash $_mhash $_fold (sk-key (Leak q) $_kbctx)) true)) ())

; A member whose open merged value stayed the same outside the rate's
; dependencies, such as a labelled past period gaining its first derived view
; under its fact, gives the rate nothing new to take, so it is not marked to
; be taken: otherwise the next query reaching the rate needs every such member
; and computes its history rows. A changed view still marks it.
!(compileadd rateSameKb (: dr (Implication (Blocked k $t) (Delayed d $t)) (CTV (STV 0.85 1.0) (STV 0.05 1.0))))
!(compileadd rateSameKb (: lr (Implication (Delayed d $t) (Late s $t)) (CTV (STV 0.9 1.0) (STV 0.05 1.0))))
!(compileadd rateSameKb (: b1 (Blocked k h1) (STV 1.0 1.0)))
!(compileadd rateSameKb (: d1 (Delayed d h1) (STV 1.0 1.0)))
!(compileadd rateSameKb (: d2 (Delayed d h2) (STV 0.0 1.0)))
!(compileadd rateSameKb (: o1 (Late s t1) (STV 1.0 1.0)))
!(collapse (query 200 rateSameKb (: $p (Delayed d t1) $tv)))
!(test
   (let* (($fold (sk-fold (rateSameKb (Delayed d $_x) extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv)))
          ($member (sk-key (Delayed d h1) (rateSameKb MAIN Nil)))
          ($_same (sk-fold-changed 0 0 $member (sk-value-same 0 0) (sk-work (empty_heap) (empty_heap)) $fold))
          ($after-same (collapse (match &sk_rate_dirty ($_h $_mh $_f $member) taken)))
          ($_view (sk-fold-changed 0 0 $member (sk-view-change 0) (sk-work (empty_heap) (empty_heap)) $fold)))
      ($after-same (collapse (match &sk_rate_dirty ($_h2 $_mh2 $_f2 $member) taken))))
   (() (taken)))
