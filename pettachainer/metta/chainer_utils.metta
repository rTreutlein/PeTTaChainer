(: tv-confidence (-[det]-> $truth-value Number))
(= (tv-confidence $tv)
   (if (is-var $tv) 1.0
      (case $tv
         (((STV $_s $c) (if (is-var $c) 1.0 $c))
          ((CTV $pos $neg) (min (tv-confidence $pos) (tv-confidence $neg)))
          ($_other 1.0)))))

(: goal-has-type-vars?
   (-[det]-> (| Goal
          (Statement KBContext Proof TV))
       Bool))
(= (goal-has-type-vars? $goal)
   (case $goal
      (((CPU $fun $args $res)
          (if
             (== (extract-vars (CPU $fun $args $res)) ())
             false true))
       (($type ($_kbid $_ctx $vars) $_prf $_tv)
          (if (== (extract-vars $type) ())
             (if (== $vars Nil) false true)
             true)))))

(: goal-key
   (-[det]-> (| Goal
          (Statement KBContext Proof TV))
       Expression))
(= (goal-key $goal)
   (case $goal
      (((CPU $fun $args $res)
          (sealed
             (extract-vars (CPU $fun $args $res))
             (CPU $fun $args $res)))
       (($type ($kbid $ctx $vars) $_prf $_tv)
          (let $sealed-goal
             (sealed
                (extract-vars (quote ($type $vars)))
                (quote ($type $vars)))
             (quote ($sealed-goal ($kbid $ctx))))))))

(: normalize-expected-stv (-[det]-> $truth-value STVType))
(= (normalize-expected-stv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (case $tv
         (((STV $s $c)
             (STV
                (if (is-var $s) 1.0 $s)
                (if (is-var $c) 1.0 $c)))
          ($other (the STVType $other))))))

;; Re-establish a TV read from untyped storage without first attaching one
;; broad union guard to an open constructor. Dispatching on the runtime tag
;; lets CTV fields receive their precise STV constraints immediately.
(: checked-stored-stv (-[det]-> Expression STVType))
(= (checked-stored-stv $tv)
   (case $tv
      (((STV $s $c)
          (STV (the Number $s) (the Number $c)))
       ($other (the STVType $other)))))

(: checked-stored-tv (-[det]-> Expression TV))
(= (checked-stored-tv $tv)
   (if (is-var $tv)
      (the TV $tv)
      (case $tv
         (((STV $s $c)
             (STV (the Number $s) (the Number $c)))
          ((CTV $pos $neg)
             (CTV
                (checked-stored-stv $pos)
                (checked-stored-stv $neg)))
          (no-evidence no-evidence)
          ($other (the TV $other))))))

(: normalize-expected-tv (-[det]-> $truth-value TV))
(= (normalize-expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (case $tv
         (((STV $s $c) (STV (if (is-var $s) 1.0 $s) (if (is-var $c) 1.0 $c)))
          ((CTV $pos $neg)
             (CTV
                (normalize-expected-stv $pos)
                (normalize-expected-stv $neg)))
          (no-evidence no-evidence)
          ($other (the TV $other))))))

(: normalize-expected-ctv
   (-[semidet]-> $truth-value CTVType))
(= (normalize-expected-ctv
      (CTV $pos $neg))
   (CTV
      (normalize-expected-stv $pos)
      (normalize-expected-stv $neg)))

(: normalize-expected-evidence-tv
   (-[semidet]-> $truth-value (| STVType CTVType)))
(= (normalize-expected-evidence-tv $tv)
   (if (is-var $tv)
      (STV 1.0 1.0)
      (case $tv
         (((STV $s $c)
             (STV
                (if (is-var $s) 1.0 $s)
                (if (is-var $c) 1.0 $c)))
          ((CTV $pos $neg)
             (CTV
                (normalize-expected-stv $pos)
                (normalize-expected-stv $neg)))
          ($_other (empty))))))

;; CPU arguments are formula-dependent and enter through a generic execution
;; record. Normalize known TV constructors without reflective checks; retain
;; an explicit checked fallback for invalid or user-extended TV values.
(: expected-tv (-[det]-> $candidate TV))
(= (expected-tv $value) (normalize-expected-tv $value))

;; Expected TVs dispatch directly on the known formula set instead of going
;; through reduce: reduce's runtime dispatch (fun/1 + current_predicate +
;; current_op per call) dominated backward-search profiles. Failure modes are
;; preserved -- a formula clause that does not match (or yields empty) makes
;; this function fail exactly like the reduce-based call did.
(: cpu-expected-tv
   (-[nondet]-> $formula $arguments  (| TV (List Atom))))
(= (cpu-expected-tv $fun ($a))
   (if (== $fun NotFormula)
      (if (is-var $a)
         (STV 1.0 1.0)
         (NotFormula (normalize-expected-stv $a)))
      ()))

(= (cpu-expected-tv $fun ($a $b))
   (case $fun
      ((CTVModusPonensFormula
         (CTVModusPonensFormula
            (normalize-expected-evidence-tv $a)
            (normalize-expected-ctv $b)))
       (CTVFormula
         (CTVFormula
            (normalize-expected-evidence-tv $a)
            (normalize-expected-ctv $b)))
       (AndFormula
         (AndFormula
            (normalize-expected-stv $a)
            (normalize-expected-stv $b)))
       (OrFormula
         (OrFormula
            (normalize-expected-stv $a)
            (normalize-expected-stv $b)))
       (LikelierThanFormula
         (LikelierThanFormula
            (normalize-expected-stv $a)
            (normalize-expected-stv $b)))
       (()
         (cons ()
            (cons (expected-tv $a)
               (cons (expected-tv $b) ()))))
       ($_other ()))))

