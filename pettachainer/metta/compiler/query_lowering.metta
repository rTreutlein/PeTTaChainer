;; Query contexts, query-local additions, and query-goal lowering.
;; One side of a total-implication / bidirectional query: allocate a fresh
;; query context, lower the premises (negatively for the refuting side of a
;; total implication, positively otherwise), and collect the context + adapter
;; atoms the chainer needs to resolve this side's conclusion. Returns the ground
;; shape-kb, the fresh proof var (shared with the caller's goal and proof
;; token), the conclusion expression, and the side's adds.
(: query-side
   (-[semidet]-> KB (| NilType (List Variable)) Bool
       Statement Statement
       (KBContext Proof Statement (List CompiledAddition))))
(= (query-side $kb $mvars $negative? $antecedent $consequent)
   (let*
      (($ctx (nextctx))
       ($shape-kb (make-kb-context $kb $ctx $mvars))
       ($premises (implication-side-conjuncts $antecedent))
       (($execs $_proofs $_atv)
          (once (if $negative?
                   (lower-query-assumption-premises-negative $kb $ctx $mvars $premises)
                   (lower-query-assumption-premises $kb $ctx $mvars $premises))))
       ($adds
          (union-compiled-additions
             (query-context-premise-adds $kb $ctx $mvars $execs)
             (collapse
                (compile-adapter-chain query
                   (: $shape-kb $prf $consequent $adapter-tv))))))
      (data
         $shape-kb (brand Proof $prf) $consequent $adds)))

;; The two sides of a total-implication query share one conclusion $b and differ
;; only in polarity. Returns the ground shape-kbs, $b, the fresh pos/neg proof
;; vars (used by the caller in its known goals and proof token), and all adds.
(: query-pos-neg-scaffold
   (-[semidet]-> KB (| NilType (List Variable))
       Statement Statement
       (KBContext KBContext Statement Proof Proof (List CompiledAddition))))
(= (query-pos-neg-scaffold $kb $mvars $antecedent $consequent)
   (let*
      ((($pos-shape-kb $pos-prf $b $pos-adds)
          (query-side $kb $mvars false $antecedent $consequent))
       (($neg-shape-kb $neg-prf $_b $neg-adds)
          (query-side $kb $mvars true $antecedent $consequent)))
      (data
         $pos-shape-kb $neg-shape-kb $b $pos-prf $neg-prf
         (union-compiled-additions $pos-adds $neg-adds))))

;; Build the empirical Member producer independently from the rest of a root
;; Inheritance query. Backward subgoals can install this same producer without
;; also introducing the root-only total-implication scaffold.
(: compile-member-inheritance-query-adds
   (-[det]-> KB Term Term (List CompiledAddition)))
(= (compile-member-inheritance-query-adds $kb $subj $concept)
   (let*
      (($member-goal (: (kbctx $kb)
          (inheritance-query-result (member-inheritance-fold cpu))
          (Inheritance $subj $concept) $member-tv))
       ;; Build empirical samples through ordinary compiled Member queries. This
       ;; lets rule-derived memberships contribute while retaining their proof
       ;; identities for overlap and cycle checks before aggregation.
       ($member-sample-pattern
          (MemberInheritanceSample
             $member-obj $subj $concept $member-atv $member-btv))
       ($member-sample-goal
          (: (kbctx $kb)
             (member-inheritance-sample $member-aprf $member-bprf)
             $member-sample-pattern
             (STV 1.0 1.0)))
       ($member-sample-rule
          (((: (kbctx $kb) $member-aprf
                (Member $member-obj $subj) $member-atv)
            (: (kbctx $kb) $member-bprf
                (Member $member-obj $concept) $member-btv))
             |- $member-sample-goal))
       ($member-rule
          (((CPU FoldAllCompiled
                 (quote
                    ($kb
                       $member-sample-pattern
                       (extract-value $member-sample-pattern
                          (WeightedTv $member-atv $member-btv))
                       (BaseRateEvidence 0.0 0.0)
                       WeightedBaseRateAcc
                       (member-inheritance $kb)
                       result-tv))
                 $member-fold-tv)
            (CPU MemberInheritanceEvidenceFormula
               ($member-fold-tv) $member-tv))
             |- $member-goal)))
      (cons (brand CompiledAddition $member-sample-rule)
         (cons (brand CompiledAddition $member-rule) ()))))

