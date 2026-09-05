;; Backward proof-merge and candidate-commit contract.
;; Owns factoring, revision/dominance, representative refresh, root fallback,
;; cycle rejection, and commitment into proof_store's durable/current views.
;; Lifting requires multiple standard implication proofs, nonempty shared facts,
;; pairwise-disjoint residual evidence, and a two-point residual round-trip on
;; strength only; confidence is nonlinear. Singletons never enter factoring.
;; Failed lifting falls back to revision/dominance, and dominance requires shared
;; rule or hypothesis evidence: fact overlap remains poolable.
;; The first candidate represents itself; later candidates dirty the output so
;; one consumer refreshes it. Superseded results remain historical incumbents,
;; and replacement invalidation must never leak semidet failure to the caller.
(: lift-split (-[semidet]-> (List Number) (List Number) (List Number) ((List Number) (List Number))))
(= (lift-split () $p $c) ($p $c))
(= (lift-split (cons $pid $rest) $p $c) (if (= (proof-output-atom-by-id $pid) (CPU $_f $_a $_r)) (lift-split $rest $p (append-flat $c ($pid))) (lift-split $rest (append-flat $p ($pid)) $c)))
(: lift-last (-[semidet]-> (List Number) Number))
(= (lift-last (cons $x $rest)) (if (== $rest ()) $x (lift-last $rest)))
(: lift-ctv (-[det]-> (List TV) (| CTVType NoCTV)))
(= (lift-ctv $values) (case $values ( (() no-ctv) ((cons $a $rest) (case $a (((CTV $pos $neg) (CTV $pos $neg)) ($_other (lift-ctv $rest))))) ($_other no-ctv))))
(: lift-and (-[semidet]-> (List STVType) STVType))
(= (lift-and (cons $tv $rest)) (if (== $rest ()) $tv (AndFormula $tv (lift-and $rest))))
(: lift-premises (-[semidet]-> (List Number) (List ProofOutputKey) TV (List STVType)))
(= (lift-premises () $_keys $_o) ())
(= (lift-premises (cons $pid $rest) $keys $o) (cons (the STVType (lift-eval $pid $keys $o)) (lift-premises $rest $keys $o)))
(: lift-eval-rule (-[semidet]-> Number (List ProofOutputKey) TV TV TV))
(= (lift-eval-rule $pid $keys $o $stored) (let* ((($prem $cpu) (lift-split (proof-children-by-id $pid) () ()))) (if (== $cpu ()) $stored (let* (((CPU $lf $la $_r) (proof-output-atom-by-id (lift-last $cpu))) ($ctv (lift-ctv (the (List TV) $la)))) (if (== $lf CTVModusPonensFormula) (case $ctv (((CTV $pos $neg) (CTVModusPonensFormula (lift-and (lift-premises $prem $keys $o)) (CTV $pos $neg))) (no-ctv $stored))) $stored)))))
(: lift-eval (-[semidet]-> Number (List ProofOutputKey) TV TV))
(= (lift-eval $pid $keys $o) (let $out (proof-output-atom-by-id $pid) (case $out ( ((CPU $_formula $_arguments $_result) (empty)) (($t $kb $prf $tv) (let $stored $tv (if (is-alpha-member (candidate-output-key $out) $keys) $o (lift-eval-rule $pid $keys $o $stored)))) ($_other (empty))))))
(: lift-proof? (-[semidet]-> Number Bool))
(= (lift-proof? $pid) (let* ((($prem $cpu) (lift-split (proof-children-by-id $pid) () ()))) (if (== $cpu ()) true (let* (((CPU $lf $la $_r) (proof-output-atom-by-id (lift-last $cpu))) ($ctv (lift-ctv (the (List TV) $la)))) (if (== $lf CTVModusPonensFormula) (if (== $ctv no-ctv) false (lift-all? $prem)) false)))))
(: lift-all? (-[semidet]-> (List Number) Bool))
(= (lift-all? ()) true)
(= (lift-all? (cons $pid $rest)) (if (lift-proof? $pid) (lift-all? $rest) false))
(: lift-facts (-[semidet]-> Number (List Evidence)))
(= (lift-facts $pid) (fact-evidence-only (snd (proof-stats-by-id $pid))))
(: lift-shared-step (-[semidet]-> (List Evidence) Number (List Evidence)))
(= (lift-shared-step $acc $pid) (evidence-intersection $acc (lift-facts $pid)))
(: lift-shared (-[semidet]-> (List Number) (List Evidence)))
(= (lift-shared (cons $pid $rest)) (proof-fold-flat-semidet lift-shared-step (lift-facts $pid) $rest))
(: factor-fact-key (-[semidet]-> Evidence ProofOutputKey))
(= (factor-fact-key (fact-ev $kb $prf $type)) (proof-output-key (quote ($type $kb))))
(: lift-leaf-work (-[semidet]-> (List Number) ProofOutputKey (| TV NoTV)))
(= (lift-leaf-work () $_key) no-tv)
(= (lift-leaf-work (cons $pid $rest) $key) (let $out (proof-output-atom-by-id $pid) (case $out ( ((CPU $_formula $_arguments $_result) (lift-leaf-work (append-flat (proof-children-by-id $pid) $rest) $key)) (($t $kb $prf $tv) (if (=alpha (candidate-output-key $out) $key) (the TV $tv) (lift-leaf-work (append-flat (proof-children-by-id $pid) $rest) $key))) ($_other (lift-leaf-work (append-flat (proof-children-by-id $pid) $rest) $key))))))
(: lift-residual (-[semidet]-> Number (List ProofOutputKey) CTVType))
(= (lift-residual $pid $keys) (CTV (the STVType (lift-eval $pid $keys (STV 1.0 1.0))) (the STVType (lift-eval $pid $keys (STV 0.0 1.0)))))
(: lift-revise (-[semidet]-> (List CTVType) CTVType))
(= (lift-revise (cons $resid ())) $resid)
(= (lift-revise (cons (CTV $p1 $n1) (cons $next $rest))) (let (CTV $p2 $n2) (lift-revise (cons $next $rest)) (CTV (mergetvs $p1 $p2) (mergetvs $n1 $n2))))
(: factor-required-leaf-tv (-[semidet]-> Number ProofOutputKey STVType))
(= (factor-required-leaf-tv $pid $key) (let $tv (lift-leaf-work ($pid) $key) (case $tv ((no-tv (empty)) ($_other (the STVType $_other))))))
(: lift-roundtrip-one? (-[semidet]-> TV CTVType STVType Bool))
(= (lift-roundtrip-one? $stored $resid $conj) (case $stored ( ((STV $sa $_ca) (case (CTVModusPonensFormula $conj $resid) ( ((STV $sb $_cb) (< (abs-math (- $sa $sb)) 0.000001)) ($_other false)))) ($_other false))))
(: lift-roundtrip (-[semidet]-> (List Number) (List ProofOutputKey) STVType (Bool (List CTVType))))
(= (lift-roundtrip () $_keys $_conj) (data true ()))
(= (lift-roundtrip (cons $pid $rest) $keys $conj) (let* ((($_t $_k $_p $stored) (proof-output-atom-by-id $pid)) ($resids (collapse (once (lift-residual $pid $keys))))) (if (== $resids ()) (data false ()) (let $resid (car-atom $resids) (if (lift-roundtrip-one? (the TV $stored) $resid $conj) (let ($valid $rest-resids) (lift-roundtrip $rest $keys $conj) (if $valid (data true (cons $resid $rest-resids)) (data false ()))) (data false ()))))))
(: lift-ref (-[semidet]-> Number Proof))
(= (lift-ref $pid) (let ($_t $_k $prf $_tv) (proof-output-atom-by-id $pid) (brand Proof $prf)))
(: lift-merged (-[semidet]-> (List Number) Proof))
(= (lift-merged (cons $pid ())) (lift-ref $pid))
(= (lift-merged (cons $pid (cons $next $rest))) (brand Proof (merge/revision (lift-ref $pid) (lift-merged (cons $next $rest)))))
(: lift-residual-evidence (-[semidet]-> (List Evidence) Number (List Evidence)))
(= (lift-residual-evidence $shared $pid) (let ($_score $ev) (proof-stats-by-id $pid) (evidence-subtraction $ev $shared)))
(: lift-disjoint-from? (-[det]-> (List Evidence) (List (List Evidence)) Bool))
(= (lift-disjoint-from? $_ev ()) true)
(= (lift-disjoint-from? $ev (cons $other $rest)) (if (evidence-sets-overlap? $ev $other) false (lift-disjoint-from? $ev $rest)))
(: lift-disjoint? (-[det]-> (List (List Evidence)) Bool))
(= (lift-disjoint? ()) true)
(= (lift-disjoint? (cons $ev $rest)) (if (lift-disjoint-from? $ev $rest) (lift-disjoint? $rest) false))
(: lifting-merge-output (-[semidet]-> (List Number) (List (Statement KBContext Proof TV))))
(= (lifting-merge-output (cons $first-pid $rest-pids)) (let $pids (cons $first-pid $rest-pids) (let $shared (lift-shared $pids) (if (== $shared ()) () (if (lift-all? $pids) (if (lift-disjoint? (map-semidet (lift-residual-evidence $shared) $pids)) (let* (($keys (map-semidet factor-fact-key $shared)) ($conj (lift-and (map-semidet (factor-required-leaf-tv $first-pid) $keys))) (($valid $resids) (lift-roundtrip $pids $keys $conj))) (if $valid (let* (($pooled (once (lift-revise $resids))) ($merged-tv (CTVModusPonensFormula $conj $pooled)) (($type $kb $_p $_t) (proof-output-atom-by-id $first-pid)) ($merged-prf (lift-merged $pids))) (cons (assemble-runtime-fact (brand Statement $type) (brand KBContext $kb) $merged-prf $merged-tv) ())) ())) ()) ())))))
(: merge-output (-[semidet]-> (List Number) (| Goal (Statement KBContext Proof TV))))
(= (merge-output (cons $pid $rest)) (if (== $rest ()) (proof-output-atom-by-id $pid) (case (proof-output-atom-by-id $pid) ( ((CPU $_function $_arguments $_result)(proof-output-atom-by-id (latest-live-proof-id (cons $pid $rest))))($_fact (let $factored (lifting-merge-output (cons $pid $rest)) (if (== $factored ()) (proof-fold-flat-semidet merge-output-step (proof-fact-output-by-id $pid) $rest) (car-atom $factored))))))))
(: evidence-step (-[semidet]-> (List Evidence) Number (List Evidence)))
(= (evidence-step $acc $pid) (let ($_score $ev) (proof-stats-by-id $pid) (list_to_set (append-flat $acc $ev))))
(: proof-evidence (-[semidet]-> (List Number) (List Evidence)))
(= (proof-evidence $pids) (proof-fold-flat-semidet evidence-step () $pids))
;; A marginal projection is a bound read off a conjunction, not an independent
;; measurement. A direct leaf of the same output with higher confidence
;; displaces it from the fact group when pooling would double-count the leaf
;; (the projection's evidence contains the leaf's) or when the projection
;; contradicts the leaf's strength; a corroborating projection with independent
;; evidence still pools. Revising the leaf would also retire every proof built
;; on it.
(: proof-leaf-class (-[semidet]-> Number Atom))
(= (proof-leaf-class $pid)
   (case (proof-kind-by-id $pid) (
      ((leaf ($_type $_kb (marginal-proj $_idx $_base) $_tv)) marginal)
      ((rule ($_type $_kb (marginal-proj $_idx $_base) $_tv)) marginal)
      ((leaf $_term) direct)
      ($_other other))))
