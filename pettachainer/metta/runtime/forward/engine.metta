;; Forward candidate acceptance: the canonical store a materializing query
;; writes through.
;; Apply cache bookkeeping for canonical changes made outside a forward run.
(: forward-apply-unqueued-change!
   (-[det]-> ForwardOutputChange (| (List $none) Bool)))
(= (forward-apply-unqueued-change! $change)
   (once
      (case $change
         ((no-forward-change ())
          ((forward-output-removed $old)
             (forward-maintain-aggregates!
                aggregate-remove $old))
          ((forward-output-added $_fact) ())
          ((forward-output-replaced $_old $_fact) ())))))

(: forward-strict-evidence-subset?
   (-[det]-> (List Evidence) (List Evidence) Bool))
(= (forward-strict-evidence-subset? $subset $superset)
   (and (evidence-subset? $subset $superset)
      (not (evidence-subset? $superset $subset))))

;; These predicates are mutually recursive; publish both contracts before
;; either body so determinism and bound-Bool certification can analyze the SCC.
(: forward-proof-list-refines? (-[det]-> (List Proof) (List Proof) Bool))
(: forward-proof-refines? (-[det]-> Proof Proof Bool))
(= (forward-proof-list-refines? () $new) (== $new ()))
(= (forward-proof-list-refines? (cons $old-first $old-rest) $new)
   (case $new (
      (() false)
      ((cons $new-first $new-rest)
         (if (forward-proof-refines? $old-first $new-first)
            (forward-proof-list-refines? $old-rest $new-rest)
            false)))))

;; A proof refines another when it has the same rule skeleton and only replaces
;; children by merges containing the earlier child. This distinguishes a
;; genuinely updated application, pToQ(p1) -> pToQ(merge(p1,p2)), from a longer
;; cyclic path such as seed -> keepLoop(seed).
(= (forward-proof-refines? $old $new)
   (if (== $old $new) true
      (if (is-expr $new)
         (if (= $new (merge/revision $left $right))
            (if (forward-proof-refines? $old (brand Proof $left)) true
               (forward-proof-refines? $old (brand Proof $right)))
            (if (if (is-expr $old)
                   (== (car-atom $old) (car-atom $new))
                   false)
               (let*
                  (($old-tail (cdr-atom $old))
                   ($new-tail (cdr-atom $new))
                   ($old-children (proof-children $old-tail))
                   ($new-children (proof-children $new-tail)))
                  (forward-proof-list-refines?
                     $old-children $new-children))
               false))
         false)))

(: forward-candidate-refines?
   (-[det]-> (Statement KBContext Proof TV) (List Evidence)
       (Statement KBContext Proof TV) (List Evidence) Bool))
(= (forward-candidate-refines? $old-fact $old-ev $new-fact $new-ev)
   (let*
      (($old-proof (proof-atom-proof $old-fact))
       ($new-proof (proof-atom-proof $new-fact)))
      (and (forward-strict-evidence-subset? $old-ev $new-ev)
         (forward-proof-refines? $old-proof $new-proof))))

;; A larger evidence set for the same output supersedes the partial estimate
;; even when the new TV has lower confidence.  Disjoint candidates remain in
;; the frontier and are revised together.  Incomparable overlapping candidates
;; retain the existing conservative policy of keeping only the stronger one.
(: ForwardFrontierOrder Type)
(: frontier-old-wins ForwardFrontierOrder)
(: frontier-new-wins ForwardFrontierOrder)
(: frontier-same ForwardFrontierOrder)
(: frontier-incomparable ForwardFrontierOrder)
(: forward-frontier-compare
   (-[det]-> (Statement KBContext Proof TV) (List Evidence)
       (Statement KBContext Proof TV) (List Evidence) ForwardFrontierOrder))
(= (forward-frontier-compare $old-fact $old-ev $new-fact $new-ev)
   (let*
      (($old-proof (proof-atom-proof $old-fact))
       ($new-proof (proof-atom-proof $new-fact)))
      (if (== $old-proof $new-proof) frontier-same
         (if (projection-dominates? $old-proof $new-proof) frontier-old-wins
            (if (projection-dominates? $new-proof $old-proof) frontier-new-wins
               (if (forward-candidate-refines?
                      $old-fact $old-ev $new-fact $new-ev) frontier-new-wins
                  (if (forward-candidate-refines?
                         $new-fact $new-ev $old-fact $old-ev) frontier-old-wins
                     (if (evidence-sets-overlap? $old-ev $new-ev)
                        (if (>= (term-confidence $old-fact)
                                (term-confidence $new-fact))
                           frontier-old-wins
                           frontier-new-wins)
                        frontier-incomparable))))))))

(: forward-frontier-has-exact?
   (-[det]-> ForwardOutputKey
       (Statement KBContext Proof TV) (List Evidence) Bool))
