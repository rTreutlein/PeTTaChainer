!(import! &self ../../pettachainer/metta/petta_chainer)

;; A node reading any proof and value is answered by every registered ground key
;; unifying with it, whichever search registered the key
;; (docs/metta/answers_by_index.md).

(: open-member-answer? (-[det]-> Atom Atom Bool))
(= (open-member-answer? $pred $arg)
   (== (collapse (match &sk_answer ($_h (($pred $v) $_c $_p $_t) (sk-key ($pred $arg) $_kc)) (is-var $v)))
       (True)))

;; Inverting r for (P alice) reads the base rate of P, which sets up its
;; member node (P $x). A key registered later by another search joins it.
!(compileadd memKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd memKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd memKb (: pb (P bob) (STV 0.7 0.8)))
!(test (case (query 200 memKb (: $prf (P alice) $tv)) (((: $p (P alice) $t) ok))) ok)
!(test (open-member-answer? P zed) False)
!(test (let $_registered (sk-register-key! (the SkeletonKey (sk-key (P zed) (memKb MAIN Nil)))) (open-member-answer? P zed)) True)

;; A member node set up after a key was registered takes the key.
!(compileadd memKb (: s (Implication (R $x) (S $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd memKb (: sa (S alice) (STV 0.9 0.8)))
!(compileadd memKb (: rb (R bob) (STV 0.7 0.8)))
!(test (let $_registered (sk-register-key! (the SkeletonKey (sk-key (R zed) (memKb MAIN Nil)))) (open-member-answer? R zed)) False)
!(test (case (query 200 memKb (: $prf (R alice) $tv)) (((: $p (R alice) $t) ok))) ok)
!(test (open-member-answer? R zed) True)

;; A join waiting on a ground premise sees the premise's key registered by
;; another search, without expanding the premise: with one step, which expands only the
;; root, its join over r completes for (P carl) and leaves a row for (Q carl).
(: concluding-rows (-[det]-> Atom Number))
(= (concluding-rows $statement)
   (list-len (collapse (match &sk_row ($_kh (sk-key $statement $_c) $_rh $_row) true))))
!(test (concluding-rows (Q carl)) 0)
!(test (let* (($_registered (sk-register-key! (the SkeletonKey (sk-key (P carl) (memKb MAIN Nil)))))
              ($_answers (collapse (query 1 memKb (: $p (Q carl) $t)))))
          (> (concluding-rows (Q carl)) 0))
       True)
