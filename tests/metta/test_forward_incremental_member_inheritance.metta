!(import! &self ../../pettachainer/metta/petta_chainer)

(: member-test-fact
   (-[det]-> KB Term Term
       (List (Statement KBContext Proof TV))))
(= (member-test-fact $kb $obj $class)
   (collapse
      (once
         (match &kb
            ((Member $obj $class) ($kb MAIN Nil) $prf $tv)
            (let*
               (($type
                   (brand Statement (Member $obj $class)))
                ($kbctx
                   (brand KBContext (quote ($kb MAIN Nil))))
                ($proof (brand Proof $prf))
                ($truth-value (the TV $tv)))
               (assemble-runtime-fact
                  $type $kbctx $proof $truth-value))))))

(: member-fold-cache
   (-[nondet]-> KB Term Term
      (| TV (List $no-result))))
(= (member-fold-cache $kb $subj $concept)
   (cached-base-rate $kb
      (MemberInheritanceSample $obj $subj $concept $atv $btv)))

(: member-fold-observation-count
   (-[nondet]-> KB Term Term Number))
(= (member-fold-observation-count $kb $subj $concept)
   (let $id
      (fa-id (forward-member-inheritance-identity $kb $subj $concept))
      (list-count
         (collapse
            (match &forward_aggregate_observation
               (forward-aggregate-observation ($id $_obj) $_value $_weight $_mass)
               true)))))

(: materialized-inheritance-facts
   (-[det]-> KB Term Term (List AnnotatedStatement)))
(= (materialized-inheritance-facts $kb $subj $concept)
   (collapse
      (match &kb
         ((Inheritance $subj $concept) ($kb MAIN Nil) $proof $tv)
         (: $proof (Inheritance $subj $concept) $tv))))

;; Open Inheritance queries compile the same fold vocabulary, but variable
;; classes cannot provide selective forward indexes and must register nothing.
!(query 0 forwardOpenMemberFoldKb
   (: $proof (Inheritance $open-subj $open-concept) $tv))

!(test
   (collapse
      (match &forward_aggregate_identity
         ($_hash
            (forward-aggregate-identity-row
               (forward-member-inheritance-identity
                  forwardOpenMemberFoldKb $_subj $_concept)
               $_id))
         true))
   ())

!(test
   (collapse
      (match &forward_aggregate_interest_by_trigger
         ($_hash
            (forward-aggregate-interest
               (fwd_member forwardOpenMemberFoldKb $_class)
               $_id
               (forward-member-inheritance-descriptor
                  $_kb $_subj $_concept $_pattern)))
         true))
   ())

!(test
   (collapse
      (match &forward_aggregate_observation
         (forward-aggregate-observation
            $_key
            (forward-member-inheritance-observation-value
               $_subject $_concept)
            $_weight $_mass)
         true))
   ())

!(test
   (collapse
      (match &base_rate_cache
         ($_hash (base-rate forwardOpenMemberFoldKb $_pattern $_tv $_source $_mode))
         true))
   ())

;; A compound class with a nested variable is also open even though its
;; top-level term is an expression rather than a variable.
!(query 0 forwardCompoundOpenMemberFoldKb
   (: $proof
      (Inheritance (Qualified Human $open-qualifier) Mortal)
      $tv))

!(test
   (collapse
      (match &forward_aggregate_identity
         ($_hash
            (forward-aggregate-identity-row
               (forward-member-inheritance-identity
                  forwardCompoundOpenMemberFoldKb $_subj $_concept)
               $_id))
         true))
   ())

!(test
   (collapse
      (match &forward_aggregate_interest_by_trigger
         ($_hash
            (forward-aggregate-interest
               (fwd_member forwardCompoundOpenMemberFoldKb $_class)
               $_id
               (forward-member-inheritance-descriptor
                  $_kb $_subj $_concept $_pattern)))
         true))
   ())

!(test
   (collapse
      (match &forward_aggregate_observation
         (forward-aggregate-observation
            $_key
            (forward-member-inheritance-observation-value
               $_subject $_concept)
            $_weight $_mass)
         true))
   ())

!(test
   (collapse
      (match &base_rate_cache
         ($_hash (base-rate forwardCompoundOpenMemberFoldKb
            $_pattern $_tv $_source $_mode))
         true))
   ())