(= (cpu-expected-tv $fun ($a $b $ctv))
   (if (== $fun CTVInversionFormula)
      (let*
         (($na (expected-tv $a))
          ($nb (expected-tv $b))
          ($nctv (expected-tv $ctv))
          ($confidence
             (* (min-atom
                  ((tv-confidence $na)
                   (tv-confidence $nb)
                   (tv-confidence $nctv)))
                0.9)))
         (if (or (is-var $a) (is-var $b))
            (CTV (STV 1.0 $confidence) (STV 1.0 $confidence))
            (CTVInversionFormula $na $nb $nctv)))
      ()))

(: first-cpu-expected-tv
   (-[det]-> $formula $arguments (| TV (List Atom))))
(= (first-cpu-expected-tv $fun $args)
   (let $res (let $hits (collapse (cpu-expected-tv $fun $args)) (if (== $hits ()) () (car-atom $hits)))
      $res))

(: cpu-expected-confidence (-[det]-> $formula $arguments Number))
(= (cpu-expected-confidence $fun $args)
   (let $res (first-cpu-expected-tv $fun $args)
      (if (== $res ()) 1.0 (tv-confidence $res))))

(: premises-expected-confidence-step
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       Number))
(= (premises-expected-confidence-step $prem $rest)
   (case $prem
      (((CPU $fun $args $res)
          (if (= $rest
                 (cons
                    (CPU CTVModusPonensFormula
                       (quote ($res $rule-tv))
                       $_mp-tv)
                    $remaining))
             (let $expected (first-cpu-expected-tv $fun $args)
                (if (== $expected ())
                   (min
                      (term-confidence (CPU $fun $args $res))
                      (premises-expected-confidence $rest))
                   (min-atom
                      ((tv-confidence $expected)
                       (cpu-expected-confidence
                          CTVModusPonensFormula
                          (quote ($expected $rule-tv)))
                       (premises-expected-confidence
                          (cdr-atom $rest))))))
             (min
                (term-confidence (CPU $fun $args $res))
                (premises-expected-confidence $rest))))
       ($other
          (min
             (term-confidence $other)
             (premises-expected-confidence $rest))))))

(: term-confidence
   (-[det]-> (| Goal
          (Statement KBContext Proof TV))
       Number))
(= (term-confidence $proof-term)
   (case $proof-term
      (((CPU $fun $args $res)
          (let $base
             (if (is-var $res)
                (cpu-expected-confidence $fun $args)
                (cpu-result-confidence $res))
             (if (== $fun AndMarginalProjection) (* 0.99 $base) $base)))
       (($_type ($_kbid $_ctx $_vars) $prf $tv)
          ;; Historically the marginal-projection arm of proof-score matched
          ;; an unbound proof token first, applying this optimism discount but
          ;; also binding the caller's variable. Preserve the search heuristic
          ;; explicitly without mutating an open goal.
          (if (is-var $prf)
             (* 0.99 (tv-confidence $tv))
             (proof-score
                (brand Proof $prf) $tv)))
       ($_other 0.0))))

(: cpu-result-confidence (-[det]-> $result Number))
(= (cpu-result-confidence $result)
   (case $result (
      ((STV $_strength $_confidence)
         (tv-confidence $result))
      ((CTV $_positive $_negative)
         (tv-confidence $result))
      ($_other 1.0))))

(: proof-score (-[det]-> Proof TV Number))
(= (proof-score $prf $tv)
   (case $prf (
      ((marginal-proj $_idx $_inner) (* 0.99 (tv-confidence $tv)))
      ($_other (tv-confidence $tv)))))

(: premises-expected-confidence
   (-[det]-> (List (| Goal (Statement KBContext Proof TV))) Number))
(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (premises-expected-confidence-step $prem $rest))

(: premise-cons
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       (List (| Goal (Statement KBContext Proof TV)))))
(= (premise-cons $premise $rest)
   (cons $premise $rest))

(: score-tv (-[det]-> Number STVType))
(= (score-tv $score) (STV 1.0 (max 0.0 (min 1.0 $score))))

(: optimistic-revision-score (-[det]-> Number Number Number))
(= (optimistic-revision-score $current-score $candidate-score)
   (tv-confidence
      (merge-stvs
         (score-tv $current-score)
         (score-tv $candidate-score))))

(: rule-marginal-score (-[det]-> (| Number NoCurrentScore) Number Number))
(= (rule-marginal-score $current-score $candidate-score)
   (if (== $current-score no-current)
      $candidate-score
      (let $score (the Number $current-score)
         (max 0.000001
            (- (max $candidate-score (optimistic-revision-score $score $candidate-score))
               $score)))))

(: frontier-proof-score (-[det]-> $proof-output Number Number))
(= (frontier-proof-score $output $score)
   (if (= $output (CPU $_fun $_args $_res))
      (max 0.000001 $score)
      $score))

