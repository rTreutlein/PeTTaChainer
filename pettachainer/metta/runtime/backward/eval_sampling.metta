;; Keep this typed step separate: a lifted lambda shares its local view across iterations.
(: sk-outcome-step (-[semidet]-> (List SkeletonReference) (List SkeletonValue) SkeletonReference (List SkeletonValue)))
(= (sk-outcome-step $references $kept $reference)
   (let (sk-reference $class $view) $reference
                      (if (if (== $class no-class) false
                             (fold-semidet (sk-outranked-step $reference) false $references))
                         $kept (cons $view $kept))))
;; A stored forward premise reads its merged facts; RuleTruth reads its learned
;; value through the supplied capability. Folds, missing facts, open statements
;; and settled variants do not supply outcome predictions.
(: sk-stored-premise-step (-[semidet]-> SkeletonValueReader EvidenceSet Atom EvidenceSet))
(= (sk-stored-premise-step $reader $ev $premise)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn)))
      (case $premise (
         ((CPU $fun $args $res)
            (if (if (aggregate-fold-function? $fun) true (== $fun SettlesFormula)) (empty)
               (case (collapse (once (cpu-call 0 $fun $args))) (
                  ((cons $result $_rest) (if (= $res $result) $ev (empty)))))))
         (($type $kbctx $proof $tv)
            (if (if (head-is? $type RuleTruth) (= $type (RuleTruth $_implication)) false)
               (case ($read (sk-key $type $kbctx) sk-any-filter ()) (
                  ((sk-val ($_type $_kbctx $truth-proof $truth) $truth-ev $_deps)
                     (if (= ($proof $tv) ($truth-proof $truth)) (evidence-union $truth-ev $ev) (empty)))
                  ($_none (empty))))
               (if (== (extract-vars $type) ())
                  (case (stored-statement-candidate (brand Statement $type) (brand KBContext $kbctx) false) (
                     ((forward-derived ($_stype $_skbctx $stored-proof $stored-tv) $stored-ev)
                        (if (= ($proof $tv) ($stored-proof $stored-tv)) (evidence-union $stored-ev $ev) (empty)))))
                  (empty))))))))

;; The views the forward rules concluding a statement give from its
;; antecedents' stored facts, when there are several and their evidence is
;; disjoint.
(: sk-outcome-views (-[det]-> SkeletonValueReader Atom Atom (List STVType)))
(= (sk-outcome-views $reader $type $kbctx)
   (case (collapse (once
         (let* (($views (collapse (match ccls_index (($type $kbctx (by $rule $premise) $tv) $_id $args)
                          (let $ev (fold-semidet (sk-stored-premise-step $reader) (ev-set 0) $args)
                             (sk-val (assemble-runtime-fact $type $kbctx (by $rule $premise) $tv) $ev 0)))))
                ($references (map-semidet sk-reference-of $views))
                ($specific (fold-semidet (sk-outcome-step $references) () $references)))
            (fold-semidet sk-disjoint-view-step (data () (ev-set 0)) (sk-sample-groups (the (List SkeletonValue) $specific)))))) (
      ((cons $found $_none)
         (case $found (
            (((cons $_one ()) $_seen) ())
            (($tvs $_evidence) (the (List STVType) $tvs)))))
      (() ()))))

;; An outcome is predicted by each mode from its views and the prior before
;; it, then counted in the prior.
(: sk-score-outcome (-[semidet]-> SkeletonValueReader CombinationTally Atom CombinationTally))
(= (sk-score-outcome $reader (combination-tally $n $sum $revision $odds $noisy) ($type $kbctx $_proof (STV $outcome $_c)))
   (let* (($y (the Number $outcome))
          ($prior (STV (/ (+ $sum 1.0) (+ $n 2.0)) (count-confidence $n))))
      (case (sk-outcome-views $reader $type $kbctx) (
         ((cons $first $rest)
            (combination-tally (+ $n 1) (+ $sum $y)
               (+ $revision (sk-log-score $y (fold-semidet mergetvs $first $rest)))
               (+ $odds (sk-log-score $y (fold-semidet (sk-mode-step odds $prior) $first $rest)))
               (+ $noisy (sk-log-score $y (fold-semidet (sk-mode-step noisy-or $prior) $first $rest)))))
         (() (combination-tally (+ $n 1) (+ $sum $y) $revision $odds $noisy))))))

;; The mode a consequent's outcomes prefer, with its prior: the better product
;; mode once its Bayes factor over revision is at least 10, else revision.
;; Pending outcomes are scored first.
(: sk-combination-mode (-[semidet]-> SkeletonValueReader KB Statement Atom))
(= (sk-combination-mode $reader $kb $type)
   (let* (($head (if (is-expr $type) (car-atom $type) $type))
          ($hash (index-hash (quote ($kb $head))))
          ($stored (case (collapse (match &combination_tally ($hash $kb $head $tally) $tally)) (
                      ((cons $found $_rest) $found)
                      (() (combination-tally 0 0.0 0.0 0.0 0.0)))))
          ($pending (collapse (match &combination_pending ($hash $kb $head $outcome) $outcome)))
          ($current
             (if (== $pending ()) $stored
                (let* (($scored (fold-semidet (sk-score-outcome $reader) $stored $pending))
                       ($_drained (remove-data-rows! &combination_pending (quote ($hash $kb $head $_outcome))))
                       ($_old (remove-data-rows! &combination_tally (quote ($hash $kb $head $_tally))))
                       ($_new (add-space-atom! &combination_tally (make-space-row4 $hash $kb $head $scored))))
                   $scored))))
      (case $current (
         ((combination-tally $n $sum $revision $odds $noisy)
            (let $prior (STV (/ (+ $sum 1.0) (+ $n 2.0)) (count-confidence $n))
               (if (>= $odds $noisy)
                  (if (>= (- $odds $revision) 2.302585092994046) (data odds $prior) (data revision $prior))
                  (if (>= (- $noisy $revision) 2.302585092994046) (data noisy-or $prior) (data revision $prior)))))))))