!(compileadd forwardMemberFoldKb
   (: aHuman (Member a Human) (STV 1.0 1.0)))
!(compileadd forwardMemberFoldKb
   (: aMortal (Member a Mortal) (STV 0.8 1.0)))

;; A zero-budget query installs the compiler-generated interest but performs no
;; backward or forward inference.  The exact interest shape registers once.
!(query 0 forwardMemberFoldKb
   (: $proof (Inheritance Human Mortal) $tv))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_identity
            ($_hash
               (forward-aggregate-identity-row
                  (forward-member-inheritance-identity
                     forwardMemberFoldKb Human Mortal)
                  $_id))
            true)))
   1)

!(test (member-fold-cache forwardMemberFoldKb Human Mortal) ())

;; Processing either indexed side recomputes only this object's joined pair.
!(forward-chain 1 forwardMemberFoldKb
   (member-test-fact forwardMemberFoldKb a Human))

!(test
   (member-fold-cache forwardMemberFoldKb Human Mortal)
   ((STV 0.8 0.0012484394506866417)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id a)
               (forward-member-inheritance-observation-value
                  $_subject $_concept)
               $_weight $_mass)
            true)))
   1)

;; Appending b adds one indexed observation without revisiting a.
!(compileadd forwardMemberFoldKb
   (: bHuman (Member b Human) (STV 0.5 1.0)))
!(compileadd forwardMemberFoldKb
   (: bMortal (Member b Mortal) (STV 0.4 1.0)))
!(forward-chain 1 forwardMemberFoldKb
   (member-test-fact forwardMemberFoldKb b Mortal))

!(test
   (member-fold-cache forwardMemberFoldKb Human Mortal)
   ((STV 0.6666666666666666 0.0018714909544603868)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id $_obj)
               (forward-member-inheritance-observation-value
                  $_subject $_concept)
               $_weight $_mass)
            true)))
   2)

;; A second Member fact for a is merged with the first.  Reprocessing that key
;; replaces a's contribution instead of adding a third observation.
!(compileadd forwardMemberFoldKb
   (: aHumanSecond (Member a Human) (STV 0.5 1.0)))
!(forward-chain 1 forwardMemberFoldKb
   (member-test-fact forwardMemberFoldKb a Human))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id $_obj)
               (forward-member-inheritance-observation-value
                  $_subject $_concept)
               $_weight $_mass)
            true)))
   2)

;; Removing one fact recomputes from the surviving one. Removing
;; the final support deletes a's joined contribution immediately.
!(remove-compiled-statement aHumanSecond)

!(test
   (member-fold-cache forwardMemberFoldKb Human Mortal)
   ((STV 0.6666666666666666 0.0018714909544603868)))

!(remove-compiled-statement aHuman)

!(test
   (let $id
      (fa-id (forward-member-inheritance-identity
         forwardMemberFoldKb Human Mortal))
      (collapse
         (match &forward_aggregate_state
            (forward-aggregate-state $id $weight $mass)
            ($weight $mass))))
   ((0.19999999999999996 0.5)))

!(test
   (member-test-fact forwardMemberFoldKb a Human)
   ())

!(test
   (member-fold-cache forwardMemberFoldKb Human Mortal)
   ((STV 0.3999999999999999 0.0006246096189881324)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id $_obj)
               (forward-member-inheritance-observation-value
                  $_subject $_concept)
               $_weight $_mass)
            true)))
   1)

;; The provisional value answers immediately, while an ordinary complete fold
;; refines it and upgrades the cache source without changing public provenance.
!(test
   (query 80 forwardMemberFoldKb
      (: $proof (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu)
      (Inheritance Human Mortal)
      (STV 0.3999999999999999 0.0006246096189881324)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom
         (base-rate-cache-entries forwardMemberFoldKb
            (MemberInheritanceSample $obj Human Mortal $atv $btv)))
      $source)
   computed)

;; A backward-computed fold decomposes into the same per-object observations
;; used by forward maintenance.  Processing only a newly added object can then
;; extend that complete snapshot without replaying the older population, and
;; the cache remains a computed snapshot rather than regressing to a partial
;; forward approximation.
!(compileadd computedForwardDeltaKb
   (: caHuman (Member a Human) (STV 1.0 1.0)))
!(compileadd computedForwardDeltaKb
   (: caMortal (Member a Mortal) (STV 0.8 1.0)))
