;; Indexed scoped fact reads and MAIN borrowing subscriptions.


(: sk-full-proof (-[det]-> Proof Proof))
(= (sk-full-proof $proof) (brand Proof (proof_dag_expand $proof)))
(: sk-full-fact (-[det]-> SkFact SkFact))
(= (sk-full-fact ($type $kbctx $proof $tv)) (data $type $kbctx (sk-full-proof $proof) $tv))
(: sk-read-fact (-[det]-> SkeletonFilter SkFact SkFact))
(= (sk-read-fact $filter ($type $scope $proof $tv))
   ;; Storage keeps one source value. A positive read projects its branch
   ;; without publishing a second value under the source's proof identity.
   (let $fact (data $type $scope $proof $tv)
      (case $filter (
         ((sk-filter $_want-proof $want-tv)
            (if (if (head-is? $want-tv STV)
                   (head-is-member? $type (Implication QuantifiedRule)) false)
               (case $tv (
                  ((CTV $positive $_negative)
                     ;; An executable conversion of a stated STV is the same
                     ;; source, not another positive judgment of it.
                     (let* (($source-proof (sk-step-proof $proof))
                            ($sources (kb-facts $type $scope))
                            ($conversion? (not (== (collapse (once
                               (let ($stored-type $stored-scope $stored-proof (STV $_s $_c))
                                  (superpose $sources)
                                  (if (=alpha (data $type $scope $source-proof)
                                              (data $stored-type $stored-scope $stored-proof))
                                     true (empty))))) ()))))
                        (if $conversion? $fact (data $type $scope $proof $positive))))
                  ($_other $fact)))
               $fact))
         (sk-any-filter $fact)))))
(: sk-fact-matches? (-[det]-> SkeletonFilter SkFact Bool))
(= (sk-fact-matches? $filter $fact)
   (case (copy_term $filter) (
      (sk-any-filter true)
      ((sk-filter $want-proof $want-tv)
         (let $read (sk-read-fact $filter $fact)
            (sk-pattern-matches? $want-proof $want-tv (copy_term $read)))))))
(: sk-pattern-matches? (-[det]-> Proof TV SkFact Bool))
(= (sk-pattern-matches? $want-proof $want-tv ($type ($_kb $ctx $_vars) $got-proof $got-tv))
   ;; Executable Assuming seeds wake their applications, but supply no
   ;; positive judgment of the assumed implication.
   (if (if (head-is? $want-tv STV)
          (if (== $ctx MAIN) (if (implication-type? $type) (assumption-proof? $got-proof) false) false)
          false) false
   (if (if (is-var $want-proof) true
           (if (head-is? $want-proof derived-implication)
              (let $step (sk-step-proof $got-proof) (head-is? $step by))
              (= (sk-full-proof $got-proof) $want-proof)))
      (if (is-var $want-tv) true (= $got-tv $want-tv))
      false)))
(: sk-leaf-facts (-[det]-> Statement KBContext SkeletonFilter (List SkFact)))
(= (sk-leaf-facts $type $kbctx $filter)
   (let* (($plain (not (space-row-present? &materialized_facts (quote (materialized-row $_hash $_type $_kb $_fact $_ev)))))
          ($local (foldr-flat (sk-leaf-fact-step $plain $filter) () (kb-facts $type $kbctx))))
      (case $kbctx (
            (($kbid $ctx $vars)
               (if (judgment-world-premise? $type $kbctx)
                  (let $_watch (sk-watch-world! $type $kbctx (brand KB $kbid))
                     (foldr-flat (sk-judgment-main-fact-step $kbctx $plain $filter) $local
                        (kb-facts $type (kbctx (brand KB $kbid)))))
                  $local))))))
(: sk-watch-world! (-[det]-> Statement KBContext KB Atom))
(= (sk-watch-world! $type $kbctx $kbid)
   (let* (($key (sk-key $type $kbctx)) ($hash (index-hash $key)))
      (if (== (collapse (once (match &sk_world_reader ($hash $stored)
                  (if (=alpha $stored $key) true (empty))))) ())
         (let* (($_reader (add-atom &sk_world_reader ($hash $key)))
                ($lookup (copy_term $type))
                ($prefixes (cons (statement-open-hash $type) (statement-open-probes $type)))
                ($_prefixes (collapse (let $prefix (superpose $prefixes)
                   (let $slot (index-hash (data $kbid $prefix))
                      (add-atom &sk_world_prefix ($slot $lookup $kbid $key))))))
                ($_open (if (== (extract-vars $type) ()) ()
                   (let $slot (index-hash (data $kbid (statement-open-hash $type)))
                      (add-atom &sk_world_open ($slot $lookup $kbid $key))))))
            ())
         ())))