(: marginal-direct-strength-conflict? (-[semidet]-> Number Number Bool))
(= (marginal-direct-strength-conflict? $marginal $direct)
   (case (proof-output-atom-by-id $marginal) (
      (($_mtype $_mkb $_mproof (STV $mstrength $_mconfidence))
         (case (proof-output-atom-by-id $direct) (
            (($_dtype $_dkb $_dproof (STV $dstrength $_dconfidence)) (not (== $mstrength $dstrength)))
            ($_other false))))
      ($_other false))))
(: marginal-displaced-by-direct? (-[semidet]-> Number Number (List Evidence) (List Number) Bool))
(= (marginal-displaced-by-direct? $_marginal $_score $_ev ()) false)
(= (marginal-displaced-by-direct? $marginal $score $ev (cons $pid $rest))
   (if (== (proof-leaf-class $pid) direct)
      (let ($direct-score $direct-ev) (proof-stats-by-id $pid)
         (if (> $direct-score $score)
            (if (== $direct-ev ())
               (marginal-displaced-by-direct? $marginal $score $ev $rest)
               (if (evidence-subset? $direct-ev $ev) true
                  (if (marginal-direct-strength-conflict? $marginal $pid) true
                     (marginal-displaced-by-direct? $marginal $score $ev $rest))))
            (marginal-displaced-by-direct? $marginal $score $ev $rest)))
      (marginal-displaced-by-direct? $marginal $score $ev $rest)))
