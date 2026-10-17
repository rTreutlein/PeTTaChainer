!(import! &self ../../pettachainer/metta/petta_chainer)

;; #54: B was first built from revision(mf, xm(xf)). A reader excluding X
;; must rebuild mb(mf), even though no query ever stored that branch.
!(compileadd historyKb (: mf (M a) (STV 1 0.8)))
!(compileadd historyKb (: xf (X a) (STV 1 0.8)))
!(compileadd historyKb (: (no_inverse xm) (Implication (X $x) (M $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd historyKb (: (no_inverse mb) (Implication (M $x) (B $x)) (CTV (STV 1 1) (STV 0 1))))
!(collapse (query 200 historyKb (: $p (M a) $tv)))
!(collapse (query 200 historyKb (: $p (B a) $tv)))

;; Rebuilding has no free recursive expansion. An unpaid read keeps no
;; inadmissible view. A direct read has no reader to stale, and the owner's
;; ordinary view must remain current.
!(change-state! sk_eval_budget 0)
!(test
   (sk-value (sk-key (B a) (historyKb MAIN Nil)) sk-any-filter
      (cons (index-hash (sk-key (X a) (historyKb MAIN Nil))) ()))
   sk-none)
!(test (search-id-value sk_eval_budget) 0)
!(test
   (let $bh (index-hash (sk-key (B a) (historyKb MAIN Nil)))
      (match &sk_row ($bh $_key $rhash $_row)
         (space-row-present? &sk_stale ($bh $rhash))))
   false)

;; The miss queued mb without spending the ordinary read's allowance. One
;; paid tier row suffices: xm necessarily reads X and cannot help, while mb
;; reads M's authored mf. Only {M,B} are dependencies and mf is the evidence.
!(change-state! sk_eval_budget 1)
!(change-state! sk_branch_budget 1)
!(test (sk-build-wanted!) true)
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil)))
          ($mh (index-hash (sk-key (M a) (historyKb MAIN Nil))))
          ($bh (index-hash $key))
          ($xh (index-hash (sk-key (X a) (historyKb MAIN Nil))))
          ((sk-val ($_type $_ctx $proof $tv) $ev $deps)
             (sk-value $key sk-any-filter (cons $xh ()))))
      ((sk-full-proof (the Proof $proof)) $tv
       (deps-within? (the Number $deps) (deps-union (deps-key $mh) (deps-key $bh)))
       (deps-meet? (cons $xh ()) (the Number $deps))
       (== $ev (evidence-set (cons (fact-evidence-entry (historyKb MAIN Nil) mf (M a)) ())))))
   ((by (no_inverse mb) mf) (STV 1 0.7999359651197002) true false true))
!(test (search-id-value sk_eval_budget) 0)

;; A settled branch survives an unrelated query and serves a stronger cut
;; without spending another row. It cannot serve a weaker cut or one meeting
;; its dependencies. This exercises both sides of the reuse rule.
!(compileadd unrelatedBranchKb (: unrelated (Unrelated) (STV 1 1)))
!(collapse (query 1 unrelatedBranchKb (: $p (Unrelated) $tv)))
!(change-state! sk_eval_budget 0)
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil)))
          ($xh (index-hash (sk-key (X a) (historyKb MAIN Nil))))
          ((sk-val ($_t $_ctx $proof $_tv) $_ev $_deps)
             (sk-value $key sk-any-filter (hash-union (cons $xh ()) (-1)))))
      (sk-full-proof (the Proof $proof)))
   (by (no_inverse mb) mf))
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil))) ($bh (index-hash $key)))
      (match &sk_row ($bh $_stored $rhash $_row)
         (sk-rebuild-view true $bh $key $rhash (-1))))
   sk-none)
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil)))
          ($mh (index-hash (sk-key (M a) (historyKb MAIN Nil))))
          ($xh (index-hash (sk-key (X a) (historyKb MAIN Nil)))))
      (sk-value $key sk-any-filter (hash-set (cons $xh (cons $mh ())))))
   sk-none)
!(test (search-id-value sk_eval_budget) 0)