(: bounded-agenda-target-size (-[det]-> Number Number))
(= (bounded-agenda-target-size $steps) (min 1000 (max 1 $steps)))
(: bounded-agenda-prune-factor (-[det]-> Number))
(= (bounded-agenda-prune-factor) 64)

(: set-bounded-agenda-pruning (-[det]-> Bool Bool))
(= (set-bounded-agenda-pruning $enabled) (change-state! bounded_agenda_pruning $enabled))
(: bounded-agenda-pruning? (-[det]-> Bool))
(= (bounded-agenda-pruning?)
   (let $state-values
      (collapse
         (catch
            (get-state bounded_agenda_pruning)))
      (if (== $state-values ())
         true
         (if-error-bool
            (car-atom $state-values) true))))

(: heap-take-best (-[det]-> Number (Heap $item) (Heap $item) (Heap $item)))
(= (heap-take-best $count $src $dst)
   (if (<= $count 0)
      $dst
      (let $pops
         (collapse (heap_pop $src))
         (if (== $pops ())
            $dst
            (let ($key $item $rest)
               (car-atom $pops)
               (let $next-values
                  (collapse
                     (add_to_heap
                        $dst (the Number $key) $item))
                  (if (== $next-values ())
                     $dst
                     (heap-take-best
                        (- $count 1)
                        $rest
                        (car-atom $next-values)))))))))

(: heap-prune-to-size (-[det]-> Number (Heap $item) (Heap $item)))
(= (heap-prune-to-size $target $agenda)
   (let $empty-values (collapse (empty_heap))
      (if (== $empty-values ())
         $agenda
         (heap-take-best
            $target $agenda
            (car-atom $empty-values)))))

(: bounded-agenda-prune (-[det]-> Number (Heap $item) (Heap $item)))
(= (bounded-agenda-prune $steps $agenda)
   (if (bounded-agenda-pruning?)
      (let*
         (($target (bounded-agenda-target-size $steps))
          ($size-values
             (collapse (heap_size $agenda)))
          ($size
             (if (== $size-values ())
                0
                (the Number
                   (car-atom $size-values))))
          ($threshold (* $target (bounded-agenda-prune-factor))))
         (if (> $size $threshold)
            (heap-prune-to-size $target $agenda)
            $agenda))
      $agenda))

(: RevisionMergeProof
   (-[det]-> (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)))

(: assemble-runtime-fact
   (-[det]-> Statement KBContext Proof TV
       (Statement KBContext Proof TV)))
(= (assemble-runtime-fact $type $kb $proof $tv)
   (quote ($type $kb $proof $tv)))

(: assemble-contextual-runtime-fact
   (-[det]-> Statement KB Atom Atom Proof TV
       (Statement KBContext Proof TV)))
(= (assemble-contextual-runtime-fact
      $type $kbid $context $variables $proof $tv)
   (quote
      ($type ($kbid $context $variables) $proof $tv)))

;; Dynamic spaces erase nominal roles. Reconstruct a fact at that boundary and
;; validate only the truth-value payload whose numeric fields affect inference.
(: assemble-stored-runtime-fact
   (-[det]-> Atom Atom Atom Atom
       (Statement KBContext Proof TV)))
(= (assemble-stored-runtime-fact $type $kb $proof $tv)
   (quote ($type $kb $proof $tv)))

;; Scalar ids recovered from erased spaces are checked individually at their
;; lookup boundary, avoiding a traversal of the collected list.
(: stored-number (-[det]-> Atom Number))
(= (stored-number $value)
   (the Number $value))

(: first-number (-[semidet]-> (List Number) Number))
(= (first-number (cons $first $_rest)) $first)

;; Evidence rows are written only by typed constructors, but spaces erase that
;; element role. Rebuild the list while restoring the erased Evidence brands;
;; the reflective fallback is reached only for a malformed non-list row.
(: stored-evidence-list (-[det]-> Atom (List Evidence)))
(= (stored-evidence-list $values)
   (case $values (
      (() ())
      ((cons $entry $rest)
         (cons (brand Evidence $entry)
            (stored-evidence-list $rest)))
      ($_malformed
         (the (List Evidence) $values)))))

(: first-evidence-list
   (-[semidet]-> (List (List Evidence)) (List Evidence)))
(= (first-evidence-list (cons $first $_rest)) $first)

;; Shared by backward proof construction and forward candidate handling, so it
;; lives before either chainer module is loaded.
(: forward-fact-evidence
   (-[det]-> Statement KBContext Proof TV (List Evidence)))
(= (forward-fact-evidence $type $kb $prf $tv)
   (let*
      (($fact (quote ($type $kb $prf $tv)))
       ($hash (term_hash (quote ($kb $type))))
       ($hits
          (collapse
             (once
                (match &forward_canonical_evidence
                   (forward-canonical-evidence-row
                      $hash $type $kb $fact $ev)
                   (stored-evidence-list $ev))))))
      (if (== $hits ())
         (let $frontier-hits
            (collapse
               (once
                  (match &forward_frontier
                     (forward-frontier-row
                        $hash $type $kb $fact $ev)
                     (stored-evidence-list $ev))))
            (if (== $frontier-hits ())
               (cons (fact-ev $kb $prf $type) ())
               (first-evidence-list $frontier-hits)))
         (first-evidence-list $hits))))

