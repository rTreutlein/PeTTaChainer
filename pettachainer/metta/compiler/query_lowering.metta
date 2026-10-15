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

;; Judgment contexts know the whole compound antecedent as well as its
;; lowered parts. In particular a Not reader of a ground And must read that
;; conjunction as assumed true, rather than finding no contextual fact and
;; falling back to MAIN. Assuming queries retain their ordinary fact lowering.
(: judgment-query-side
   (-[semidet]-> KB (| NilType (List Variable)) Bool
       Statement Statement
       (KBContext Proof Statement (List CompiledAddition))))
(= (judgment-query-side $kb $mvars $negative? $antecedent $consequent)
   (let* ((($shape-kb $prf $b $adds)
              (query-side $kb $mvars $negative? $antecedent $consequent))
          (($_source-kb $ctx $_vars) $shape-kb)
          ($whole-tv (if $negative? (STV 0 1) (STV 1 1))))
      (data $shape-kb $prf $b
         (if (head-is-member? $antecedent (And Or))
            (cons (brand CompiledAddition
               (() |- (: $shape-kb (ctx proof $ctx whole) $antecedent $whole-tv)))
               $adds)
            $adds))))

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
          (judgment-query-side $kb $mvars false $antecedent $consequent))
       (($neg-shape-kb $neg-prf $_b $neg-adds)
          (judgment-query-side $kb $mvars true $antecedent $consequent)))
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
;; goal's positive branch instead of folding the instances again.
(: rule-truth-installed? (-[det]-> KB Atom Bool))
(= (rule-truth-installed? $kb $Type)
   (let $truth (copy_term (RuleTruth $Type))
      (not (== (collapse (once (match &rule_truth_shapes ($kb $truth) true))) ()))))

(: rule-truth-query-adds (-[det]-> KB Atom Atom Atom (List CompiledAddition)))
(= (rule-truth-query-adds $kb $Type $antecedent $consequent)
   (let $premises
      (cons (: (kbctx $kb) $truth-prf (RuleTruth $Type) $truth-tv)
         (append-goals
            (antecedent-rate-premises $kb (copy_term (rule-query-pattern (brand Statement $antecedent))) $atv)
            (append-goals
               (base-rate-premises $kb (copy_term (rule-query-pattern (brand Statement $consequent))) $btv)
               (cons (CPU ImplicationCTVFormula (quote ($atv $btv $truth-tv)) $ctv) ()))))
      (cons
         (brand CompiledAddition
            (cons $premises
               (cons |- (cons (: (kbctx $kb) (rule-truth $truth-prf) $Type $ctv) ()))))
         ())))

;; Storage keeps both rule branches; public statement judgments use the positive one.
(: query-positive-tv (-[semidet]-> TV STVType))
(= (query-positive-tv $tv)
   (case $tv (((CTV $pos $_neg) $pos) ((STV $s $c) (STV $s $c)))))

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

(: statement-query-tv (-[semidet]-> TV STVType))
(= (statement-query-tv $tv)
   (if (is-var $tv) (STV $strength $confidence)
      (case $tv (((STV $s $c) (STV $s $c)) ($_other (empty))))))

;; Private implication premises read both branches for modus ponens. Public
;; compileQuery never calls this CTV plan.
(: compile-implication-subgoal-query
   (-[semidet]-> KB AnnotatedStatement CompilationPlan))
(= (compile-implication-subgoal-query $kb (: $prf (Implication $a $b) (CTV $pos $neg)))
   (let*
      (($type (brand Statement (Implication $a $b)))
       (($antecedent $consequent)
          (if (implication-type? (brand Statement $b))
             (let ($parts $last) (nested-implication-parts $type)
                (data (cons And $parts) $last))
             (data $a $b)))
       ($mvars (query-variables (extract-vars $type)))
       (($pk $nk $concl $pp $np $adds)
          (query-pos-neg-scaffold $kb $mvars (brand Statement $antecedent) (brand Statement $consequent))))
      (compilation-plan (: (kbctx $kb) $prf $type (CTV $pos $neg))
         (cons (brand CompiledAddition
            ((the (List Goal) ((: $pk $pp $concl $pos) (: $nk $np $concl $neg)))
               |- (: (kbctx $kb) (total-implication-frontier (total-implication $pp $np)) $type (CTV $pos $neg))))
            (append-compiled-additions
               (if (rule-truth-installed? $kb $type)
                  (rule-truth-query-adds $kb $type $antecedent $consequent)
                  (compile-implication-instance-adds true $kb $type (brand Statement $antecedent) (brand Statement $consequent)))
               $adds)))))

