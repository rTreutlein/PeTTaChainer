;; Query contexts, query-local additions, and query-goal lowering.
;; One side of a total-implication / bidirectional query: allocate a fresh
;; query context, lower the premises (negatively for the refuting side of a
;; total implication, positively otherwise), and collect the context + adapter
;; atoms the chainer needs to resolve this side's conclusion. Returns the ground
;; shape-kb, the bundle reading the conclusion there (a negated conclusion
;; reads its statement), and the side's adds.
;;
;; Judgment contexts know the whole compound antecedent as well as its
;; lowered parts. In particular a Not reader of a ground And must read that
;; conjunction as assumed true, rather than finding no contextual fact and
;; falling back to MAIN. Assuming queries retain their ordinary fact lowering.
;; The antecedent is judged with its double negations cancelled.
(: judgment-query-side
   (-[semidet]-> KB (| NilType (List Variable)) Bool
       Statement Statement
       (KBContext PremiseBundle (List CompiledAddition))))
(= (judgment-query-side $kb $mvars $negative? $antecedent $consequent)
   (let* ((($key $odd) (canon $antecedent))
          ($normalized (if $odd (brand Statement (Not $key)) $key))
          ($nnf (query-assumption-nnf $normalized)))
      (if (if $negative? false
              (if (contains-head? (== Or) $normalized) true (contains-head? (== Or) $nnf)))
         (disjunction-judgment-query-side $kb $mvars $normalized $consequent)
         (if (if $negative? (head-is? $normalized Or) false)
            (let $refuting (brand Statement (cons And
                   (map-flat (|-> ($child) (brand Statement (Not $child)))
                      (statement-children (cdr-atom $normalized)))))
               (judgment-query-side-basic $kb $mvars false false $refuting $consequent))
            (judgment-query-side-basic $kb $mvars $negative? false $normalized $consequent)))))

(: judgment-query-side-basic
   (-[semidet]-> KB (| NilType (List Variable)) Bool Bool Statement Statement
       (KBContext PremiseBundle (List CompiledAddition))))
(= (judgment-query-side-basic $kb $mvars $negative? $whole-only? $antecedent $consequent)
   (once (let*
      (($ctx (nextctx))
       ($shape-kb (make-kb-context $kb $ctx $mvars))
       ($premises (implication-side-conjuncts $antecedent))
       (($execs $_proofs $_atv)
          (if $whole-only?
             (data (map-flat (judgment-whole-premise $shape-kb) $premises) () (STV 1 1))
             (once (if $negative?
                      (lower-query-assumption-premises-negative $kb $ctx $mvars $premises)
                      (lower-query-assumption-premises $kb $ctx $mvars $premises)))))
       ($goal (if (contains-explicit-exists? $consequent)
                  (let $claim (canonical-existential-side $consequent)
                     (brand Statement (ExistsJudgment $claim)))
                  $consequent))
       ;; The consequent is read as a whole: a negation through its view, so
       ;; its evidence is the statement's as written; a compound through its
       ;; key, whose producers the chainer installs.
       ($goal-adds
          (collapse (if (contains-explicit-exists? $consequent)
             (let (premise-bundle $goal-execs $goal-tv $goal-proof)
                (lower $shape-kb $consequent)
                (brand CompiledAddition ($goal-execs |- (: $shape-kb $goal-proof $goal $goal-tv))))
             (root-adapters (: $shape-kb $prf $consequent $adapter-tv)))))
       ($goal-read (premise-bundle ((: $shape-kb $read-proof $goal $read-tv)) $read-tv $read-proof))
       ;; Query-local metadata uses the existing temporary fact lifecycle in
       ;; a separate namespace: it is never available as a logical premise.
       ($target-kb (make-kb-context (brand KB (judgment-consequent $kb)) $ctx $mvars))
       (($target $_negated) (canon $goal))
       ($adds (cons (brand CompiledAddition
          (() |- (: $target-kb (ctx consequent $ctx) $target (STV 1 1))))
          (union-compiled-additions
             (query-context-premise-adds $kb $ctx $mvars (the (List Goal) $execs)) (the (List CompiledAddition) $goal-adds))))
       ($whole-tv (if $negative? (STV 0 1) (STV 1 1))))
      (data $shape-kb $goal-read
         (if (head-is-member? $antecedent (And Or))
            (cons (brand CompiledAddition
               (() |- (: $shape-kb (ctx proof $ctx whole) $antecedent $whole-tv)))
               $adds)
            $adds)))))