(: revision-merge-tv (-[det]-> TV TV TV))
(= (revision-merge-tv $tv1 $tv2)
   (case $tv1
      (((STV $m1 $c1)
          (case $tv2
             (((STV $m2 $c2)
                 (merge-stv-fields $m1 $c1 $m2 $c2))
              ($_other-tv $tv1))))
       ($_other $tv1))))

(= (RevisionMergeProof ($type1 $kb $prf1 $tv1) ($_type2 $_kb2 $prf2 $tv2))
   (assemble-runtime-fact
      $type1 $kb
      (brand Proof (merge/revision $prf1 $prf2))
      (revision-merge-tv $tv1 $tv2)))

(: proof-atom-proof
   (-[det]-> (Statement KBContext Proof TV) Proof))
(= (proof-atom-proof ($_type $_kb $prf $_tv)) $prf)

(: foreach-flat
   (-[$e]-> (-[$e]-> $item $effect)
       (List $item) (List $none)))
(= (foreach-flat $f ()) ())
(= (foreach-flat $f (cons $x $xs))
   (progn ($f $x) (foreach-flat $f $xs)))

(: chainer-acyclic-term? (-[det]-> $term Bool))
(= (chainer-acyclic-term? $term)
   (== (collapse
          (callPredicate (Predicate (cyclic_term $term))))
       ()))

(: chainer-add-atom
   (-[semidet]-> $space $expression  (| Bool (List $no-result))))
(= (chainer-add-atom $space $expr)
   (if (chainer-acyclic-term? $expr)
      (add-atom $space $expr)
      (empty)))

;; Build erased, raw atom-space rows without letting a variable first field be
;; interpreted as a function head.  The nominal result also proves to
;; add-atom that the row is bound and nonempty.
(: make-space-pair (-[det]-> $left $right SpaceAtom))
(= (make-space-pair $left $right)
   (brand SpaceAtom
      (cons $left (cons $right ()))))

(: make-space-row3
   (-[det]-> $first $second $third SpaceAtom))
(= (make-space-row3 $first $second $third)
   (brand SpaceAtom
      (cons $first
         (cons $second
            (cons $third ())))))

(: make-space-row4
   (-[det]-> $first $second $third $fourth SpaceAtom))
(= (make-space-row4 $first $second $third $fourth)
   (brand SpaceAtom
      (cons $first
         (cons $second
            (cons $third
               (cons $fourth ()))))))

(: add-space-atom! (-[det]-> $space SpaceAtom Bool))
(= (add-space-atom! $space $row)
   (add-atom $space $row))

(: next-search-id (-[det]-> CounterKey Number))
(= (next-search-id $key)
   (let*
      (($state-values (collapse (catch (get-state $key))))
       ($n
          (if (== $state-values ())
             0
             (if-error-number (car-atom $state-values) 0))))
      (progn (change-state! $key (+ $n 1)) $n)))

(: next-gid (-[det]-> Number))
(= (next-gid) (next-search-id bwd_gid))

(: next-pid (-[det]-> Number))
(= (next-pid) (next-search-id bwd_pid))

(: cpu-call (-[nondet]-> Number $formula $arguments  $result))
(= (cpu-call $_steps $fun $args) (reduce (reduce (cons $fun $args))))

(: proof-stats-by-id
   (-[semidet]-> Number (Number (List Evidence))))
(= (proof-stats-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_gid $_output $_kind
            $score $ev $_children)
         (quote ($score $ev)))))

(: proof-term-leaf-head? (-[det]-> $head Bool))
(= (proof-term-leaf-head? $head) (is-member $head (() fact-ev CPU STV CTV)))

;; cdr-atom exposes the erased proof representation as an untyped list. This
;; is the boundary that restores the semantic Proof brand to each raw child.
(: proof-children (-[det]-> Atom (List Proof)))
(= (proof-children $children)
   (case $children (
      (() ())
      ((cons $child $rest)
         (cons
            (brand Proof $child)
            (proof-children $rest)))
      ($_other ()))))

(: proof-term-children-mode
   (-[det]-> $mode Proof (List Proof)))
(= (proof-term-children-mode $mode $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf)
         (let $children
            (if (== $head conjunction) (cdr-atom $prf)
               (if (== $mode proof-walk-in-kb)
                  (if (proof-term-leaf-head? $head)
                     ()
                     (cdr-atom $prf))
                  ()))
            (proof-children $children)))
      ()))

(: append-evidence
   (-[det]-> (List Evidence) (List Evidence) (List Evidence)))
(= (append-evidence $left $right)
   (case $left (
      (() $right)
      ((cons $head $tail)
         (cons $head (append-evidence $tail $right))))))

(: proof-term-evidence-children-mode
   (-[semidet]-> $mode (List Proof) (List Evidence)))
(= (proof-term-evidence-children-mode $mode ()) ())
(= (proof-term-evidence-children-mode $mode (cons $child $rest))
   (append-evidence
      (proof-term-evidence-list-mode $mode $child)
      (proof-term-evidence-children-mode $mode $rest)))

(: evidence-negate (-[det]-> Evidence Evidence))
(= (evidence-negate $ev)
   (case $ev (
      ((fact-ev $kb $prf $type) (not-fact-ev $kb $prf $type))
      ((not-fact-ev $kb $prf $type) (fact-ev $kb $prf $type))
      ($other (not-ev $other)))))

(: evidence-negate-list
   (-[det]-> (List Evidence) (List Evidence)))
