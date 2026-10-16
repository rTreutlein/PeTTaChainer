!(import! &self ../../pettachainer/metta/petta_chainer)

;; A private positive scaffold for an open individual cannot be reused for
;; a bound instance. The index lookup must retain the original alpha shape.
!(let (compiled-query $_goal $adds)
   (mm2compileQuery scaffoldConjKb (: $p (Implication (A $x) (B $x)) $tv))
   (collapse (once (inject-compiled-adds $adds))))
!(inject-special-subgoal-query-adds temp
   (brand Statement (Implication (A a) (B a)))
   (brand KBContext (quote ((implication-query scaffoldConjKb) MAIN Nil))) (brand Proof $p) (the TV (STV $s $c)))
!(test (not (== (collapse (once
   (match ccls_index
      (((Implication $a $b) ((implication-query scaffoldConjKb) MAIN Nil)
         (conditional-implication $_proof) (STV $_s $_c)) $_id $_args)
      (if (=alpha (Implication $a $b) (Implication (A a) (B a))) true (empty))))) ())) true)
!(clear-temp-query-adds)

;; Alpha-renamed positive subgoals reuse the indexed scaffold once.
!(let (compiled-query $_goal $adds)
   (mm2compileQuery stvScaffoldConjKb (: $p (Implication (A $x) (B $x)) $tv))
   (collapse (once (inject-compiled-adds $adds))))
!(inject-special-subgoal-query-adds temp
   (brand Statement (Implication (A $renamed) (B $renamed)))
   (brand KBContext (quote ((implication-query stvScaffoldConjKb) MAIN Nil))) (brand Proof $p) (the TV (STV $s $c)))
!(test (list-len (collapse
   (match ccls_index
      (((Implication $a $b) ((implication-query stvScaffoldConjKb) MAIN Nil)
         (conditional-implication $_proof) (STV $_s $_c)) $id $_args) $id))) 1)
!(clear-temp-query-adds)

;; Internal CTV premise scaffolds retain both branches and the same alpha rule.
!(let (compilation-plan $_goal $adds)
   (compile-implication-subgoal-query ctvScaffoldConjKb
      (: $p (Implication (A $x) (B $x)) (CTV $pos $neg)))
   (collapse (once (inject-compiled-adds (map-flat mm2stmt $adds)))))
!(inject-special-subgoal-query-adds temp
   (brand Statement (Implication (A a) (B a)))
   (kbctx ctvScaffoldConjKb) (brand Proof $p) (the TV $tv))
!(test (list-len (collapse
   (match ccls_index
      (((Implication $a $b) (ctvScaffoldConjKb MAIN Nil)
         (total-implication-frontier $_proof) (CTV $_pos $_neg)) $id $_args) $id))) 2)
!(clear-temp-query-adds)

;; An opposite-only rule cannot answer the positive judgment. Changing
;; main-world g cannot change that result, directly or inside a conjunction.
!(compileadd reviewerConjKb (: g (G) (STV 0.5 0.9)))
!(compileadd reviewerConjKb (: rn (Implication (Not (G)) (Y)) (STV 0.9 0.9)))
!(compileadd reviewerConjKb (: m (M) (STV 1 1)))
!(test (collapse (let (: $p $type $tv)
   (query 300 reviewerConjKb (: $q (Implication (G) (Y)) $value)) $tv))
   ((STV 0.0 0.0)))
!(test (let (: $p $type (STV $s $c))
   (query 300 reviewerConjKb (: $q (And (M) (Implication (G) (Y))) $tv)) (< $c 1e-3)) true)
!(compileadd oppositeOnlyLowGKb (: g (G) (STV 0.1 0.9)))
!(compileadd oppositeOnlyLowGKb (: rn (Implication (Not (G)) (Y)) (STV 0.9 0.9)))
!(test (collapse (let (: $p $type $tv)
   (query 300 oppositeOnlyLowGKb (: $q (Implication (G) (Y)) $value)) $tv))
   ((STV 0.0 0.0)))
;; The explicit negative statement reads its stated conditional directly.
!(test (collapse (let (: $p $type $tv)
   (query 300 reviewerConjKb (: $q (And (M) (Implication (Not (G)) (Y))) $value)) $tv))
   ((STV 0.9 0.8999999992707871)))
