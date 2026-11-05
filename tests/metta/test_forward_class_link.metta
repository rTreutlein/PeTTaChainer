!(import! &self ../../pettachainer/metta/petta_chainer)

;; A class link (Inheritance A B) is the implication (A $x) -> (B $x). Its
;; instance fold is kept by the forward interest of its two classes: a class
;; fact marks its subject's sample, which the fold takes when next read, at
;; any budget (fa-class-link-dirty!, sk-instance-take-step).

(: member-test-fact
   (-[det]-> KB Term Term
       (List (Statement KBContext Proof TV))))
(= (member-test-fact $kb $obj $class)
   (collapse
      (once
         (match &kb
            (($class $obj) ($kb MAIN Nil) $prf $tv)
            (let*
               (($type
                   (brand Statement (cons $class (cons $obj ()))))
                ($kbctx
                   (brand KBContext (quote ($kb MAIN Nil))))
                ($proof (brand Proof $prf))
                ($truth-value (the TV $tv)))
               (assemble-runtime-fact
                  $type $kbctx $proof $truth-value))))))

(: link-interest-count (-[det]-> KB Number))
(= (link-interest-count $kb)
   (list-count
      (collapse
         (match &forward_aggregate_interest_by_trigger
            ($_hash (forward-aggregate-interest $_trigger $_id (forward-class-link-descriptor $kb $_sub $_super $_fold)))
            true))))

(: link-identity-count (-[det]-> KB Number))
(= (link-identity-count $kb)
   (list-count
      (collapse
         (match &forward_aggregate_identity
            ($_hash (forward-aggregate-identity-row (forward-class-link-identity $kb $_sub $_super) $_id))
            true))))

;; Open classes give no selective trigger and register nothing.
!(query 0 openLinkKb (: $proof (Inheritance $open-subj $open-concept) $tv))
!(test (link-identity-count openLinkKb) 0)

;; A zero-budget query registers the link's interest once, one per class.
!(compileadd linkKb (: aHuman (Member a Human) (STV 1.0 1.0)))
!(compileadd linkKb (: aMortal (Member a Mortal) (STV 0.8 1.0)))
!(query 0 linkKb (: $proof (Inheritance Human Mortal) $tv))
!(test (link-identity-count linkKb) 1)
!(test (link-interest-count linkKb) 2)
!(query 0 linkKb (: $proof (Inheritance Human Mortal) $tv))
!(test (link-identity-count linkKb) 1)

;; The facts stored before it registered count at the next read.
!(test
   (query 5 linkKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.8 0.0012484394506866417)))

;; Appending b adds its sample at the next read, without a forward run.
!(compileadd linkKb (: bHuman (Member b Human) (STV 0.5 1.0)))
!(compileadd linkKb (: bMortal (Member b Mortal) (STV 0.4 1.0)))
!(test
   (query 0 linkKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.6666666666666666 0.0018714909544603868)))

;; A second Member fact for a is merged with the first: a's sample is
;; replaced, not counted again. With (Member a Human) at .75 the fold is
;; (.8 * .75 + .4 * .5) / (.75 + .5) = .64.
!(compileadd linkKb (: aHumanSecond (Member a Human) (STV 0.5 1.0)))
!(forward-chain 1 linkKb (member-test-fact linkKb a Human))
!(test
   (query 5 linkKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.64 0.0015600624024961)))

;; A materialized answer is read at budget zero; a later sample extends it.
!(compileadd materializedLinkKb (: maHuman (Member a Human) (STV 1.0 1.0)))
!(compileadd materializedLinkKb (: maMortal (Member a Mortal) (STV 0.8 1.0)))
!(compileadd materializedLinkKb (: mbHuman (Member b Human) (STV 0.5 1.0)))
!(compileadd materializedLinkKb (: mbMortal (Member b Mortal) (STV 0.4 1.0)))
!(test
   (query-materialize 1000 materializedLinkKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.6666666666666666 0.0018714909544603868)))
!(test
   (query 0 materializedLinkKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.6666666666666666 0.0018714909544603868)))
!(compileadd materializedLinkKb (: mcHuman (Member c Human) (STV 1.0 1.0)))
!(compileadd materializedLinkKb (: mcMortal (Member c Mortal) (STV 0.6 1.0)))
!(test
   (query 0 materializedLinkKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.64 0.003115264797507788)))
!(test
   (query 1000 materializedLinkKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.64 0.003115264797507788)))