(= (evidence-negate-list ()) ())
(= (evidence-negate-list (cons $ev $rest))
   (cons (evidence-negate $ev) (evidence-negate-list $rest)))

(: proof-term-negated? (-[det]-> Proof Bool))
(= (proof-term-negated? $prf)
   (if (is-expr $prf) (== (car-atom $prf) negated) false))

(: proof-from-atom (-[det]-> Atom Proof))
(= (proof-from-atom $proof) (brand Proof $proof))

(: kb-from-atom (-[det]-> Atom KB))
(= (kb-from-atom $kb) (brand KB $kb))

(: proof-term-evidence-list-mode
   (-[semidet]-> $mode Atom (List Evidence)))
(= (proof-term-evidence-list-mode $mode $prf)
   (case $prf (
      ((@ $_ref (proof-ref $pid))
         (let ($_score $evidence)
            (proof-stats-by-id (the Number $pid))
            $evidence))
      ((@ $_merge (merge/revision $left $right))
         (let*
            (($left-proof (brand Proof $left))
             ($right-proof (brand Proof $right)))
            (append-evidence
               (proof-term-evidence-list-mode $mode $left-proof)
               (proof-term-evidence-list-mode $mode $right-proof))))
      ($_other
         (let $proof (proof-from-atom $prf)
            (if (is-var $prf) ()
            (if (assumption-proof? $proof) ()
               (if (proof-term-negated? $proof)
                  (let $inner-proof
                     (brand Proof (car-atom (cdr-atom $proof)))
                     (evidence-negate-list
                        (proof-term-evidence-list-mode
                           $mode $inner-proof)))
                  (let $children (proof-term-children-mode $mode $proof)
                     (if (== $children ())
                        (cons (brand Evidence $prf) ())
                        (proof-term-evidence-children-mode $mode $children)))))))))))

(: proof-atom-evidence-set
   (-[semidet]-> (Statement KBContext Proof TV)
       (List Evidence)))
(= (proof-atom-evidence-set ($_type $kb $prf $_tv))
   (list_to_set
      (once
         (proof-term-evidence-list-mode
            proof-walk-in-kb (brand Proof $prf)))))

(: evidence-intersection
   (-[det]-> (List Evidence) (List Evidence) (List Evidence)))
(= (evidence-intersection $set-a $set-b)
   (fold-flat
      (evidence-intersection-step $set-b)
      () $set-a))

(: evidence-member?
   (-[det]-> Evidence (List Evidence) Bool))
(= (evidence-member? $entry $entries)
   (case $entries (
      (() false)
      ((cons $head $tail)
         (if (== $entry $head)
            true
            (evidence-member? $entry $tail))))))

(: evidence-subtraction
   (-[det]-> (List Evidence) (List Evidence) (List Evidence)))
(= (evidence-subtraction () $_removed) ())
(= (evidence-subtraction (cons $entry $rest) $removed)
   (if (evidence-member? $entry $removed)
      (evidence-subtraction $rest $removed)
      (cons $entry
         (evidence-subtraction $rest $removed))))

(: evidence-intersection-step
   (-[det]-> (List Evidence) (List Evidence) Evidence (List Evidence)))
(= (evidence-intersection-step $set-b $acc $entry)
   (if (evidence-member? $entry $set-b)
      (cons $entry $acc)
      $acc))

(: evidence-sets-overlap?
   (-[det]-> (List Evidence) (List Evidence) Bool))
(= (evidence-sets-overlap? $set-a $set-b)
   (if (== (evidence-intersection $set-a $set-b) ())
      false
      true))

(: fact-evidence-only-step
   (-[det]-> (List Evidence) Evidence (List Evidence)))
(= (fact-evidence-only-step $acc $entry)
   (if (= $entry (rule-ev $_kb $_name))
      $acc
      (append-evidence $acc (cons $entry ()))))

(: fact-evidence-only
   (-[det]-> (List Evidence) (List Evidence)))
(= (fact-evidence-only ()) ())
(= (fact-evidence-only (cons $entry $rest))
   (if (= $entry (rule-ev $_kb $_name))
      (fact-evidence-only $rest)
      (cons $entry (fact-evidence-only $rest))))

;; The non-fact part of an evidence set (rule applications and hypotheses).
;; Two proofs are genuinely *dependent* only when these overlap: sharing a fact
;; is poolable (lifting-merge factors the shared fact out), whereas sharing a
;; rule or hypothesis means pooling would double-count its uncertainty.
(: non-fact-evidence
   (-[det]-> (List Evidence) (List Evidence)))
(= (non-fact-evidence $ev)
   (evidence-subtraction $ev (fact-evidence-only $ev)))
(: evidence-sets-dependent?
   (-[det]-> (List Evidence) (List Evidence) Bool))
(= (evidence-sets-dependent? $set-a $set-b)
   (evidence-sets-overlap? (non-fact-evidence $set-a) (non-fact-evidence $set-b)))

(: premise-evidence-overlap?
   (-[det]-> (List Evidence) (List Evidence) Bool))
(= (premise-evidence-overlap? $seen $pev)
   (evidence-sets-overlap? (fact-evidence-only $seen) (fact-evidence-only $pev)))

(: evidence-subset?
   (-[det]-> (List Evidence) (List Evidence) Bool))