!(compileadd computedForwardDeltaKb
   (: cbHuman (Member b Human) (STV 0.5 1.0)))
!(compileadd computedForwardDeltaKb
   (: cbMortal (Member b Mortal) (STV 0.4 1.0)))
!(query 80 computedForwardDeltaKb
   (: $_proof (Inheritance Human Mortal) $_tv))

!(test
   (member-fold-observation-count
      computedForwardDeltaKb Human Mortal)
   2)

!(compileadd computedForwardDeltaKb
   (: ccHuman (Member c Human) (STV 1.0 1.0)))
!(compileadd computedForwardDeltaKb
   (: ccMortal (Member c Mortal) (STV 0.6 1.0)))
!(test
   (forward-chain 1 computedForwardDeltaKb
      (member-test-fact computedForwardDeltaKb c Mortal))
   ())

!(test
   (member-fold-cache computedForwardDeltaKb Human Mortal)
   ((STV 0.64 0.003115264797507788)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom
         (base-rate-cache-entries computedForwardDeltaKb
            (MemberInheritanceSample $obj Human Mortal $atv $btv)))
      $source)
   computed)

!(test
   (member-fold-observation-count
      computedForwardDeltaKb Human Mortal)
   3)

;; A materialized backward answer records the aggregate value it consumed.
;; Mere additions leave that answer current. Forward maintenance publishes the
;; newer cached snapshot on demand, which can rebuild the conclusion before a
;; later live fold takes the new members and materializes them for zero-budget
;; reuse.
!(compileadd materializedForwardDeltaKb
   (: maHuman (Member a Human) (STV 1.0 1.0)))
!(compileadd materializedForwardDeltaKb
   (: maMortal (Member a Mortal) (STV 0.8 1.0)))
!(compileadd materializedForwardDeltaKb
   (: mbHuman (Member b Human) (STV 0.5 1.0)))
!(compileadd materializedForwardDeltaKb
   (: mbMortal (Member b Mortal) (STV 0.4 1.0)))

!(test
   (query-materialize 1000 materializedForwardDeltaKb
      (: $proof (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu) (Inheritance Human Mortal) (STV 0.6666666666666666 0.0018714909544603868)))

!(compileadd materializedForwardDeltaKb
   (: mcHuman (Member c Human) (STV 1.0 1.0)))
!(compileadd materializedForwardDeltaKb
   (: mcMortal (Member c Mortal) (STV 0.6 1.0)))

;; The forward-maintained estimate already counts c, so a zero-budget read
;; takes it over the older fold.
!(test
   (query 0 materializedForwardDeltaKb
      (: $proof (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu)
      (Inheritance Human Mortal)
      (STV 0.64 0.003115264797507788)))

!(forward-chain 4 materializedForwardDeltaKb
   (member-test-fact materializedForwardDeltaKb c Mortal))

;; The fold over a, b and c computed when c arrived is as confident as the
;; estimate.
!(test
   (query 5 materializedForwardDeltaKb
      (: $proof (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu)
      (Inheritance Human Mortal)
      (STV 0.64 0.003115264797507788)))

!(test
   (query 1000 materializedForwardDeltaKb
      (: $proof (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu) (Inheritance Human Mortal) (STV 0.64 0.003115264797507788)))

!(test
   (query-materialize 1000 materializedForwardDeltaKb
      (: $proof (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu) (Inheritance Human Mortal) (STV 0.64 0.003115264797507788)))

!(test
   (materialized-inheritance-facts
      materializedForwardDeltaKb Human Mortal)
   ((: (inheritance-query-result (member-inheritance-fold cpu)) (Inheritance Human Mortal) (STV 0.64 0.003115264797507788))))

!(test
   (query 0 materializedForwardDeltaKb
      (: $proof (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu) (Inheritance Human Mortal) (STV 0.64 0.003115264797507788)))

;; Similar and arbitrary folds are outside the supported registration shape.
!(register-forward-aggregate-premises! false
   ((CPU FoldAllCompiled
       (forwardMemberFoldKb (Member $x Human) extract-tv
          (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv)
       $result)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_identity
            ($_hash
               (forward-aggregate-identity-row
                  (forward-member-inheritance-identity
                     forwardMemberFoldKb $subj $concept)
                  $_id))
            true)))
   1)
