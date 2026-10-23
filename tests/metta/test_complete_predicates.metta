!(import! &self ../../pettachainer/metta/petta_chainer)

;; A complete predicate's rules and facts are the only ways one of its
;; statements becomes true (docs/metta/complete_predicates.md). The loop:
;; (P t) holds by stock (S t) or by (M t), and (M t) holds when (P t) does and
;; (Deg t) does not.

;; No stock: nothing outside the loop makes either true, so both are false. P
;; reads M with P itself unfounded, and M reads P with M unfounded.
!(set-complete-predicate offKb P)
!(set-complete-predicate offKb M)
!(compileadd offKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd offKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd offKb (: s (S t) (STV 0 1)))
!(compileadd offKb (: d (Deg t) (STV 0 1)))

!(test (query 100 offKb (: $p (P t) $tv))
   (: (by rp (conjunction s (by rm (conjunction unfounded (negated d))))) (P t) (STV 0.0 0.9996001597861454)))
!(test (query 100 offKb (: $p (M t) $tv))
   (: (by rm (conjunction (by rp (conjunction s unfounded)) (negated d))) (M t) (STV 0.0 0.9996001597861454)))

;; Undeclared, the same KB is open-world: the loop's only proof is circular,
;; and there is no answer.
!(compileadd openKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd openKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd openKb (: s (S t) (STV 0 1)))
!(compileadd openKb (: d (Deg t) (STV 0 1)))

!(test (query 100 openKb (: $p (P t) $tv)) ())
!(test (query 100 openKb (: $p (M t) $tv)) ())

;; Stock: both true. The stock settles the Or; P's complete row reads (M t)
;; closed, the mine's production with P pinned false, and M reads P's
;; settled value.
!(set-complete-predicate onKb P)
!(set-complete-predicate onKb M)
!(compileadd onKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd onKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd onKb (: s (S t) (STV 1 1)))
!(compileadd onKb (: d (Deg t) (STV 0 1)))

!(test (query 100 onKb (: $p (P t) $tv))
   (: (by rp (conjunction s (by rm (conjunction unfounded (negated d))))) (P t) (STV 1.0 0.9998000399670116)))
!(test (query 100 onKb (: $p (M t) $tv))
   (: (by rm (conjunction (by rp (settled s)) (negated d))) (M t) (STV 1.0 0.9996001597861454)))

;; Uncertain stock: P has the stock's strength, OrFormula(0.9, 0), and M the
;; same through P.
!(set-complete-predicate partKb P)
!(set-complete-predicate partKb M)
!(compileadd partKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd partKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd partKb (: s (S t) (STV 0.9 0.9)))
!(compileadd partKb (: d (Deg t) (STV 0 1)))

!(test (query 100 partKb (: $p (P t) $tv))
   (: (by rp (conjunction s (by rm (conjunction unfounded (negated d))))) (P t) (STV 0.9 0.8999999992437459)))
!(test (query 100 partKb (: $p (M t) $tv))
   (: (by rm (conjunction (by rp (conjunction s unfounded)) (negated d))) (M t) (STV 0.9 0.8999999977853199)))

;; An uncertain degradation leaves P at the stock's strength and lowers M:
;; 0.9 times P(not degraded) = 0.9 * 0.7.
!(set-complete-predicate degKb P)
!(set-complete-predicate degKb M)
!(compileadd degKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd degKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd degKb (: s (S t) (STV 0.9 0.9)))
!(compileadd degKb (: d (Deg t) (STV 0.3 0.9)))

!(test (query 100 degKb (: $p (P t) $tv))
   (: (by rp (conjunction s (by rm (conjunction unfounded (negated d))))) (P t) (STV 0.9 0.8999999992437459)))
!(test (query 100 degKb (: $p (M t) $tv))
   (: (by rm (conjunction (by rp (conjunction s unfounded)) (negated d))) (M t) (STV 0.63 0.9073568643833784)))

;; An open predicate in the body stays open: with (S t) unknown, nothing is
;; concluded, false or otherwise.
!(set-complete-predicate unknownKb P)
!(set-complete-predicate unknownKb M)
!(compileadd unknownKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unknownKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unknownKb (: d (Deg t) (STV 0 1)))

