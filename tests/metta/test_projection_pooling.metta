!(import! &self ../../pettachainer/metta/petta_chainer)

;; One joint observation, three properties: its projections count the
;; observation once, whether they are joined directly or after separate rules.
!(compileadd demo (: observation
    (And (Powered robot) (Connected robot) (Calibrated robot))
    (STV 0.9 0.99)))

;; A strict subset: Calibrated is unnecessary, and the source counts once.
!(test (query 100 demo (: $p (And (Connected robot) (Powered robot)) $tv))
    (: (conjunction (marginal-proj 1 observation) (marginal-proj 0 observation))
       (And (Connected robot) (Powered robot)) (STV 0.9 0.9889012208657048)))

;; The subset can supply the premises of a further inference.
!(compileadd demo (: ready-rule
    (Implication (And (Powered $x) (Connected $x)) (Ready $x)) (STV 1.0 0.9)))
!(test (query 100 demo (: $p (Ready robot) $tv))
    (: (by ready-rule (conjunction (marginal-proj 0 observation) (marginal-proj 1 observation)))
       (Ready robot) (STV 0.9 0.9888133108035946)))

;; Transform the projections along separate branches.
!(compileadd demo (: move-rule
    (Implication (Powered $x) (CanMove $x)) (STV 1.0 0.9)))
!(compileadd demo (: report-rule
    (Implication (Connected $x) (CanReport $x)) (STV 1.0 0.9)))
!(test (query 100 demo (: $p (CanMove robot) $tv))
    (: (by move-rule (marginal-proj 0 observation))
       (CanMove robot) (STV 0.9 0.9888133108035946)))
!(test (query 100 demo (: $p (CanReport robot) $tv))
    (: (by report-rule (marginal-proj 1 observation))
       (CanReport robot) (STV 0.9 0.9888133108035946)))

;; Join the separate branches. Both outputs share the observation, so the
;; chainer conditions on it instead of multiplying the two 0.9 strengths.
!(test (query 300 demo (: $p (And (CanMove robot) (CanReport robot)) $tv))
    (: (conditioned observation
          (conjunction (by move-rule (marginal-proj 0 (given true)))
                       (by report-rule (marginal-proj 1 (given true))))
          (conjunction (by move-rule (marginal-proj 0 (given false)))
                       (by report-rule (marginal-proj 1 (given false)))))
       (And (CanMove robot) (CanReport robot)) (STV 0.9 0.9899980381745921)))
