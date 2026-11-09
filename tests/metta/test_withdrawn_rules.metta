!(import! &self ../../pettachainer/metta/petta_chainer)

;; Certain rules carry no statistical evidence. Retirement must nevertheless
;; remove their existing views, their cached merges and downstream views.
!(compileadd retireKb (: old (Implication (A $t) (B $t)) (STV 1 1)))
!(compileadd retireKb (: downstream (Implication (B $t) (D $t)) (STV 1 1)))
!(compileadd retireKb (: alternative (Implication (C $t) (B $t)) (STV 0.2 1)))
!(compileadd retireKb (: a (A warm) (STV 1 1)))
!(compileadd retireKb (: c (C warm) (STV 1 1)))
!(query 40 retireKb (: $p (D warm) $tv))
!(withdraw-named-rules! old)
!(test (let (: $proof $_statement (STV $strength $_confidence))
               (query 40 retireKb (: $p (B warm) $tv))
            (data $proof $strength))
   ((by alternative c) 0.2))
!(test (let (: $proof $_statement (STV $strength $_confidence))
               (query 40 retireKb (: $p (D warm) $tv))
            (data $proof $strength))
   ((by downstream (by alternative c)) 0.6000000000000001))
;; The old open waiter must never build a row for a new ground time point.
!(compileadd retireKb (: a-fresh (A fresh) (STV 1 1)))
!(compileadd retireKb (: c-fresh (C fresh) (STV 1 1)))
!(test (let (: $proof $_statement (STV $strength $_confidence))
               (query 40 retireKb (: $p (B fresh) $tv))
            (data $proof $strength))
   ((by alternative c-fresh) 0.2))

