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
   ((STV 0.05887282839676099 0.9999)))

;; Degraded plant t2: the persistence from t1 and the t2 report share the
;; storm too; the running plant settles it in either branch (exact: 0), and t3
;; is the persistence's start rate 0.05 (exact: 0.05).
!(test (map-flat overlap-tv (collapse (query 2000 stage3Kb (: $p (Degraded plant t2) $tv))))
   ((STV 0.0 0.9999)))
;; Its confidence propagates the t2 update's own confidence above; shared
;; estimates did not supply an independent confidence increment.
!(test (map-flat overlap-tv (collapse (query 2000 stage3Kb (: $p (Degraded plant t3) $tv))))
   ((STV 0.05 0.9999)))

;; Conditioning a key is paid for from the evaluation allowance. A query that
;; cannot pay keeps its one-step waiting value. A root that spends its whole
;; slice sleeps; a later query with a larger slice can condition it. The same knowledge
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
;; Ten steps supply floor((2*10)/8)=2 units to the root claim. It is
;; dormant after exhausting those units, rather than queued to repeat them.
!(test (collapse (match &sk_root_exhausted
   ($_hash (sk-key (Degraded plant t1) (budgetKb MAIN Nil)) (sk-root-limit $cap $_epoch)) $cap)) (2))
!(test (map-flat overlap-tv (collapse (query 200 budgetKb (: $p (Degraded plant t1) $tv))))
   ((STV 0.05887282839676099 0.9999)))

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
;; #49/#77: no live shared-class estimate resolves this overlap. Keep the
;; population strength and halve confidence for the minimum R=1 allowance.
!(test (query 100 premiseKb (: $p (X b) $tv))
   (: (combination odds (prior (STV 0.5 0.0)) ((by ra (conjunction link sa)) (by rb (conjunction link sb)))) (X b) (STV 0.5518672199170126 0.0012671764103957621)))
;; A row conditioned on the statement its premises share keeps its rule's
;; class: it combines with a sibling rule's view by odds, as the unconditioned
;; row would, not by revision.
!(compileadd condSiblingKb (: link (Link a b) (STV 1 1)))
!(compileadd condSiblingKb (: s (S a) (STV 0.6 0.9)))
!(compileadd condSiblingKb (: sb (B b) (STV 0.3 0.9)))
!(compileadd condSiblingKb (: sx (Implication (S $x) (X $x)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd condSiblingKb (: sy (Implication (S $x) (Y $x)) (CTV (STV 0.8 1) (STV 0.1 1))))
!(compileadd condSiblingKb (: ra (Implication (And (Link $x $y) (X $x) (Y $x)) (W $y)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd condSiblingKb (: rb (Implication (And (Link $x $y) (B $y)) (W $y)) (CTV (STV 0.7 1) (STV 0.1 1))))
!(test (query 2000 condSiblingKb (: $p (W b) $tv))
   (: (combination odds (prior (STV 0.5 0.0))
         ((by rb (conjunction link sb))
          (conditioned s (by ra (conjunction link (by sx (given true)) (by sy (given true))))
                         (by ra (conjunction link (by sx (given false)) (by sy (given false)))))))
      (W b) (STV 0.28649693844666446 0.0016625662924501777)))
