!(import! &self ../../pettachainer/metta/petta_chainer)

(: structural-prefilter-goal
   (-[det]-> Statement (Statement KBContext Proof TV)))
(= (structural-prefilter-goal $statement)
   (assemble-runtime-fact
      $statement
      (brand KBContext (structuralPrefilterKb MAIN Nil))
      (brand Proof probe)
      (STV 1.0 1.0)))

;; A missing input is not an impossible computation: the durable join must
;; subscribe to it so a later fact can complete the rule.
!(test
   (any-flat? prefilter-premise-blocks?
      (cons (structural-prefilter-goal (MissingThing)) ()))
   false)

!(compileadd structuralPrefilterKb (: seed0 (Seed one) (STV 1.0 1.0)))
!(test
   (any-flat? prefilter-premise-blocks?
      (cons (structural-prefilter-goal (Seed one)) ()))
   false)