(= (evidence-subset? $set-a $set-b)
   (== (evidence-subtraction $set-a $set-b) ()))

(: proof-term-contains-negated-list? (-[det]-> (List Proof) Bool))
(= (proof-term-contains-negated-list? ()) false)
(= (proof-term-contains-negated-list? (cons $child $rest))
   (if (proof-term-contains-negated? $child)
      true
      (proof-term-contains-negated-list? $rest)))

(: proof-term-contains-negated? (-[det]-> Proof Bool))
(= (proof-term-contains-negated? $prf)
   (if (is-var $prf) false
      (if (proof-term-negated? $prf) true
         (if (is-expr $prf)
            (proof-term-contains-negated-list?
               (proof-children (cdr-atom $prf)))
            false))))

(: rule-evidence-head (-[det]-> Proof Proof))
(= (rule-evidence-head $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf)
         (proof-from-atom
            (if (is-expr $head)
               (if (= $head (inverted $inv with $_pa $_pb)) $inv
                  (if (= $head (bi-forward $fwd)) $fwd
                     (if (= $head (bi-backward $bwd)) $bwd
                        (if (= $head (no_inverse $inner))
                           $inner
                           $head))))
               $head)))
      $prf))

(: rule-application-evidence
   (-[det]-> KBContext Proof (List Evidence)))
(= (rule-application-evidence $kb $prf)
   (once
      (if (= $kb ($kbid $_ctx $_vars))
         (let $name (rule-evidence-head $prf)
            (if (is-expr $name) ()
               (if (rule-evidence-registered?
                     (brand KB $kbid) (brand Proof $name))
                  (cons
                     (rule-ev
                        (brand KB $kbid) (brand Proof $name))
                     ())
                  ())))
         ())))

;; Forward materialization and backward rule application must attach exactly
;; the same provenance.  Otherwise a materialized rule result looks like a new
;; independent fact when the backward chainer rediscovers that rule path.
(: rule-result-evidence
   (-[semidet]-> (Statement KBContext Proof TV)
       (List Evidence) (List Evidence)))
(= (rule-result-evidence ($_type $kb $prf $_tv) $ev)
   (let*
      (($base
          (if (proof-term-contains-negated? $prf)
             (list_to_set (once (proof-term-evidence-list-mode proof-walk-in-kb $prf)))
             $ev))
       ($rule-ev (rule-application-evidence $kb $prf)))
      (if (== $rule-ev ())
         $base
         (list_to_set (append-evidence $base $rule-ev)))))

(: projection-proof-key
   (-[det]-> Proof (| ProjectionKey NoProjectionKey)))
(= (projection-proof-key $prf)
   (case $prf (
      ((marginal-proj $idx $base) (projection-key $idx $base))
      (((proj $idx $base) $_evidence) (projection-key $idx $base))
      ($_ no-projection-key))))

(: strict-projection-proof? (-[det]-> Proof Bool))
(= (strict-projection-proof? $prf)
   (case $prf (
      (((proj $_idx $_base) $_evidence) true)
      ($_ false))))

(: projection-dominates? (-[det]-> Proof Proof Bool))
(= (projection-dominates? $prf-a $prf-b)
   (let*
      (($key-a (projection-proof-key $prf-a))
       ($key-b (projection-proof-key $prf-b)))
      (if (== $key-a no-projection-key)
         false
         (if (== $key-a $key-b)
            (if (strict-projection-proof? $prf-a)
               (if (strict-projection-proof? $prf-b) false true)
               false)
            false))))

(: merge-proof-candidates
   (-[det]-> ((Statement KBContext Proof TV) (List Evidence))
       ((Statement KBContext Proof TV) (List Evidence))
       ((Statement KBContext Proof TV) (List Evidence))))
(= (merge-proof-candidates ($proof-a $ev-a) ($proof-b $ev-b))
   (if (== $proof-a $proof-b)
      (data
         $proof-a
         (list_to_set (append-evidence $ev-a $ev-b)))
      (let*
         (($overlap? (evidence-sets-overlap? $ev-a $ev-b))
          ($all-ev (list_to_set (append-evidence $ev-a $ev-b)))
          ($proof-token-a (proof-atom-proof $proof-a))
          ($proof-token-b (proof-atom-proof $proof-b)))
         (if (projection-dominates? $proof-token-a $proof-token-b)
            (data
               $proof-a $ev-a)
            (if (projection-dominates? $proof-token-b $proof-token-a)
               (data
                  $proof-b $ev-b)
               (if $overlap?
                  (if (>= (term-confidence $proof-a)
                          (term-confidence $proof-b))
                     (data
                        $proof-a $ev-a)
                     (data
                        $proof-b $ev-b))
                  (if (>= (term-confidence $proof-a)
                          (term-confidence $proof-b))
                     (data
                        (RevisionMergeProof $proof-a $proof-b) $all-ev)
                     (data
                        (RevisionMergeProof $proof-b $proof-a) $all-ev))))))))

(: proof-candidate-pair
   (-[det]-> (Statement KBContext Proof TV) (List Evidence)
       ((Statement KBContext Proof TV) (List Evidence))))
(= (proof-candidate-pair $proof $evidence)
   (data $proof $evidence))

(: merge-proof-atoms
   (-[semidet]-> (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)))
