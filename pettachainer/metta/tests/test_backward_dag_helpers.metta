!(import! &self petta_chainer)

!(test (tv-confidence (STV 0.7 0.35)) 0.35)

!(test (tv-confidence maybeUnknown) 1.0)

!(test (term-confidence (CPU MpFormula ((STV 1.0 0.6) (STV 0.8 0.9)) $out)) 0.54)

!(test (term-confidence (CPU AndFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out)) 0.4)

!(test (term-confidence (CPU OrFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out)) 0.7)

!(test (term-confidence (CPU LikelierThanFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out))
   0.4)

!(test (term-confidence (CPU InversionFormula ($a $b (STV 0.8 0.632121)) $out))
   0.5689089)

!(test
   (premises-expected-confidence
      (cons (CPU MpFormula ((STV 1.0 0.2) (STV 1.0 1.0)) $tv1)
         (cons (CPU MpFormula ((STV 1.0 0.55) $tv1) $tv2) ())))
   0.18000000000000002)

!(test
   (premises-expected-confidence
      (cons ((Animal #) (kb MAIN Nil) $prfA $tvA)
         (cons ((Creature #) (kb MAIN Nil) $prfB $tvB)
            (cons (CPU InversionFormula ($tvA $tvB (STV 0.8 0.632121)) $iitv)
               (cons ((Creature #) (kb MAIN Nil) $prfC $tvB)
                  (cons (CPU MpFormula ($iitv $tvB) $tvA) ()))))))
   0.5689089)

!(test
   (goal-key-eq? ((LoopGoal $x) (kb MAIN ()) p1 (STV 1.0 1.0))
      ((LoopGoal $y) (kb MAIN ()) p2 (STV 1.0 0.4)))
   true)

!(test
   (goal-key-eq? ((LoopGoal) (kb MAIN ()) p1 (STV 1.0 1.0))
      ((LoopGoal) (kb ALT ()) p2 (STV 1.0 1.0)))
   false)

!(test
      (let*
      (($_gclear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($g1 (ensure-goal ((LoopGoal $x) (kb MAIN ()) p1 (STV 1.0 1.0))))
        ($g2 (ensure-goal ((LoopGoal $y) (kb MAIN ()) p2 (STV 1.0 0.3)))))
      (cons $g1 (cons $g2 (collapse (match &goal ($gid $_depth $_goal $_expanded $_pending) $gid)))))
   (0 0 0))

!(test
   (let*
      (($_gclear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($g1 (ensure-goal ((LoopGoal) (kb MAIN ()) p1 (STV 1.0 1.0))))
        ($g2 (ensure-goal ((LoopGoal) (kb ALT ()) p2 (STV 1.0 1.0)))))
      (cons $g1 (cons $g2 ())))
   (0 1))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal ((Goal) (kb MAIN ()) $prf (STV 1.0 1.0))))
        ($pid
           (store-proof-candidate $gid
              (proof-candidate (leaf ((Goal) (kb MAIN ()) factA (STV 1.0 0.8)))
                 0.8
                 ((fact-ev (kb MAIN ()) factA (Goal)))
                 ()))))
      (proof-term-evidence-list (proof-ref $pid)))
   ((fact-ev (kb MAIN ()) factA (Goal))))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal ((Goal) (kb MAIN ()) $prf (STV 1.0 1.0))))
        ($pid-a
           (store-proof-candidate $gid
              (proof-candidate
                 (leaf ((Goal) (kb MAIN ()) (bench-base-fact demo 1 1) (STV 1.0 0.8)))
                 0.8
                 ((fact-ev (kb MAIN ()) (bench-base-fact demo 1 1) (Goal)))
                 ())))
        ($pid-b
           (store-proof-candidate $gid
              (proof-candidate
                 (leaf ((Goal) (kb MAIN ()) (bench-base-fact demo 1 2) (STV 1.0 0.7)))
                 0.7
                 ((fact-ev (kb MAIN ()) (bench-base-fact demo 1 2) (Goal)))
                 ()))))
      (evidence-sets-overlap? (snd (proof-stats-by-id $pid-a))
         (snd (proof-stats-by-id $pid-b))))
   false)

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal ((Goal) (kb MAIN ()) $prf (STV 1.0 1.0))))
        ($pid
           (store-proof-candidate $gid
              (proof-candidate (leaf ((Goal) (kb MAIN ()) factA (STV 1.0 0.8)))
                 0.8
                 ((fact-ev (kb MAIN ()) factA (Goal)))
                 ()))))
      (materialize-proof $pid))
   factA)

