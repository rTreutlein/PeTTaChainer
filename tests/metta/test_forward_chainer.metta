!(import! &self ../../pettachainer/metta/petta_chainer)

;; Forward chaining consumes canonical compiled facts. Tests that want to
;; select by surface type do that explicitly outside the chainer.
(: test-selected-facts
   (-[det]-> KB Statement
      (List (Statement KBContext Proof TV))))
(= (test-selected-facts $kb $type)
   (collapse
      (once
         (match &kb
            ($type ($kb MAIN Nil) $prf $tv)
            (assemble-stored-runtime-fact
               $type ($kb MAIN Nil) $prf $tv)))))

;; A forward run returns the values of the keys it built on; these read them.
(: result-statements (-[det]-> (List (Statement KBContext Proof TV)) (List Atom)))
(= (result-statements ()) ())
(= (result-statements (cons ($type $_kbctx $_proof $_tv) $rest)) (cons $type (result-statements $rest)))

(: result-for (-[det]-> Atom (List (Statement KBContext Proof TV)) (List Atom)))
(= (result-for $_type ()) ())
(= (result-for $type (cons ($statement $_kbctx $proof $tv) $rest))
   (if (== $statement $type) (cons ((sk-full-proof $proof) $tv) ()) (result-for $type $rest)))

(: query-for (-[nondet]-> KB Statement (List Atom)))
(= (query-for $kb $type)
   (case (collapse (query 200 $kb (: $proof $type $tv))) (
      ((cons (: $p $_t $v) $_more) (cons ($p $v) ()))
      (() ()))))