(= (forward-frontier-has-exact?
      (forward-output-key $kb $type) $fact $ev)
   (let $hash
      (forward-output-index-hash
         (forward-output-key $kb $type))
      (space-row-present? &forward_frontier
         (forward-frontier-row $hash $type $kb $fact $ev))))

(: forward-frontier-rejects?
   (-[det]-> ForwardOutputKey
       (Statement KBContext Proof TV) (List Evidence) Bool))
(= (forward-frontier-rejects?
      (forward-output-key $kb $type) $fact $ev)
   (let $hash
      (forward-output-index-hash
         (forward-output-key $kb $type))
      (not (==
         (collapse
            (once
               (match &forward_frontier
                  (forward-frontier-row
                     $hash $type $kb $old-fact $old-ev)
                  (if (== (forward-frontier-compare
                             $old-fact $old-ev $fact $ev)
                          frontier-old-wins)
                     true
                     (empty)))))
         ()))))

(: forward-prune-frontier-for!
   (-[det]-> ForwardOutputKey
       (Statement KBContext Proof TV) (List Evidence) (List $none)))
(= (forward-prune-frontier-for!
      (forward-output-key $kb $type) $fact $ev)
   (let $hash
      (forward-output-index-hash
         (forward-output-key $kb $type))
      (collapse
         (match &forward_frontier
            (forward-frontier-row
               $hash $type $kb $old-fact $old-ev)
            (case (forward-frontier-compare $old-fact $old-ev $fact $ev) (
               (frontier-old-wins ())
               (frontier-incomparable ())
               ($_superseded
                  (remove-atom &forward_frontier
                     (forward-frontier-row
                        $hash $type $kb $old-fact $old-ev)))))))))

(: forward-record-inheritance-nodes! (-[det]-> (Statement KBContext Proof TV) Bool Atom))
(= (forward-record-inheritance-nodes! $fact $record-subject?)
   (case $fact (
      (((Inheritance $subj $concept) ($kbid $_ctx $_vars) $_prf $_tv)
         (if (is-var $subj) ()
            (let* (($typed-kb (brand KB $kbid))
                   ($typed-subj (brand Statement $subj))
                   ($_subject (if $record-subject? (record-inheritance-subject! $typed-kb $typed-subj) ())))
               (record-inheritance-nodes! $typed-kb $typed-subj (brand Statement $concept)))))
      ($_other ()))))

(: forward-add-frontier-row!
   (-[nondet]-> ForwardOutputKey
      (Statement KBContext Proof TV) (List Evidence)
      Bool
       (List $none)))
(= (forward-add-frontier-row!
      (forward-output-key $kb $type) $fact $ev $record-subject?)
   (let*
      (($hash
          (forward-output-index-hash
             (forward-output-key $kb $type)))
       ($_nodes
          (forward-record-inheritance-nodes! $fact $record-subject?))
       ($_frontier
          (chainer-add-atom &forward_frontier
             (forward-frontier-row
                $hash $type $kb $fact $ev))))
      ()))

(: forward-candidate-upsert!
   (-[nondet]-> ForwardDerived Bool ForwardOutputChange))
(= (forward-candidate-upsert!
      (forward-derived $fact $ev) $record-subject?)
   (let $output-key (forward-fact-key $fact)
      (if (forward-frontier-has-exact? $output-key $fact $ev) no-forward-change
         (let $canonical-rows
            (collapse (once (forward-output-row-for-fact $fact)))
            (if (== $canonical-rows ())
               (let $_add
                  (forward-add-frontier-row!
                     $output-key $fact $ev $record-subject?)
                  (forward-store-output-candidate!
                     $output-key (forward-derived $fact $ev)))
               (let (forward-derived $canonical $canonical-ev)
                  (first-forward-output-row $canonical-rows)
                  (if (not (evidence-sets-overlap? $canonical-ev $ev))
                     ;; Disjoint evidence cannot evict an existing frontier
                     ;; branch.  Merge directly with the cached canonical fact
                     ;; instead of scanning and folding the frontier.
                     (let*
                        (($_add
                            (forward-add-frontier-row!
                               $output-key $fact $ev $record-subject?))
                         (($merged $merged-ev)
                            (merge-proof-candidates
                               (data $canonical $canonical-ev)
                               (data $fact $ev))))
                        (forward-store-output-candidate!
                           $output-key
                           (forward-derived $merged $merged-ev)))
                     (if (forward-frontier-rejects? $output-key $fact $ev)
                        no-forward-change
                        (let*
                           (($_prune
                                (forward-prune-frontier-for!
                                   $output-key $fact $ev))
                            ($_add
                                (forward-add-frontier-row!
                                   $output-key $fact $ev
                                   $record-subject?)))
                           (forward-refresh-output-key! $output-key))))))))))