;; Positive query values use a private KB namespace, preserving the public
;; statement shape. Ordinary predicate rules and main-context populations
;; therefore cannot treat query judgments as new world observations.
(: statement-query-kb (-[det]-> KB KB))
(= (statement-query-kb $kb)
   (if (head-is-member? $kb (implication-query implication-stated))
      (let $source-kb (car-atom (cdr-atom $kb)) (brand KB $source-kb))
      $kb))

;; Runtime clause premises are erased tuples; recover their compiler roles.
(: query-source-premise (-[semidet]-> Atom Goal))
(= (query-source-premise $premise)
   (if (head-is? $premise CPU)
      (let (CPU $fun $args $res) $premise (CPU $fun $args $res))
      (let ($type $kb $proof $tv) $premise
         (: (the KBContext $kb) (brand Proof $proof) (brand Statement $type) (the TV $tv)))))

;; Project only the requested conclusion, preserving every producer's premises
;; and proof. Sample producers pass through; an STV already is the positive
;; judgment. Alpha identity does not bind a producer into a different shape.
(: positive-implication-producer
   (-[nondet]-> KBContext Statement CompiledAddition CompiledAddition))
(= (positive-implication-producer $query-ctx $wanted ($premises |- (: $kb $proof $type $tv)))
   (if (=alpha $type $wanted)
      (let*
         (($positive-premises
             (if (head-is? $tv STV) $premises
                (append-goals (the (List Goal) $premises)
                   (cons (CPU query-positive-tv (quote ($tv)) $positive-tv) ()))))
          ($result-tv (if (head-is? $tv STV) $tv $positive-tv))
          ($goal (: $query-ctx (brand Proof $proof) (brand Statement $type) (the TV $result-tv))))
         (brand CompiledAddition ($positive-premises |- $goal)))
      (brand CompiledAddition ($premises |- (: $kb $proof $type $tv)))))

(: implication-statement-query-adds
   (-[det]-> KB KBContext Statement (List CompiledAddition)))
(= (implication-statement-query-adds $kb $query-ctx $type)
   (append-compiled-additions
      (collapse
         (let $lookup-type (copy_term $type)
            (match ccls_index
               (($lookup-type ($kb MAIN Nil) (by $rule $token) $source-tv) $_id $premises)
               ;; Only rule-application producers (by rule token) are projected
               ;; here. Other producer shapes are not collected; stored facts
               ;; and the dedicated hypothetical/empirical scaffolds below
               ;; remain separate sources (derived_implications.md, Limits).
               ;; A general producer may prove a bound instance. Project
               ;; its instantiated conclusion, retaining the rule's scope.
               (let*
                  (($source-premises (map-flat query-source-premise $premises))
                   ($source-goal (: (kbctx $kb) (by $rule $token)
                      (brand Statement $lookup-type) (the TV $source-tv)))
                   ($source-add (brand CompiledAddition ($source-premises |- $source-goal))))
                  (positive-implication-producer $query-ctx (brand Statement $lookup-type) $source-add)))))
      (collapse
         (let $lookup-type (copy_term $type)
            (match &kb ($lookup-type ($kb MAIN Nil) $proof $source-tv)
               (let*
                  (($source-goal (: (kbctx $kb) (brand Proof $proof)
                      (brand Statement $lookup-type) (the TV $source-tv)))
                   ($source-add (brand CompiledAddition (() |- $source-goal))))
                  (positive-implication-producer $query-ctx (brand Statement $lookup-type) $source-add)))))))

(: ConjunctionQueryPart (Alias (Statement Goal TV Proof)))

;; Implication judgments need a child query plan.
;; Other compound queries keep their adapters and computed-premise lowering.
(: conjunction-query-needs-lowering? (-[det]-> Statement Bool))
(= (conjunction-query-needs-lowering? $type)
   (if (head-is? $type Implication) true
      (if (head-is? $type And)
         (fold-flat conjunction-query-needs-lowering-step false
            (statement-children (cdr-atom $type)))
         false)))

(: conjunction-query-needs-lowering-step (-[det]-> Bool Statement Bool))
(= (conjunction-query-needs-lowering-step $found $child)
   (if $found true (conjunction-query-needs-lowering? $child)))

(: compile-conjunction-query
   (-[nondet]-> KB Statement TV CompilationPlan))