(: representative-input-step (-[semidet]-> (List Number) (List Number) Number (List Number)))
(= (representative-input-step $pids $acc $pid)
   (if (== (proof-leaf-class $pid) marginal)
      (let ($score $ev) (proof-stats-by-id $pid)
         (if (marginal-displaced-by-direct? $pid $score $ev $pids) $acc (cons $pid $acc)))
      (cons $pid $acc)))
(: representative-input-pids (-[semidet]-> (List Number) (List Number)))
(= (representative-input-pids $pids) (reverse-number-list (proof-fold-flat-semidet (representative-input-step $pids) () $pids)))
;; Generated reverse rules (inverted, projection, antecedent completion) are
;; secondary derivations. For a goal that a direct leaf already proves they may
;; only combine premises that are already established with independent
;; evidence: opening new search through them re-derives the leaf from itself
;; and, on fact-heavy KBs, costs a full search on every re-query.
(: generated-rule-head (-[det]-> Proof Atom))
(= (generated-rule-head $proof)
   (if (is-expr $proof)
      (let $outer (car-atom $proof)
         (if (is-expr $outer)
            (let $head (car-atom $outer) (if (is-var $head) none $head))
            (if (is-var $outer) none $outer)))
      none))
(: inverted-rule-proof? (-[det]-> Proof Bool))
(= (inverted-rule-proof? $proof) (== (generated-rule-head $proof) inverted))
(: generated-reverse-rule-proof? (-[det]-> Proof Bool))
(= (generated-reverse-rule-proof? $proof)
   (let $head (generated-rule-head $proof)
      (stored-list-member? $head (inverted proj marginal-proj antecedent-completion))))