;; Restating a withdrawn rule's statement creates new rule identities, without
;; resurrecting the views of the earlier rule. The withdrawn name keeps its
;; value (#113), so the restatement takes a new name.
!(compileadd reuseKb (: reusable (Implication (Input $t) (Output $t)) (STV 1 1)))
!(compileadd reuseKb (: input (Input warm) (STV 1 1)))
!(query 40 reuseKb (: $p (Output warm) $tv))
!(withdraw-named-rules! reusable)
!(compileadd reuseKb (: restated (Implication (Input $t) (Output $t)) (STV 0.2 1)))
!(test (let (: $proof $_statement (STV $strength $_confidence))
               (query 40 reuseKb (: $p (Output warm) $tv))
            (data $proof $strength))
   ((by restated input) 0.2))


;; Cached fold proofs carry their members' rule identities too.
!(compileadd foldRetireKb (: fold-old (Implication (A $t) (B $t)) (CTV (STV 0.8 1) (STV 0 1))))
!(compileadd foldRetireKb (: fold-live (Implication (C $t) (B $t)) (CTV (STV 0.2 1) (STV 0 1))))
!(compileadd foldRetireKb (: fold-a (A warm) (STV 1 1)))
!(compileadd foldRetireKb (: fold-c (C warm) (STV 1 1)))
!(query 40 foldRetireKb (: $p (FoldAllTruth (B $t) (STV $s $_c) $s 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total) $tv))
!(withdraw-named-rules! fold-old)
!(test (let (: $_proof (FoldAllTruth $_pattern $_tv-pattern $_extractor $_init $_fun -> $total) $_tv)
               (query 40 foldRetireKb (: $p (FoldAllTruth (B $t) (STV $s $_c) $s 0 (|-> ($acc $elem) (+ $acc $elem)) -> $result) $tv))
            $total)
   0.2)

;; Compression retains retirement provenance after the old rows are gone.
!(set-forgetting 1 1.0)
!(compileadd summaryRetireKb (: summary-old (Implication (A $t) (B $t)) (CTV (STV 0.8 1) (STV 0 1))))
!(compileadd summaryRetireKb (: summary-a (A warm) (STV 1 1)))
!(query 40 summaryRetireKb (: $p (B warm) $tv))
!(advance-epoch)
!(advance-epoch)
!(withdraw-named-rules! summary-old)
!(test (collapse (query 40 summaryRetireKb (: $p (B warm) $tv))) ())
!(set-forgetting 0 1.0)

;; A mixed compressed summary must reconstruct its live part at either budget.
;; Explicit branches keep this fixture historical; STV readers of live base
;; rates are replayable caches and are evicted instead of summarized.
!(set-forgetting 1 1.0)
!(compileadd mixedSummaryKb (: s-old (Implication (A $t) (B $t)) (CTV (STV 0.9 1) (STV 0 1))))
!(compileadd mixedSummaryKb (: s-live (Implication (C $t) (B $t)) (CTV (STV 0.2 1) (STV 0 1))))
!(compileadd mixedSummaryKb (: sa (A warm) (STV 1 1)))
!(compileadd mixedSummaryKb (: sc (C warm) (STV 1 1)))
!(query 40 mixedSummaryKb (: $p (B warm) $tv))
!(advance-epoch)
!(advance-epoch)
!(test (not (== (collapse (match &sk_summary ($_h (sk-key (B warm) (mixedSummaryKb MAIN Nil)) $_fact $_ev $_deps) true)) ())) true)
!(test (let $key-digest (link-digest (sk-key (B warm) (mixedSummaryKb MAIN Nil))) (not (== (collapse (match &sk_join_link ($key-digest $_digest) true)) ()))) true)
!(withdraw-named-rules! s-old)
!(test (let $key-digest (link-digest (sk-key (B warm) (mixedSummaryKb MAIN Nil))) (collapse (match &sk_join_link ($key-digest $_digest) true))) ())
!(test (let (: $proof $_stmt (STV $s $_c)) (query 40 mixedSummaryKb (: $p (B warm) $tv)) (data $proof $s)) ((by s-live sc) 0.2))
!(test (let (: $proof $_stmt (STV $s $_c)) (query 200 mixedSummaryKb (: $p (B warm) $tv)) (data $proof $s)) ((by s-live sc) 0.2))
!(test (collapse (let (: $proof $_stmt (STV $s $_c)) (query 40 mixedSummaryKb (: $p (B $t) $tv)) (data $proof $s))) (((by s-live sc) 0.2)))
!(set-forgetting 0 1.0)

;; Materialization publishes expanded proofs; retirement retains their source
;; set and removes them from every direct KB reader as well as root fallback.
!(compileadd materialRetireKb (: m-old (Implication (A $t) (B $t)) (STV 0.9 1)))
!(compileadd materialRetireKb (: ma (A warm) (STV 1 1)))
!(query-materialize 40 materialRetireKb (: $p (B warm) $tv))
!(test (not (== (collapse (match &kb ((B warm) (materialRetireKb MAIN Nil) $_proof $_tv) true)) ())) true)
!(withdraw-named-rules! m-old)
!(test (collapse (query 40 materialRetireKb (: $p (B warm) $tv))) ())
!(test (collapse (match &kb ((B warm) (materialRetireKb MAIN Nil) $_proof $_tv) true)) ())
!(test (collapse (match &materialized_facts (materialized-row $_h (B warm) (materialRetireKb MAIN Nil) $_fact $_ev) true)) ())

;; Incomparable containing classes form a distribution mixture, rather than
;; a recursively revised prior. Build the complete frontier in either order;
;; its disagreement makes #69's centre weight zero for this specific view.
!(compileadd priorOrderA (: specific (Implication (And (A $x) (B $x)) (Win $x)) (CTV (STV 0.99 0.4) (STV 0.5 0))))
!(compileadd priorOrderA (: general-a (Implication (A $x) (Win $x)) (CTV (STV 0.2 0.5) (STV 0.5 0))))
!(compileadd priorOrderA (: general-b (Implication (B $x) (Win $x)) (CTV (STV 0.8 0.5) (STV 0.5 0))))
!(compileadd priorOrderB (: general-b (Implication (B $x) (Win $x)) (CTV (STV 0.8 0.5) (STV 0.5 0))))
!(compileadd priorOrderB (: general-a (Implication (A $x) (Win $x)) (CTV (STV 0.2 0.5) (STV 0.5 0))))
!(compileadd priorOrderB (: specific (Implication (And (A $x) (B $x)) (Win $x)) (CTV (STV 0.99 0.4) (STV 0.5 0))))
!(compileadd priorOrderA (: a (A new) (STV 1 1)))
!(compileadd priorOrderA (: b (B new) (STV 1 1)))
!(compileadd priorOrderB (: a (A new) (STV 1 1)))
!(compileadd priorOrderB (: b (B new) (STV 1 1)))
!(test
   (let* (((: $_p $_type (STV $first $_c)) (query 100 priorOrderA (: $p (Win new) $tv)))
          ((: $_q $_other (STV $second $_d)) (query 100 priorOrderB (: $p (Win new) $tv))))
      (data $first $second))
   (0.9899999999999999 0.9899999999999999))

;; A forward copy leaves the KB when its supporting rule is withdrawn.
!(compileadd forwardRetireKb (: f-old (Implication (A $t) (B $t)) (STV 0.9 1)))
!(compileadd forwardRetireKb (: fa (A warm) (STV 1 1)))
!(forward-chain 40 forwardRetireKb (the (List (Statement KBContext Proof TV)) (((A warm) (forwardRetireKb MAIN Nil) fa (STV 1 1)))))
!(test (not (== (collapse (match &sk_forward_stored ($_h $_key ((B warm) (forwardRetireKb MAIN Nil) $_p $_tv) $_ev $_deps) true)) ())) true)
!(withdraw-named-rules! f-old)
!(test (collapse (match &kb ((B warm) (forwardRetireKb MAIN Nil) $_proof $_tv) true)) ())
!(test (collapse (query 40 forwardRetireKb (: $p (B warm) $tv))) ())

;; Closed reads discard encountered retired work and rows, including their
;; pending-work counts, instead of filtering the same entries on every read.
!(test
   (let* (($key (sk-key (CleanupB warm) (cleanupKb MAIN Nil)))
          ($node (assemble-stored-runtime-fact (CleanupB warm) (cleanupKb MAIN Nil) $p $tv))
          ($hash (sk-node-hash $node))
          ($child (assemble-stored-runtime-fact (CleanupA warm) (cleanupKb MAIN Nil) $cp $ctv))
          ($child-hash (sk-node-hash $child))
          ($conclusion (the SkFact $node))
          ($waiter (sk-partial $node 999800 $conclusion () (cons $child ()) ()))
          ($row (sk-row (sk-ident 999800 () $key) $conclusion () 999804))
          ($_retired (withdraw-rule! 999800))
          ($_expanded (add-atom &sk_expanded ($hash $node)))
          ($prems (cons $child ()))
          ($_definition (add-space-atom! ccls_index (quote ($conclusion 999800 $prems))))
          ($_wait (sk-store-wait! 999805 $child-hash $child $waiter))
          ($_join (add-atom &sk_deferred_joins ($hash 999801 (sk-join $node 999800 999806))))
          ($_deferred (add-atom &sk_deferred ($hash 999802 (sk-deferred $node 999800))))
          ($_added-row (add-atom &sk_row ($hash $key 999803 $row)))
          ($_work (sk-work! $hash $node 2))
          ($_waiting (sk-application-waits? $node false (sk-node-at $child-hash $child)))
          ($_settled (sk-settled? $key))
          ($_founded (sk-founded? $hash $key)))
      (data
         (== (collapse (match &sk_wait ($child-hash $_c $_w) true)) ())
         (== (collapse (match &sk_deferred_joins ($hash $_jh $_j) true)) ())
         (== (collapse (match &sk_deferred ($hash $_rh $_r) true)) ())
         (== (collapse (match &sk_row ($hash $_k $_rr $_stored-row) true)) ())
         (sk-pending? $hash $node)))
   (true true true true false))


;; Two independent ground source facts contribute to an open query after
;; join deduplication indexes the bound conclusion.
!(compileadd digestKb (: join-source (Implication (JoinA $t) (JoinB $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd digestKb (: join-open (JoinA warm) (STV 0.2 0.5)))
!(compileadd digestKb (: join-ground (JoinA warm) (STV 0.8 0.5)))
!(test (let (: $_p $_statement (STV $s $_c)) (query 40 digestKb (: $p (JoinB $t) $tv)) $s) 0.5)

;; A withdrawn rule's specialization state leaves with it (#114): a later
;; structural fact grounds no instance of it, and no query applies it.
!(set-specializing-predicate Symmetric)
!(compileadd specKb (: spec-old (Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x)) (STV 0.9 0.9)))
!(compileadd specKb (: lift-old (Implication (And (Member $x A) (Aux $x)) (Member $x B)) (CTV (STV 0.9 0.9) (STV 0.0 1.0))))
!(compileadd specKb (: aux (Aux c) (STV 1 1)))
!(withdraw-named-rules! spec-old)
!(withdraw-named-rules! lift-old)
!(compileadd specKb (: tag (Symmetric Friend) (STV 1 1)))
!(compileadd specKb (: f1 (Friend bob alice) (STV 1 1)))
!(compileadd specKb (: ca (Member c A) (STV 1 1)))
!(test (collapse (match &spec_template ($_hash (specialization-template-row specKb $_head $_triggers $_job)) true)) ())
!(test (collapse (query 100 specKb (: $p (Friend alice bob) $tv))) ())
!(test (collapse (query 100 specKb (: $p (Member c B) $tv))) ())