;; Compile a public query into one goal rule plus temporary additions.
;; Implication queries return the STV proved in the positive assumption context;
;; bidirectional queries require one context per direction. A concrete
;; Inheritance query accepts only the total-implication producer plus the
;; Member producer, which the chainer installs as ordinary rules when it
;; expands the link; ordinary direct proofs cannot answer its constrained root
;; goal.
;; A conjunction compiles implication children as ordinary STV statements;
;; other ordinary queries need only their source adapters.
(: compile-existential-query (-[nondet]-> KB AnnotatedStatement CompilationPlan))
(= (compile-existential-query $kb (: $prf $type $tv))
   (if (explicit-exists-term? $type)
      (let* (((premise-bundle $execs $result-tv $proof)
                 (lower-source-premise-with-existentials $kb MAIN Nil $type))
             ($query-tv (statement-query-tv $tv))
             ($canonical (canonical-existential-side $type)))
         (compilation-plan (: (kbctx $kb) $prf (ExistsJudgment $canonical) $query-tv)
            (cons (brand CompiledAddition
               ($execs |- (: (kbctx $kb) $proof (ExistsJudgment $canonical) $result-tv))) ())))
      (let* (((Implication $a $b) $type)
             ($_valid (validate-explicit-exists-rule $a $b))
             ($canonical (Implication
                (canonical-existential-side (brand Statement $a))
                (canonical-existential-side (brand Statement $b))))
             ($hash (index-hash $canonical))
             ($scope (make-kb-context (brand KB (implication-query $kb)) MAIN Nil))
             ($query-tv (statement-query-tv $tv)))
         (once (match &kb ((QuantifiedRule $hash $stored) $scope $proof $value)
            (if (=alpha $canonical $stored)
               (compilation-plan
                  (: $scope $prf (QuantifiedRule $hash $stored) $query-tv) ())
               (empty)))))))

(: compileQuery
   (-[nondet]-> KB AnnotatedStatement CompilationPlan))