(: proof-list-has-direct-leaf? (-[semidet]-> (List Number) Bool))
(= (proof-list-has-direct-leaf? ()) false)
(= (proof-list-has-direct-leaf? (cons $pid $rest))
   (if (== (proof-leaf-class $pid) direct) true (proof-list-has-direct-leaf? $rest)))
;; Keyed by output rather than goal key: a premise that was never scheduled has
;; no stored key. A ground output key goes through the hash column; a pattern
;; with variables matches its instances by unification instead.
(: current-proof-ids-for-output (-[det]-> (| Goal (Statement KBContext Proof TV)) (List Number)))
(= (current-proof-ids-for-output $premise)
   (let $okey (copy_term (candidate-output-key $premise))
      (if (== (extract-vars $okey) ())
         (let $ohash (index-hash $okey)
            (collapse (match &proof_current (current-row $_khash $ohash $_key $okey $pid) (stored-number $pid))))
         (collapse (match &proof_current (current-row $_khash $_ohash $_key $okey $pid) (stored-number $pid))))))
(: premise-current-pid-lists
   (-[semidet]-> Bool (List (| Goal (Statement KBContext Proof TV))) (List (List Number))))
;; Existence pass: an unestablished premise yields the sentinel (cons () ()) at
;; once, before any evidence is folded. A stored fact without a current
;; derivation may stand in only for inverted rules or compound premises.
(= (premise-current-pid-lists $_stored-ok ()) ())
(= (premise-current-pid-lists $stored-ok (cons $premise $rest))
   (case $premise (
      ((CPU $_function $_arguments $_result) (premise-current-pid-lists $stored-ok $rest))
      (($type $_kb $_proof $_tv)
         (let $pids (current-proof-ids-for-output $premise)
            (if (== $pids ())
               (if (if $stored-ok true (if (is-expr $type) (compound-connective? (car-atom $type)) false))
                  (if (== (collapse (once (match &kb (@ $_stored $premise) true))) ())
                     (cons () ())
                     (premise-current-pid-lists $stored-ok $rest))
                  (cons () ()))
               (let $more (premise-current-pid-lists $stored-ok $rest)
                  (if (== $more (cons () ())) $more (cons $pids $more)))))))))
(: premise-evidence-independent? (-[semidet]-> (List Evidence) (List (List Number)) Bool))
(= (premise-evidence-independent? $_evidence ()) true)
(= (premise-evidence-independent? $incumbent-evidence (cons $pids $rest))
   (if (== $pids ()) false
      (if (evidence-sets-overlap? (proof-evidence $pids) $incumbent-evidence) false
         (premise-evidence-independent? $incumbent-evidence $rest))))
(: reverse-rule-premises-current?
   (-[semidet]-> Bool (List Evidence) (List (| Goal (Statement KBContext Proof TV))) Bool))
(= (reverse-rule-premises-current? $stored-ok $incumbent-evidence $premises)
   (premise-evidence-independent? $incumbent-evidence (premise-current-pid-lists $stored-ok $premises)))
(: representative-for-key (-[semidet]-> ProofGoalKey ProofOutputGroup Number))
;; Output groups are keyed by output, so the head pid's output kind (CPU vs
;; fact) is uniform across the group: dispatch on it first and pay the
;; latest-live probe fold only for CPU groups.
(= (representative-for-key $gkey (proof-output-group $_key $pids))
   (case $pids (
      ((cons $pid ()) $pid)
      ((cons $hpid $_rest)
         (case (proof-output-atom-by-id $hpid) (
            ((CPU $_function $_arguments $_result) (latest-live-proof-id $pids))
            ($_fact
               (let $preferred (representative-input-pids $pids)
                  (case $preferred (
                     ((cons $pid ()) $pid)
                     ($_multiple
                        (let* (($owner (merged-proof-group $gkey))
                               ($output (merge-output $preferred))
                               ($score (term-confidence $output))
                               ($ev (proof-evidence $preferred))
                               ($hits (collapse (once (match &proof (stored-proof-row $saved-pid $owner $output (merged $output) (proof-support $score $ev $_contribution) $preferred) $saved-pid)))))
                           (if (== $hits ())
                              (let* (($pid (next-pid))
                                     ($_store (once (chainer-add-atom &proof (stored-proof-row $pid $owner $output (merged $output) (proof-support $score $ev (stored-contribution (merged $output) $output)) $preferred))))
                                     ($_index (index-goal-proof! &proof_result $gkey $pid)))
                                 $pid)
                              (car-atom $hits))))))))))))))