;; A membership a rule derives counts with the member's stored membership once
;; a search builds its sample: (Member a B) through specialB.
!(compileadd derivedLinkKb (: ma (Member a A) (STV 1.0 1.0)))
!(compileadd derivedLinkKb (: mb (Member b A) (STV 1.0 1.0)))
!(compileadd derivedLinkKb (: mbb (Member b B) (STV 1.0 1.0)))
!(compileadd derivedLinkKb (: sa (Special a) (STV 1.0 1.0)))
!(compileadd derivedLinkKb
   (: specialB (Implication (Special $x) (Member $x B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test
   (query 100 derivedLinkKb (: $p (Inheritance A B) $tv))
   (: (implication-instance-fold cpu) (Inheritance A B) (STV 1.0 0.0024937655860349127)))

;; Order does not matter: the link is stationary, so its estimate is the
;; plain frequency of its samples, whatever order they arrive in.
!(compileadd orderKb (: o1 (Member x1 Human) (STV 1 1)))
!(compileadd orderKb (: o2 (Member x1 Mortal) (STV 1 1)))
!(compileadd orderKb (: o3 (Member x2 Human) (STV 1 1)))
!(compileadd orderKb (: o4 (Member x2 Mortal) (STV 0 1)))
!(test
   (query 100 orderKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.5 0.0024937655860349127)))

;; A sample no search built is read from its sides' stored values, a forward
;; run's copy included, and the link's estimate is
;; the frequency as it is, not made consistent with base rates that do not
;; count a derived member yet: at any budget, c's Mortal derived by sp counts.
!(compileadd derivedCopyKb (: ah (Member a Human) (STV 1.0 1.0)))
!(compileadd derivedCopyKb (: am (Member a Mortal) (STV 0.8 1.0)))
!(query 0 derivedCopyKb (: $p (Inheritance Human Mortal) $tv))
!(compileadd derivedCopyKb (: bh (Member b Human) (STV 1.0 1.0)))
!(compileadd derivedCopyKb (: bm (Member b Mortal) (STV 0.0 1.0)))
!(compileadd derivedCopyKb (: sp (Implication (Special $x) (Member $x Mortal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd derivedCopyKb (: ch (Member c Human) (STV 1.0 1.0)))
!(compileadd derivedCopyKb (: cs (Special c) (STV 1.0 1.0)))
!(forward-chain 50 derivedCopyKb
   (collapse (match &kb ((Special c) (derivedCopyKb MAIN Nil) $p $tv) (assemble-stored-runtime-fact (Special c) (derivedCopyKb MAIN Nil) $p $tv))))
!(test
   (query 1 derivedCopyKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.6 0.0037359900373599006)))
!(test
   (query 5 derivedCopyKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.6 0.0037359900373599006)))
!(compileadd derivedCopyUnregisteredKb (: ah (Member a Human) (STV 1.0 1.0)))
!(compileadd derivedCopyUnregisteredKb (: am (Member a Mortal) (STV 0.8 1.0)))
!(compileadd derivedCopyUnregisteredKb (: bh (Member b Human) (STV 1.0 1.0)))
!(compileadd derivedCopyUnregisteredKb (: bm (Member b Mortal) (STV 0.0 1.0)))
!(compileadd derivedCopyUnregisteredKb (: sp (Implication (Special $x) (Member $x Mortal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd derivedCopyUnregisteredKb (: ch (Member c Human) (STV 1.0 1.0)))
!(compileadd derivedCopyUnregisteredKb (: cs (Special c) (STV 1.0 1.0)))
!(forward-chain 50 derivedCopyUnregisteredKb
   (collapse (match &kb ((Special c) (derivedCopyUnregisteredKb MAIN Nil) $p $tv) (assemble-stored-runtime-fact (Special c) (derivedCopyUnregisteredKb MAIN Nil) $p $tv))))
!(test
   (query 1 derivedCopyUnregisteredKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.6 0.0037359900373599006)))
!(test
   (query 5 derivedCopyUnregisteredKb (: $proof (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu) (Inheritance Human Mortal) (STV 0.6 0.0037359900373599006)))

;; A forward copy derived through the link's own stated rule is left out of
;; the link's samples; the sample is then still to be computed, not read from
;; the stored facts alone, which would drop c's Mortal from sp. At budget 1 c's
;; sample waits for its search and the fold holds a and b; at budget 500 it
;; answers as a cold KB does.
!(compileadd excludedCopyKb (: hm (Inheritance Human Mortal) (STV 0.9 0.5)))
!(compileadd excludedCopyKb (: sp (Implication (Special $x) (Member $x Mortal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd excludedCopyKb (: ah (Member a Human) (STV 1.0 1.0)))
!(compileadd excludedCopyKb (: am (Member a Mortal) (STV 0.8 1.0)))
!(compileadd excludedCopyKb (: bh (Member b Human) (STV 1.0 1.0)))
!(compileadd excludedCopyKb (: bm (Member b Mortal) (STV 0.0 1.0)))
!(query 0 excludedCopyKb (: $p (Inheritance Human Mortal) $tv))
!(compileadd excludedCopyKb (: ch (Member c Human) (STV 1.0 1.0)))
!(compileadd excludedCopyKb (: cs (Special c) (STV 1.0 1.0)))
!(forward-chain 50 excludedCopyKb
   (collapse (match &kb ((Human c) (excludedCopyKb MAIN Nil) $p $tv) (assemble-stored-runtime-fact (Human c) (excludedCopyKb MAIN Nil) $p $tv))))
!(forward-chain 50 excludedCopyKb
   (collapse (match &kb ((Special c) (excludedCopyKb MAIN Nil) $p $tv) (assemble-stored-runtime-fact (Special c) (excludedCopyKb MAIN Nil) $p $tv))))
!(test
   (query 1 excludedCopyKb (: $p (Inheritance Human Mortal) $tv))
   (: (merge/revision hm (implication-instance-fold cpu)) (Inheritance Human Mortal) (STV 0.8987531172069825 0.5006242197253433)))
!(test
   (query 500 excludedCopyKb (: $p (Inheritance Human Mortal) $tv))
   (: (merge/revision hm (implication-instance-fold cpu)) (Inheritance Human Mortal) (STV 0.898879202988792 0.5009357454772302)))
