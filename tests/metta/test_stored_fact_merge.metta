!(import! &self ../../pettachainer/metta/petta_chainer)

;; A statement's stored facts are one candidate merged by the key merge
;; (sk-merge-facts): for independent facts, revision. Each fact here holds one
;; observation (confidence 0.5 is count 1 at k = 1), so two of them merge to
;; strength (0.8 + 0.4) / 2 = 0.6 at count 2, confidence 2/3, and a third at
;; 0.2 gives strength 1.4 / 3 at count 3, confidence 3/4. Each caller of the
;; candidate below must see the merge, not the first fact: the forward schema
;; calls sk-merge-facts before backward/evaluation.metta defines it.
!(compileadd mergeKb (: a1 (P a) (STV 0.8 0.5)))
!(compileadd mergeKb (: a2 (P a) (STV 0.4 0.5)))

(= (candidate-tv $kb $type)
   (case (stored-statement-candidate $type ($kb MAIN Nil) false) (
      ((forward-derived ($_type $_kbctx $_proof $tv) $_ev) $tv)
      (no-forward-output-candidate none))))

!(test (candidate-tv mergeKb (P a)) (STV 0.6 0.6666666666666666))
!(test (query 50 mergeKb (: $p (P a) $tv)) (: (merge/revision a2 a1) (P a) (STV 0.6 0.6666666666666666)))

!(compileadd mergeKb (: a3 (P a) (STV 0.2 0.5)))
!(test (candidate-tv mergeKb (P a)) (STV 0.46666666666666656 0.75))

;; A removed fact leaves what the others say (remove-named-fact!).
!(remove-compiled-statement a3)
!(test (candidate-tv mergeKb (P a)) (STV 0.6 0.6666666666666666))

;; Membership reads the stored facts merged (fa-member), as aggregate
;; seeding counts a statement once with its facts merged (fa-seed-statement).
!(compileadd mergeKb (: d1 (Member rex Dog) (STV 0.8 0.5)))
!(compileadd mergeKb (: d2 (Member rex Dog) (STV 0.4 0.5)))
!(test (case (fa-member mergeKb rex Dog) (((forward-derived ($_t $_c $_p $tv) $_ev) $tv) ($other $other)))
   (STV 0.6 0.6666666666666666))
!(test (case (fa-seed-statement (mergeKb MAIN Nil) () (Member rex Dog)) (((cons ($_t $_c $_p $tv) ()) $tv) ($other $other)))
   (STV 0.6 0.6666666666666666))

;; A rule premise read from the stored facts matches their merged value
;; (sk-stored-premise-step): its evidence is the facts'.
!(test (case (collapse (sk-stored-premise-step (evidence-set ())
               ((P a) (mergeKb MAIN Nil) (merge/revision a1 a2) (STV 0.6 0.6666666666666666)))) (
          ((cons $ev ()) (== $ev (evidence-set ())))
          ($other $other)))
   False)