(: proof-output-group-representative-pids (-[semidet]-> Number (List ProofOutputGroup) (List Number)))
(= (proof-output-group-representative-pids $gid $groups) (let $gkey (proof-goal-key-by-goal-id $gid) (map-semidet (representative-for-key $gkey) $groups)))
(: live-output-pids (-[semidet]-> Number ProofOutputKey (List Number)))
(= (live-output-pids $gid $key) (let* (((stored-goal-row $_gid $_depth $goal $_expanded $_pending) (goal-by-id $gid)) ($gkey (proof-goal-key-by-goal-id $gid))) (reverse-number-list (proof-fold-flat-semidet (current-proof-step $goal) () (current-output-pids $gkey $key)))))
;; Candidate membership and the published result are authoritative. Replacing
;; a result invalidates its query-local frontier paths, not its proof history.
(: refresh-result! (-[semidet]-> ProofGoalKey ProofOutputKey (List $none)))
(= (refresh-result! $gkey $okey) (let* (($old (collapse (once (current-proof-result-id-for-output-key $gkey $okey)))) ($pids (current-output-pids $gkey $okey))) (if (== $pids ()) (let* (($_remove (remove-result! $gkey $okey)) ($_paths (foreach-flat invalidate-proof-paths! $old)) ($_clean (clear-dirty! $gkey $okey))) ()) (let* (($new-pid (representative-for-key $gkey (proof-output-group $okey $pids))) ($_replace (index-result! $gkey $okey $new-pid)) ($_paths (foreach-flat (|-> ($old-pid) (if (== $old-pid $new-pid) () (invalidate-proof-paths! $old-pid))) $old)) ($_clean (clear-dirty! $gkey $okey))) ()))))
(: refresh-dirty! (-[semidet]-> ProofGoalKey (List (List $none))))
(= (refresh-dirty! $gkey) (map-semidet (refresh-result! $gkey) (dirty-keys $gkey)))
(: goal-merged-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-merged-proof-ids $gid) (let* (((stored-goal-row $_gid $_depth $goal $_expanded $_pending) (goal-by-id $gid)) ($key (proof-goal-key-by-goal-id $gid)) ($_refresh (refresh-dirty! $key))) (reverse-number-list (proof-fold-flat-semidet (current-proof-step $goal) () (result-ids $key)))))
(: goal-merged-proof-id-for-pid (-[semidet]-> Number Number Number))
(= (goal-merged-proof-id-for-pid $gid $pid) (let* (($gkey (proof-goal-key-by-goal-id $gid)) ($okey (output-key $pid)) ($_refresh (if (result-dirty? $gkey $okey) (refresh-result! $gkey $okey) ()))) (current-proof-result-id-for-output-key $gkey $okey)))
(: output-covered? (-[semidet]-> (List Number) Number Bool))
(= (output-covered? () $_pid) false)
(= (output-covered? (cons $covered-pid $rest) $pid) (if (=alpha (output-key $covered-pid) (output-key $pid)) true (output-covered? $rest $pid)))
(: uncovered-step (-[semidet]-> (List Number) (List Number) Number (List Number)))
(= (uncovered-step $covered $acc $pid) (if (output-covered? $covered $pid) $acc (cons $pid $acc)))
(: goal-incumbent-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-incumbent-proof-ids $gid) (let* (($merged (latest-proof-output-group-ids (proof-output-groups (indexed-goal-pids &proof_result $gid)))) ($raw (goal-live-proof-ids $gid)) ($uncovered (reverse-number-list (proof-fold-flat-semidet (uncovered-step $merged) () $raw)))) (append-flat $merged $uncovered)))
(: root-pids (-[semidet]-> Number (List Number)))
(= (root-pids $gid)
   (let $current
      (let $live (goal-live-proof-ids $gid)
         (if (== $live ())
            (proof-output-group-representative-pids $gid (proof-output-groups (goal-incumbent-proof-ids $gid)))
            (goal-merged-proof-ids $gid)))
      (if (== $current ())
         (latest-proof-output-group-ids (proof-output-groups (goal-proof-ids $gid)))
         $current)))
