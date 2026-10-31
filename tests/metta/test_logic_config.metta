!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self ./posterior_assertions)

(: CustomLogic LogicName)
(: NoOrLogic LogicName)

(: logic-test-runtime-fact
   (-[det]-> Statement Proof TV
       (Statement KBContext Proof TV)))
(= (logic-test-runtime-fact $statement $proof $tv)
   (assemble-runtime-fact
      $statement
      (brand KBContext (projectionDominanceKb MAIN Nil))
      $proof
      $tv))

!(compileadd plnLogicKb (: a (A) (STV 1.0 1.0)))

;; A certain-true disjunct settles the Or without a proof of the other.
!(test
   (query 20 plnLogicKb (: $prf (Or (A) (B)) $tv))
   (: (settled a) (Or (A) (B)) (STV 1.0 1.0)))

;; The observed (And (A) (B)) at (1, .9) is Pearl evidence at its mean m =
;; 7201/7202 (exact only at confidence 1): with A unknown, lambda1 = .5 and
;; lambda0 = 1 - m, so B = .5/(.5 + (1 - m)) = .99972 on its uniform prior,
;; its variance the exact integral over B's prior and A's (2.20e-6, c .1354).
!(compileadd plnProjectionNeedsEvidenceKb (: ab (And (A) (B)) (STV 1.0 0.9)))

!(test
   (posterior-tv-near? 0.9997223764575236 0.0 (let (: $_proof (B) $tv) (query 20 plnProjectionNeedsEvidenceKb (: $prf (B) $tv)) $tv))
   true)

;; With A certain too, the message is lambda1 = m, lambda0 = 1 - m: B = m.
!(compileadd plnProjectionKb (: ab (And (A) (B)) (STV 1.0 0.9)))
!(compileadd plnProjectionKb (: a (A) (STV 1.0 1.0)))

!(test
   (posterior-tv-near? 0.9998611496806441 0.000624869674253918 (let (: $_proof (B) $tv) (query 20 plnProjectionKb (: $prf (B) $tv)) $tv))
   true)

!(compileadd plnOrProjectionKb (: ab (Or (A) (B)) (STV 1.0 0.9)))
!(compileadd plnOrProjectionKb (: a (A) (STV 1.0 1.0)))

;; A true disjunct leaves the other undetermined: the message gives no value
;; rather than one of confidence 0.
!(test (query 20 plnOrProjectionKb (: $prf (B) $tv)) ())

!(import! &self ../../pettachainer/metta/core/logic_configs/predicate_logic)

!(compileadd predicateLogicKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 predicateLogicKb (: $prf (Or (A) (B)) $tv))
   (: (Orintroduction a) (Or (A) (B)) (STV 1.0 1.0)))

;; An open compound query must keep the complete child shape available to the
;; conclusion index. Both alternatives remain reachable without falling back
;; to an outer-head-only scan of every generated Or introduction rule.
!(compileadd predicateLogicOpenOrKb
   (: p-one (P one) (STV 1.0 1.0)))
!(compileadd predicateLogicOpenOrKb
   (: q-two (Q two) (STV 1.0 1.0)))

!(test
   (length
      (collapse
         (query 20 predicateLogicOpenOrKb
            (: $prf (Or (P $x) (Q $x)) $tv))))
   2)

!(import! &self ../../pettachainer/metta/core/logic_configs/pln)

!(compileadd plnAfterSwitchKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 plnAfterSwitchKb (: $prf (Or (A) (B)) $tv))
   (: (settled a) (Or (A) (B)) (STV 1.0 1.0)))

!(clear-logic-config)
!(set-logic-name CustomLogic)
!(set-compound-connective Either Any NoProjection)

!(compileadd customEitherKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 customEitherKb (: $prf (Either (A) (B)) $tv))
   (: (Eitherintroduction a) (Either (A) (B)) (STV 1.0 1.0)))

!(clear-logic-config)
!(set-logic-name NoOrLogic)
!(set-compound-connective And All ProjectAll)

!(compileadd noOrKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 noOrKb (: $prf (Or (A) (B)) $tv))
   ())

!(import! &self ../../pettachainer/metta/core/logic_configs/pln)