;; E1 may contain an unrelated exclusion. Its branch must also serve the
;; weaker E2 once the actual cut X is retained, with no rebuilding allowance.
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil)))
          ($bh (index-hash $key))
          ($xh (index-hash (sk-key (X a) (historyKb MAIN Nil)))))
      (match &sk_row ($bh $key $rhash $_row)
         (let* (($_clear (sk-drop-branch! () (index-hash ($bh $rhash))))
                ($_first-budget (change-state! sk_eval_budget 1))
                ($_first (sk-rebuild-view true $bh $key $rhash (hash-union (cons $xh ()) (-1))))
                ($_second-budget (change-state! sk_eval_budget 0))
                ((sk-val ($_t $_ctx $proof $_tv) $_ev $_deps)
                   (sk-value $key sk-any-filter (cons $xh ()))))
            (sk-full-proof (the Proof $proof)))))
   (by (no_inverse mb) mf))

!(compileadd historyKb (: (no_inverse bx) (Implication (B $x) (X $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (query 200 historyKb (: $p (X a) $tv))
   (: (merge/revision xf (by (no_inverse bx) (by (no_inverse mb) mf))) (X a) (STV 1.0 0.888849375588311)))

;; An unpaid branch belongs to bx's read of B, not to mb's valid ordinary
;; view. Hold bx during evaluation; stale it only after answers are read.
!(test
   (let* (($bkey (sk-key (B a) (historyKb MAIN Nil)))
          ($bh (index-hash $bkey))
          ($xkey (sk-key (X a) (historyKb MAIN Nil)))
          ($xh (index-hash $xkey))
          ($_drop (match &sk_row ($bh $bkey $br $_brow)
                     (sk-drop-branch! () (index-hash ($bh $br)))))
          ($_holding (change-state! sk_holding 1))
          ($_budget (change-state! sk_eval_budget 0)))
      (match &sk_row ($xh $xkey $xr $row)
         (let* (($_unpaid (sk-row-view () () $xh $xkey $xr $row))
                ($held (space-row-present? &sk_held ($xh $xr $_reason)))
                ($before (space-row-present? &sk_stale ($xh $xr)))
                ($owner (match &sk_row ($bh $bkey $br $_brow)
                           (space-row-present? &sk_stale ($bh $br))))
                ($_release (sk-stale-held!)))
            ($held $before $owner (space-row-present? &sk_stale ($xh $xr))))))
   (true false false true))
!(test (query 200 historyKb (: $p (X a) $tv))
   (: (merge/revision xf (by (no_inverse bx) (by (no_inverse mb) mf))) (X a) (STV 1.0 0.888849375588311)))

;; Branch proofs and cuts are roots of both collectors.
!(stored-refs-gc!)
!(deps-gc! (sk-deps-roots))
!(change-state! sk_eval_budget 0)
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil)))
          ($xh (index-hash (sk-key (X a) (historyKb MAIN Nil))))
          ((sk-val ($_t $_ctx $proof $_tv) $_ev $_deps)
             (sk-value $key sk-any-filter (cons $xh ()))))
      (sk-full-proof (the Proof $proof)))
   (by (no_inverse mb) mf))

;; Invalidation unsubscribes a stale row once. A settled refresh must
;; subscribe it again, so another input change still reaches its cache.
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil)))
          ($bh (index-hash $key))
          ($input (sk-key (M a) (historyKb MAIN Nil)))
          ($mh (index-hash $input))
          ($xh (index-hash (sk-key (X a) (historyKb MAIN Nil)))))
      (match &sk_row ($bh $key $rhash $_row)
         (let* (($slot (index-hash ($bh $rhash)))
                ($_changed (sk-invalidate-branches! $input))
                ($unlinked (space-row-present? &sk_branch_reader ($mh $input $slot)))
                ($_budget (change-state! sk_eval_budget 1))
                ($_refreshed (sk-rebuild-view true $bh $key $rhash (cons $xh ()))))
            ($unlinked (space-row-present? &sk_branch_reader ($mh $input $slot))))))
   (false true))

;; A new input invalidates the cached branch through its selective readers.
!(compileadd historyKb (: mf2 (M a) (STV 0 0.8)))
!(collapse (query 200 historyKb (: $p (M a) $tv)))
!(change-state! sk_eval_budget 20)
!(change-state! sk_branch_budget 20)
!(sk-value (sk-key (B a) (historyKb MAIN Nil)) sk-any-filter
   (cons (index-hash (sk-key (X a) (historyKb MAIN Nil))) ()))
!(sk-build-wanted!)
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil)))
          ($xh (index-hash (sk-key (X a) (historyKb MAIN Nil))))
          ((sk-val ($_t $_ctx $_proof (STV $s $_c)) $ev $_deps)
             (sk-value $key sk-any-filter (cons $xh ()))))
      ($s (evidence-subset? (the EvidenceSet $ev) (evidence-set
         (cons (fact-evidence-entry (historyKb MAIN Nil) mf (M a))
            (cons (fact-evidence-entry (historyKb MAIN Nil) mf2 (M a)) ()))))
         (length (evidence-entries (the EvidenceSet $ev)))))
   (0.5 true 2))