!(compileadd reviewerConjKb (: r (Implication (G) (Y))
   (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
;; rn contributes nothing under G; the stated r is exactly 0.8.
!(test (collapse (let (: $p $type $tv)
   (query 300 reviewerConjKb (: $q (And (M) (Implication (G) (Y))) $value)) $tv))
   ((STV 0.8 0.8999999996758992)))
;; Under Not G, independent rn=0.9 and r's negative branch=0.2 revise.
!(test (collapse (let (: $p $type $tv)
   (query 300 reviewerConjKb (: $q (And (M) (Implication (Not (G)) (Y))) $value)) $tv))
   ((STV 0.5499999999999999 0.947368420942915)))

;; Both M and the derived Gate -> Y statement depend on world g. Condition
;; that shared source once: P(Not G)*0.9=0.45, rather than 0.5*0.45=0.225.
;; Gate is the judgment's assumption; g remains an independent source gate.
!(compileadd sharedGivenConjKb (: g (G) (STV 0.5 0.9)))
!(compileadd sharedGivenConjKb (: rn
   (Implication (G) (Implication (Gate) (Y)))
   (CTV (STV 0 1) (STV 0.9 1))))
!(compileadd sharedGivenConjKb (: (no_inverse fromNotG)
   (Implication (Not (G)) (M)) (CTV (STV 1 1) (STV 0 1))))
!(test (collapse (let (: (conditioned g $positive $negative) $type $tv)
   (query 300 sharedGivenConjKb (: $q (And (M) (Implication (Gate) (Y))) $value)) $tv))
   ((STV 0.45 0.9166609536894368)))

;; CTV rule storage stays internal even for an explicit answer selector.
!(test (collapse (query 300 reviewerConjKb
   (: $p (Implication (G) (Y)) (CTV $pos $neg)))) ())

;; The condition is a statement conjunct, not another hypothetical joint proof:
;; P(G) * positive(G->Y) = 0.5 * 0.8 = 0.4.
!(compileadd tiedConjKb (: g (G) (STV 0.5 0.9)))
!(compileadd tiedConjKb (: r (Implication (G) (Y))
   (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
!(test (collapse (let (: (conjunction g r)
   (And (G) (Implication (G) (Y))) $tv)
   (query 300 tiedConjKb (: $q (And (G) (Implication (G) (Y))) $value)) $tv))
   ((STV 0.4 0.9152538782542383)))
!(test (let (: $p (And (Implication (G) (Y)) (G)) (STV $s $c))
   (query 300 tiedConjKb (: $q (And (Implication (G) (Y)) (G)) $tv)) $s) 0.4)
!(compileadd tiedConjKb (: (no_inverse m) (Implication (G) (M))
   (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p (And (M) (Implication (G) (Y))) (STV $s $c))
   (query 300 tiedConjKb (: $q (And (M) (Implication (G) (Y))) $tv)) $s) 0.4)
!(test (let (: $p (And (G) (Implication (G) (Y)) (Implication (G) (M))) (STV $s $c))
   (query 300 tiedConjKb (: $q (And (G) (Implication (G) (Y)) (Implication (G) (M))) $tv)) $s) 0.4)
!(test (let (: $p (And (G) (And (G) (Implication (G) (Y)))) (STV $s $c))
   (query 300 tiedConjKb (: $q (And (G) (And (G) (Implication (G) (Y)))) $tv)) $s) 0.4)

;; The negative statement is requested explicitly and still returns an STV.
!(test (let (: $p (Implication (Not (G)) (Y)) (STV $s $c))
   (query 300 tiedConjKb (: $q (Implication (Not (G)) (Y)) $tv)) $s) 0.2)

;; A rule-derived implication projection and M share their source. Condition
;; R once: 0.6 * 0.8 = 0.48, rather than 0.6 * the marginal 0.56 = 0.336.
!(compileadd sharedConjKb (: source (Recorded R) (STV 0.6 0.9)))
!(compileadd sharedConjKb (: (no_inverse metadata)
   (Implication (Recorded R) (Meta R)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd sharedConjKb (: outer
   (Implication (Recorded R) (Implication (Gate R) (Outcome x)))
   (CTV (STV 0.8 1) (STV 0.2 1))))
!(test (collapse (let
   (: (conditioned source
         (conjunction (by (no_inverse metadata) (given true)) (by outer (given true)))
         (conjunction (by (no_inverse metadata) (given false)) (by outer (given false))))
      (And (Meta R) (Implication (Gate R) (Outcome x))) $tv)
   (query 300 sharedConjKb (: $p (And (Meta R) (Implication (Gate R) (Outcome x))) $value)) $tv))
   ((STV 0.48 0.9359829770008133)))
!(test (collapse (let (: $p (And (Implication (Gate R) (Outcome x)) (Meta R)) $tv)
   (query 300 sharedConjKb (: $q (And (Implication (Gate R) (Outcome x)) (Meta R)) $value)) $tv))
   ((STV 0.48 0.9359829770008133)))
