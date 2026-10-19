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

;; A stated implication carries the same rule evidence as its applications,
;; including when query lowering reads it in a private namespace. Other stored
;; facts retain their own evidence identity.
(: fact-evidence-entry (-[det]-> KBContext Proof Statement Evidence))
(= (fact-evidence-entry $kb $prf $type)
   (case $prf (
      ((rule-axiom $name) (rule-ev (statement-query-kb (brand KB (car-atom $kb))) $name))
      ($_other
         (if (if (implication-type? $type) true (head-is? $type QuantifiedRule))
            (let* (($source-kb (statement-query-kb (brand KB (car-atom $kb))))
                   ($name (rule-evidence-base-name $prf)))
               (if (rule-evidence-registered? $source-kb $name)
                  (rule-ev $source-kb $name)
                  (fact-ev $kb $prf $type)))
            (fact-ev $kb $prf $type))))))

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
      (add-space-atom! $space (brand SpaceAtom $expr))
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

;; A counter's value, 0 before it is set (runtime_helpers.pl): read on every
;; search step, so kept native.
(: search-id-value (-[det]-> CounterKey Number))

(: next-search-id (-[det]-> CounterKey Number))
(= (next-search-id $key)
   (let $n (search-id-value $key)
      (progn (change-state! $key (+ $n 1)) $n)))

(: cpu-call (-[nondet]-> Number $formula $arguments  $result))
(= (cpu-call $_steps $fun $args) (reduce (reduce (cons $fun $args))))

(: proof-ref-evidence (-[det]-> Number EvidenceSet))
(= (proof-ref-evidence $pid)
   (case (collapse (once (match &proof ($pid $_proof $ev $_flags) $ev))) (
      ((cons $ev $_rest) $ev)
      (() (ev-set 0)))))

(: proof-ref-negated? (-[det]-> Number Bool))
(: proof-zero-likelihood? (-[det]-> Proof Bool))
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

;; A det boundary: the strict checker rejects is-member inline below.
(: proof-term-leaf-head? (-[det]-> $head Bool))
(= (proof-term-leaf-head? $head) (is-member $head (() fact-ev fact-source CPU STV CTV)))

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

(: proof-term-evidence-children
   (-[semidet]-> $mode (List Proof) EvidenceSet))
(= (proof-term-evidence-children $mode ()) (ev-set 0))
(= (proof-term-evidence-children $mode (cons $child $rest))
   (evidence-union
      (proof-term-evidence $mode $child)
      (proof-term-evidence-children $mode $rest)))

(: proof-term-negated? (-[det]-> Proof Bool))
(= (proof-term-negated? $prf)
   (if (is-expr $prf) (== (car-atom $prf) negated) false))

;; A context assumption, or a statement a conditioned read takes as known.
(: assumption-proof? (-[det]-> Proof Bool))
(= (assumption-proof? $prf)
   (if (is-expr $prf)
      (let $head (car-atom $prf) (if (== $head ctx) true (== $head given)))
      false))

;; A typing boundary: a direct brand conflicts with the Evidence uses below.
(: proof-from-atom (-[det]-> Expression Proof))
(= (proof-from-atom $proof) (brand Proof $proof))

(: proof-term-evidence
   (-[semidet]-> $mode Atom EvidenceSet))