(= (merge-proof-atoms $proof-a $proof-b)
   (let ($merged $_ev)
      (merge-proof-candidates
         (proof-candidate-pair
            $proof-a (proof-atom-evidence-set $proof-a))
         (proof-candidate-pair
            $proof-b (proof-atom-evidence-set $proof-b)))
      $merged))

;; Base-rate cache operations are shared by forward chaining and the compiled
;; query runtime, so they must be available before either consumer is loaded.
(: base-rate-cache-entries (-[det]-> KB Statement (List BaseRateEntry)))
(= (base-rate-cache-entries $kbid $pattern)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $mode)
         (if (=alpha $stored $pattern)
            (base-rate $kbid $stored $tv $source $mode)
            (empty)))))

(: base-rate-cache-entries-for-mode
   (-[det]-> KB Statement $mode (List BaseRateEntry)))
(= (base-rate-cache-entries-for-mode $kbid $pattern $mode)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $emode)
         (if (and (=alpha $stored $pattern)
                  (or (== $emode any) (== $emode $mode)))
            (base-rate $kbid $stored $tv $source $emode)
            (empty)))))

(: base-rate-cache-remove-entry!
   (-[det]-> BaseRateEntry Bool))
(= (base-rate-cache-remove-entry! $entry)
   (remove-atom &base_rate_cache $entry))

(: base-rate-cache-remove! (-[det]-> KB Statement (List $none)))
(= (base-rate-cache-remove! $kbid $pattern)
   (let $_
      (foreach-flat base-rate-cache-remove-entry!
         (base-rate-cache-entries $kbid $pattern))
      ()))

(: base-rate-cache-remove-derived!
   (-[det]-> KB Statement $mode (List $none)))
(= (base-rate-cache-remove-derived! $kbid $pattern $mode)
   (let $_
      (foreach-flat base-rate-cache-remove-entry!
         (collapse
            (match &base_rate_cache
               (base-rate $kbid $stored $tv $source $mode)
               (if (and (not (== $source user)) (=alpha $stored $pattern))
                  (base-rate $kbid $stored $tv $source $mode)
                  (empty)))))
      ()))

(: cached-base-rate
   (-[nondet]-> KB Statement (List TV)))
(= (cached-base-rate $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) ()
         (let (base-rate $_kbid $_stored $tv $_source $_mode)
            (car-atom $entries)
            (cons $tv ())))))

(: base-rate-user-set? (-[det]-> KB Statement Bool))
(= (base-rate-user-set? $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) false
         (let (base-rate $_kbid $_stored $_tv $source $_mode)
            (car-atom $entries)
            (== $source user)))))

(: store-base-rate! (-[det]-> KB Statement TV (List $none)))
(= (store-base-rate! $kbid $pattern $tv)
   (let*
      (($stored (copy_term $pattern))
       ($_old (base-rate-cache-remove! $kbid $pattern))
       ($_new
          (add-atom &base_rate_cache
             (base-rate $kbid $stored $tv user any))))
      ()))

(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (store-base-rate! $kbid $pattern $tv))

(: clear-base-rate (-[det]-> KB Statement (List $none)))
(= (clear-base-rate $kbid $pattern)
   (base-rate-cache-remove! $kbid $pattern))

(: store-computed-base-rate!
   (-[det]-> KB Statement TV $mode (List $none)))
(= (store-computed-base-rate! $kbid $pattern $tv $mode)
   (if (base-rate-user-set? $kbid $pattern) ()
      (let*
         (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove-derived! $kbid $pattern $mode))
          ($_new
             (add-atom &base_rate_cache
                (base-rate $kbid $stored $tv computed $mode))))
         ())))

(: store-forward-base-rate!
   (-[det]-> KB Statement TV $mode (List $none)))
(= (store-forward-base-rate! $kbid $pattern $tv $mode)
   (if (== $tv no-evidence) ()
      (if (base-rate-user-set? $kbid $pattern) ()
         (let*
            (($stored (copy_term $pattern))
             ($_old (base-rate-cache-remove-derived! $kbid $pattern $mode))
             ($_new
                (add-atom &base_rate_cache
                   (base-rate $kbid $stored $tv forward-approx $mode))))
            ()))))

(: invalidate-computed-base-rates! (-[det]-> KB (List $none)))
(= (invalidate-computed-base-rates! $kbid)
   (let*
      (($entries
          (collapse
             (match &base_rate_cache
                (base-rate $kbid $stored $tv $source $mode)
                (if (== $source user) (empty)
                   (base-rate $kbid $stored $tv $source $mode)))))
       ($_ (foreach-flat base-rate-cache-remove-entry! $entries)))
      ()))

(: universe-size-entries (-[det]-> KB (List UniverseSizeEntry)))
(= (universe-size-entries $kbid)
   (collapse
      (match &universe_size (universe-size $kbid $n)
         (universe-size $kbid $n))))

(: universe-size-remove-entry!
   (-[det]-> UniverseSizeEntry Bool))
(= (universe-size-remove-entry! $entry)
   (remove-atom &universe_size $entry))