!(test
   (proof-term-children (custom-proof left right))
   ())

!(test
   (proof-term-children-in-kb (kb MAIN ()) (custom-proof left right))
   (left right))

!(test
   (proof-term-children-in-kb (kb MAIN ()) (CPU SomeRuntimeThing (arg1 arg2) out))
   ())

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal ((Goal) (kb MAIN ()) $prf (STV 1.0 1.0))))
        ($weak
           (proof-candidate (leaf ((Goal) (kb MAIN ()) sharedFact (STV 1.0 0.6)))
              0.6
              ((fact-ev (kb MAIN ()) sharedFact (Goal)))
              ()))
        ($_weak
           (commit-proof-candidate $gid
              (classify-goal-proof-candidate $gid
                 ((fact-ev (kb MAIN ()) sharedFact (Goal)))
                 0.6)
              $weak))
        ($strong
           (proof-candidate (leaf ((Goal) (kb MAIN ()) sharedFact (STV 1.0 0.8)))
              0.8
              ((fact-ev (kb MAIN ()) sharedFact (Goal)))
              ()))
        ($_strong
           (commit-proof-candidate $gid
              (classify-goal-proof-candidate $gid
                 ((fact-ev (kb MAIN ()) sharedFact (Goal)))
                 0.8)
              $strong)))
      (goal-results $gid))
   (((Goal) (kb MAIN ()) sharedFact (STV 1.0 0.8))))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal ((Goal) (kb MAIN ()) $prf (STV 1.0 1.0))))
        ($strong
           (proof-candidate (leaf ((Goal) (kb MAIN ()) sharedFact (STV 1.0 0.8)))
              0.8
              ((fact-ev (kb MAIN ()) sharedFact (Goal)))
              ()))
        ($_strong
           (commit-proof-candidate $gid
              (classify-goal-proof-candidate $gid
                 ((fact-ev (kb MAIN ()) sharedFact (Goal)))
                 0.8)
              $strong))
        ($weak
           (proof-candidate (leaf ((Goal) (kb MAIN ()) sharedFact (STV 1.0 0.6)))
              0.6
              ((fact-ev (kb MAIN ()) sharedFact (Goal)))
              ()))
        ($_weak
           (commit-proof-candidate $gid
              (classify-goal-proof-candidate $gid
                 ((fact-ev (kb MAIN ()) sharedFact (Goal)))
                 0.6)
              $weak)))
      (catch (get-state bwd_pid)))
   1)

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal ((Goal) (kb MAIN ()) $prf (STV 1.0 1.0))))
        ($a
           (proof-candidate (leaf ((Goal) (kb MAIN ()) factA (STV 1.0 0.6)))
              0.6
              ((fact-ev (kb MAIN ()) factA (Goal)))
              ()))
        ($_a
           (commit-proof-candidate $gid
              (classify-goal-proof-candidate $gid
                 ((fact-ev (kb MAIN ()) factA (Goal)))
                 0.6)
              $a))
        ($b
           (proof-candidate (leaf ((Goal) (kb MAIN ()) factB (STV 1.0 0.8)))
              0.8
              ((fact-ev (kb MAIN ()) factB (Goal)))
              ()))
        ($_b
           (commit-proof-candidate $gid
              (classify-goal-proof-candidate $gid
                 ((fact-ev (kb MAIN ()) factB (Goal)))
                 0.8)
              $b)))
      (goal-results $gid))
   (((Goal) (kb MAIN ()) (merge/revision factB factA) (STV 1.0 0.8461538461538461))))

!(test
   (proof-term-evidence-list
      (rule-proof own_have (fact-ev (kb MAIN ()) i_have_max (Have (i max)))))
   ((fact-ev (kb MAIN ()) i_have_max (Have (i max)))))