(: sk-world-readers (-[det]-> Statement KB (List SkeletonKey)))
(= (sk-world-readers $type $kbid)
   (let* (($prefix (statement-open-hash $type))
          ($slot (index-hash (data $kbid $prefix)))
          ($shorter (statement-open-probes $type)))
      (append-flat
         (collapse (match &sk_world_prefix ($slot $type $kbid $key) $key))
         (collapse (let $open (superpose $shorter)
            (let $open-slot (index-hash (data $kbid $open))
               (match &sk_world_open ($open-slot $type $kbid $key) $key)))))))
(: sk-leaf-fact-step (-[det]-> Bool SkeletonFilter SkFact (List SkFact) (List SkFact)))
(= (sk-leaf-fact-step $plain $filter $fact $facts)
   (let $read (sk-read-fact $filter $fact)
      (if (sk-fact-matches? $filter $read)
         (if (chainer-acyclic-term? $read)
            (if $plain (cons $read $facts)
               (if (materialized-forward-fact? $fact) $facts (cons $read $facts)))
            $facts)
         $facts)))
(: sk-judgment-main-fact-step
   (-[det]-> KBContext Bool SkeletonFilter SkFact (List SkFact) (List SkFact)))
(= (sk-judgment-main-fact-step $kbctx $plain $filter ($type $main $proof $tv) $facts)
   (if (judgment-consequent? true $type $kbctx) $facts
   (if (judgment-assumed-key? $type $kbctx) $facts
      (if (== (sk-leaf-fact-step $plain $filter (data $type $main $proof $tv) ()) ()) $facts
         (let $hash (index-hash (sk-key $type $main))
            (if (space-row-present? &sk_forward_stored ($hash $_key ($type $main $proof $tv) $_ev $_deps)) $facts
               (cons (sk-read-fact $filter (data $type $kbctx $proof $tv)) $facts)))))))
(: context-vars-in-type? (-[det]-> Atom Atom Bool))
(= (context-vars-in-type? $type $vars)
   (if (== $vars Nil) false
      (let $type-vars (extract-vars $type)
         (any-flat? (|-> ($var) (stored-list-member? $var $type-vars))
            (the (List Variable) $vars)))))
(: judgment-consequent? (-[det]-> Bool Atom KBContext Bool))
(= (judgment-consequent? $instances? $type ($kbid $ctx $vars))
   (let* ((($base $_negated) (canon (brand Statement $type)))
          ($scope (make-kb-context (brand KB (judgment-consequent $kbid)) $ctx $target-vars))
          ($targets (kb-facts $base $scope)))
      (not (== (collapse (once
         (let ($target ($_metadata-kb $_metadata-ctx $stored-vars) $_proof $_tv) (superpose $targets)
            (if (if $instances? (=alpha $base $target)
                    (=alpha (data $base $vars) (data $target $stored-vars))) true (empty))))) ()))))
(: judgment-world-premise? (-[det]-> Statement KBContext Bool))
(= (judgment-world-premise? $type ($kbid $ctx $vars))
   (if (== $ctx MAIN) false
      (if (judgment-consequent? true $type (make-kb-context (brand KB $kbid) $ctx $vars)) false
      (if (== $vars Nil) true
         (if (== (extract-vars $vars) $vars) (not (context-vars-in-type? $type $vars)) false)))))
(: judgment-assumed-key? (-[det]-> Atom KBContext Bool))
(= (judgment-assumed-key? $type $kbctx)
   (if (judgment-assumption-fact? $type $kbctx) true
      (judgment-assumption-fact? (JudgmentPrior $type) $kbctx)))
(: judgment-assumption-fact? (-[det]-> Atom KBContext Bool))
(= (judgment-assumption-fact? $type $kbctx)
   (let* ((($probe-type $probe-ctx) (copy_term (data $type $kbctx)))
          ($facts (let ($lookup-type $lookup-ctx) (copy_term (data $probe-type $probe-ctx))
             (kb-facts (brand Statement $lookup-type) (brand KBContext $lookup-ctx)))))
      (not (== (collapse (once (let ($assumed $assumed-ctx $proof $_tv) (superpose $facts)
         (if (assumption-proof? (brand Proof $proof))
            (if (=alpha (data $probe-type $probe-ctx) (data $assumed $assumed-ctx)) true
               ;; An open reader can consume a ground assumption. Match a
               ;; copy so this test cannot bind the rule's premise variables;
               ;; non-ground hypothetical keys still require alpha identity.
               (if (== (extract-vars $assumed) ())
                  ;; Indexed unification can ground a hypothetical variable.
                  ;; Its context must still have the original sharing shape.
                  (if (=alpha $probe-ctx $assumed-ctx)
                     (if (= (copy_term $probe-type) $assumed) true (empty))
                     (empty))
                  (empty)))
            (empty))))) ()))))
