;; Proof structure, evidence identity, overlap, dominance, and revision.
;; Schema-less proof/result stores erase nominal roles. Reconstruct a fact only
;; at those boundaries and validate the truth-value payload whose numeric
;; fields affect inference. Typed &kb reads do not pass through this adapter.
(: assemble-stored-runtime-fact
   (-[det]-> Atom Atom Atom Atom
       (Statement KBContext Proof TV)))
(= (assemble-stored-runtime-fact $type $kb $proof $tv)
   (data
      (brand Statement $type)
      (brand KBContext $kb)
      (brand Proof $proof)
      (the TV $tv)))

;; Scalar ids recovered from erased spaces are checked individually at their
;; lookup boundary, avoiding a traversal of the collected list.
(: stored-number (-[det]-> Atom Number))
(= (stored-number $value)
   (the Number $value))

(: first-number (-[semidet]-> (List Number) Number))
(= (first-number (cons $first $_rest)) $first)
(: chainer-first-or (-[det]-> $value (List $value) $value))
(= (chainer-first-or $fallback ()) $fallback)
(= (chainer-first-or $_fallback (cons $value $_rest)) $value)
(: space-row-present? (-[det]-> $space $row Bool))
(= (space-row-present? $space $row) (not (== (collapse (once (match $space $row true))) ())))

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

(: search-id-value (-[det]-> CounterKey Number))
(= (search-id-value $key)
   (let $state-values (collapse (catch (get-state $key)))
      (if (== $state-values ())
         0
         (if-error-number (car-atom $state-values) 0))))

(: next-search-id (-[det]-> CounterKey Number))
(= (next-search-id $key)
   (let $n (search-id-value $key)
      (progn (change-state! $key (+ $n 1)) $n)))

(: cpu-call (-[nondet]-> Number $formula $arguments  $result))
(= (cpu-call $_steps $fun $args) (reduce (reduce (cons $fun $args))))

(: proof-stats-by-id
   (-[semidet]-> Number (Number (List Evidence))))
(= (proof-stats-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_gid $_output $_kind
            (proof-support $score $ev $_contribution) $_children)
         (quote ($score $ev)))))

;; cdr-atom exposes the erased proof representation as an untyped list. This
;; is the boundary that restores the semantic Proof brand to each raw child.
(: proof-children (-[det]-> Expression (List Proof)))
(= (proof-children $children)
   (case $children (
      (() ())
      ((cons $child $rest)
         (cons
            (brand Proof $child)
            (proof-children $rest)))
      ($_other ()))))

(: proof-term-leaf-head? (-[det]-> $head Bool))
(= (proof-term-leaf-head? $head) (is-member $head (() fact-ev CPU STV CTV)))

(: proof-term-children-mode
   (-[det]-> $mode Proof (List Proof)))
(= (proof-term-children-mode $mode $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf)
         (let $children
            (if (== $head conjunction) (cdr-atom $prf)
               (if (== $head by)
                  (cdr-atom (cdr-atom $prf))
               (if (== $mode proof-walk-in-kb)
                  (if (proof-term-leaf-head? $head)
                     ()
                     (cdr-atom $prf))
                  ())))
            (proof-children $children)))
      ()))


(: proof-term-evidence-children-mode
   (-[semidet]-> $mode (List Proof) (List Evidence)))
(= (proof-term-evidence-children-mode $mode ()) ())
(= (proof-term-evidence-children-mode $mode (cons $child $rest))
   (append-flat
      (proof-term-evidence-list-mode $mode $child)
      (proof-term-evidence-children-mode $mode $rest)))

(: evidence-negate (-[det]-> Evidence Evidence))
(= (evidence-negate $ev)
   (case $ev (
      ((fact-ev $kb $prf $type) (not-fact-ev $kb $prf $type))
      ((not-fact-ev $kb $prf $type) (fact-ev $kb $prf $type))
      ($other (not-ev $other)))))

(: proof-term-negated? (-[det]-> Proof Bool))
(= (proof-term-negated? $prf)
   (if (is-expr $prf) (== (car-atom $prf) negated) false))

(: assumption-proof? (-[det]-> Proof Bool))
(= (assumption-proof? $prf)
   (if (is-expr $prf) (== (car-atom $prf) ctx) false))

