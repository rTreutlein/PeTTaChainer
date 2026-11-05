!(import! &self ../../pettachainer/metta/petta_chainer)

;; A part known with certainty at its connective's absorbing value settles the
;; compound whatever the other parts are, including parts with no proof: a
;; certain-true disjunct makes an Or true, a certain-false conjunct makes an
;; And false.

!(test (OrFormula (STV 1 1) (STV 0.5 0.0)) (STV 1.0 1.0))
!(test (AndFormula (STV 0.3 0.4) (STV 0 1)) (STV 0.0 1.0))
!(test (SettlesFormula (STV 1 1) (STV 1.0 1.0)) (STV 1.0 1.0))
!(test (collapse (SettlesFormula (STV 1 0.9) (STV 1.0 1.0))) ())

;; Or: (B t) has no proof, (A t) is certain.
!(compileadd orKb (: r (Implication (Or (A $t) (B $t)) (C $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd orKb (: a (A t) (STV 1 1)))

!(test (query 50 orKb (: $p (Or (A t) (B t)) $tv))
   (: (settled a) (Or (A t) (B t)) (STV 1.0 0.9999)))
;; (A t) true leaves (B t) undetermined, so nothing gives (B t) a value and
;; the complete rule application has none: the settled step is the answer.
!(test (query 50 orKb (: $p (C t) $tv))
   (: (by r (settled a)) (C t) (STV 1.0 0.9999)))

;; And: (D t) has no proof, (E t) is certain, so (Not (E t)) is certainly false
;; and the rule concludes by its negative branch.
!(compileadd andKb (: r (Implication (And (D $t) (Not (E $t))) (F $t)) (CTV (STV 1 1) (STV 0.2 1))))
!(compileadd andKb (: e (E t) (STV 1 1)))

!(test (query 50 andKb (: $p (And (E t) (D t)) $tv)) ())
!(test (query 50 andKb (: $p (F t) $tv))
   (: (by r (settled (negated e))) (F t) (STV 0.2 0.9999)))

;; Only certainty settles: an uncertain disjunct, or a certain-false one in an
;; Or, leaves the compound waiting for its other parts.
!(compileadd unsettledKb (: r (Implication (Or (A $t) (B $t)) (C $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unsettledKb (: a (A t) (STV 1 0.9)))
!(compileadd unsettledKb (: a2 (A u) (STV 0 1)))

!(test (query 50 unsettledKb (: $p (C t) $tv)) ())
!(test (query 50 unsettledKb (: $p (C u) $tv)) ())

;; A reader can bind variables absent from the settling part. An open reader
;; still cannot enumerate the other part's unconstrained domain.
!(compileadd openKb (: r (Implication (Or (A $t) (B $t $u)) (C $t $u)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd openKb (: a (A t) (STV 1 1)))

!(test (query 50 openKb (: $p (C t v) $tv))
   (: (by r (settled a)) (C t v) (STV 1.0 0.9999)))
!(test (query 50 openKb (: $p (C t $u) $tv)) ())
!(test (query 50 openKb (: $p (Or (A t) (B t $u)) $tv)) ())

;; The same binding rule applies to And's certain-false settling value.
!(compileadd falseKb (: r (Implication (Not (And (A $t) (B $t $u))) (C $t $u)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd falseKb (: a (A t) (STV 0 1)))
!(test (let (: $_p $_q (STV $s $_c)) (query 50 falseKb (: $p (C t v) $tv)) $s) 1.0)
!(test (query 50 falseKb (: $p (C t $u) $tv)) ())

;; A computation's bundle carries its TV already, without SettlesFormula.
!(compileadd computeKb (: r (Implication (Or (Compute + (1 2) -> $v) (Missing $u)) (Result $v $u)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $_p $_q (STV $s $_c)) (query 50 computeKb (: $p (Result 3 bound) $tv)) $s) 1.0)
!(test (query 50 computeKb (: $p (Result 3 $u) $tv)) ())

;; The untimed SupplyNet cycle: the plant runs when fuelled and not degraded,
;; fuelled by stock or by the mine's fuel arriving, and the mine runs on the
;; plant's power. With stock the Or is settled by the stock alone, so the
;; loop disjunct, which only the cycle could prove, no longer blocks it.
!(compileadd stockedKb (: fuelled (Implication (Or (StockedFuel $t) (FuelArrived $t)) (Fuelled power $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd stockedKb (: runs-power (Implication (And (Fuelled power $t) (Not (Degraded power $t))) (Producing power $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd stockedKb (: runs-mine (Implication (And (Producing power $t) (Not (Degraded mine $t))) (Producing mine $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd stockedKb (: fuel-arrives (Implication (And (Producing mine $t) (Not (Blocked fuel $t))) (FuelArrived $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd stockedKb (: dp (Degraded power t) (STV 0 1)))
!(compileadd stockedKb (: dm (Degraded mine t) (STV 0 1)))
!(compileadd stockedKb (: bf (Blocked fuel t) (STV 0 1)))
!(compileadd stockedKb (: s (StockedFuel t) (STV 1 1)))

!(test (query 200 stockedKb (: $p (Producing power t) $tv))
   (: (by runs-power (conjunction (by fuelled (settled s)) (negated dp))) (Producing power t) (STV 1.0 0.9999)))
!(test (query 200 stockedKb (: $p (Producing mine t) $tv))
   (: (by runs-mine (conjunction (by runs-power (conjunction (by fuelled (settled s)) (negated dp))) (negated dm))) (Producing mine t) (STV 1.0 0.9999)))

;; Without stock nothing but the loop could fuel the plant. The plant is in
;; fact not running (the least fixed point), but the chainer is open-world:
;; with no proof outside the cycle it does not conclude false, and the loop must
;; not prove itself running either. So there is no answer.
!(compileadd unstockedKb (: fuelled (Implication (Or (StockedFuel $t) (FuelArrived $t)) (Fuelled power $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unstockedKb (: runs-power (Implication (And (Fuelled power $t) (Not (Degraded power $t))) (Producing power $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unstockedKb (: runs-mine (Implication (And (Producing power $t) (Not (Degraded mine $t))) (Producing mine $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unstockedKb (: fuel-arrives (Implication (And (Producing mine $t) (Not (Blocked fuel $t))) (FuelArrived $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unstockedKb (: dp (Degraded power t) (STV 0 1)))
!(compileadd unstockedKb (: dm (Degraded mine t) (STV 0 1)))
!(compileadd unstockedKb (: bf (Blocked fuel t) (STV 0 1)))
!(compileadd unstockedKb (: s (StockedFuel t) (STV 0 1)))

!(test (query 200 unstockedKb (: $p (Producing power t) $tv)) ())
!(test (query 200 unstockedKb (: $p (Producing mine t) $tv)) ())

;; Without stock and with the mine degraded, the mine's And is settled false
;; by its degradation alone, which breaks the loop: no fuel arrives, and the
;; plant is not running.
!(compileadd mineDownKb (: fuelled (Implication (Or (StockedFuel $t) (FuelArrived $t)) (Fuelled power $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd mineDownKb (: runs-power (Implication (And (Fuelled power $t) (Not (Degraded power $t))) (Producing power $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd mineDownKb (: runs-mine (Implication (And (Producing power $t) (Not (Degraded mine $t))) (Producing mine $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd mineDownKb (: fuel-arrives (Implication (And (Producing mine $t) (Not (Blocked fuel $t))) (FuelArrived $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd mineDownKb (: dp (Degraded power t) (STV 0 1)))
!(compileadd mineDownKb (: dm (Degraded mine t) (STV 1 1)))
!(compileadd mineDownKb (: bf (Blocked fuel t) (STV 0 1)))
!(compileadd mineDownKb (: s (StockedFuel t) (STV 0 1)))

!(test (query 200 mineDownKb (: $p (Producing power t) $tv))
   (: (by runs-power (conjunction (by fuelled (conjunction s (by fuel-arrives (conjunction (by runs-mine (settled (negated dm))) (negated bf))))) (negated dp))) (Producing power t) (STV 0.0 0.9999)))
