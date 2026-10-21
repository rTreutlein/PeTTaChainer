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
               ($_obs-hash ($id $_obj) $_value $_weight $_mass $_sources)
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
         ($_obs-hash
            $_key
            (forward-member-inheritance-observation-value
               $_subject $_concept)
            $_weight $_mass $_sources)
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
         ($_obs-hash
            $_key
            (forward-member-inheritance-observation-value
               $_subject $_concept)
            $_weight $_mass $_sources)
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
            ($_obs-hash
               ($_id a)
               (forward-member-inheritance-observation-value
                  $_subject $_concept)
               $_weight $_mass $_sources)
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
            ($_obs-hash
               ($_id $_obj)
               (forward-member-inheritance-observation-value
                  $_subject $_concept)
               $_weight $_mass $_sources)
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
            ($_obs-hash
               ($_id $_obj)
               (forward-member-inheritance-observation-value
                  $_subject $_concept)
               $_weight $_mass $_sources)
            true)))
   2)

;; The provisional value answers immediately, while an ordinary complete fold
;; refines it and upgrades the cache source without changing public provenance.
;; With a's two Member facts merged, (Member a Human) is .75, so the complete
;; fold is (.8 * .75 + .4 * .5) / (.75 + .5) = .64.
!(test
   (query 80 forwardMemberFoldKb
      (: $proof (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu)
      (Inheritance Human Mortal)
      (STV 0.64 0.0015600624024961)))
!(test
   (let (: $proof $_type $tv)
      (query 80 forwardMemberFoldKb
         (: $proof (Inheritance Human Mortal) $tv))
      (data $proof (== (cons $tv ()) (member-fold-cache forwardMemberFoldKb Human Mortal))))
   ((member-inheritance-fold cpu) true))

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

;; A membership a forward run derives counts with the member's other, stored
;; membership: taking (Member a B) keeps a in the A -> B estimate beside b,
;; though the run stores its copy only when it ends.
!(compileadd forwardDerivedMemberKb (: ma (Member a A) (STV 1.0 1.0)))
!(compileadd forwardDerivedMemberKb (: mb (Member b A) (STV 1.0 1.0)))
!(compileadd forwardDerivedMemberKb (: mbb (Member b B) (STV 1.0 1.0)))
!(compileadd forwardDerivedMemberKb (: sa (Special a) (STV 1.0 1.0)))
!(compileadd forwardDerivedMemberKb
   (: specialB (Implication (Special $x) (Member $x B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(collapse (query 100 forwardDerivedMemberKb (: $p (Inheritance A B) $tv)))
!(forward-chain 20 forwardDerivedMemberKb
   (collapse (once (match &kb ((Special a) (forwardDerivedMemberKb MAIN Nil) $p $tv)
      (assemble-stored-runtime-fact (Special a) (forwardDerivedMemberKb MAIN Nil) $p $tv)))))
!(test (member-fold-observation-count forwardDerivedMemberKb A B) 2)

;; Member inheritance of a concept in itself has one trigger: its one Member
;; fact is a sample once.
(: member-fold-interest-count (-[det]-> KB Term Term Number))
(= (member-fold-interest-count $kb $subj $concept)
   (list-count
      (collapse
         (match &forward_aggregate_interest_by_trigger
            ($_hash
               (forward-aggregate-interest $_trigger $_id
                  (forward-member-inheritance-descriptor $kb $subj $concept $_pattern)))
            true))))

!(compileadd sameConceptKb (: sa (Member a Human) (STV 1.0 1.0)))
!(compileadd sameConceptKb (: sb (Member b Human) (STV 0.5 1.0)))
!(query 0 sameConceptKb (: $proof (Inheritance Human Human) $tv))
!(test (member-fold-interest-count sameConceptKb Human Human) 1)
!(forward-chain 1 sameConceptKb (member-test-fact sameConceptKb a Human))
!(test (member-fold-observation-count sameConceptKb Human Human) 1)
!(test (member-fold-cache sameConceptKb Human Human) ((STV 1.0 0.0012484394506866417)))
!(test
   (let $id (fa-id (forward-member-inheritance-identity sameConceptKb Human Human))
      (collapse (match &forward_aggregate_state ($id $weight $mass $_members) ($weight $mass))))
   ((1.0 1.0)))

;; Registering the same premises again adds no identity, interest or state, and
;; seeding the registered aggregate counts nothing twice.
!(compileadd repeatRegisterKb (: ra (Member a A) (STV 1.0 1.0)))
!(compileadd repeatRegisterKb (: rab (Member a B) (STV 0.8 1.0)))
!(register-forward-aggregate-premises! false
   ((CPU FoldAllCompiled
       (repeatRegisterKb (MemberInheritanceSample $x A B $s $c)
          (extract-value (MemberInheritanceSample $x A B $s $c) (WeightedTv $s $c))
          (BaseRateEvidence 0.0 0.0) WeightedBaseRateAcc (member-inheritance repeatRegisterKb) result-tv)
       $result)))
!(register-forward-aggregate-premises! false
   ((CPU FoldAllCompiled
       (repeatRegisterKb (MemberInheritanceSample $x A B $s $c)
          (extract-value (MemberInheritanceSample $x A B $s $c) (WeightedTv $s $c))
          (BaseRateEvidence 0.0 0.0) WeightedBaseRateAcc (member-inheritance repeatRegisterKb) result-tv)
       $result)))
!(test
   (list-count
      (collapse
         (match &forward_aggregate_identity
            ($_hash (forward-aggregate-identity-row
               (forward-member-inheritance-identity repeatRegisterKb A B) $_id))
            true)))
   1)
!(test (member-fold-interest-count repeatRegisterKb A B) 2)
!(test
   (let $id (fa-id (forward-member-inheritance-identity repeatRegisterKb A B))
      (list-count (collapse (match &forward_aggregate_state ($id $weight $mass $_members) true))))
   1)
!(forward-seed-fold!
   (CPU FoldAllCompiled
      (repeatRegisterKb (MemberInheritanceSample $x A B $s $c)
         (extract-value (MemberInheritanceSample $x A B $s $c) (WeightedTv $s $c))
         (BaseRateEvidence 0.0 0.0) WeightedBaseRateAcc (member-inheritance repeatRegisterKb) result-tv)
      $result))
!(test (member-fold-observation-count repeatRegisterKb A B) 1)
!(test
   (let $id (fa-id (forward-member-inheritance-identity repeatRegisterKb A B))
      (collapse (match &forward_aggregate_state ($id $weight $mass $_members) ($weight $mass))))
   ((0.8 1.0)))
!(test (member-fold-cache repeatRegisterKb A B) ((STV 0.8 0.0012484394506866417)))
!(forward-seed-fold!
   (CPU FoldAllCompiled
      (repeatRegisterKb (MemberInheritanceSample $x A B $s $c)
         (extract-value (MemberInheritanceSample $x A B $s $c) (WeightedTv $s $c))
         (BaseRateEvidence 0.0 0.0) WeightedBaseRateAcc (member-inheritance repeatRegisterKb) result-tv)
      $result))
!(test
   (let $id (fa-id (forward-member-inheritance-identity repeatRegisterKb A B))
      (collapse (match &forward_aggregate_state ($id $weight $mass $_members) ($weight $mass))))
   ((0.8 1.0)))
!(test (member-fold-interest-count repeatRegisterKb A B) 2)