;; Distinct, necessary cuts cannot grow a row's cache without bound. Each
;; Source contributes independent evidence; excluding a different Source
;; requires a different branch because every other Source remains a dependency.
(: bound-branch-input (-[semidet]-> Atom Number Atom))
(= (bound-branch-input $_acc $i)
   (let* (($_fact (collapse (compileadd boundBranchKb (: (source $i) (Source $i) (STV 1 0.8)))))
          ($_rule (collapse (compileadd boundBranchKb (: (no_inverse (rule $i))
             (Implication (Source $i) (M)) (CTV (STV 1 1) (STV 0 1)))))))
      ()))
!(fold-semidet bound-branch-input () (1 2 3 4 5 6 7 8 9 10))
!(compileadd boundBranchKb (: (no_inverse mb) (Implication (M) (B)) (CTV (STV 1 1) (STV 0 1))))
!(collapse (query 200 boundBranchKb (: $p (B) $tv)))
!(test
   (let* (($key (sk-key (B) (boundBranchKb MAIN Nil)))
          ($bh (index-hash $key)))
      (match &sk_row ($bh $key $rhash $_row)
         (let* (($slot (index-hash ($bh $rhash)))
                ($_clear (sk-drop-branch! () $slot))
                ($_budget (change-state! sk_eval_budget 10))
                ($contexts (collapse (match &kb ((Source $i) (boundBranchKb MAIN Nil) $_p $_tv)
                   (cons (index-hash (sk-key (Source $i) (boundBranchKb MAIN Nil))) ()))))
                ($_built (map-semidet (sk-rebuild-view true $bh $key $rhash) $contexts))
                ($kept (length (collapse (match &sk_branch ($slot $_cached-key $_cached-row $_cuts $_fresh $_view) true))))
                ($_retired (sk-drop-branch! () $slot)))
            ($kept (length (collapse (match &sk_branch_reader ($_input $_key $slot) true)))))))
   (8 0))

;; A settled empty branch is reusable too. Once independent support arrives,
;; the failed read's subscriptions invalidate it, so it does not hide mf.
!(compileadd emptyBranchKb (: xf (X a) (STV 1 0.8)))
!(compileadd emptyBranchKb (: (no_inverse xm) (Implication (X $x) (M $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd emptyBranchKb (: (no_inverse mb) (Implication (M $x) (B $x)) (CTV (STV 1 1) (STV 0 1))))
!(collapse (query 200 emptyBranchKb (: $p (B a) $tv)))
!(change-state! sk_eval_budget 1)
!(test
   (sk-value (sk-key (B a) (emptyBranchKb MAIN Nil)) sk-any-filter
      (cons (index-hash (sk-key (X a) (emptyBranchKb MAIN Nil))) ()))
   sk-none)
!(change-state! sk_branch_budget 1)
!(test (sk-build-wanted!) true)
!(test
   (let* (($before (search-id-value sk_branch_unpaid))
          ($_budget (change-state! sk_eval_budget 0))
          ($_again (sk-value (sk-key (B a) (emptyBranchKb MAIN Nil)) sk-any-filter
             (cons (index-hash (sk-key (X a) (emptyBranchKb MAIN Nil))) ()))))
      (== $before (search-id-value sk_branch_unpaid)))
   true)
!(compileadd emptyBranchKb (: mf (M a) (STV 1 0.8)))
!(collapse (query 200 emptyBranchKb (: $p (M a) $tv)))
!(change-state! sk_eval_budget 1)
!(change-state! sk_branch_budget 1)
!(sk-value (sk-key (B a) (emptyBranchKb MAIN Nil)) sk-any-filter
   (cons (index-hash (sk-key (X a) (emptyBranchKb MAIN Nil))) ()))
!(sk-build-wanted!)
!(test
   (let* (((sk-val ($_t $_ctx $proof $_tv) $_ev $_deps)
             (sk-value (sk-key (B a) (emptyBranchKb MAIN Nil)) sk-any-filter
                (cons (index-hash (sk-key (X a) (emptyBranchKb MAIN Nil))) ()))) )
      (sk-full-proof (the Proof $proof)))
   (by (no_inverse mb) mf))