(= (proof-term-evidence $mode $prf)
   (case $prf (
      ((zero-likelihood $source) (proof-term-evidence $mode $source))
      ((fact-source $source-ev $_source) $source-ev)
      ((proof-ref $pid) (proof-ref-evidence $pid))
      ;; A shared subproof counts once, at its first occurrence.
      ((shared $_id $shared-proof) (proof-term-evidence $mode (brand Proof $shared-proof)))
      ((shared $_id) (ev-set 0))
      ;; A projection position is metadata, not a source of evidence.
      ((marginal-proj $_index $source)
         (proof-term-evidence $mode (brand Proof $source)))
      (((proj $_index $source) $siblings)
         (evidence-union
            (proof-term-evidence $mode (brand Proof $source))
            (proof-term-evidence $mode (brand Proof $siblings))))
      ;; The population base rate an inversion or completion updates is no
      ;; evidence about the instance, nor is the prior of one more member read
      ;; from it.
      (cpu (ev-set 0))
      ((population-prior $_pattern) (ev-set 0))
      ((class-mixture $sources)
         (proof-term-evidence-children $mode (proof-children $sources)))
      ;; A factored merge's evidence is its prior view's and its updates';
      ;; the prior's truth value is none.
      ((factored-revision $base $_prior $parts)
         (evidence-union
            (proof-term-evidence $mode (brand Proof $base))
            (proof-term-evidence-children $mode (proof-children $parts))))
      ;; Combined forward views: their evidence; the prior's is none.
      ((combination $_combination $_combination-prior $combined)
         (proof-term-evidence-children $mode (proof-children $combined)))
      ((@ $_merge (merge/revision $left $right))
         (let*
            (($left-proof (brand Proof $left))
             ($right-proof (brand Proof $right)))
            (evidence-union
               (proof-term-evidence $mode $left-proof)
               (proof-term-evidence $mode $right-proof))))
      ($_other
         (let $proof (proof-from-atom $prf)
            (if (is-var $prf) (ev-set 0)
            (if (assumption-proof? $proof) (ev-set 0)
               (if (proof-term-negated? $proof)
                  (let $inner-proof (brand Proof (car-atom (cdr-atom $proof)))
                     (evidence-negated (proof-term-evidence $mode $inner-proof)))
                  (let $children (proof-term-children-mode $mode $proof)
                     (if (== $children ())
                        (evidence-set (cons (brand Evidence $prf) ()))
                        (proof-term-evidence-children $mode $children)))))))))))

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

;; Stored binary-certain facts are givens, including observations of statements
;; with forward rules. Keep their provenance in results, but compare views and
;; choose conditioning cuts without them, in either evidence polarity.
(: evidence-certainty-step (-[det]-> Bool (List Evidence) Evidence (List Evidence)))
(= (evidence-certainty-step $certain $kept $entry)
   (if (== (certain-fact-evidence? $entry) $certain) (cons $entry $kept) $kept))

(: uncertain-evidence-step (-[det]-> Bool Evidence Bool))
(= (uncertain-evidence-step $found $entry)
   (if $found true (not (certain-fact-evidence? $entry))))

;; Ordinary conjunction premises cannot reuse the same uncertain fact
;; evidence. This check excludes rule applications from the compared evidence
;; sets, except the rules the row excludes, which no premise may use.
;; Projection pooling and compiler-marked shared-evidence joins decide their
;; exceptions at the consumer before accepting a premise.
(: premise-evidence-overlap?
   (-[det]-> EvidenceSet EvidenceSet Bool))
(= (premise-evidence-overlap? $seen $pev)
   (if (fold-flat uncertain-evidence-step false (evidence-shared-facts $seen $pev))
      true
      (evidence-excludes? $seen $pev)))

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
            ((negated $inner) (rule-evidence-head (brand Proof $inner)))
            ((zero-likelihood $inner) (rule-evidence-head $inner))
            ;; Conditional consequent projections retain their source rule's
            ;; evidence and withdrawal identity, including repeated layers.
            ((consequent-projection $_source $_child $base)
               (rule-evidence-head (brand Proof $base)))
            ((cons by (cons $name $_rest))
               (if (head-is? $name consequent-projection)
                  (rule-evidence-head (brand Proof $name))
                  (brand Proof $name)))
            ((cons (antecedent-completion $src $_idx with $_c1 $_c2) $_rest)
               (rule-evidence-head (brand Proof $src)))
            ((cons (inverted $inv with $_pa $_pb) $_rest) (rule-evidence-head (brand Proof $inv)))
            ((cons (bi-forward $fwd) $_rest) (brand Proof $fwd))
            ((cons (bi-backward $bwd) $_rest) (brand Proof $bwd))
            ((cons (no_inverse $inner) $_rest) (brand Proof $inner))
            ((cons $head $_rest) (brand Proof $head)))))
      $prf))

;; Complement the accumulated premise evidence once per output Not. Do not
;; rewalk premise proofs: their evidence already includes all earlier negations
;; and the rule identities their printed terms cannot reconstruct.
(: proof-output-evidence (-[det]-> Proof EvidenceSet EvidenceSet))
(= (proof-output-evidence $proof $ev)
   (if (proof-term-negated? $proof)
      (evidence-negated (proof-output-evidence (brand Proof (car-atom (cdr-atom $proof))) $ev))
      $ev))

;; Forward materialization and backward rule application must attach exactly
;; the same provenance.  Otherwise a materialized rule result looks like a new
;; independent fact when the backward chainer rediscovers that rule path.
(: rule-result-evidence
   (-[semidet]-> (Statement KBContext Proof TV)
       EvidenceSet EvidenceSet))