!(compileadd fwdkb (: edgeAB (Edge A B) (STV 1.0 1.0)))
!(compileadd fwdkb (: edgeBC (Edge B C) (STV 1.0 1.0)))
!(compileadd fwdkb
   (: edgeToPath (Implication (Edge $x $y) (Path $x $y)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd fwdkb
   (: (no_inverse pathStep) (Implication (And (Path $x $y) (Edge $y $z)) (Path $x $z)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd fwdkb
   (: pathIdempotent (Implication (Path $x $y) (Path $x $y)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; No seeds, or no budget, builds nothing.
!(test (collapse (forward-chain 20 fwdkb ())) (()))
!(test (forward-chain 0 fwdkb (test-selected-facts fwdkb (Edge A B))) ())

;; Guard removal permits induction through pathStep, enlarging the closure
;; with reverse paths and existential joins even when only forward-chain is
;; called. This fixture tests traversal of a directed graph, so pathStep opts
;; out of inversion; the induction and stored-dependency tests cover that path.
;; A run joins what it derives with the facts already stored: Path A C needs
;; Edge B C, which was never a seed.
!(test
   (result-for (Path A C) (forward-chain 50 fwdkb (test-selected-facts fwdkb (Edge A B))))
   (((by (no_inverse pathStep) (conjunction (by edgeToPath edgeAB) edgeBC)) (STV 1.0 0.9996001597861454))))

;; Taking the same seed again changes nothing, so nothing is built.
!(test (forward-chain 50 fwdkb (test-selected-facts fwdkb (Edge A B))) ())

;; A forward result is the value a backward query reads for the statement.
!(test (query-for fwdkb (Path A C))
   (((by (no_inverse pathStep) (conjunction (by edgeToPath edgeAB) edgeBC)) (STV 1.0 0.9996001597861454))))

;; A rule concluding its own premise supports itself, and derives nothing.
!(compileadd loopkb (: seedLoop (Loop Start) (STV 1.0 1.0)))
!(compileadd loopkb
   (: keepLoop (Implication (Loop $x) (Loop $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (forward-chain 200 loopkb (test-selected-facts loopkb (Loop Start))) ())

;; Two rules conclude SwitchGoal; the forward value is the one the backward
;; chainer reads.
!(compileadd mergekb (: weakFact (WeakPremise) (STV 1.0 0.1)))
!(compileadd mergekb (: baseFact (BasePremise) (STV 1.0 1.0)))
!(compileadd mergekb
   (: ruleHighThenDrop (Implication (And (WeakPremise) (BasePremise)) (SwitchGoal)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd mergekb
   (: ruleStable (Implication (BasePremise) (SwitchGoal)) (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(test
   (let $forward (result-for (SwitchGoal) (forward-chain 50 mergekb (test-selected-facts mergekb (BasePremise))))
      (== $forward (query-for mergekb (SwitchGoal))))
   true)

;; A run that builds on a key whose value is one of its stored facts stores no
;; copy of it, so replacing what an earlier run stored never removes the fact.
!(forward-chain 50 mergekb (test-selected-facts mergekb (BasePremise)))
!(test (collapse (match &kb ((WeakPremise) $_kbctx weakFact $tv) $tv)) ((STV 1.0 0.1)))

;; The most promising item goes first: with two units, a seed that triggers
;; no rule builds nothing, and one that does computes its conclusion with one
;; and builds on it with the other.
!(compileadd deltakb (: highFact (HighPriority) (STV 1.0 1.0)))
!(compileadd deltakb (: lowFact (LowPriority) (STV 1.0 0.8)))
!(compileadd deltakb
   (: lowToGoal (Implication (LowPriority) (DeltaGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (forward-chain 2 deltakb (test-selected-facts deltakb (HighPriority))) ())
!(test (result-statements (forward-chain 2 deltakb (test-selected-facts deltakb (LowPriority)))) ((DeltaGoal)))

;; Adding a rule schedules nothing by itself; a run whose seed triggers it
;; builds its conclusion.
!(compileadd ruleaddkb (: oldSeed (RuleSeed) (STV 1.0 1.0)))
!(test (forward-chain 1 ruleaddkb (test-selected-facts ruleaddkb (RuleSeed))) ())
!(compileadd ruleaddkb
   (: seedToGoal (Implication (RuleSeed) (RuleAddGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test (result-statements (forward-chain 2 ruleaddkb (test-selected-facts ruleaddkb (RuleSeed)))) ((RuleAddGoal)))

;; Formulas run in evaluation; a result's truth value is never an unevaluated
;; call.
!(compileadd dedupekb (: dedupeSeed (DedupeSeed) (STV 1.0 0.4)))
!(compileadd dedupekb
   (: dedupeRule (Implication (DedupeSeed) (DedupeGoal)) (CTV (STV 1.0 0.5) (STV 0.0 1.0))))

!(test
   (case (result-for (DedupeGoal) (forward-chain 10 dedupekb (test-selected-facts dedupekb (DedupeSeed)))) (
      ((cons ($_proof (STV $_s $_c)) ()) true)
      ($_other false)))
   true)

;; A rule whose truth needs base rates fires forward: its fold premises are
;; fold keys, read as a query reads them.
!(compileadd stvFwdKb (: a (A x) (STV 1.0 0.9)))
!(compileadd stvFwdKb (: b (B x) (STV 1.0 0.9)))
!(compileadd stvFwdKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (STV 0.9 0.9)))

!(test
   (let $forward (result-for (C x) (forward-chain 50 stvFwdKb (test-selected-facts stvFwdKb (A x))))
      (== $forward (query-for stvFwdKb (C x))))
   true)

!(compileadd shareFwdKb (: l1 (Leak u1) (STV 0.2 0.9)))
!(compileadd shareFwdKb (: l2 (Leak u2) (STV 0.6 0.8)))
!(compileadd shareFwdKb
   (: share
      (Implication
         (And (FoldAllTruth (Leak $v) (STV $s $_c) $s 0.0
                 (|-> ($acc $elem) (+ $acc $elem)) -> $total)
              (Leak $u)
              (FoldAllTruth (Leak $u) (STV $su $_cu) $su 0.0
                 (|-> ($acc $elem) $elem) -> $mine)
              (Compute / ($mine $total) -> $p))
         (Share $u))
      (CTV (STV $p 1.0) (STV $p 1.0))))

!(test
   (case (result-for (Share u1) (forward-chain 50 shareFwdKb (test-selected-facts shareFwdKb (Leak u1)))) (
      ((cons ($_proof $tv) ()) $tv)
      ($_other ())))
   (STV 0.25 0.9999320001831821))

;; A key whose value rests on less than one observation's worth of evidence is
;; not built on. The minimum is configurable.
!(compileadd weakFwdKb (: seed (WeakSeed) (STV 1.0 0.9)))
!(compileadd weakFwdKb (: weakRule (Implication (WeakSeed) (WeakGoal)) (CTV (STV 1.0 0.0005) (STV 0.0 1.0))))

!(test (forward-chain 50 weakFwdKb (test-selected-facts weakFwdKb (WeakSeed))) ())
!(test
   (let* (($_min (set-forward-min-evidence 0.0))
          ($statements (result-statements (forward-chain 50 weakFwdKb (test-selected-facts weakFwdKb (WeakSeed)))))
          ($_restored (set-forward-min-evidence 1.0)))
      $statements)
   ((WeakGoal)))

;; B revises A's and C's derivations. B -> A reads only B's derivation that
;; does not depend on A, as a query does, so A never rests on itself.
(= (result-tv-close? (($_fp (STV $fs $fc))) (($_bp (STV $bs $bc))))
   (and (<= (abs-math (- $fs $bs)) 1e-12)
        (<= (abs-math (- $fc $bc)) 1e-12)))

!(compileadd cycleFwdKb (: a0 (CycA) (STV 0.6 0.5)))
!(compileadd cycleFwdKb (: c0 (CycC) (STV 0.6 0.5)))
!(compileadd cycleFwdKb (: aToB (Implication (CycA) (CycB)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd cycleFwdKb (: cToB (Implication (CycC) (CycB)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd cycleFwdKb (: bToA (Implication (CycB) (CycA)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let $forward
      (result-for (CycA)
         (forward-chain 50 cycleFwdKb
            (append-flat (test-selected-facts cycleFwdKb (CycA)) (test-selected-facts cycleFwdKb (CycC)))))
      ;; Reading the result may refresh a base-rate parameter in its proof.
      ;; Compare both truth components; the acyclic cases retain full proofs.
      (result-tv-close? $forward (query-for cycleFwdKb (CycA))))
   true)

;; A statement's stored facts leave out a forward run's copies also when the
;; reader is open: the copy of (P a) is found under its own key, so (P $x)
;; reads only the stored fact pall, not the derived value that already counts
;; pall.
!(compileadd openKb (: qp (Implication (Q $x) (P $x)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd openKb (: qa (Q a) (STV 1.0 0.9)))
!(compileadd openKb (: pall (P a) (STV 0.5 0.9)))
!(forward-chain 20 openKb (test-selected-facts openKb (Q a)))
!(test
   (case (stored-statement-candidate (P $x) (openKb MAIN Nil) false) (
      ((forward-derived ($_type $_kbctx $proof $tv) $_ev) ($proof $tv))
      ($other $other)))
   (pall (STV 0.5 0.9)))
