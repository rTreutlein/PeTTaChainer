!(import! &self ../../pettachainer/metta/petta_chainer)
;; Stated judgments read their source first, even at zero budget.
;; The ordinary-budget checks reproduce the downstream failures.
!(compileadd negCtxK1 (: r1 (Implication (Not (A Item)) (B Item)) (STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 negCtxK1 (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 negCtxK1 (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd negCtxK1 (: (no_inverse bridge)
   (Implication (B $x) (C $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 negCtxK1 (: $q (Implication (Not (A Item)) (C Item)) $tv)) (<= (abs-math (- $s 0.8)) 1e-12)) true)
!(compileadd negCtxK2 (: r2 (Implication (Not (A $x)) (B $x)) (STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 negCtxK2 (: $q (Implication (Not (A $x)) (B $x)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 negCtxK2 (: $q (Implication (Not (A $x)) (B $x)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 negCtxK2 (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 negCtxK2 (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd negCtxK2 (: (no_inverse bridge)
   (Implication (B $x) (C $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 negCtxK2 (: $q (Implication (Not (A Item)) (C Item)) $tv)) (<= (abs-math (- $s 0.8)) 1e-12)) true)
!(compileadd negCtxK4 (: r4 (Implication (Not (A Item)) (B Item)) (STV 0.8 0.9)))
!(compileadd negCtxK4 (: a4 (A Item) (STV 0.1 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 negCtxK4 (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 negCtxK4 (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd negCtxK4 (: (no_inverse bridge)
   (Implication (B $x) (C $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 negCtxK4 (: $q (Implication (Not (A Item)) (C Item)) $tv)) (<= (abs-math (- $s 0.8)) 1e-12)) true)
!(compileadd negCtxK3 (: r3 (Implication (A $x) (B $x))
   (CTV (STV 0.3 0.9) (STV 0.8 0.9))))
!(test (collapse (let (: $p $type $value)
   (query 0 negCtxK3 (: $q (Implication (Not (A $x)) (B $x)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 negCtxK3 (: $q (Implication (Not (A $x)) (B $x)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 negCtxK3 (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 negCtxK3 (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd posCtxK1 (: r1 (Implication (A Item) (B Item)) (STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 posCtxK1 (: $q (Implication (A Item) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 posCtxK1 (: $q (Implication (A Item) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd posCtxK1 (: (no_inverse bridge)
   (Implication (B $x) (C $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 posCtxK1 (: $q (Implication (A Item) (C Item)) $tv)) (<= (abs-math (- $s 0.8)) 1e-12)) true)
!(compileadd posCtxK2 (: r2 (Implication (A $x) (B $x)) (STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 posCtxK2 (: $q (Implication (A $x) (B $x)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 posCtxK2 (: $q (Implication (A $x) (B $x)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 posCtxK2 (: $q (Implication (A Item) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 posCtxK2 (: $q (Implication (A Item) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd posCtxK2 (: (no_inverse bridge)
   (Implication (B $x) (C $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 posCtxK2 (: $q (Implication (A Item) (C Item)) $tv)) (<= (abs-math (- $s 0.8)) 1e-12)) true)
!(compileadd posCtxK4 (: r4 (Implication (A Item) (B Item)) (STV 0.8 0.9)))
!(compileadd posCtxK4 (: a4 (A Item) (STV 0.1 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 posCtxK4 (: $q (Implication (A Item) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 posCtxK4 (: $q (Implication (A Item) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd posCtxK4 (: (no_inverse bridge)
   (Implication (B $x) (C $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 posCtxK4 (: $q (Implication (A Item) (C Item)) $tv)) (<= (abs-math (- $s 0.8)) 1e-12)) true)
!(compileadd posCtxK3 (: r3 (Implication (A $x) (B $x))
   (CTV (STV 0.3 0.9) (STV 0.8 0.9))))
!(test (collapse (let (: $p $type $value)
   (query 0 posCtxK3 (: $q (Implication (A $x) (B $x)) $tv)) $value))
   ((STV 0.3 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 posCtxK3 (: $q (Implication (A $x) (B $x)) $tv)) $value))
   ((STV 0.3 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 0 posCtxK3 (: $q (Implication (A Item) (B Item)) $tv)) $value))
   ((STV 0.3 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 posCtxK3 (: $q (Implication (A Item) (B Item)) $tv)) $value))
   ((STV 0.3 0.9)))
!(compileadd negstvPremiseCtx (: r (Implication (Not (A Item)) (B Item)) (STV 0.8 0.9)))
!(compileadd negstvPremiseCtx (: a (A Item) (STV 0.1 0.9)))
!(add-to-kb (rules
   ((((Implication (Not (A Item)) (B Item)) (negstvPremiseCtx MAIN Nil) $p (STV $s $c)))
    |- ((Result) (negstvPremiseCtx MAIN Nil) (read $p) (STV $s $c)))))
!(test (collapse (let (: $p $type $value)
   (query 100 negstvPremiseCtx (: $q (Result) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd negctvPremiseCtx (: r (Implication (Not (A Item)) (B Item)) (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
!(compileadd negctvPremiseCtx (: a (A Item) (STV 0.1 0.9)))
!(add-to-kb (rules
   ((((Implication (Not (A Item)) (B Item)) (negctvPremiseCtx MAIN Nil) $p (CTV (STV $s $c) $negative)))
    |- ((Result) (negctvPremiseCtx MAIN Nil) (read $p) (STV $s $c)))))
!(test (collapse (let (: $p $type $value)
   (query 100 negctvPremiseCtx (: $q (Result) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd posstvPremiseCtx (: r (Implication (A Item) (B Item)) (STV 0.8 0.9)))
!(compileadd posstvPremiseCtx (: a (A Item) (STV 0.1 0.9)))
!(add-to-kb (rules
   ((((Implication (A Item) (B Item)) (posstvPremiseCtx MAIN Nil) $p (STV $s $c)))
    |- ((Result) (posstvPremiseCtx MAIN Nil) (read $p) (STV $s $c)))))
!(test (collapse (let (: $p $type $value)
   (query 100 posstvPremiseCtx (: $q (Result) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd posctvPremiseCtx (: r (Implication (A Item) (B Item)) (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
!(compileadd posctvPremiseCtx (: a (A Item) (STV 0.1 0.9)))
!(add-to-kb (rules
   ((((Implication (A Item) (B Item)) (posctvPremiseCtx MAIN Nil) $p (CTV (STV $s $c) $negative)))
    |- ((Result) (posctvPremiseCtx MAIN Nil) (read $p) (STV $s $c)))))
!(test (collapse (let (: $p $type $value)
   (query 100 posctvPremiseCtx (: $q (Result) $tv)) $value))
   ((STV 0.8 0.9)))

;; A negated reader of a positively assumed ground key must also read the
;; assumption, never the main-world 0.1. This rule has no stated query match.
!(compileadd positiveReadCtx (: a (A Item) (STV 0 1)))
!(compileadd positiveReadCtx (: (no_inverse rn)
   (Implication (Not (A Item)) (Y Item)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 positiveReadCtx (: $q (Implication (A Item) (Y Item)) $tv)) (<= (abs-math (- $s 0.2)) 1e-12)) true)

;; Querying does not assume anything in the world or store a judgment there.
!(test (collapse (query 0 negCtxK1 (: $p (A Item) $tv))) ())
!(test (collapse (query 0 posCtxK1 (: $p (A Item) $tv))) ())

;; The positive-assumption negated reader also works below another rule,
;; where no stated complementary branch can answer the query directly.
!(compileadd positiveReadCtx (: (no_inverse bridge)
   (Implication (Y Item) (Z Item)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 positiveReadCtx (: $q (Implication (A Item) (Z Item)) $tv)) (<= (abs-math (- $s 0.2)) 1e-12)) true)

;; Independent rules revise; rediscovering their applications is not another
;; observation. A later source must also reach a previously queried judgment.
!(compileadd revisedNegCtx (: r1
   (Implication (Not (A Item)) (B Item)) (STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 revisedNegCtx (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))
!(compileadd revisedNegCtx (: r2
   (Implication (Not (A Item)) (B Item)) (STV 0.4 0.9)))
!(test (let (: $p $type (STV $s $c))
   (query 100 revisedNegCtx (: $q (Implication (Not (A Item)) (B Item)) $tv)) (<= (abs-math (- $s 0.6)) 1e-12)) true)
!(test (let (: $p $type (STV $s $c))
   (query 0 revisedNegCtx (: $q (Implication (Not (A Item)) (B Item)) $tv)) (<= (abs-math (- $s 0.6)) 1e-12)) true)

;; Retaining a source must not turn a consequent-only witness into an
;; arbitrary universal individual. The compiler's witness still limits it.
!(compileadd sourceWitnessCtx (: witness
   (Implication (A $x) (B $y)) (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
!(test (collapse (query 0 sourceWitnessCtx
   (: $p (Implication (A Item) (B Unrelated)) $tv))) ())
;; A repeated query variable must not bind to its own witness term.
!(test (collapse (query 0 sourceWitnessCtx
   (: $p (Implication (A $x) (B $x)) $tv))) ())

;; A stated read remains current when the implication is a cached premise.
!(compileadd negstvPremiseCtx (: r2
   (Implication (Not (A Item)) (B Item)) (STV 0.4 0.9)))
!(test (let (: $p $type (STV $s $c))
   (query 100 negstvPremiseCtx (: $q (Result) $tv)) (<= (abs-math (- $s 0.6)) 1e-12)) true)

;; Wrapped rule names keep the same evidence identity in the judgment.
!(compileadd wrappedNegCtx (: (no_inverse rn)
   (Implication (Not (A Item)) (B Item)) (STV 0.8 0.9)))
!(test (collapse (let (: $p $type $value)
   (query 50 wrappedNegCtx (: $q (Implication (Not (A Item)) (B Item)) $tv)) $value))
   ((STV 0.8 0.9)))

;; Whole compound antecedents are assumed, including when their negation
;; is read below another rule. The corresponding world belief is irrelevant.
!(compileadd compoundReadCtx (: g (And (G) (H)) (STV 0 1)))
!(compileadd compoundReadCtx (: rn
   (Implication (Not (And (G) (H))) (Y))
   (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd compoundReadCtx (: (no_inverse bridge)
   (Implication (Y) (Z)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 compoundReadCtx (: $q (Implication (And (G) (H)) (Z)) $tv)) (<= (abs-math (- $s 0.2)) 1e-12)) true)
!(test (let (: $p $type (STV $s $c))
   (query 100 compoundReadCtx (: $q (Implication (Not (And (G) (H))) (Z)) $tv)) (<= (abs-math (- $s 0.9)) 1e-12)) true)

;; Negated compound assumptions override a certain true joint in the world.
!(compileadd compoundNegReadCtx (: g (And (G) (H)) (STV 1 1)))
!(compileadd compoundNegReadCtx (: rn
   (Implication (Not (And (G) (H))) (Y))
   (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd compoundNegReadCtx (: (no_inverse bridge)
   (Implication (Y) (Z)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 compoundNegReadCtx (: $q (Implication (Not (And (G) (H))) (Z)) $tv))
   (<= (abs-math (- $s 0.9)) 1e-12)) true)

;; An open premise reader also consumes the ground assumption when its
;; individual is absent from the consequent. The bridge prevents a direct
;; source statement from masking the reader's context.
!(compileadd genericNegReadCtx (: a (A Item) (STV 1 1)))
!(compileadd genericNegReadCtx (: (no_inverse rn)
   (Implication (Not (A $x)) (Y)) (CTV (STV 0.8 1) (STV 0 1))))
!(compileadd genericNegReadCtx (: (no_inverse bridge)
   (Implication (Y) (Z)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 genericNegReadCtx (: $q (Implication (Not (A Item)) (Z)) $tv))
   (<= (abs-math (- $s 0.8)) 1e-12)) true)
!(compileadd genericPosReadCtx (: a (A Item) (STV 0 1)))
!(compileadd genericPosReadCtx (: (no_inverse rn)
   (Implication (Not (A $x)) (Y)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd genericPosReadCtx (: (no_inverse bridge)
   (Implication (Y) (Z)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 100 genericPosReadCtx (: $q (Implication (A Item) (Z)) $tv))
   (<= (abs-math (- $s 0.2)) 1e-12)) true)

;; Wrapped rules carry their registered base evidence in MAIN too. A CTV
;; implication premise must not revise its axiom with its own application.
!(compileadd wrappedMainNegCtxKb (: (no_inverse wrapped)
   (Implication (A Item) (B Item)) (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
!(test (rule-result-evidence
   (assemble-runtime-fact (brand Statement (quote (B Item)))
      (kbctx wrappedMainNegCtxKb)
      (brand Proof (quote (by (no_inverse wrapped) (ctx proof test)))) (STV 0.8 0.9)) (ev-set 0))
   (evidence-set ((rule-ev wrappedMainNegCtxKb wrapped))))
!(compileadd wrappedMainNegCtxKb (: consumer
   (Implication (Implication (A Item) (B Item)) (Checked Item))
   (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $p $type (STV $s $c))
   (query 300 wrappedMainNegCtxKb (: $q (Checked Item) $tv))
   (and (<= (abs-math (- $s 0.8)) 1e-12) (< $c 0.90001))) true)

;; An independently observed consequent remains visible in the judgment.
;; The false assumed STV application still contributes no extra evidence.
!(compileadd unsupportedPopulationNegCtxKb (: g (G) (STV 0.5 0.9)))
!(compileadd unsupportedPopulationNegCtxKb (: y (Y) (STV 0.95 0.9)))
!(compileadd unsupportedPopulationNegCtxKb (: rn
   (Implication (Not (G)) (Y)) (STV 0.9 0.9)))
;; Read the judgment context itself: a public query also has independent
;; empirical instance evidence from g and y, which remains valid.
!(let* ((($shape $_assumption $conclusion $adds)
            (judgment-query-side unsupportedPopulationNegCtxKb Nil false
               (brand Statement (quote (G))) (brand Statement (quote (Y)))))
          ($_injected (collapse (once (inject-compiled-adds (map-flat mm2stmt $adds)))))
          ($_answers (chainer 300 (internalize-proof-structure (: $shape $q $conclusion $tv))))
          ((sk-val ($_type $_context $_proof $value) $ev $_deps)
             (sk-value (sk-key $conclusion $shape) sk-any-filter ()))
          ($valid (and (=alpha $value (STV 0.9500000000000001 0.9))
             (== $ev (evidence-set ((fact-ev (unsupportedPopulationNegCtxKb MAIN Nil) y (Y)))))))
          ($_cleared (clear-temp-query-adds)))
   (test $valid true))

;; Prefix lookup may specialize a variable assumption to a ground reader.
;; That specialization must not turn its hypothetical individual into Fixed.
!(let* (($a (quote (A $prototype)))
          ($b (quote (B $prototype)))
          ($vars (cons (brand Variable $prototype) ()))
          (($shape $_proof $_b $adds)
             (judgment-query-side indexedPrototypeNegCtxKb $vars false
                (brand Statement $a) (brand Statement $b)))
          ($_injected (collapse (once (inject-compiled-adds (map-flat mm2stmt $adds)))))
          ($fixed (quote (A Fixed)))
          ($valid (and (judgment-assumed-key? $a $shape)
             (not (judgment-assumed-key? $fixed $shape))))
          ($_cleared (clear-temp-query-adds)))
   (test $valid true))
