!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self ./posterior_assertions)

;; A rule reads a compound antecedent through its key, whose producer rows
;; read the parts (#142). These are the reader's reading of the parts, so a
;; part's change must reach the reader as when the rule read the part itself,
;; each reader excludes only what it concludes, and the key answers as the
;; parts give it.

;; Late facts of a part, in MAIN: the producer row of (Or (A k) (B k)) is
;; needed at its reader's depth, so the facts reach Q four rules up. Needed
;; one level further, it stayed stale and Q kept 0.6306, the value before a2
;; and a3, however often it was asked.
!(compileadd lateKb (: rq2 (Implication (Q $t) (Q2 $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd lateKb (: rq (Implication (Y $t) (Q $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd lateKb (: ry (Implication (X $t) (Y $t)) (CTV (STV 0.8 1) (STV 0.2 1))))
!(compileadd lateKb (: rx (Implication (Or (A $t) (B $t)) (X $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd lateKb (: b (B k) (STV 0.8 0.9)))
!(compileadd lateKb (: a1 (A k) (STV 0.2 0.5)))
!(test (let (: $_p $_t $tv) (query 2000 lateKb (: $p (Q2 k) $tv)) $tv) (STV 0.6044480000000001 0.9930340836384924))
!(compileadd lateKb (: a2 (A k) (STV 0.95 0.9)))
!(compileadd lateKb (: a3 (A k) (STV 0.05 0.9)))
!(test (let (: $_p $_t $tv) (query 2000 lateKb (: $p (Q k) $tv)) $tv) (STV 0.6523873684210526 0.9965947262536551))
!(test (let (: $_p $_t $tv) (query 2000 lateKb (: $p (Q k) $tv)) $tv) (STV 0.6523873684210526 0.9965947262536551))

;; A late certain stock in MAIN reaches the plant through the Or key the
;; same way.
!(set-complete-predicate lateStockKb Producing)
!(set-complete-predicate lateStockKb Fuelled)
!(set-complete-predicate lateStockKb FuelArrived)
!(set-complete-predicate lateStockKb StockedFuel)
!(compileadd lateStockKb (: fuelled (Implication (Or (StockedFuel $t) (FuelArrived $t)) (Fuelled $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd lateStockKb (: runs (Implication (And (Fuelled $t) (Not (Degraded $t)) (InService $t)) (Producing $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd lateStockKb (: arrives (Implication (And (NextPeriod $p $t) (Producing $p)) (FuelArrived $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd lateStockKb (: (no_inverse out) (Implication (And (Value $v) (Producing $t)) (Outcome $t $v)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd lateStockKb (: v (Value 1) (STV 1 1)))
!(compileadd lateStockKb (: n (NextPeriod t0 t1) (STV 1 1)))
!(compileadd lateStockKb (: p0 (Producing t0) (STV 0 1)))
!(compileadd lateStockKb (: d (Degraded t1) (STV 0.05 1)))
!(compileadd lateStockKb (: ins (InService t1) (STV 1 1)))
!(test (let (: $_p $_t $tv) (query 350 lateStockKb (: $p (Outcome t1 $v) $tv)) $tv) (STV 0.0 0.9999))
!(compileadd lateStockKb (: st (StockedFuel t1) (STV 1 1)))
!(test (let (: $_p $_t $tv) (query 450 lateStockKb (: $p (Outcome t1 $v) $tv)) $tv) (STV 0.95 0.9999))
!(test (let (: $_p $_t $tv) (query 450 lateStockKb (: $p (Producing t1) $tv)) $tv) (STV 0.95 0.9999))

;; Assuming worlds in turn, each reaching the plant through the Or key's
;; producer row: a world assuming the stock never reads the stock of a world
;; without it, nor the other way round.
!(set-complete-predicate worldsKb Producing)
!(set-complete-predicate worldsKb Fuelled)
!(set-complete-predicate worldsKb FuelArrived)
!(set-complete-predicate worldsKb StockedFuel)
!(compileadd worldsKb (: fuelled (Implication (Or (StockedFuel $t) (FuelArrived $t)) (Fuelled $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd worldsKb (: runs (Implication (And (Fuelled $t) (Not (Degraded $t)) (InService $t)) (Producing $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd worldsKb (: arrives (Implication (And (NextPeriod $p $t) (Producing $p)) (FuelArrived $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd worldsKb (: (no_inverse out) (Implication (And (Value $v) (Producing $t)) (Outcome $t $v)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd worldsKb (: v (Value 1) (STV 1 1)))
!(compileadd worldsKb (: n (NextPeriod t0 t1) (STV 1 1)))
!(compileadd worldsKb (: p0 (Producing t0) (STV 0 1)))
!(compileadd worldsKb (: d (Degraded t1) (STV 0.05 1)))
!(test (let (: $_p $_t $tv) (query 450 worldsKb (: $p (Assuming (And (StockedFuel t1) (InService t1) (Repairing t1)) (Outcome t1 $v)) $tv)) $tv)
   (STV 0.95 0.9999))
!(test (let (: $_p $_t $tv) (query 450 worldsKb (: $p (Assuming (InService t1) (Outcome t1 $v)) $tv)) $tv)
   (STV 0.0 0.9999))
!(test (query 450 worldsKb (: $p (Assuming (FuelArrived t1) (Outcome t1 $v)) $tv)) ())
!(test (let (: $_p $_t $tv) (query 450 worldsKb (: $p (Assuming (And (StockedFuel t1) (InService t1) (Repairing t1)) (Outcome t1 $v)) $tv)) $tv)
   (STV 0.95 0.9999))
!(test (let (: $_p $_t $tv) (query 450 worldsKb (: $p (Assuming (InService t1) (Outcome t1 $v)) $tv)) $tv)
   (STV 0.0 0.9999))

;; Two rules read the Or. Each excludes its own conclusion, X or Y, at its own
;; read; the producer row shared by both excludes neither. Excluding both
;; there dropped A's view through y, which depends on Y, for X and the Or root
;; as well: X 0.564, the Or 0.58, so a rule added took evidence away.
!(compileadd readersKb (: (no_inverse r1) (Implication (Or (A $t) (B $t)) (X $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd readersKb (: (no_inverse rya) (Implication (Y $t) (A $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd readersKb (: y (Y k) (STV 0.95 0.9)))
!(compileadd readersKb (: a (A k) (STV 0.4 0.5)))
!(compileadd readersKb (: b (B k) (STV 0.3 0.9)))
!(compileadd readersKb (: (no_inverse r2) (Implication (Or (A $t) (B $t)) (Y $t)) (CTV (STV 0.8 1) (STV 0.2 1))))
!(test (let (: $_p $_t $tv) (query 2000 readersKb (: $p (X k) $tv)) $tv) (STV 0.7937704918032787 0.8331346175941209))
!(test (let (: $_p $_t $tv) (query 2000 readersKb (: $p (Or (A k) (B k)) $tv)) $tv) (STV 0.8672131147540985 0.6920372940176395))

;; Without a fact of A, its only view is through y: excluding both readers'
;; conclusions left X and the Or no answer.
!(compileadd readers2Kb (: (no_inverse r1) (Implication (Or (A $t) (B $t)) (X $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd readers2Kb (: (no_inverse rya) (Implication (Y $t) (A $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd readers2Kb (: y (Y k) (STV 0.95 0.9)))
!(compileadd readers2Kb (: b (B k) (STV 0.3 0.9)))
!(compileadd readers2Kb (: (no_inverse r2) (Implication (Or (A $t) (B $t)) (Y $t)) (CTV (STV 0.8 1) (STV 0.2 1))))
!(test (let (: $_p $_t $tv) (query 2000 readers2Kb (: $p (X k) $tv)) $tv) (STV 0.8243999999999999 0.992573949927829))
!(test (let (: $_p $_t $tv) (query 2000 readers2Kb (: $p (Or (A k) (B k)) $tv)) $tv) (STV 0.9055 0.9806063902763618))

;; V reads the Or as the Or answers, X's observation included through rx's
;; inversion, in whatever order the queries come: the Or's graph posterior
;; .7823994913 (its root answer below) through rv, .2 + .5 (.7823994913).
;; Reading the parts, V had 0.42, the Or without that observation.
!(compileadd orderKb (: rx (Implication (Or (A $t) (B $t)) (X $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd orderKb (: rw (Implication (X $t) (W $t)) (CTV (STV 0.8 1) (STV 0.3 1))))
!(compileadd orderKb (: rv (Implication (Or (A $t) (B $t)) (V $t)) (CTV (STV 0.7 1) (STV 0.2 1))))
!(compileadd orderKb (: x (X k) (STV 0.9 0.9)))
!(compileadd orderKb (: b (B k) (STV 0.3 0.9)))
!(compileadd orderKb (: a (A k) (STV 0.2 0.3)))
!(compileadd orderKb (: x2 (X j) (STV 0.3 0.9)))
!(compileadd orderKb (: a2 (A j) (STV 0.6 0.9)))
!(compileadd orderKb (: b2 (B j) (STV 0.2 0.9)))
!(test (let (: $_p $_t $tv) (query 2000 orderKb (: $p (V k) $tv)) $tv) (STV 0.5911997456448431 0.7999663161978653))
!(test
   (posterior-tv-near? 0.7823994912896864 0.41289069125729083 (let (: $_p $_t $tv) (query 2000 orderKb (: $p (Or (A k) (B k)) $tv)) $tv))
   true)
!(compileadd order2Kb (: rx (Implication (Or (A $t) (B $t)) (X $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd order2Kb (: rw (Implication (X $t) (W $t)) (CTV (STV 0.8 1) (STV 0.3 1))))
!(compileadd order2Kb (: rv (Implication (Or (A $t) (B $t)) (V $t)) (CTV (STV 0.7 1) (STV 0.2 1))))
!(compileadd order2Kb (: x (X k) (STV 0.9 0.9)))
!(compileadd order2Kb (: b (B k) (STV 0.3 0.9)))
!(compileadd order2Kb (: a (A k) (STV 0.2 0.3)))
!(compileadd order2Kb (: x2 (X j) (STV 0.3 0.9)))
!(compileadd order2Kb (: a2 (A j) (STV 0.6 0.9)))
!(compileadd order2Kb (: b2 (B j) (STV 0.2 0.9)))
!(test
   (posterior-tv-near? 0.7407897728058923 0.8286414873667223 (let (: $_p $_t $tv) (query 2000 order2Kb (: $p (W k) $tv)) $tv))
   true)
!(test
   (posterior-tv-near? 0.7823994912896864 0.41289069125729083 (let (: $_p $_t $tv) (query 2000 order2Kb (: $p (Or (A k) (B k)) $tv)) $tv))
   true)
!(test (let (: $_p $_t $tv) (query 2000 order2Kb (: $p (V k) $tv)) $tv) (STV 0.5911997456448431 0.7999663161978653))

;; A completion's consequence is no view derived from the compound it
;; completes. Here r1 and r2 read the Or, y observes Y, and rya concludes A.
;; X has no observation, only its prediction from the Or inverted from y; r1's
;; completion of A read that prediction as X's observation, shared y's
;; evidence with r2's completion, and the merge took it instead: A 0.401.
;; Exact enumeration of the DAG: A 0.567, X 0.7577, the Or 0.8222; A here is
;; r2's completion revised with a (master's 0.560).
!(compileadd consequenceKb (: r1 (Implication (Or (A $t) (B $t)) (X $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd consequenceKb (: rya (Implication (Y $t) (A $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd consequenceKb (: y (Y k) (STV 0.95 0.9)))
!(compileadd consequenceKb (: a (A k) (STV 0.4 0.5)))
!(compileadd consequenceKb (: b (B k) (STV 0.3 0.9)))
!(compileadd consequenceKb (: r2 (Implication (Or (A $t) (B $t)) (Y $t)) (CTV (STV 0.8 1) (STV 0.2 1))))
!(test (let (: $_p $_t $tv) (query 2000 consequenceKb (: $p (X k) $tv)) $tv) (STV 0.7577269944980254 0.8634780467586617))
!(test (let (: $_p $_t $tv) (query 2000 consequenceKb (: $p (A k) $tv)) $tv) (STV 0.560039770239416 0.49342278189196137))
!(test (let (: $_p $_t $tv) (query 2000 consequenceKb (: $p (Or (A k) (B k)) $tv)) $tv) (STV 0.8221587431225318 0.7632249553719406))