;; A rule reading a whole event already knows its conditional, even when
;; the event's population probability is unknown. This separate context never
;; makes the prior world's event certain or selects any of its alternatives.
(: judgment-whole-premise (-[det]-> KBContext Atom Goal))
(= (judgment-whole-premise $scope $source)
   (let ($key $odd) (canon (brand Statement $source))
      (: $scope $proof $key (if $odd (STV 0 1) (STV 1 1)))))

;; Evaluate P(B and D) in the private prior world, then divide by P(D).
;; Unlike making every disjunct true, this preserves the alternatives of D.
;; Ordinary shared-premise conditioning computes the numerator, including
;; the dependence between B and the disjuncts it reads. No Boolean worlds
;; are enumerated by the compiler.
(: disjunction-judgment-prior (-[nondet]-> KB $context $variables Statement CompiledAddition))
(= (disjunction-judgment-prior $kb $ctx $vars $source)
   (let ($type $_odd) (canon $source)
      (if (head-is-member? $type (And Or))
         (let* (($children (statement-children (cdr-atom $type))) ($child (superpose $children)))
            (disjunction-judgment-prior $kb $ctx $vars $child))
         (let* (($scope (make-kb-context $kb $ctx $vars))
                ($marker (brand Statement (JudgmentPrior $type)))
                ($idx (index-hash $type))
                ($rate-goals (base-rate-premises $kb (rule-base-rate-pattern () $type) $rate))
                ($premises (cons (: $scope $assumption $marker (STV 1 1)) $rate-goals)))
            (superpose (
               (brand CompiledAddition (() |- (: $scope (ctx proof $ctx $idx) $marker (STV 1 1))))
               (brand CompiledAddition
                  ($premises |- (: $scope (judgment-prior $assumption) $type $rate)))))))))

(: disjunction-judgment-query-side
   (-[semidet]-> KB (| NilType (List Variable)) Statement Statement
       (KBContext PremiseBundle (List CompiledAddition))))
(= (disjunction-judgment-query-side $kb $mvars $antecedent $consequent)
   (once (let* (($parts (implication-side-conjuncts $antecedent))
          (($alternatives $fixed) (foldr-flat judgment-condition-part (() ()) $parts))
          ($event (brand Statement (seq2expr (the (List Atom) $alternatives))))
          ($assumptions (brand Statement (seq2expr
             (cons (JudgmentPrior $event) (the (List Atom) $fixed)))))
          (($scope $_assumed-read $adds)
             (judgment-query-side-basic $kb $mvars false false $assumptions $consequent))
          (($kbid $ctx $vars) $scope)
          ($priors (list_to_set (collapse (disjunction-judgment-prior $kb $ctx $mvars $event))))
          ;; The probability read retains the source event's key. Its joint
          ;; uses Boolean normal form, including negated compounds.
          ($normal-event (query-assumption-nnf $event))
          ($joint (brand Statement (And $consequent $normal-event)))
          ($result (brand Statement (JudgmentConditioned $antecedent $consequent)))
          ($rates (base-rate-premises $kb (rule-base-rate-pattern () $event) $rate))
          ($result-premises (cons (: $scope $joint-proof $joint $joint-tv)
             (append-goals $rates ((CPU AndProjection ($joint-tv $rate) $result-tv)))))
          ($result-add (brand CompiledAddition
             ($result-premises |-
                (: $scope (conditioned-disjunction $joint-proof) $result $result-tv))))
          (($_direct-scope (premise-bundle $direct-goals $direct-tv $direct-proof) $direct-adds)
             (judgment-query-side-basic $kb $mvars false true $antecedent $consequent))
          ($direct-add (brand CompiledAddition
             ($direct-goals |- (: $scope (conditioned-disjunction $direct-proof) $result $direct-tv)))))
      (data $scope (premise-bundle ((: $scope $result-proof $result $result-read-tv)) $result-read-tv $result-proof)
         (cons $direct-add (cons $result-add (append-compiled-additions $direct-adds
            (append-compiled-additions $adds $priors))))))))

