!(import! &self ../../pettachainer/metta/petta_chainer)

;; Reads stay deterministic and live after a normal late shallower occurrence;
;; the goal's shared statement/proof variable must remain unbound.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($goal (assemble-runtime-fact
             (brand Statement (Shallower $x))
             (brand KBContext (shallowerAudit MAIN Nil))
             (brand Proof (alias $x)) (STV 1.0 0.8)))
          ($original (copy_term $goal))
          ($gid (ensure-goal-at-depth $goal 4))
          ($before ((collapse (goal-shallower? $gid 3))
                    (collapse (goal-shallower? $gid 4))
                    (collapse (goal-shallower? $gid 5))
                    (collapse (goal-shallower? -1 5))))
          ($same (ensure-goal-at-depth $goal 2))
          ($after ((collapse (goal-shallower? $gid 3))
                   (collapse (goal-shallower? $gid 2))))
          ($_deeper (ensure-goal-at-depth $goal 9))
          ($retained (collapse (goal-shallower? $gid 3)))
          ((stored-goal-row $_stored-gid $_depth $stored $_expanded $_state)
             (goal-by-id $gid))
          ($unchanged (=alpha $original $stored))
          ($_reset (clear-backward-query-state!)))
      ($before $after $retained (== $gid $same) $unchanged
       (=alpha $original $goal) (is-var $x)
       (collapse (goal-shallower? $gid 100))))
   (((false) (false) (true) (false)) ((true) (false)) (true)
    true true true true (false)))
