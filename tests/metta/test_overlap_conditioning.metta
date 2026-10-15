!(import! &self ../../pettachainer/metta/petta_chainer)

;; Two views of one key that share an uncertain statement, neither containing
;; the other's evidence, are mixed over that statement: the key's merge with
;; it known true and known false, weighted by its value
;; (docs/metta/overlap_conditioning.md).

(= (overlap-tv (: $_proof $_type $tv)) $tv)
(= (overlap-step (: $proof $_type $_tv)) (car-atom $proof))

;; SupplyNet stage 3 in small. The storm of t1 (0.6) persists with (0.7, 0.3);
;; fuel arrives with 0.2 in a storm and 0.9 without; the plant runs exactly
;; when fuelled and not degraded; degradation persists with (0.75, 0.05). The
;; plant is sound in t0, off in t1 and running in t2.
!(compileadd stage3Kb (: storm-t1 (Storm t1) (STV 0.6 1)))
!(compileadd stage3Kb (: persist-storm (Implication (And (NextPeriod $p $t) (Storm $p)) (Storm $t)) (CTV (STV 0.7 1) (STV 0.3 1))))
!(compileadd stage3Kb (: fuel (Implication (Storm $t) (Fuelled plant $t)) (CTV (STV 0.2 1) (STV 0.9 1))))
!(compileadd stage3Kb (: runs-plant (Implication (And (Fuelled plant $t) (Not (Degraded plant $t))) (Producing plant $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd stage3Kb (: persist-degraded (Implication (And (NextPeriod $p $t) (Degraded plant $p)) (Degraded plant $t)) (CTV (STV 0.75 1) (STV 0.05 1))))
!(set-base-rate stage3Kb (Degraded plant $t) (STV 0.25 0.9))
!(set-base-rate stage3Kb (Storm $t) (STV 0.4 0.9))
!(compileadd stage3Kb (: sound-t0 (Degraded plant t0) (STV 0 1)))
!(compileadd stage3Kb (: next-t1 (NextPeriod t0 t1) (STV 1 1)))
!(compileadd stage3Kb (: next-t2 (NextPeriod t1 t2) (STV 1 1)))
!(compileadd stage3Kb (: next-t3 (NextPeriod t2 t3) (STV 1 1)))
!(compileadd stage3Kb (: off-t1 (Producing plant t1) (STV 0 1)))
!(compileadd stage3Kb (: on-t2 (Producing plant t2) (STV 1 1)))

;; Degraded plant t1 has two views reading the storm: the t1 report merged with
;; the persistence from t0, odds 0.05/0.95 / (1 - P(fuel t1)), and the
;; smoothing completion from t2, where the running plant means not degraded,
;; a likelihood ratio of 0.25/0.95. Given the storm: odds 0.05/0.95 / 0.8 *
;; 0.25/0.95, 0.0170; given none: / 0.1, 0.1217; mixed by the storm's 0.6:
;; 0.0589. The more confident view alone was 0.0919. The exact posterior,
;; where both reports also update the storm (to 0.864), is 0.0312: a stored
;; soft fact applies no rules, so the weight is its stored value.
!(test (map-flat overlap-step (collapse (query 2000 stage3Kb (: $p (Degraded plant t1) $tv)))) (conditioned))
!(test (map-flat overlap-tv (collapse (query 2000 stage3Kb (: $p (Degraded plant t1) $tv))))
   ((STV 0.05887282355682909 0.9998816871581414)))

;; Degraded plant t2: the persistence from t1 and the t2 report share the
;; storm too; the running plant settles it in either branch (exact: 0), and t3
;; is the persistence's start rate 0.05 (exact: 0.05).
!(test (map-flat overlap-tv (collapse (query 2000 stage3Kb (: $p (Degraded plant t2) $tv))))
   ((STV 6.784293260625639e-07 0.9999596483266605)))
!(test (map-flat overlap-tv (collapse (query 2000 stage3Kb (: $p (Degraded plant t3) $tv))))
   ((STV 0.050000474900528245 0.9999000106180916)))

;; Conditioning a key is paid for from the evaluation allowance. A query that
;; cannot pay keeps the more confident view and leaves the key waiting; a
;; later query that needs it and can pay conditions it. The same knowledge
;; base as above.
!(compileadd budgetKb (: storm-t1 (Storm t1) (STV 0.6 1)))
!(compileadd budgetKb (: persist-storm (Implication (And (NextPeriod $p $t) (Storm $p)) (Storm $t)) (CTV (STV 0.7 1) (STV 0.3 1))))
!(compileadd budgetKb (: fuel (Implication (Storm $t) (Fuelled plant $t)) (CTV (STV 0.2 1) (STV 0.9 1))))
!(compileadd budgetKb (: runs-plant (Implication (And (Fuelled plant $t) (Not (Degraded plant $t))) (Producing plant $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd budgetKb (: persist-degraded (Implication (And (NextPeriod $p $t) (Degraded plant $p)) (Degraded plant $t)) (CTV (STV 0.75 1) (STV 0.05 1))))
!(set-base-rate budgetKb (Degraded plant $t) (STV 0.25 0.9))
!(set-base-rate budgetKb (Storm $t) (STV 0.4 0.9))
!(compileadd budgetKb (: sound-t0 (Degraded plant t0) (STV 0 1)))
!(compileadd budgetKb (: next-t1 (NextPeriod t0 t1) (STV 1 1)))
!(compileadd budgetKb (: next-t2 (NextPeriod t1 t2) (STV 1 1)))
!(compileadd budgetKb (: next-t3 (NextPeriod t2 t3) (STV 1 1)))
!(compileadd budgetKb (: off-t1 (Producing plant t1) (STV 0 1)))
!(compileadd budgetKb (: on-t2 (Producing plant t2) (STV 1 1)))
!(test (map-flat overlap-step (collapse (query 10 budgetKb (: $p (Degraded plant t1) $tv)))) (factored-revision))
!(test (== (collapse (match &sk_given_pending ($_hash -1 $cost) $cost)) ()) false)
!(test (map-flat overlap-tv (collapse (query 20 budgetKb (: $p (Degraded plant t1) $tv))))
   ((STV 0.05887282355682909 0.9998816871581414)))

;; Views that share only a fact no rule concludes, here the link both rules
;; read, and hold evidence of their own are independent given it. These
;; distinct sibling rule conditions combine by odds over the neutral prior. A fact some rule concludes may be an observation both update on,
;; and keeps them dependent (test_antecedent_completion: wet-d read by an
;; inversion and a completion).
!(compileadd premiseKb (: link (Link a b) (STV 1 1)))
!(compileadd premiseKb (: sa (A a) (STV 0.8 0.9)))
!(compileadd premiseKb (: sb (B b) (STV 0.3 0.9)))
!(compileadd premiseKb (: ra (Implication (And (Link $x $y) (A $x)) (X $y)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd premiseKb (: rb (Implication (And (Link $x $y) (B $y)) (X $y)) (CTV (STV 0.7 1) (STV 0.1 1))))
!(test (query 100 premiseKb (: $p (X b) $tv))
   (: (combination odds (prior (STV 0.5 0.0)) ((by ra (conjunction link sa)) (by rb (conjunction link sb)))) (X b) (STV 0.5518672199170126 1.35971765734789e-05)))
