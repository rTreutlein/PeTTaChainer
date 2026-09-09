!(import! &self ../../pettachainer/metta/petta_chainer)

(: dependency-test-goal (-[semidet]-> Statement Number))
(= (dependency-test-goal $statement)
   (ensure-goal-at-depth
      (assemble-runtime-fact $statement (brand KBContext (dependencyTest MAIN Nil))
         (brand Proof $proof) (the TV $tv)) 0))

;; Two parents share a descendant. Every immutable node gets one negative
;; result; another parent reuses those cached subproblems. A positive result
;; visits only the first matching branch, retaining child-list short circuiting.
!(test
   (let* (($_clear (clear-backward-state))
          ($shared (dependency-test-goal (Shared)))
          ($left (dependency-test-goal (Left)))
          ($right (dependency-test-goal (Right)))
          ($top (dependency-test-goal (Top)))
          ($next (dependency-test-goal (Next)))
          ($absent (dependency-test-goal (Absent)))
          ($shared-pid (store-proof-candidate $shared
             (leaf-result-candidate
                (assemble-runtime-fact (Shared) (brand KBContext (dependencyTest MAIN Nil))
                   (brand Proof shared) (STV 1.0 0.8)) ())))
          ($left-pid (store-proof-candidate $left
             (aggregate-result-candidate
                (assemble-runtime-fact (Left) (brand KBContext (dependencyTest MAIN Nil))
                   (brand Proof left) (STV 1.0 0.8)) () ($shared-pid))))
          ($right-pid (store-proof-candidate $right
             (aggregate-result-candidate
                (assemble-runtime-fact (Right) (brand KBContext (dependencyTest MAIN Nil))
                   (brand Proof right) (STV 1.0 0.8)) () ($shared-pid))))
          ($top-pid (store-proof-candidate $top
             (aggregate-result-candidate
                (assemble-runtime-fact (Top) (brand KBContext (dependencyTest MAIN Nil))
                   (brand Proof top) (STV 1.0 0.8)) () ($left-pid $right-pid))))
          ($first (proof-depends-on-goal? $top-pid $absent closed-goal))
          ($second (proof-depends-on-goal? $top-pid $absent closed-goal))
          ($rows-before (length (collapse (match &proof_cycle_cache
             ($_pid $absent closed-goal $_value) cached))))
          ($next-pid (store-proof-candidate $next
             (aggregate-result-candidate
                (assemble-runtime-fact (Next) (brand KBContext (dependencyTest MAIN Nil))
                   (brand Proof next) (STV 1.0 0.8)) () ($left-pid $right-pid))))
          ($third (proof-depends-on-goal? $next-pid $absent closed-goal))
          ($rows-after (length (collapse (match &proof_cycle_cache
             ($_pid $absent closed-goal $_value) cached))))
          ($positive (proof-depends-on-goal? $top-pid $shared closed-goal)))
      ($first $second $third $rows-before $rows-after $positive
       (space-row-present? &proof_cycle_cache ($right-pid $shared closed-goal $_value))))
   (false false false 4 5 true false))

;; One open owner key has distinct output bindings. Closed-goal rejection uses
;; the owner, while an output-constrained consumer rejects only its own binding.
!(test
   (let* (($_clear (clear-backward-state))
          ($goal (dependency-test-goal (Choice $x)))
          ($a (assemble-runtime-fact (Choice a) (brand KBContext (dependencyTest MAIN Nil))
             (brand Proof choice-a) (STV 1.0 0.8)))
          ($b (assemble-runtime-fact (Choice b) (brand KBContext (dependencyTest MAIN Nil))
             (brand Proof choice-b) (STV 1.0 0.8)))
          ($a-pid (store-proof-candidate $goal (leaf-result-candidate $a ())))
          ($b-pid (store-proof-candidate $goal (leaf-result-candidate $b ())))
          ($a-key (candidate-output-key $a))
          ($b-key (candidate-output-key $b)))
      ((proof-depends-on-goal? $a-pid $goal $a-key)
       (proof-depends-on-goal? $a-pid $goal $b-key)
       (proof-depends-on-goal? $b-pid $goal $a-key)
       (proof-depends-on-goal? $b-pid $goal $b-key)
       (proof-depends-on-goal? $a-pid $goal closed-goal)
       (proof-depends-on-goal? $b-pid $goal closed-goal)))
   (true false false true true true))

;; Missing proof IDs remain semidet failure, not a cached negative. An already
;; positive fold does not inspect its later missing child.
!(test
   (let* (($_clear (clear-backward-state))
          ($goal (dependency-test-goal (MissingTarget)))
          ($missing 999999999)
          ($absent (collapse (proof-depends-on-goal? $missing $goal closed-goal)))
          ($short-circuited (depends-step $goal closed-goal true $missing)))
      ($absent $short-circuited
       (space-row-present? &proof_cycle_cache ($missing $_gid $_key $_result))))
   (() true false))