;; A collapse/superpose partition would freshen the hypothetical variables
;; away from the consequent. Keep the source sharing through this fold.
(: judgment-condition-part (-[det]-> Atom ((List Atom) (List Atom)) ((List Atom) (List Atom))))
(= (judgment-condition-part $part ($alternatives $fixed))
   (let $nnf (query-assumption-nnf (brand Statement $part))
      (if (if (contains-head? (== Or) $part) true (contains-head? (== Or) $nnf))
         (data (cons $part $alternatives) $fixed)
         (data $alternatives (cons $part $fixed)))))

;; The two sides of a total-implication query share one conclusion $b and differ
;; only in polarity. Returns the ground shape-kbs, $b, the fresh pos/neg proof
;; vars (used by the caller in its known goals and proof token), and all adds.
(: query-pos-neg-scaffold
   (-[semidet]-> KB (| NilType (List Variable))
       Statement Statement
       (KBContext KBContext PremiseBundle PremiseBundle (List CompiledAddition))))
(= (query-pos-neg-scaffold $kb $mvars $antecedent $consequent)
   (let*
      ((($pos-shape-kb $pos-read $pos-adds)
          (judgment-query-side $kb $mvars false $antecedent $consequent))
       (($neg-shape-kb $neg-read $neg-adds)
          (judgment-query-side $kb $mvars true $antecedent $consequent)))
      (data
         $pos-shape-kb $neg-shape-kb $pos-read $neg-read
         (union-compiled-additions $pos-adds $neg-adds))))

;; Under rule refinement a rule's instance fold proves its rule-truth goal
;; (see `set-rule-refinement`), so an implication query of that shape reads
;; goal's positive branch instead of folding the instances again.
(: rule-truth-installed? (-[det]-> KB Atom Bool))
(= (rule-truth-installed? $kb $Type)
   (not (== (collapse (once (match &rule_truth_shapes ($kb $stored)
      (if (term-covers? $stored (RuleTruth $Type)) true (empty))))) ())))

(: rule-truth-query-adds (-[det]-> KB Atom Atom Atom (List CompiledAddition)))
(= (rule-truth-query-adds $kb $Type $antecedent $consequent)
   (let* ((($ctv-goals $ctv $_likelihoods)
             (implication-ctv-goals $kb () (brand Statement $antecedent) (brand Statement $consequent) $truth-tv false))
          ($premises (cons (: (kbctx $kb) $truth-prf (RuleTruth $Type) $truth-tv) $ctv-goals)))
      (cons
         (brand CompiledAddition
            (cons $premises (cons |- (cons (: (kbctx $kb) (rule-truth $truth-prf) $Type $ctv) ()))))
         ())))

;; Storage keeps both rule branches; public statement judgments use the positive one.
(: query-positive-tv (-[semidet]-> TV STVType))
(= (query-positive-tv $tv) (case $tv (((CTV $pos $_neg) $pos) ((STV $s $c) (STV $s $c)))))

(: statement-query-tv (-[semidet]-> TV STVType))
(= (statement-query-tv $tv)
   (if (is-var $tv) (STV $strength $confidence)
      (case $tv (((STV $s $c) (STV $s $c)) ($_other (empty))))))

;; A nested implication a → (x → y) is judged as its exported form (a ∧ x) → y
;; (docs/metta/derived_implications.md): the antecedent its query contexts
;; assume and the consequent they prove. Answers keep the stated form.
(: implication-query-sides (-[semidet]-> Statement (Statement Statement)))
(= (implication-query-sides $type)
   (let (Implication $a $b) $type
      (if (implication-type? (brand Statement $b))
         (let ($parts $last) (nested-implication-parts $type)
            (data (brand Statement (cons And $parts)) $last))
         (data (brand Statement $a) (brand Statement $b)))))