(= (rule-result-evidence ($_type ($kbid $_ctx $_vars) $prf $_tv) $ev)
   (let*
      (($base
          ;; A judgment only wraps its premise proof. Negations have already
          ;; transformed the evidence below it; rewalking the printed proof
          ;; here loses the applied rule's evidence and revises it twice.
          (if (head-is-member? $prf (conditional-implication total-implication-frontier)) $ev
             (if (proof-term-negated? $prf)
                (proof-output-evidence $prf $ev)
                (if (proof-term-contains-negated? $prf)
                   ;; Conditioned reads carry inline premise proofs rather
                   ;; than references. Their printed by-terms omit rule
                   ;; evidence, which must survive the signed fact walk.
                   (evidence-union
                      (once (proof-term-evidence proof-walk-in-kb $prf))
                      (evidence-subtraction $ev
                         (evidence-set (evidence-shared-facts $ev $ev))))
                   $ev))))
       ($name
          (rule-evidence-base-name (rule-evidence-head $prf)))
       ($storage-kbid (brand KB $kbid))
       ($typed-kbid (statement-query-kb $storage-kbid)))
      (if (is-expr $name) $base
         (if (rule-evidence-registered? $typed-kbid $name)
            (evidence-union $base (evidence-set (cons (rule-ev $typed-kbid $name) ())))
            $base))))

(: stored-list-member? (-[det]-> $item (List $item) Bool))
(= (stored-list-member? $_needle ()) false)
(= (stored-list-member? $needle (cons $first $rest))
   (if (== $needle $first) true (stored-list-member? $needle $rest)))

;; A proof that gives way to another: a marginal projection to the full
;; projection of the same source, a settled step to the complete step it
;; settles, which reads the settling part with the compound's other parts.
(: sk-step-proof (-[det]-> Proof Proof))
(: proof-dominates? (-[det]-> Proof Proof Bool))
(= (proof-dominates? $prf-a $prf-b)
   (case $prf-a (
      (((proj $idx $base) $_evidence)
         (== $prf-b (marginal-proj $idx $base)))
      ($_
         (if (settled-within? $prf-b $prf-a) true
            ;; Applying an implication statement to its query's certain
            ;; assumption restates that statement's positive branch. This is
            ;; the same source even when a certain rule has no evidence id.
            (case (sk-step-proof $prf-b) (
               ((conditional-implication $inner)
                  (case (sk-step-proof (brand Proof $inner)) (
                     ((by $statement $assumption)
                        (if (assumption-proof? (sk-step-proof (brand Proof $assumption)))
                           (== (sk-step-proof $prf-a) (sk-step-proof (brand Proof $statement))) false))
                     ($_other-inner false))))
               ($_other-proof false))))))))

;; The stored facts a rule application reads directly, or none when it reads
;; a derived premise.
(: application-facts (-[det]-> Atom (List Atom)))
(= (application-facts $premise)
   (let $source (sk-step-proof (brand Proof $premise))
      (if (is-expr $source)
         (case $source (
            ((cons conjunction $names)
               (let $sources (map-flat sk-step-proof (proof-children $names))
                  (if (leaf-names? (the (List Atom) $sources)) (the (List Atom) $sources) ())))
            ($_other ())))
         (cons $source ()))))

;; The folds run over parameters, as the determinism checker requires.
(: leaf-names? (-[det]-> (List Atom) Bool))
(= (leaf-names? $names) (fold-flat leaf-name-step true $names))

(: leaf-name-step (-[det]-> Bool Atom Bool))
(= (leaf-name-step $leaves $name) (if $leaves (not (is-expr $name)) false))

(: all-members? (-[det]-> (List Atom) (List Atom) Bool))
(= (all-members? $set $items) (fold-flat (member-of-step $set) true $items))

(: member-of-step (-[det]-> (List Atom) Bool Atom Bool))
(= (member-of-step $set $members $item) (if $members (stored-list-member? $item $set) false))

;; Specificity compares the observed premise sources, not the rules used to
;; derive a generalized premise. Stored references carry semantic fact entries;
;; direct source proofs still name their facts by proof alone.
(: evidence-fact-proof (-[det]-> Evidence Atom))
(= (evidence-fact-proof $entry)
   (case $entry (
      ((fact-ev $_scope $proof $_statement) $proof)
      ((not-fact-ev $_scope $proof $_statement) (not-ev $proof))
      ($_raw $entry))))