!(test (query 100 unknownKb (: $p (P t) $tv)) ())
!(test (query 100 unknownKb (: $p (M t) $tv)) ())

;; A complete statement no rule concludes and no fact states is false.
!(set-complete-predicate emptyKb Q)
!(compileadd emptyKb (: r (Implication (R $x) (Other $x)) (STV 0.9 0.9)))

!(test (query 10 emptyKb (: $p (Q a) $tv)) (: unfounded (Q a) (STV 0.0 1.0)))

;; A budget too small to reach a proof concludes nothing: (G t) reads the
;; complete (K t), which holds through a chain of open statements down to the
;; fact (B t). Until the search has examined (K t)'s rule application to the
;; end, (K t) is not settled, and (G t) has no answer rather than a false one.
!(set-complete-predicate deepKb G)
!(set-complete-predicate deepKb K)
!(compileadd deepKb (: rg (Implication (K $t) (G $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: rk (Implication (A1 $t) (K $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: r1 (Implication (A2 $t) (A1 $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: r2 (Implication (A3 $t) (A2 $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: r3 (Implication (B $t) (A3 $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: b (B t) (STV 1 1)))

!(test (query 1 deepKb (: $p (G t) $tv)) ())
!(test (query 2 deepKb (: $p (G t) $tv)) ())
!(test (query 3 deepKb (: $p (G t) $tv))
   (: (by rg (by rk (by r1 (by r2 (by r3 b))))) (G t) (STV 1 0.9994003594095785)))

;; An Assuming query's context holds the world's facts and rules with its
;; assumptions, so its complete statements read closed as the main context's
;; do: a decision that does not assume the stock has none, and P runs on F
;; alone; assuming the stock runs it.
!(set-complete-predicate actKb S)
!(set-complete-predicate actKb P)
!(compileadd actKb (: rp (Implication (Or (S $t) (F $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd actKb (: f (F t) (STV 0.3 0.9)))

!(test (query 100 actKb (: $p (Assuming (Decide t) (P t)) $tv))
   (: (assuming (by rp (conjunction unfounded f))) (Assuming (Decide t) (P t)) (STV 0.3 0.8999999995871378)))
!(test (query 100 actKb (: $p (Assuming (S t) (P t)) $tv))
   (: (assuming (by rp (conjunction (ctx proof 1) f))) (Assuming (S t) (P t)) (STV 1.0 0.9998000399670116)))

;; A complete statement no rule concludes and no fact states is false to
;; every reader once its search settles, not only to a rule concluding a
;; complete predicate: its negation is true, and B, an open predicate, reads
;; it through Not.
!(set-complete-predicate repairKb R)
!(compileadd repairKb (: a1 (A t1) (STV 1 1)))
!(compileadd repairKb (: r9 (R t9) (STV 1 1)))
!(compileadd repairKb (: rb (Implication (And (A $t) (Not (R $t))) (B $t)) (CTV (STV 0.8 1) (STV 0.1 1))))

!(test (query 100 repairKb (: $p (Not (R t1)) $tv))
   (: (negated unfounded) (Not (R t1)) (STV 1.0 1.0)))
!(test (query 100 repairKb (: $p (B t1) $tv))
   (: (by rb (conjunction a1 (negated unfounded))) (B t1) (STV 0.8 0.999900009386623)))

;; A closed read's unfounded statement has no evidence (#128). Evidence read
;; off a proof term once named a fact by the bare leaf `unfounded`, so two
;; closed reads, here of the stock at t8 inside the plant's t8 completion and
;; of the stock at t9, shared one uncertain item. Its run read the two premises
;; as a clash with no statement to condition on, derived nothing, and the
;; decision context answered the population prior once its search reached the
;; t8 completion (SupplyNet stage 4, t9: power output 0.95 exact).
(= (stage4-kb $kb)
   (let* (($_p (set-complete-predicate $kb Producing))
          ($_f (set-complete-predicate $kb Fuelled))
          ($_a (set-complete-predicate $kb FuelArrived))
          ($_s (set-complete-predicate $kb StockedFuel))
          ($_v (set-positive-only-predicate $kb FuelVia))
          ($_i (set-positive-only-predicate $kb InService))
          ($_added (collapse (compileadd $kb (superpose (
         (: persist-east (Implication (And (NextPeriod $p $t) (Storm east $p)) (Storm east $t)) (CTV (STV 0.7 1) (STV 0.3 1)))
         (: block-rf (Implication (Storm east $p) (Blocked rf $p)) (CTV (STV 0.8 1) (STV 0.03 1)))
         (: block-ra (Implication (Storm east $p) (Blocked ra $p)) (CTV (STV 0.4 1) (STV 0.03 1)))
         (: persist-degraded-power-plant (Implication (And (NextPeriod $p $t) (Degraded power-plant $p) (Not (Repairing power-plant $p))) (Degraded power-plant $t)) (CTV (STV 0.75 1) (STV 0.05 1)))
         (: fuel-arrives (Implication (And (NextPeriod $p $t) (Producing mine $p) (FuelVia $r $p) (Not (Blocked $r $p))) (FuelArrived $t)) (CTV (STV 1 1) (STV 0 1)))
         (: fuelled (Implication (Or (StockedFuel $t) (FuelArrived $t)) (Fuelled power-plant $t)) (CTV (STV 1 1) (STV 0 1)))
         (: runs-power-plant (Implication (And (Fuelled power-plant $t) (Not (Degraded power-plant $t)) (InService power-plant $t)) (Producing power-plant $t)) (CTV (STV 1 1) (STV 0 1)))
         (: runs-mine (Implication (And (Producing power-plant $t) (Not (Degraded mine $t)) (InService mine $t)) (Producing mine $t)) (CTV (STV 1 1) (STV 0 1)))
         (: runs-plant-a (Implication (And (Producing power-plant $t) (InputArrived plant-a $t) (Not (Degraded plant-a $t)) (InService plant-a $t)) (Producing plant-a $t)) (CTV (STV 1 1) (STV 0 1)))
         (: runs-plant-b (Implication (And (Producing power-plant $t) (InputArrived plant-b $t) (Not (Degraded plant-b $t)) (InService plant-b $t)) (Producing plant-b $t)) (CTV (STV 1 1) (STV 0 1)))
         (: via-t7 (FuelVia ra t7) (STV 1 1))
         (: stocked-t7 (StockedFuel t7) (STV 1 1))
         (: repairing-power-plant-t7 (Repairing power-plant t7) (STV 0 1))
         (: in-service-power-plant-t7 (InService power-plant t7) (STV 1 1))
         (: next-t8 (NextPeriod t7 t8) (STV 1 1))
         (: blocked-rf-t8 (Blocked rf t8) (STV 0 1))
         (: degraded-mine-t8 (Degraded mine t8) (STV 0 1))
         (: producing-mine-t7 (Producing mine t7) (STV 1 1))
         (: producing-power-plant-t7 (Producing power-plant t7) (STV 1 1))
         (: via-t8 (FuelVia rf t8) (STV 1 1))
         (: repairing-power-plant-t8 (Repairing power-plant t8) (STV 0 1))
         (: in-service-mine-t8 (InService mine t8) (STV 1 1))
         (: in-service-power-plant-t8 (InService power-plant t8) (STV 1 1))
         (: next-t9 (NextPeriod t8 t9) (STV 1 1))
         (: producing-mine-t8 (Producing mine t8) (STV 1 1))))))))
      true))
(= (stage4-tv $kb $budget)
   (let (: $_prf (Assuming $_facts $_goal) $tv)
      (car-atom (collapse (query $budget $kb (: $prf (Assuming (And (FuelVia rf t9) (InService mine t9) (InService power-plant t9) (InService plant-a t9) (InService plant-b t9)) (Producing power-plant t9)) $tv))))
      $tv))
!(test (stage4-kb stage4Fresh) true)
!(test (stage4-kb stage4Warm) true)
!(test (stage4-tv stage4Fresh 200) (STV 0.95 0.9998999947967693))
!(test (let $_degraded (collapse (query 50 stage4Warm (: $prf (Degraded power-plant t8) $tv))) (stage4-tv stage4Warm 50))
   (STV 0.95 0.9998999947967693))