(: first-pid-list (-[det]-> (List Number) (List Number)))
(= (first-pid-list ()) ())
(= (first-pid-list (cons $pid $_rest)) (cons $pid ()))
(: root-goal-results-with-materialization (-[semidet]-> Number Bool (List RuntimeResult)))
(= (root-goal-results-with-materialization $gid $materialize?)(let* (($reps (root-pids $gid))($selected (if (== $reps ())(goal-incumbent-proof-ids $gid)$reps))($committed (if $materialize? (first-pid-list $selected) $selected))($current-rows (collapse (once (map-semidet materialize-result (map-semidet proof-output-atom-by-id $committed)))))($current (if (== $current-rows ())()(car-atom $current-rows)))($_materialized (if $materialize? (materialize-list! $committed) ())))(if (== $current ())(map-semidet materialize-result (map-semidet proof-output-atom-by-id (goal-incumbent-proof-ids $gid)))$current)))
(: goal-current-confidence (-[semidet]-> Number (| Number NoCurrentScore)))
(= (goal-current-confidence $gid) (let $cached (collapse (once (match &goal_current_confidence (current-confidence-row $gid $value) $value))) (if (== $cached ()) (let* (($pids (goal-merged-proof-ids $gid)) ((stored-goal-row $_gid $_depth $goal $_expanded $_pending) (goal-by-id $gid)) ($value (if (goal-has-type-vars? $goal) no-current (case $pids ((() no-current) ((cons $pid $rest) (term-confidence (merge-output (cons $pid $rest)))))))) ($_cache (once (add-atom &goal_current_confidence (current-confidence-row $gid $value))))) $value) (car-atom $cached))))
(: leaf-evidence-for-result (-[det]-> (| Goal (Statement KBContext Proof TV)) (List Evidence)))
(= (leaf-evidence-for-result $result) (once (case $result ( ((CPU $_formula $_arguments $_result) ()) (($type $kb $proof $tv) (let $typed-proof (brand Proof $proof) (if (assumption-proof? $typed-proof) () (forward-fact-evidence (brand Statement $type) (brand KBContext $kb) $typed-proof (the TV $tv))))) ($_other ())))))
(: ProofRank Type)
(: proof-value (-[det]-> Proof ProofRank))
(: no-proof-value ProofRank)
(: kind-value (-[det]-> ProofKind ProofRank))
(= (kind-value $kind) (once (case $kind ( ((leaf ($_type $_kb $proof $_tv)) (proof-value (brand Proof $proof))) ((rule ($_type $_kb $proof $_tv)) (proof-value (brand Proof $proof))) ((aggregate (CPU $_formula $_arguments $_result)) no-proof-value) ((aggregate ($_type $_kb $proof $_tv)) (proof-value (brand Proof $proof))) ($_other no-proof-value)))))
(: kind-refines? (-[det]-> ProofKind (List Evidence) ProofKind (List Evidence) Bool))
(= (kind-refines? $old-kind $old-ev $new-kind $new-ev) (let* (($old-proof-value (kind-value $old-kind)) ($new-proof-value (kind-value $new-kind))) (if (= $old-proof-value (proof-value $old-proof)) (if (= $new-proof-value (proof-value $new-proof)) (and (forward-strict-evidence-subset? $old-ev $new-ev) (forward-proof-refines? (brand Proof $old-proof) (brand Proof $new-proof))) false) false)))
(: overlap-dominates? (-[det]-> ProofKind (List Evidence) Number ProofKind (List Evidence) Number Bool))
(= (overlap-dominates? $old-kind $old-ev $old-score $new-kind $new-ev $new-score) (let $_metric (increment-backward-query-metric! dominance-checks) (if (evidence-sets-dependent? $old-ev $new-ev) (if (kind-refines? $old-kind $old-ev $new-kind $new-ev) false (if (kind-refines? $new-kind $new-ev $old-kind $old-ev) true (if (> $old-score $new-score) true (if (== $old-score $new-score) (evidence-subset? $new-ev $old-ev) false)))) false)))
;; Candidates compete within their output key. Equal score and equal
;; non-empty evidence is the same derivation; without evidence
;; (evidence-transparent chains) the children's outputs decide, so distinct
;; instances stay distinct and a re-derivation is dropped.
(: same-child-outputs? (-[semidet]-> (List Number) (List Number) Bool))
(= (same-child-outputs? () $new) (== $new ()))
(= (same-child-outputs? (cons $old $old-rest) $new) (case $new ( (() false) ((cons $pid $new-rest) (if (=alpha (proof-output-atom-by-id $old) (proof-output-atom-by-id $pid)) (same-child-outputs? $old-rest $new-rest) false)))))
;; Derivation identity: the rule token with premise references (and merges of
;; them) erased plus the output keys of the premises, in order, repeats collapsed, that are not
;; formula evaluations. A current proof with the identity of a new candidate
;; and no evidence the candidate lacks is the same derivation over replaced
;; inputs: storing the candidate supersedes it. Same identity and the same
;; premise proofs is a duplicate.
(: same-derivation? (-[semidet]-> ProofKind (List Number) Number Bool))
(= (same-derivation? (rule $term) $children $oldpid) (case (proof-kind-by-id $oldpid) ( ((rule $old-term) (if (=alpha (derivation-shape $term) (derivation-shape $old-term)) (=alpha (premise-keys $children) (premise-keys (proof-children-by-id $oldpid))) false)) ($_other false))))
(= (same-derivation? (leaf $_term) $_children $_oldpid) false)
(= (same-derivation? (aggregate $_term) $_children $_oldpid) false)
(: supersedes-derivation? (-[semidet]-> ProofKind (List Evidence) (List Number) Number Bool))
(= (supersedes-derivation? $kind $ev $children $oldpid) (if (same-derivation? $kind $children $oldpid) (if (== (proof-children-by-id $oldpid) $children) false (let ($_old-score $old-ev) (proof-stats-by-id $oldpid) (evidence-subset? $old-ev $ev))) false))
;; Current rule candidates are indexed by the hash of (goal key, derivation
;; identity); -1 stands for kinds without one. Dropping a current candidate
;; removes its index row; merely losing the merged-result role does not.
;; The full goal key and derivation comparison reject hash collisions.
(: superseded-derivation-pids (-[semidet]-> ProofGoalKey Number ProofKind (List Evidence) (List Number) (List Number)))
(= (superseded-derivation-pids $gkey $dhash $kind $ev $children)
   (collapse
      (match &proof_derivation (derivation-row $dhash $saved-key $pid)
         (if (=alpha $saved-key $gkey)
            (if (supersedes-derivation? $kind $ev $children $pid)
               (stored-number $pid)
               (empty))
            (empty)))))
