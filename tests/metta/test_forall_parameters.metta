!(import! &self ../../pettachainer/metta/petta_chainer)

;; A ForAll parameter is universal in a rule's conclusions (#142): one
;; occurring only in the conclusion is no Skolem witness.

(: stored-facts (-[det]-> KB Statement (List (Statement KBContext Proof TV))))
(= (stored-facts $kb $type)
   (collapse
      (once
         (match &kb ($type ($kb MAIN Nil) $prf $tv)
            (assemble-stored-runtime-fact $type ($kb MAIN Nil) $prf $tv)))))
(: result-values (-[det]-> (List (Statement KBContext Proof TV)) (List Atom)))
(= (result-values ()) ())
(= (result-values (cons ($type $_kbctx $_proof $tv) $rest)) (cons ($type $tv) (result-values $rest)))

;; The parameter $c occurs only in the conclusion: the forward run derives the
;; open statement, and an instance of it counts the rule once, after the run
;; as before it. A forward run stores only closed keys.
!(compileadd paramKb (: aa (A a) (STV 0.9 0.9)))
!(compileadd paramKb (: r (ForAll ($c) (Implication (A $x) (B $c $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(test (result-values (forward-chain 100 paramKb (stored-facts paramKb (A a))))
   (((B $_0 a) (STV 0.7300000000000001 0.9103924430491427))))
!(test (query 100 paramKb (: $prf (B m a) $tv))
   (: (by r aa) (B m a) (STV 0.7300000000000001 0.9103924430491427)))

;; Controls: a plain rule, and a parameter the antecedent binds.
!(compileadd plainKb (: aa (A a) (STV 0.9 0.9)))
!(compileadd plainKb (: r (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(test (result-values (forward-chain 100 plainKb (stored-facts plainKb (A a))))
   (((B a) (STV 0.7300000000000001 0.9103924430491427))))
!(test (query 100 plainKb (: $prf (B a) $tv))
   (: (by r aa) (B a) (STV 0.7300000000000001 0.9103924430491427)))
!(compileadd boundKb (: aa (A k a) (STV 0.9 0.9)))
!(compileadd boundKb (: r (ForAll ($c) (Implication (A $c $x) (B $c $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(test (result-values (forward-chain 100 boundKb (stored-facts boundKb (A k a))))
   (((B k a) (STV 0.7300000000000001 0.9103924430491427))))
!(test (query 100 boundKb (: $prf (B k a) $tv))
   (: (by r aa) (B k a) (STV 0.7300000000000001 0.9103924430491427)))

;; An inverse conclusion keeps the parameter universal too: observing (B a)
;; supports (A k a) for every value of the parameter.
!(compileadd inverseKb (: bb (B a) (STV 0.9 0.9)))
!(compileadd inverseKb (: r (ForAll ($c) (Implication (A $c $x) (B $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(test (query 100 inverseKb (: $prf (A k a) $tv))
   (: ((inverted r with cpu (prior (STV 0.5 0.0))) bb) (A k a) (STV 0.8181718195152319 0.004449397590627516)))