(: proof-from-atom (-[det]-> Expression Proof))
(= (proof-from-atom $proof) (brand Proof $proof))

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
            (append-flat
               (proof-term-evidence-list-mode $mode $left-proof)
               (proof-term-evidence-list-mode $mode $right-proof))))
      ($_other
         (let $proof (proof-from-atom $prf)
            (if (is-var $prf) ()
            (if (assumption-proof? $proof) ()
               (if (proof-term-negated? $proof)
                  (let $inner-proof
                     (brand Proof (car-atom (cdr-atom $proof)))
                     (map-flat evidence-negate
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
            proof-walk-in-kb $prf))))

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
   (not (== (evidence-intersection $set-a $set-b) ())))

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
(= (non-fact-evidence ()) ())
(= (non-fact-evidence (cons $entry $rest))
   (if (= $entry (rule-ev $_kb $_name))
      (cons $entry (non-fact-evidence $rest))
      (non-fact-evidence $rest)))
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
               (proof-term-children-mode proof-walk-in-kb $prf))
            false))))

(: rule-evidence-head (-[det]-> Proof Proof))
(= (rule-evidence-head $prf)
   (if (is-expr $prf)
      (if (is-var (car-atom $prf)) (brand Proof (car-atom $prf))
         (case $prf (
            ((cons by (cons $name $_rest)) (brand Proof $name))
            ((cons (antecedent-completion $src $_idx with $_c1 $_c2) $_rest)
               (brand Proof $src))
            ((cons (inverted $inv with $_pa $_pb) $_rest) (brand Proof $inv))
            ((cons (bi-forward $fwd) $_rest) (brand Proof $fwd))
            ((cons (bi-backward $bwd) $_rest) (brand Proof $bwd))
            ((cons (no_inverse $inner) $_rest) (brand Proof $inner))
            ((cons $head $_rest) (brand Proof $head)))))
      $prf))

;; Forward materialization and backward rule application must attach exactly
;; the same provenance.  Otherwise a materialized rule result looks like a new
;; independent fact when the backward chainer rediscovers that rule path.
(: rule-result-evidence
   (-[semidet]-> (Statement KBContext Proof TV)
       (List Evidence) (List Evidence)))
(= (rule-result-evidence ($_type ($kbid $_ctx $_vars) $prf $_tv) $ev)
   (let*
      (($base
          (if (proof-term-contains-negated? $prf)
             (list_to_set (once (proof-term-evidence-list-mode proof-walk-in-kb $prf)))
             $ev))
       ($name (rule-evidence-head $prf))
       ($typed-kbid (brand KB $kbid)))
      (if (is-expr $name) $base
         (if (rule-evidence-registered? $typed-kbid $name)
            (list_to_set (append-flat $base (cons (rule-ev $typed-kbid $name) ())))
            $base))))

(: projection-dominates? (-[det]-> Proof Proof Bool))
(= (projection-dominates? $prf-a $prf-b)
   (case $prf-a (
      (((proj $idx $base) $_evidence)
         (== $prf-b (marginal-proj $idx $base)))
      ($_ false))))

(: merge-proof-candidates
   (-[det]-> ((Statement KBContext Proof TV) (List Evidence))
       ((Statement KBContext Proof TV) (List Evidence))
       ((Statement KBContext Proof TV) (List Evidence))))
(= (merge-proof-candidates ($proof-a $ev-a) ($proof-b $ev-b))
   (if (== $proof-a $proof-b)
      (data $proof-a (list_to_set (append-flat $ev-a $ev-b)))
      (let*
         (($proof-token-a (proof-atom-proof $proof-a))
          ($proof-token-b (proof-atom-proof $proof-b)))
         (if (projection-dominates? $proof-token-a $proof-token-b)
            (data $proof-a $ev-a)
            (if (projection-dominates? $proof-token-b $proof-token-a)
               (data $proof-b $ev-b)
               (if (evidence-sets-overlap? $ev-a $ev-b)
                  (let $both-nonempty?
                     (if (== $ev-a ()) false (not (== $ev-b ())))
                     (if (if $both-nonempty? (evidence-subset? $ev-a $ev-b) false)
                        (data $proof-b $ev-b)
                        (if (if $both-nonempty? (evidence-subset? $ev-b $ev-a) false)
                           (data $proof-a $ev-a)
                           (if (>= (term-confidence $proof-a)
                                   (term-confidence $proof-b))
                              (data $proof-a $ev-a)
                              (data $proof-b $ev-b)))))
                  (let $all-ev (list_to_set (append-flat $ev-a $ev-b))
                     (if (>= (term-confidence $proof-a)
                             (term-confidence $proof-b))
                        (data (RevisionMergeProof $proof-a $proof-b) $all-ev)
                        (data (RevisionMergeProof $proof-b $proof-a) $all-ev)))))))))

(: merge-proof-atoms
   (-[semidet]-> (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)))
(= (merge-proof-atoms $proof-a $proof-b)
   (let ($merged $_ev)
      (merge-proof-candidates
         (data $proof-a (proof-atom-evidence-set $proof-a))
         (data $proof-b (proof-atom-evidence-set $proof-b)))
      $merged))