(: candidate-step (-[semidet]-> ProofKind (List Evidence) Number (List Number) Bool Number Bool))
(= (candidate-step $_kind $_ev $_score $_children false $_oldpid) false)
(= (candidate-step $kind $ev $score $children true $oldpid) (if (same-derivation? $kind $children $oldpid) (if (== (proof-children-by-id $oldpid) $children) false (if (supersedes-derivation? $kind $ev $children $oldpid) true (candidate-compare $kind $ev $score $children $oldpid))) (candidate-compare $kind $ev $score $children $oldpid)))
(: candidate-compare (-[semidet]-> ProofKind (List Evidence) Number (List Number) Number Bool))
(= (candidate-compare $kind $ev $score $children $oldpid) (let* (($_metric (increment-backward-query-metric! candidate-comparisons)) (($old-score $old-ev) (proof-stats-by-id $oldpid)) ($old-kind (proof-kind-by-id $oldpid))) (if (if (== $old-score $score) (if (== $old-ev $ev) (if (== $ev ()) (same-child-outputs? (proof-children-by-id $oldpid) $children) true) false) false) false (if (overlap-dominates? $old-kind $old-ev $old-score $kind $ev $score) false true))))
(: classify-goal-proof-candidate (-[semidet]-> Number ProofCandidate Bool))
(= (classify-goal-proof-candidate $gid (proof-candidate $kind $score $ev $children)) (let $outkey (candidate-output-key (candidate-kind-term $kind)) (proof-fold-flat-semidet (candidate-step $kind $ev $score $children) true (live-output-pids $gid $outkey))))
(: normalize-proof-candidate-evidence (-[semidet]-> ProofCandidate ProofCandidate))
(= (normalize-proof-candidate-evidence (proof-candidate $kind $score $ev $children)) (proof-candidate $kind $score (case $kind ( ((rule ($type $kb $prf $tv)) (rule-result-evidence (assemble-runtime-fact (brand Statement $type) (brand KBContext $kb) (brand Proof $prf) (the TV $tv)) $ev)) ($_other $ev))) $children))
(: store-proof-candidate (-[nondet]-> Number ProofCandidate Number))
(= (store-proof-candidate $gid (proof-candidate $kind $score $ev $children)) (let* (($_metric (increment-backward-query-metric! proofs-stored)) ($gkey (proof-goal-key-by-goal-id $gid)) ($owner (proof-goal $gkey)) ($pid (next-pid)) ($output (stored-output $kind $pid)) ($okey (candidate-output-key $output)) ($dhash (derivation-hash $gkey $kind $children)) ($_stale (if (< $dhash 0) () (collapse (foreach-flat supersede-current-proof! (superseded-derivation-pids $gkey $dhash $kind $ev $children))))) ($old-rep (collapse (once (current-proof-result-id-for-output-key $gkey $okey)))) ($result-dirty? (result-dirty? $gkey $okey)) ($_1 (chainer-add-atom &proof (stored-proof-row $pid $owner $output $kind (proof-support $score $ev (stored-contribution $kind $output)) $children))) ($_index (index-goal-proof! &proof_goal $gkey $pid)) ($_current (index-current! $gkey $okey $pid)) ($_derivation (if (< $dhash 0) () (once (add-atom &proof_derivation (derivation-row $dhash $gkey $pid))))) ($_confidence (clear-current-confidence! $gid)) ($_result (if (= $kind (aggregate $_snapshot)) (replace-result! $gkey $okey $old-rep $pid) (if $result-dirty? () (if (== $old-rep ()) (index-result! $gkey $okey $pid) (let* (($_remove-result (remove-result-output! $gkey $okey)) ($_paths (foreach-flat invalidate-proof-paths! $old-rep)) ($_dirty (mark-dirty! $gkey $okey))) ())))))) $pid))
(: leaf-result-candidate (-[det]-> (| Goal (Statement KBContext Proof TV)) (List Evidence) ProofCandidate))
(= (leaf-result-candidate $result $ev) (once (case $result ( ((CPU $_formula $_arguments $_cpu-result) (proof-candidate (leaf $result) (term-confidence $result) $ev ())) (($type ($kbid $context $variables) $prf $tv) (let $fact (assemble-contextual-runtime-fact $type $kbid $context $variables $prf $tv) (proof-candidate (leaf $fact) (term-confidence $fact) $ev ()))) ($_other (proof-candidate (leaf $result) (term-confidence $result) $ev ()))))))
(: aggregate-result-candidate (-[det]-> (| Goal (Statement KBContext Proof TV)) (List Evidence) (List Number) ProofCandidate))
(= (aggregate-result-candidate $result $ev $children) (proof-candidate (aggregate $result) (term-confidence $result) $ev $children))
(: candidate-kind-term (-[semidet]-> ProofKind (| Goal (Statement KBContext Proof TV))))
(= (candidate-kind-term (leaf $term)) $term)
(= (candidate-kind-term (rule $term)) $term)
(= (candidate-kind-term (aggregate $term)) $term)
(: cyclic-dependency? (-[semidet]-> Number Number (| ProofOutputKey ClosedGoalKey) Bool))
(= (cyclic-dependency? $pid $gid $cycle) (if (== $cycle closed-goal) (=alpha (owner-key $pid) (proof-goal-key-by-goal-id $gid)) (=alpha (output-key $pid) $cycle)))
(: proof-depends-on-goal-seen? (-[semidet]-> Number Number (| ProofOutputKey ClosedGoalKey) (List Number) Bool))
(: depends-step (-[semidet]-> Number (| ProofOutputKey ClosedGoalKey) (List Number) Bool Number Bool))
(= (depends-step $gid $cycle $seen-pids $acc $child) (if $acc true (proof-depends-on-goal-seen? $child $gid $cycle $seen-pids)))
(= (proof-depends-on-goal-seen? $pid $gid $cycle ()) (let $hits (collapse (once (match &proof_cycle_cache ($pid $gid $saved-key $result) (if (=alpha $saved-key $cycle) $result (empty))))) (case $hits ( (() (let* (($result (proof-depends-on-goal-seen? $pid $gid $cycle (cons -1 ()))) (($saved-key $stored-result) (copy_term (quote ($cycle $result)))) ($_cache (once (add-atom &proof_cycle_cache ($pid $gid $saved-key $stored-result))))) $result)) ((cons $result $_rest) $result)))))
(= (proof-depends-on-goal-seen? $pid $gid $cycle (cons $seen-pid $rest-seen-pids)) (let $seen-pids (cons $seen-pid $rest-seen-pids) (if (stored-list-member? $pid $seen-pids) false (if (cyclic-dependency? $pid $gid $cycle) true (proof-fold-flat-semidet (depends-step $gid $cycle (cons $pid $seen-pids)) false (proof-children-by-id $pid))))))
(: candidate-cycle-key (-[semidet]-> Number ProofKind (| ProofOutputKey ClosedGoalKey)))
(= (candidate-cycle-key $gid $kind) (let* (((stored-goal-row $_gid $_depth $goal $_expanded $_pending) (goal-by-id $gid))) (if (goal-has-type-vars? $goal) (candidate-output-key (candidate-kind-term $kind)) closed-goal)))
(: candidate-is-cyclic? (-[semidet]-> Number ProofKind (List Number) Bool))
(= (candidate-is-cyclic? $gid $kind $children) (if (== $children ()) false (let $cycle (candidate-cycle-key $gid $kind) (proof-fold-flat-semidet (depends-step $gid $cycle ()) false $children))))