;; Under rule refinement a rule's instance fold proves its rule-truth goal
;; (see `set-rule-refinement`), so an implication query of that shape reads
;; the goal instead of folding the instances again; an STV truth gets its
;; negative branch from both sides' base rates.
(: rule-truth-installed? (-[det]-> KB Atom Bool))
(= (rule-truth-installed? $kb $Type)
   (let $truth (copy_term (RuleTruth $Type))
      (not (== (collapse (once (match &rule_truth_shapes ($kb $truth) true))) ()))))

(: rule-truth-query-adds (-[det]-> KB Atom Atom Atom (List CompiledAddition)))
(= (rule-truth-query-adds $kb $Type $antecedent $consequent)
   (let $premises
      (cons (: (kbctx $kb) $truth-prf (RuleTruth $Type) $truth-tv)
         (append-goals
            (base-rate-premises $kb (copy_term (rule-query-pattern (brand Statement $antecedent))) $atv)
            (append-goals
               (base-rate-premises $kb (copy_term (rule-query-pattern (brand Statement $consequent))) $btv)
               (cons (CPU ImplicationCTVFormula (quote ($atv $btv $truth-tv)) $ctv) ()))))
      (cons
         (brand CompiledAddition
            (cons $premises
               (cons |- (cons (: (kbctx $kb) (rule-truth $truth-prf) $Type $ctv) ()))))
         ())))

(: compile-inheritance-query
   (-[semidet]-> KB Term Term
       CompilationPlan))
(= (compile-inheritance-query $kb $subj $concept)
   (let*
      (;; Constrain the root proof so ordinary public Inheritance rules cannot
       ;; answer beside the total-implication producer. The wrapper is removed
       ;; when results are externalized; it is selection state, not evidence.
       ($goal (: (kbctx $kb) (inheritance-query-result $proof)
          (Inheritance $subj $concept) $tv))
       ($antecedent (Inheritance $x $subj))
       ($consequent (Inheritance $x $concept))
       ($mvars (cons (brand Variable $x) ()))
       (($pos-shape-kb $neg-shape-kb $b
            $pos-prf $neg-prf $all-adds)
          (query-pos-neg-scaffold $kb $mvars
             (brand Statement $antecedent)
             (brand Statement $consequent)))
       ($pos-lift-adds
          (collect-inheritance-lifts-for-context
             $kb $pos-shape-kb))
       ($neg-lift-adds
          (collect-inheritance-lifts-for-context
             $kb $neg-shape-kb))
       ($known-pos-goal (: $pos-shape-kb $pos-prf $b $induction-tv))
      ($known-neg-goal (: $neg-shape-kb $neg-prf $b $negative-tv))
      ($induction-goal (: (kbctx $kb) (inheritance-query-result
         (total-implication-frontier
            (inheritance-implication-fold (total-implication $pos-prf $neg-prf))))
         (Inheritance $subj $concept) $induction-tv))
      ($induction-rule
         (brand CompiledAddition
            ((quote ($known-pos-goal $known-neg-goal)) |- $induction-goal)))
      ($query-adds
         (list_to_set
            (append-compiled-additions $all-adds
               (append-compiled-additions $pos-lift-adds
                  (append-compiled-additions $neg-lift-adds
                     (cons $induction-rule ())))))))
      (compilation-plan $goal $query-adds)))

(: implication-query-known-tv-parts
   (-[semidet]-> TV (STVType STVType CTVType)))
(= (implication-query-known-tv-parts $tv)
   (if (is-var $tv)
      (data
         (the STVType $pos-tv)
         (the STVType $neg-tv)
         (CTV $pos-tv $neg-tv))
      (case $tv
         (((CTV $pos-tv $neg-tv)
             (data $pos-tv $neg-tv (CTV $pos-tv $neg-tv)))
          ((STV $s $c)
             (let $neg-tv (the STVType $stv-neg-tv)
                (data
                   (STV $s $c)
                   $neg-tv
                   (CTV (STV $s $c) $neg-tv))))
          (no-evidence (empty))))))

