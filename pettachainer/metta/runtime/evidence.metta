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

(: chainer-first-or (-[det]-> $value (List $value) $value))
(= (chainer-first-or $fallback ()) $fallback)
(= (chainer-first-or $_fallback (cons $value $_rest)) $value)
(: space-row-present? (-[det]-> $space $row Bool))
(= (space-row-present? $space $row) (not (== (collapse (once (match $space $row true))) ())))

;; A stored fact is its own evidence, except a refined rule's axiom, which
;; carries the rule's evidence: a proof through the axiom and a proof through
;; the rule are dependent and never revise.
(: fact-evidence-entry (-[det]-> KBContext Proof Statement Evidence))
(= (fact-evidence-entry $kb $prf $type)
   (case $prf (
      ((rule-axiom $name) (rule-ev (brand KB (car-atom $kb)) $name))
      ($_other (fact-ev $kb $prf $type)))))

(: revision-merge-tv (-[det]-> TV TV TV))
(= (revision-merge-tv $tv1 $tv2)
   (case $tv1
      (((STV $m1 $c1)
          (case $tv2
             (((STV $m2 $c2)
                 (merge-stv-fields $m1 $c1 $m2 $c2))
              ;; A plain proof of a conditional is its positive branch; the
              ;; conditional proof supplies the negative branch.
              ((CTV (STV $pm2 $pc2) $neg2)
                 (CTV (merge-stv-fields $m1 $c1 $pm2 $pc2) $neg2))
              ($_other-tv $tv1))))
       ;; Two conditional proofs revise branch by branch.
       ((CTV (STV $pm1 $pc1) (STV $nm1 $nc1))
          (case $tv2
             (((CTV (STV $pm2 $pc2) (STV $nm2 $nc2))
                 (CTV (merge-stv-fields $pm1 $pc1 $pm2 $pc2)
                    (merge-stv-fields $nm1 $nc1 $nm2 $nc2)))
              ((STV $m2 $c2)
                 (CTV (merge-stv-fields $pm1 $pc1 $m2 $c2) (STV $nm1 $nc1)))
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

(: proof-ref-evidence (-[det]-> Number (List Evidence)))
(= (proof-ref-evidence $pid)
   (case (collapse (once (match &proof ($pid $_proof $ev $_negated) $ev))) (
      ((cons $ev $_rest) $ev)
      (() ()))))

(: proof-ref-negated? (-[det]-> Number Bool))
(= (proof-ref-negated? $pid)
   (case (collapse (once (match &proof ($pid $_proof $_ev $negated) $negated))) (
      ((cons $negated $_rest) $negated)
      (() false))))

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
      (let* (($head (car-atom $prf))
             ($children
                (if (== $head conjunction) (cdr-atom $prf)
                   (if (== $head by)
                      (cdr-atom (cdr-atom $prf))
                   (if (== $mode proof-walk-in-kb)
                      (if (proof-term-leaf-head? $head)
                         ()
                         (cdr-atom $prf))
                      ())))))
         (proof-children $children))
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

;; A context assumption, or a statement a conditioned read takes as known.
(: assumption-proof? (-[det]-> Proof Bool))
(= (assumption-proof? $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf) (if (== $head ctx) true (== $head given)))
      false))

(: proof-from-atom (-[det]-> Expression Proof))
(= (proof-from-atom $proof) (brand Proof $proof))

(: proof-term-evidence-list-mode
   (-[semidet]-> $mode Atom (List Evidence)))
(= (proof-term-evidence-list-mode $mode $prf)
   (case $prf (
      ((proof-ref $pid) (proof-ref-evidence $pid))
      ;; A shared subproof counts once, at its first occurrence.
      ((shared $_id $shared-proof) (proof-term-evidence-list-mode $mode (brand Proof $shared-proof)))
      ((shared $_id) ())
      ;; The population base rate an inversion or completion updates is no
      ;; evidence about the instance.
      (cpu ())
      ;; A factored merge's evidence is its prior view's and its updates';
      ;; the prior's truth value is none.
      ((factored-revision $base $_prior $parts)
         (append-flat
            (proof-term-evidence-list-mode $mode (brand Proof $base))
            (proof-term-evidence-children-mode $mode (proof-children $parts))))
      ;; Combined forward views: their evidence; the prior's is none.
      ((combination $_combination $_combination-prior $combined)
         (proof-term-evidence-children-mode $mode (proof-children $combined)))
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


(: fact-evidence-only
   (-[det]-> (List Evidence) (List Evidence)))
(= (fact-evidence-only ()) ())
(= (fact-evidence-only (cons $entry $rest))
   (if (= $entry (rule-ev $_kb $_name))
      (fact-evidence-only $rest)
      (if (= $entry (rule-excluded $_kb $_name))
         (fact-evidence-only $rest)
         (cons $entry (fact-evidence-only $rest)))))

;; The rules a row excludes, as the evidence a premise using them carries.
(: excluded-rule-step (-[det]-> (List Evidence) Evidence (List Evidence)))
(= (excluded-rule-step $acc $entry)
   (case $entry (
      ((rule-excluded $kb $name) (cons (rule-ev $kb $name) $acc))
      ($_other $acc))))

;; A certain fact, strength 0 or 1 at confidence 1, joins the same whether its
;; evidence is shared or not: P(K and X) is P(X) or 0 either way. Evidence read
;; off a proof term names the fact by its proof alone, negated under a Not.
(: certain-tvs? (-[det]-> (List TV) Bool))
(= (certain-tvs? $tvs)
   (case $tvs (
      ((cons (STV $s $c) $_rest)
         (if (>= $c 1.0) (if (>= $s 1.0) true (<= $s 0.0)) false))
      ($_other false))))
(: stored-proof-tvs (-[det]-> Atom (List TV)))
(= (stored-proof-tvs $name) (collapse (once (match &kb ($type $kbctx $name $tv) $tv))))
(: certain-fact-evidence? (-[det]-> Evidence Bool))
(= (certain-fact-evidence? $entry)
   (case $entry (
      ((not-ev $inner) (certain-fact-evidence? $inner))
      ((fact-ev $kbctx $proof $type) (certain-tvs? (collapse (once (match &kb ($type $kbctx $proof $tv) $tv)))))
      ((not-fact-ev $nkbctx $nproof $ntype) (certain-tvs? (collapse (once (match &kb ($ntype $nkbctx $nproof $ntv) $ntv)))))
      ($name (if (is-expr $name) false (certain-tvs? (stored-proof-tvs $name)))))))

(: uncertain-evidence-step (-[det]-> Bool Evidence Bool))
(= (uncertain-evidence-step $found $entry)
   (if $found true (not (certain-fact-evidence? $entry))))

;; Ordinary conjunction premises cannot reuse the same uncertain fact
;; evidence. This check excludes rule applications from the compared evidence
;; sets, except the rules the row excludes, which no premise may use.
;; Projection pooling and compiler-marked shared-evidence joins decide their
;; exceptions at the consumer before accepting a premise.
(: premise-evidence-overlap?
   (-[det]-> (List Evidence) (List Evidence) Bool))
(= (premise-evidence-overlap? $seen $pev)
   (if (fold-flat uncertain-evidence-step false
          (evidence-intersection (fact-evidence-only $seen) (fact-evidence-only $pev)))
      true
      (evidence-sets-overlap? (fold-flat excluded-rule-step () $seen) $pev)))

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
            (case $prf (
               ((proof-ref $pid) (proof-ref-negated? $pid))
               ($_other
                  (proof-term-contains-negated-list?
                     (proof-term-children-mode proof-walk-in-kb $prf)))))
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

(: stored-list-member? (-[det]-> $item (List $item) Bool))
(= (stored-list-member? $_needle ()) false)
(= (stored-list-member? $needle (cons $first $rest))
   (if (== $needle $first) true (stored-list-member? $needle $rest)))

;; A proof that gives way to another: a marginal projection to the full
;; projection of the same source, and a settled step to the complete step it
;; settles, which reads the settling part with the compound's other parts.
(: proof-dominates? (-[det]-> Proof Proof Bool))
(= (proof-dominates? $prf-a $prf-b)
   (case $prf-a (
      (((proj $idx $base) $_evidence)
         (== $prf-b (marginal-proj $idx $base)))
      ($_ (settled-within? $prf-b $prf-a)))))

;; The settled proof equals the complete one except where it reads one part
;; `(settled P)` and the complete proof the conjunction of P with the others.
(: settled-within? (-[det]-> Atom Atom Bool))
(: settled-args-within? (-[det]-> Atom Atom Bool))
(= (settled-within? $settled $full)
   (if (is-expr $settled)
      (if (is-expr $full)
         (case $settled (
            ((settled $part)
               (case $full (
                  ((cons conjunction $parts) (stored-list-member? $part (the (List Atom) $parts)))
                  ($_other false))))
            ($_other
               (if (== (car-atom $settled) (car-atom $full))
                  (let* (($settled-args (cdr-atom $settled))
                         ($full-args (cdr-atom $full)))
                     (settled-args-within? $settled-args $full-args))
                  false))))
         false)
      false))
(= (settled-args-within? $settled-args $full-args)
   (case (data $settled-args $full-args) (
      ((() ()) true)
      (((cons $a $as) (cons $b $bs))
         (if (if (== $a $b) true (settled-within? $a $b)) (settled-args-within? $as $bs) false))
      ($_other false))))

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
         (if (proof-dominates? $proof-token-a $proof-token-b)
            (data $proof-a $ev-a)
            (if (proof-dominates? $proof-token-b $proof-token-a)
               (data $proof-b $ev-b)
               (if (evidence-sets-overlap? $ev-a $ev-b)
                  (if (evidence-subset? $ev-a $ev-b)
                     (data $proof-b $ev-b)
                     (if (evidence-subset? $ev-b $ev-a)
                        (data $proof-a $ev-a)
                        (if (>= (term-confidence $proof-a)
                                (term-confidence $proof-b))
                           (data $proof-a $ev-a)
                           (data $proof-b $ev-b))))
                  (let $all-ev (list_to_set (append-flat $ev-a $ev-b))
                     (if (>= (term-confidence $proof-a)
                             (term-confidence $proof-b))
                        (data (RevisionMergeProof $proof-a $proof-b) $all-ev)
                        (data (RevisionMergeProof $proof-b $proof-a) $all-ev)))))))))