;; Two rules applied to the same statement, the first reading stored facts
;; directly: the first's antecedent, as instantiated, entails the second's,
;; whose rate is a marginal over the first's and over cases this one is not
;; (see sk-specialized), when the second reads a proper subset of those facts,
;; or reads a derived premise resting only on them: a generalization of the
;; first's antecedent, such as (Member pingu Bird) derived from (Member pingu
;; Penguin).
(: specialization-includes? (-[det]-> Proof Proof Bool))
(= (specialization-includes? $specific $general)
   (case (sk-step-proof $specific) (
      ((specializes $_specific $prior $_raw $_ptv) (specialization-has-rule? (brand Proof $prior) $general))
      ($_other false))))

;; Membership here compares by-proof rule names, not compiled ids or premises.
(: specialization-has-rule? (-[det]-> Proof Proof Bool))
(= (specialization-has-rule? $prior $other)
   (case (data (sk-step-proof $prior) (sk-step-proof $other)) (
      (((by $rule $_premise) (by $other-rule $_other-premise)) (== $rule $other-rule))
      (((merge/revision $left $right) $_other)
         (if (specialization-has-rule? (brand Proof $left) $other) true
            (specialization-has-rule? (brand Proof $right) $other)))
      (($_prior (specializes $specific $_general $_raw $_ptv))
         (specialization-has-rule? $prior (brand Proof $specific)))
      ($_other false))))

(: more-specific-application? (-[semidet]-> Proof Proof Bool))
(= (more-specific-application? $prf-a $prf-b)
   (let* (($step-a (sk-step-proof $prf-a))
          ($step-b (sk-step-proof $prf-b)))
   (case (data $step-a $step-b) (
      (((specializes $specific-a $prior-a $_raw-a $_ptv-a) $_other-b)
         (if (specialization-has-rule? (brand Proof $prior-a) $prf-b) false
            (more-specific-application? (brand Proof $specific-a) $prf-b)))
      (($_other-a (specializes $specific-b $_prior-b $_raw-b $_ptv-b))
         (more-specific-application? $prf-a (brand Proof $specific-b)))
      (($_other-a (merge/revision $left-b $right-b))
         (if (more-specific-application? $prf-a (brand Proof $left-b))
            (more-specific-application? $prf-a (brand Proof $right-b)) false))
      (((by $rule-a $premise-a) (by $rule-b $premise-b))
         (if (== $rule-a $rule-b) false
            (let* (($facts-a (application-facts $premise-a))
                   ($facts-b (application-facts $premise-b)))
               (if (== $facts-a ()) false
                  (if (== $facts-b ())
                     (let* (($ev-b (proof-term-evidence proof-walk-in-kb $premise-b))
                            ($sources-b (map-flat evidence-fact-proof (evidence-shared-facts $ev-b $ev-b))))
                        (if (== $sources-b ()) false (all-members? $facts-a $sources-b)))
                     (if (< (list-len $facts-b) (list-len $facts-a)) (all-members? $facts-a $facts-b) false))))))
      ($_other false)))))

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
   (-[det]-> ((Statement KBContext Proof TV) EvidenceSet)
       ((Statement KBContext Proof TV) EvidenceSet)
       ((Statement KBContext Proof TV) EvidenceSet)))
(= (merge-proof-candidates ($proof-a $ev-a) ($proof-b $ev-b))
   (if (== $proof-a $proof-b)
      (data $proof-a (evidence-union $ev-a $ev-b))
      (let*
         (($proof-token-a (proof-atom-proof $proof-a))
          ($proof-token-b (proof-atom-proof $proof-b)))
         (if (proof-dominates? $proof-token-a $proof-token-b)
            (data $proof-a $ev-a)
            (if (proof-dominates? $proof-token-b $proof-token-a)
               (data $proof-b $ev-b)
               (if (evidence-overlap? $ev-a $ev-b)
                  (if (evidence-subset? $ev-a $ev-b)
                     (data $proof-b $ev-b)
                     (if (evidence-subset? $ev-b $ev-a)
                        (data $proof-a $ev-a)
                        (if (>= (term-confidence $proof-a)
                                (term-confidence $proof-b))
                           (data $proof-a $ev-a)
                           (data $proof-b $ev-b))))
                  (let $all-ev (evidence-union $ev-a $ev-b)
                     (if (>= (term-confidence $proof-a)
                             (term-confidence $proof-b))
                        (data (RevisionMergeProof $proof-a $proof-b) $all-ev)
                        (data (RevisionMergeProof $proof-b $proof-a) $all-ev)))))))))