;; Compile a public query into one goal rule plus temporary additions.
;; Implication queries require positive and refuting assumption contexts;
;; bidirectional queries require one context per direction. A concrete
;; Inheritance query accepts only the total-implication producer plus the
;; Member producer, which the chainer installs as ordinary rules when it
;; expands the link; ordinary direct proofs cannot answer its constrained root
;; goal.
;; Ordinary queries remain a direct known goal with only the adapters their
;; source syntax requires.
(: compileQuery
   (-[nondet]-> KB AnnotatedStatement CompilationPlan))
(= (compileQuery $kb (: $prf $Type $tv))
   (if (is-var $Type)
      (compilation-plan (: (kbctx $kb) $prf $Type $tv) ())
      (if (contains-explicit-exists? $Type) (empty)
      (if (= $Type (Implication $antecedent $consequent))
         (let*
            (($mvars (query-variables (extract-vars $Type)))
             (($pos-shape-kb $neg-shape-kb $b
                  $pos-prf $neg-prf $all-adds)
                (query-pos-neg-scaffold $kb $mvars
                   (brand Statement $antecedent)
                   (brand Statement $consequent)))
             (($known-pos-tv $known-neg-tv $known-tv)
                (implication-query-known-tv-parts $tv))
             ($known-pos-goal (: $pos-shape-kb $pos-prf $b $known-pos-tv))
             ($known-neg-goal (: $neg-shape-kb $neg-prf $b $known-neg-tv))
             ;; The two contextual answers are alternative evaluations of one
             ;; conditional, not independent conjuncts. Mark their combining
             ;; frontier so shared source facts remain admissible.
             ($known-goal (: (kbctx $kb)
                (total-implication-frontier
                   (total-implication $pos-prf $neg-prf))
                $Type $known-tv)))
            ;; The root proof is open so the instance fold answers beside the
            ;; hypothetical producer and the two revise into one answer.
            (compilation-plan
               (: (kbctx $kb) $root-prf $Type $known-tv)
               (cons
                  (brand CompiledAddition
                     ((the (List Goal)
                          ($known-pos-goal $known-neg-goal))
                        |- $known-goal))
                  (append-compiled-additions
                     (if (rule-truth-installed? $kb $Type)
                        (rule-truth-query-adds $kb $Type $antecedent $consequent)
                        (compile-implication-instance-adds true $kb
                           (brand Statement $Type)
                           (brand Statement $antecedent)
                           (brand Statement $consequent)))
                     $all-adds))))
         (if (implication-type? $Type) (empty)
         (if (bidirectional-implication-type? $Type)
            (let*
               ((($_head $left $right) $Type)
                ($mvars (query-variables (extract-vars $Type)))
                (($left-shape-kb $left-prf
                      $left-goal-expr $left-adds)
                    (query-side $kb $mvars false
                       (brand Statement $left)
                       (brand Statement $right)))
                 (($right-shape-kb $right-prf
                      $right-goal-expr $right-adds)
                    (query-side $kb $mvars false
                       (brand Statement $right)
                       (brand Statement $left)))
                 ($left-goal (: $left-shape-kb $left-prf $left-goal-expr $left-tv))
                 ($right-goal (: $right-shape-kb $right-prf $right-goal-expr $right-tv))
                 ($goal (: (kbctx $kb) (bidirectional $left-prf $right-prf) $Type $tv)))
               (compilation-plan
                  $goal
                  (cons
                     (brand CompiledAddition
                        ((the (List Goal)
                             ($left-goal $right-goal
                                (CPU AndFormula
                                   ($left-tv $right-tv) $tv)))
                           |- $goal))
                     (union-compiled-additions
                        $left-adds $right-adds))))
            (if (and (= $Type (Inheritance $subj $concept)) (concrete-inheritance-link? $subj $concept))
               (compile-inheritance-query $kb (brand Term $subj) (brand Term $concept))
               (compilation-plan
                  (: (kbctx $kb) $prf $Type $tv)
                  (collapse
                     (compile-adapter-chain query
                        (: (kbctx $kb) $prf $Type $tv)))))))))))


(: query-temp-rule-premise (-[det]-> Atom Statement))
(= (query-temp-rule-premise $premise)
   (case $premise (
      ((Compute $f $args $res)
         (brand Statement (Compute $f $args -> $res)))
      ($_other (brand Statement $premise)))))