(: clear-universe-size (-[det]-> KB (List $none)))
(= (clear-universe-size $kbid)
   (let*
      (($_remove
          (foreach-flat universe-size-remove-entry!
             (universe-size-entries $kbid)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-universe-size (-[det]-> KB Number (List $none)))
(= (set-universe-size $kbid $n)
   (let*
      (($_old (clear-universe-size $kbid))
       ($_new (add-atom &universe_size (universe-size $kbid $n)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: kb-universe-size
   (-[det]-> KB (| Number UniverseSizeUnavailable)))
(= (kb-universe-size $kbid)
   (let $entries (universe-size-entries $kbid)
      (if (== $entries ()) no-universe-size
         (let (universe-size $_kbid $n) (car-atom $entries) $n))))

;; Values recovered from the erased inheritance index are statements by the
;; index's construction invariant. Keep that boundary local so collapse can
;; retain the nominal element type without validating the whole result list.
(: statement-from-atom (-[det]-> Atom Statement))
(= (statement-from-atom $atom)
   (brand Statement $atom))

(: inheritance-subjects (-[det]-> KB (List Statement)))
(= (inheritance-subjects $kbid)
   (list_to_set
      (collapse
         (match &inheritance_subject ($kbid $subj)
            (statement-from-atom $subj)))))

;; Concept metadata and aggregate finalizers are shared by both forward and
;; backward execution, so they must be available before forward_chainer loads.
(: record-concept-node! (-[det]-> KB Statement (| Bool (List $none))))
(= (record-concept-node! $kbid $node)
   (if (is-var $node) ()
      (once
         (let $row
            (make-space-pair $kbid $node)
            (add-space-atom! &concept_node $row)))))

(: record-inheritance-nodes!
   (-[det]-> KB Statement Statement (| Bool (List $none))))
(= (record-inheritance-nodes! $kbid $subj $concept)
   (progn
      (record-concept-node! $kbid $subj)
      (record-concept-node! $kbid $concept)))

(: default-concept-prior-confidence (-[det]-> Number))
(= (default-concept-prior-confidence) 0.000001)

(: concept-prior-confidence-entries
   (-[det]-> KB (List ConceptPriorConfidence)))
(= (concept-prior-confidence-entries $kbid)
   (collapse
      (match &concept_prior_confidence
         (concept-prior-confidence $kbid $c)
         (concept-prior-confidence $kbid $c))))

(: concept-prior-confidence-remove-entry!
   (-[det]-> ConceptPriorConfidence Bool))
(= (concept-prior-confidence-remove-entry! $entry)
   (remove-atom &concept_prior_confidence $entry))

(: clear-concept-prior-confidence (-[det]-> KB (List $none)))
(= (clear-concept-prior-confidence $kbid)
   (let*
      (($_remove
          (foreach-flat concept-prior-confidence-remove-entry!
             (concept-prior-confidence-entries $kbid)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-concept-prior-confidence (-[det]-> KB Number (List $none)))
(= (set-concept-prior-confidence $kbid $c)
   (let*
      (($_old (clear-concept-prior-confidence $kbid))
       ($_new
          (add-atom &concept_prior_confidence
             (concept-prior-confidence $kbid $c)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: kb-concept-prior-confidence (-[det]-> KB Number))
(= (kb-concept-prior-confidence $kbid)
   (let $entries (concept-prior-confidence-entries $kbid)
      (if (== $entries ()) (default-concept-prior-confidence)
         (let (concept-prior-confidence $_kbid $c)
            (car-atom $entries)
            $c))))

(: known-concept-node? (-[det]-> KB Statement Bool))
(= (known-concept-node? $kbid $node)
   (not
      (== (collapse
             (once
                (match &concept_node ($kbid $node) true)))
          ())))

(: concept-nodes (-[det]-> KB (List Statement)))
(= (concept-nodes $kbid)
   (list_to_set
      (collapse
         (match &concept_node ($kbid $node)
            (statement-from-atom $node)))))

(: concept-node-prior-tv
   (-[det]-> KB Statement OptionalSTV))
(= (concept-node-prior-tv $kbid $node)
   (if (known-concept-node? $kbid $node)
      (let $n (list-len (concept-nodes $kbid))
         (if (<= $n 0) no-evidence
            (STV (/ 1.0 $n)
               (kb-concept-prior-confidence $kbid))))
      no-evidence))

(: ConceptNodePriorFormula
   (-[det]-> KB Statement OptionalSTV))
(= (ConceptNodePriorFormula $kbid $node)
   (concept-node-prior-tv $kbid $node))

(: resolve-base-rate-prior
   (-[det]-> BaseRatePrior OptionalSTV))
(= (resolve-base-rate-prior (ConceptNodePriorRuntime $kbid $node))
   (concept-node-prior-tv
      (brand KB $kbid) (brand Statement $node)))
(= (resolve-base-rate-prior (STV $s $c)) (STV $s $c))
(= (resolve-base-rate-prior no-evidence) no-evidence)

(: WeightedBaseRateWithPriorTv
   (-[det]-> BaseRateEvidenceWithPriorState OptionalSTV))
(= (WeightedBaseRateWithPriorTv
      (BaseRateEvidenceWithPrior $prior $ev))
   (BaseRateWithPriorFormula
      (resolve-base-rate-prior (brand BaseRatePrior $prior))
      (WeightedBaseRateTv $ev)))

(: member-inheritance-tv
   (-[det]-> KB BaseRateEvidenceState OptionalSTV))
(= (member-inheritance-tv $kbid $ev)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedCountBaseRateTv $ev)
         (WeightedUniverseBaseRateTv
            (the Number $universe-size) $ev))))