;; Private implication premises read both branches for modus ponens. Public
;; compileQuery never calls this CTV plan.
(: compile-implication-subgoal-query (-[semidet]-> KB AnnotatedStatement CompilationPlan))
(= (compile-implication-subgoal-query $kb (: $prf (Implication $a $b) (CTV $pos $neg)))
   (let*
      (($type (brand Statement (Implication $a $b)))
       (($antecedent $consequent) (implication-query-sides $type))
       ($mvars (query-variables (extract-vars $type)))
       (($_pk $_nk (premise-bundle $pos-goals $pos-tv $pp) (premise-bundle $neg-goals $neg-tv $np) $adds)
          (query-pos-neg-scaffold $kb $mvars $antecedent $consequent)))
      (compilation-plan (: (kbctx $kb) $prf $type (CTV $pos $neg))
         (cons (brand CompiledAddition
            ((append-goals $pos-goals $neg-goals)
               |- (: (kbctx $kb) (total-implication-frontier (total-implication $pp $np)) $type (CTV $pos-tv $neg-tv))))
            (append-compiled-additions
               (if (rule-truth-installed? $kb $type)
                  (rule-truth-query-adds $kb $type $antecedent $consequent)
                  (compile-implication-instance-adds true $kb $type $antecedent $consequent))
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

(: implication-statement-query-adds (-[det]-> KB KBContext Statement (List CompiledAddition)))
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

;; Compile a public query into one goal rule plus temporary additions.
;; Implication queries return the STV proved in the positive assumption context;
;; bidirectional queries require one context per direction.
;; A conjunction compiles implication children as ordinary STV statements;
;; other ordinary queries need only their source adapters.
(: compile-existential-query (-[nondet]-> KB AnnotatedStatement CompilationPlan))
(= (compile-existential-query $kb (: $prf $type $tv))
   (if (explicit-exists-term? $type)
      (let* (((premise-bundle $execs $result-tv $proof)
                 (lower (kbctx $kb) $type))
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
             ($query-tv (statement-query-tv $tv))
             ($mvars (query-variables (extract-vars $canonical)))
             (($_positive (premise-bundle $positive-goals $positive-tv $positive-proof) $adds)
                (judgment-query-side $kb $mvars false (brand Statement $a) (brand Statement $b))))
         (compilation-plan (: $scope $prf (QuantifiedRule $hash $canonical) $query-tv)
            (cons (brand CompiledAddition
               ($positive-goals
                  |- (: $scope (conditional-implication $positive-proof)
                     (QuantifiedRule $hash $canonical) $positive-tv))) $adds)))))

;; Reopen canonical slots with fresh local binders before an Assuming answer
;; can bind free goal variables. Equal source spellings across scopes must not
;; turn a binder into a categorical individual in the public answer.
(: scope-query-existentials (-[nondet]-> Atom Statement))
(= (scope-query-existentials $statement)
   (if (head-is? $statement And)
      (let $children (the (List Atom) (cdr-atom $statement))
         (brand Statement (cons And (map-flat scope-query-existentials $children))))
      (if (source-exists? $statement)
         (let $canonical (canonical-existential-side (brand Statement $statement))
            (existential-source $canonical))
         (brand Statement $statement))))

;; An Assuming fact written `(: name statement tv)` is held in the query's
;; world with that value at its canonical key, as `compileadd` would store it;
;; a bare fact is certain. Only Assuming facts take this form;
;; `check-query-annotations!` rejects an annotation in any other statement
;; position.
(: assuming-premises-step
   (-[nondet]-> KB $context (List Goal) Atom (List Goal)))
(= (assuming-premises-step $kb $ctx $reversed $premise)
   (if (head-is? $premise :)
      (let* ((($source $value) (weighted-assumption $premise))
             (($type $odd) (canon (brand Statement $source))))
         (cons (: (make-kb-context $kb $ctx Nil) $prf $type (if $odd (NotFormula (the STVType $value)) $value)) $reversed))
      (let (premise-bundle $execs $_tv $_proof)
         (lower-query-assumption-premise $kb $ctx Nil (brand Statement $premise))
         (prepend-reversed-goals $execs $reversed))))

;; A class link's instance estimate depends only on the link, so its sample
;; and fold rules are permanent backward rules, installed once when a root or
;; an expanded node of the link or of an instance of it needs them
;; (install-class-link-rules!):
;; their rows outlive the query, and a later query reads the tally instead of
;; sampling the population again. A query of the link, or of the link applied
;; to one constant, which the link's rules answer for that constant, leaves
;; them out of its own additions. The fold concludes the samples' frequency as
;; it is: a query answers the positive branch, which a CTV would make
;; consistent with base rates that may not count a derived member yet.
(: class-link-query-adds (-[nondet]-> KB KBContext Statement (List CompiledAddition)))
(= (class-link-query-adds $kb $query-ctx $type)
   (let* ((($antecedent $consequent) (implication-query-sides $type))
          ($adds (compile-implication-instance-adds false $kb $type $antecedent $consequent)))
      (map-flat (positive-implication-producer $query-ctx $type) $adds)))

(: compileQuery (-[nondet]-> KB AnnotatedStatement CompilationPlan))
(= (compileQuery $kb (: $prf $Type $tv))
   (if (head-is? $Type ExistentialAlternatives)
      (let* (((ExistentialAlternatives $claim $channel) $Type)
             ((Exists $_binder $body) (existential-source $claim))
             ($groups (list_to_set (extract-vars $claim)))
             ($alternative-kb (make-kb-context $kb $alternative-ctx $alternative-vars))
             ((premise-bundle $execs $witness-tv $_witness-proof)
                (fold-existential-premise-bundle (kbctx $kb)
                   (brand Statement $body) (the (List Variable) $groups) OrFormula (STV 0 0))))
         (compilation-plan (: (kbctx $kb) $prf $Type $tv)
            (the (List CompiledAddition)
               ((((: $alternative-kb $claim-proof $claim $claim-tv)
                  (CPU existential-outer-values? ($groups) true))
                    |- (: $alternative-kb $claim-proof
                       (ExistentialAlternatives $claim direct) $claim-tv))
                ($execs |- (: $alternative-kb cpu
                   (ExistentialAlternatives $claim witnesses) $witness-tv))))))
   (if (is-var $Type)
      (compilation-plan (: (kbctx $kb) $prf $Type $tv) ())
      (if (if (head-is? $Type Assuming) (= $Type (Assuming $facts $goal)) false)
         (let* (($scoped-facts (scope-query-existentials $facts))
                ($scoped-goal (scope-query-existentials $goal))
                ($ctx (nextctx))
                ($scope (make-kb-context $kb $ctx Nil))
                ($premises (implication-side-conjuncts $scoped-facts))
                ($execs (prepend-reversed-goals
                   (fold-flat (assuming-premises-step $kb $ctx) () $premises) ()))
                ($assumed (query-context-premise-adds $kb $ctx Nil $execs))
                ($_world (context-create! $scope))
                ((compilation-plan $inner $adapters)
                   (compileQuery $kb (: $inner-proof $scoped-goal $inner-tv))))
            (compilation-plan
               (CPU ContextQuery (quote ($scope $scoped-facts $inner $prf $tv)) $result)
               (append-compiled-additions $assumed $adapters)))
      (if (source-exists? $Type)
         (compile-existential-query $kb (: $prf $Type $tv))
      (if (if (head-is? $Type Implication) (= $Type (Implication $_antecedent $_consequent)) false)
         (let*
            ((($antecedent $consequent) (implication-query-sides (brand Statement $Type)))
             ($query-tv (statement-query-tv $tv))
             ($query-kb (brand KB (implication-query $kb)))
             ($query-ctx (make-kb-context $query-kb MAIN Nil))
             ($mvars (query-variables (extract-vars $Type)))
             (($_pos-shape-kb (premise-bundle $pos-goals $pos-tv $pos-prf) $pos-adds)
                (judgment-query-side $kb $mvars false $antecedent $consequent)))
            (compilation-plan
               (: $query-ctx $root-prf $Type $query-tv)
               (cons
                  (brand CompiledAddition
                     ($pos-goals |- (: $query-ctx (conditional-implication $pos-prf) $Type $pos-tv)))
                  (append-compiled-additions
                     (implication-statement-query-adds $kb $query-ctx (brand Statement $Type))
                     (append-compiled-additions
                        (map-flat (positive-implication-producer $query-ctx (brand Statement $Type))
                           (if (rule-truth-installed? $kb $Type)
                              (rule-truth-query-adds $kb $Type $antecedent $consequent)
                              (if (class-link-instance? $antecedent $consequent) (the (List CompiledAddition) ())
                                 (compile-implication-instance-adds true $kb
                                    (brand Statement $Type) $antecedent $consequent))))
                        $pos-adds)))))
         (if (implication-type? $Type) (empty)
         (if (bidirectional-implication-type? $Type)
            (let*
               ((($_head $left $right) $Type)
                ($mvars (query-variables (extract-vars $Type)))
                (($_left-shape-kb (premise-bundle $left-goals $left-tv $left-prf) $left-adds)
                    (judgment-query-side $kb $mvars false
                       (brand Statement $left)
                       (brand Statement $right)))
                 (($_right-shape-kb (premise-bundle $right-goals $right-tv $right-prf) $right-adds)
                    (judgment-query-side $kb $mvars false
                       (brand Statement $right)
                       (brand Statement $left)))
                 ($goal (: (kbctx $kb) (bidirectional $left-prf $right-prf) $Type $tv)))
               (compilation-plan
                  $goal
                  (cons
                     (brand CompiledAddition
                        ((append-goals $left-goals
                            (append-goals $right-goals ((CPU AndFormula ($left-tv $right-tv) $tv))))
                           |- $goal))
                     (union-compiled-additions $left-adds $right-adds))))
            (let $query-tv (if (head-is? $Type And) (statement-query-tv $tv) $tv)
               (compilation-plan
                  (: (kbctx $kb) $prf $Type $query-tv)
                  (collapse (root-adapters
                     (: (kbctx $kb) $prf $Type $query-tv)))))))))))))

;; Query assumptions with no caller-supplied TV are treated as certain. An
;; implication needs a CTV-shaped default because its positive and negative
;; support are tracked separately throughout the query compiler.
(: default-query-assumption-tv (-[det]-> Statement TV TV))
(= (default-query-assumption-tv $type $tv)
   (if (is-var $tv)
      (if (if (head-is? $type Implication) (= $type (Implication $_antecedent $_consequent)) false)
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))
         (STV 1.0 1.0))
      $tv))

;; An implication used as a query assumption must be executable inside its
;; fresh context, not merely stored as an inert contextual fact. Compile its
;; forward rule from every lowering of its antecedent, as `compile-rule` does,
;; against the same shaped KB so it can consume sibling assumptions. Its stated
;; value and its applications share one evidence identity, as a stored rule's
;; do, so neither supports the other.
(: query-context-assumed-implication-rules
   (-[det]-> KB $context $variables Proof Statement TV (List CompiledAddition)))
(= (query-context-assumed-implication-rules $kbid $ctx $mvars $ctxprf $type $tv)
   (if (not (head-is? $type Implication)) ()
      (case $type (
         ((Implication $antecedent $consequent)
            (let* (($a (brand Statement (implication-source-term $antecedent)))
                   ($shape-kb (make-kb-context $kbid $ctx $mvars))
                   ($_named (register-rule-evidence! $kbid $ctxprf $tv (== (extract-vars $type) ()))))
               ;; The producers of a compound the antecedent reads hold in the
               ;; assumption's own context, which no later query reuses.
               (append-compiled-additions
                  (collapse
                     (compile-implication-forward-rules
                        $kbid $shape-kb
                        $ctxprf $tv () $tv () $a (brand Statement $consequent)
                        (list_to_set (extract-vars $a))
                        (antecedent-lowerings $shape-kb (brand Statement $antecedent))))
                  (collapse (let $producers (producers $shape-kb $a) (superpose $producers))))))
         ($_other ())))))

(: query-context-premise-adds-step
   (-[det]-> KB $context $variables
       (Number (List CompiledAddition))
       Goal
       (Number (List CompiledAddition))))
(= (query-context-premise-adds-step $kbid $ctx $mvars ($idx $adds) $premise)
   (let $ctxprf
      (brand Proof (if (== $idx 0) (data ctx proof $ctx) (data ctx proof $ctx $idx)))
      (case $premise
         (((CPU $_fun $_args $_res) ($idx $adds))
             ((: $_kb $_prf $type $tv)
                (let $assumed-tv (default-query-assumption-tv $type $tv)
                   ((+ $idx 1)
                    (prepend-reversed-compiled-additions
                       (cons
                          (brand CompiledAddition
                             (() |- (: (make-kb-context $kbid $ctx $mvars)
                                        $ctxprf $type $assumed-tv)))
                          (query-context-assumed-implication-rules
                             $kbid $ctx $mvars $ctxprf $type $assumed-tv))
                       $adds))))
          ($_other ($idx $adds))))))

(: query-context-premise-adds (-[det]-> KB $context $variables (List Goal) (List CompiledAddition)))
(= (query-context-premise-adds $kbid $ctx $mvars $premises)
   (let ($_idx $adds)
      (fold-flat (query-context-premise-adds-step $kbid $ctx $mvars) (0 ()) $premises)
      (list_to_set (prepend-reversed-compiled-additions $adds ()))))