(= (compileQuery $kb (: $prf $Type $tv))
   (if (head-is? $Type ExistentialAlternatives)
      (let* (((ExistentialAlternatives $claim $channel) $Type)
             ((Exists $_binder $body) (existential-source $claim))
             ($groups (list_to_set (extract-vars $claim)))
             ((premise-bundle $execs $witness-tv $_witness-proof)
                (fold-existential-premise-bundle $kb MAIN Nil
                   (brand Statement $body) (the (List Variable) $groups) OrFormula (STV 0 0))))
         (compilation-plan (: (kbctx $kb) $prf $Type $tv)
            (the (List CompiledAddition)
               ((((: (kbctx $kb) $claim-proof $claim $claim-tv)
                  (CPU existential-outer-values? ($groups) true))
                    |- (: (kbctx $kb) $claim-proof
                       (ExistentialAlternatives $claim direct) $claim-tv))
                ($execs |- (: (kbctx $kb) cpu
                   (ExistentialAlternatives $claim witnesses) $witness-tv))))))
   (if (is-var $Type)
      (compilation-plan (: (kbctx $kb) $prf $Type $tv) ())
      (if (contains-explicit-exists? $Type)
         (compile-existential-query $kb (: $prf $Type $tv))
      (if (= $Type (Assuming $facts $goal))
         ;; The facts hold in a fresh context that sees the world: the goal's
         ;; answers there, one per binding of its variables
         ;; (docs/metta/assumption_queries.md).
         ;; It has no hypothetical individual, so its context names no
         ;; variables and its keys stay ground.
         (let*
            ((($shape-kb $prf $b $adds)
                (query-side $kb Nil false (brand Statement $facts) (brand Statement $goal)))
             ($_world (context-world! $shape-kb (brand Statement $facts))))
            (compilation-plan
               (: (kbctx $kb) $root-prf $Type $tv)
               (cons
                  (brand CompiledAddition
                     ((the (List Goal) ((: $shape-kb $prf $b $tv)))
                        |- (: (kbctx $kb) (assuming $prf) $Type $tv)))
                  $adds)))
      (if (= $Type (Implication $stated-antecedent $stated-consequent))
         ;; A nested implication a → (x → y) is judged as its exported form
         ;; (a ∧ x) → y (docs/metta/derived_implications.md): its contexts
         ;; assume a and x and prove y, and the answer keeps the stated form.
         (let ($antecedent $consequent)
            (if (implication-type? (brand Statement $stated-consequent))
               (let ($inner $last) (nested-implication-parts (brand Statement $Type))
                  (data (cons And $inner) $last))
               (data $stated-antecedent $stated-consequent))
         (let*
            (($query-tv (statement-query-tv $tv))
             ($query-kb (brand KB (implication-query $kb)))
             ($query-ctx (make-kb-context $query-kb MAIN Nil))
             ($mvars (query-variables (extract-vars $Type)))
             (($pos-shape-kb $pos-prf $b $pos-adds)
                (judgment-query-side $kb $mvars false
                   (brand Statement $antecedent)
                   (brand Statement $consequent))))
            (compilation-plan
               (: $query-ctx $root-prf $Type $query-tv)
               (cons
                  (brand CompiledAddition
                     ((the (List Goal) ((: $pos-shape-kb $pos-prf $b $query-tv)))
                        |- (: $query-ctx (conditional-implication $pos-prf) $Type $query-tv)))
                  (append-compiled-additions
                     (implication-statement-query-adds $kb $query-ctx (brand Statement $Type))
                     (append-compiled-additions
                        (map-flat (positive-implication-producer $query-ctx (brand Statement $Type))
                           (if (rule-truth-installed? $kb $Type)
                              (rule-truth-query-adds $kb $Type $antecedent $consequent)
                              (compile-implication-instance-adds true $kb
                                 (brand Statement $Type)
                                 (brand Statement $antecedent)
                                 (brand Statement $consequent))))
                        $pos-adds))))))
         (if (implication-type? $Type) (empty)
         (if (bidirectional-implication-type? $Type)
            (let*
               ((($_head $left $right) $Type)
                ($mvars (query-variables (extract-vars $Type)))
                (($left-shape-kb $left-prf
                      $left-goal-expr $left-adds)
                    (judgment-query-side $kb $mvars false
                       (brand Statement $left)
                       (brand Statement $right)))
                 (($right-shape-kb $right-prf
                      $right-goal-expr $right-adds)
                    (judgment-query-side $kb $mvars false
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
               (if (if (head-is? $Type And) (conjunction-query-needs-lowering? $Type) false)
                  (compile-conjunction-query $kb $Type $tv)
                  (let $query-tv (if (head-is? $Type And) (statement-query-tv $tv) $tv)
                     (compilation-plan
                        (: (kbctx $kb) $prf $Type $query-tv)
                        (collapse (compile-adapter-chain query
                           (: (kbctx $kb) $prf $Type $query-tv)))))))))))))))

(: compile-conjunction-child
   (-[nondet]-> KB Statement
       (ConjunctionQueryPart (List CompiledAddition))))
(= (compile-conjunction-child $kb $child)
   (let (compilation-plan $goal $adds)
      (once (compileQuery $kb (: $proof $child $tv)))
      (let (: $ctx $prf $type $child-tv) $goal
         (data (data (brand Statement $type)
                  (: (the KBContext $ctx) (brand Proof $prf) (brand Statement $type) $child-tv)
                  (the TV $child-tv) (brand Proof $prf))
            $adds))))

(: conjunction-query-fold
   (-[det]-> ((List Statement) CompiledPremises) ConjunctionQueryPart
       ((List Statement) CompiledPremises)))
(= (conjunction-query-fold ($types $premises) ($type $goal $tv $proof))
   (data (cons $type $types) (in_fold AndFormula $premises (data $goal $tv $proof))))

(= (compile-conjunction-query $kb $type $tv)
   (let*
      (($children (statement-children (cdr-atom $type)))
       ($plans (once (map-flat (compile-conjunction-child $kb) $children)))
       ($parts (the (List ConjunctionQueryPart) (map-flat fst $plans)))
       ($child-adds (map-flat snd $plans))
       ($adds (fold-flat union-compiled-additions () $child-adds))
       ((cons ($first-type $first-goal $first-tv $first-proof) $rest) $parts)
       (($reversed-types ($reversed-goals $reversed-proofs $result-tv))
          (fold-flat conjunction-query-fold
             (data (cons $first-type ())
                (the CompiledPremises
                   (data (cons $first-goal ()) (cons $first-proof ()) $first-tv)))
             $rest))
       ($result-type (brand Statement (cons And (reverse $reversed-types))))
       ($root-tv (statement-query-tv $tv))
       ($conclusion (: (kbctx $kb)
          (implication-proof-token (prepend-reversed-proofs $reversed-proofs ()))
          $result-type $result-tv)))
      (compilation-plan (: (kbctx $kb) $root-proof $result-type $root-tv)
         (cons (brand CompiledAddition
            ((prepend-reversed-goals $reversed-goals ()) |- $conclusion)) $adds))))

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
            $kbid $shape-kb
            $ctxprf $tv () $tv () $a $consequent
            (list_to_set (extract-vars $a))
            (cons (data $execs $proofs $atv) ())))))

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
