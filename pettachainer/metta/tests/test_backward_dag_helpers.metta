!(import! &self petta_chainer)

!(test (tv-confidence (STV 0.7 0.35)) 0.35)

!(test (tv-confidence maybeUnknown) 1.0)

!(test (term-confidence (CPU MpFormula ((STV 1.0 0.6) (STV 0.8 0.9)) $out)) 0.6)

!(test (term-confidence (CPU AndFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out)) 0.4)

!(test (term-confidence (CPU OrFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out)) 0.7)

!(test (term-confidence (CPU LikelierThanFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out)) 0.4)

!(test
   (premises-expected-confidence
      (cons (CPU MpFormula ((STV 1.0 0.2) (STV 1.0 1.0)) $tv1)
         (cons (CPU MpFormula ((STV 1.0 0.55) $tv1) $tv2) ())))
   0.2)

!(test
   (goal-key-eq? (: (kb MAIN ()) p1 (LoopGoal $x) (STV 1.0 1.0))
      (: (kb MAIN ()) p2 (LoopGoal $y) (STV 1.0 0.4)))
   true)

!(test
   (goal-key-eq? (: (kb MAIN ()) p1 (LoopGoal) (STV 1.0 1.0))
      (: (kb ALT ()) p2 (LoopGoal) (STV 1.0 1.0)))
   false)

!(test
   (let*
      (($_gclear (remove-all-atoms &goal_store))
        ($_gidreset (change-state! bwd_gid 0))
        ($g1 (ensure-goal (: (kb MAIN ()) p1 (LoopGoal $x) (STV 1.0 1.0))))
        ($g2 (ensure-goal (: (kb MAIN ()) p2 (LoopGoal $y) (STV 1.0 0.3)))))
      (cons $g1 (cons $g2 (collapse (match &goal_store (goal-node $gid $_goal) $gid)))))
   (0 0 0))

!(test
   (let*
      (($_gclear (remove-all-atoms &goal_store))
        ($_gidreset (change-state! bwd_gid 0))
        ($g1 (ensure-goal (: (kb MAIN ()) p1 (LoopGoal) (STV 1.0 1.0))))
        ($g2 (ensure-goal (: (kb ALT ()) p2 (LoopGoal) (STV 1.0 1.0)))))
      (cons $g1 (cons $g2 ())))
   (0 1))

!(test
   (let*
      (($_gclear (remove-all-atoms &goal_store))
        ($_pclear (remove-all-atoms &proof_store))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal (: (kb MAIN ()) $prf (Goal) (STV 1.0 1.0))))
        ($pid (store-leaf-proof $gid (: (kb MAIN ()) factA (Goal) (STV 1.0 0.8)))))
      (proof-term-evidence-list (proof-ref $pid)))
   (factA))

!(test
   (let*
      (($_gclear (remove-all-atoms &goal_store))
        ($_pclear (remove-all-atoms &proof_store))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal (: (kb MAIN ()) $prf (Goal) (STV 1.0 1.0))))
        ($pid (store-leaf-proof $gid (: (kb MAIN ()) factA (Goal) (STV 1.0 0.8)))))
      (materialize-proof $pid))
   factA)

!(test
   (let*
      (($_gclear (remove-all-atoms &goal_store))
        ($_pclear (remove-all-atoms &proof_store))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal (: (kb MAIN ()) $prf (Goal) (STV 1.0 1.0))))
        ($_weak (emit-leaf-result $gid (: (kb MAIN ()) sharedFact (Goal) (STV 1.0 0.6))))
        ($_strong (emit-leaf-result $gid (: (kb MAIN ()) sharedFact (Goal) (STV 1.0 0.8)))))
      (goal-results $gid))
   ((: (kb MAIN ()) sharedFact (Goal) (STV 1.0 0.8))))

!(test
   (let*
      (($_gclear (remove-all-atoms &goal_store))
        ($_pclear (remove-all-atoms &proof_store))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal (: (kb MAIN ()) $prf (Goal) (STV 1.0 1.0))))
        ($_a (emit-leaf-result $gid (: (kb MAIN ()) factA (Goal) (STV 1.0 0.6))))
        ($_b (emit-leaf-result $gid (: (kb MAIN ()) factB (Goal) (STV 1.0 0.8)))))
      (goal-results $gid))
   ((: (kb MAIN ()) (merge/revision factB factA) (Goal) (STV 1.0 0.8461538461538461))))