(: compound-query-temp-stmt
   (-[semidet]-> AnnotatedStatement AnnotatedStatement))
(= (compound-query-temp-stmt (: $_prf $type $_tv))
   (let $premises
      (map-flat query-temp-rule-premise
         (statement-children (cdr-atom $type)))
      (: query-compound
         (Implication (seq2expr $premises) $type)
         (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))

;; Query assumptions with no caller-supplied TV are treated as certain. An
;; implication needs a CTV-shaped default because its positive and negative
;; support are tracked separately throughout the query compiler.
(: default-query-assumption-tv (-[det]-> Statement TV TV))
(= (default-query-assumption-tv $type $tv)
   (if (is-var $tv)
      (if (= $type (Implication $_antecedent $_consequent))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))
         (STV 1.0 1.0))
      $tv))

;; An implication used as a query assumption must be executable inside its
;; fresh context, not merely stored as an inert contextual fact. Compile its
;; forward rule against the same shaped KB so it can consume sibling assumptions.
(: query-context-compile-assumed-implication
   (-[det]-> KB $context $variables Proof TV Statement
       CompiledPremises
       (List CompiledAddition)))
(= (query-context-compile-assumed-implication
      $kbid $ctx $mvars $ctxprf $tv $consequent
      ($execs $proofs $atv))
   (let*
      (($shape-kb
          (make-kb-context $kbid $ctx $mvars))
       ($a
          (brand Statement
             (execs-goal-type $execs))))
      (collapse
         (compile-implication-forward-rules
            $kbid $shape-kb $shape-kb
            $ctxprf $tv () $tv () $a $consequent
            (list_to_set (extract-vars $a))
            $execs $proofs $atv))))

(: query-context-assumed-implication-rules
   (-[det]-> KB $context $variables Proof Statement TV
       (List CompiledAddition)))
(= (query-context-assumed-implication-rules $kbid $ctx $mvars $ctxprf $type $tv)
   (if (is-var $type) ()
      (case $type (
         ((Implication $antecedent $consequent)
            (let*
               (($lowered
                   (collapse
                      (once
                         (lower-implication-antecedent
                            $kbid $ctx $mvars
                            (brand Statement $antecedent))))))
               (case $lowered (
                  (() ())
                  ((cons $compiled-premises $_rest)
                     (query-context-compile-assumed-implication
                        $kbid $ctx $mvars $ctxprf $tv
                        (brand Statement $consequent)
                        $compiled-premises))))))
         ($_other ())))))

(: query-context-premise-assumption-adds
   (-[det]-> KB $context $variables Proof Statement TV
       (List CompiledAddition)))
(= (query-context-premise-assumption-adds $kbid $ctx $mvars $ctxprf $type $tv)
   (cons
      (brand CompiledAddition
         (() |- (: (make-kb-context $kbid $ctx $mvars)
                    $ctxprf $type $tv)))
      (query-context-assumed-implication-rules
         $kbid $ctx $mvars $ctxprf $type $tv)))

(: query-context-premise-adds-step
   (-[det]-> KB $context $variables
       (Number (List CompiledAddition))
       Goal
       (Number (List CompiledAddition))))
(= (query-context-premise-adds-step $kbid $ctx $mvars ($idx $adds) $premise)
   (let $ctxprf
      (brand Proof
         (if (== $idx 0)
            (data ctx proof $ctx)
            (data ctx proof $ctx $idx)))
      (case $premise
         (((CPU $_fun $_args $_res) ($idx $adds))
             ((: $_kb $_prf $type $tv)
                ((+ $idx 1)
                 (prepend-reversed-compiled-additions
                    (query-context-premise-assumption-adds
                       $kbid $ctx $mvars $ctxprf $type
                       (default-query-assumption-tv $type $tv))
                    $adds)))
          ($_other ($idx $adds))))))

(: query-context-premise-adds
   (-[det]-> KB $context $variables
       (List Goal)
       (List CompiledAddition)))
(= (query-context-premise-adds $kbid $ctx $mvars $premises)
   (let ($_idx $adds)
      (fold-flat
         (query-context-premise-adds-step $kbid $ctx $mvars)
         (0 ()) $premises)
      (list_to_set
         (prepend-reversed-compiled-additions $adds ()))))
