!(import! &self ../petta_chainer)

!(compileadd structuralPrefilterKb
   (: pair-rule
      (Implication
         (Seed $x)
         (Pair $x $x))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

(: structural-prefilter-goal
   (-[det]-> Statement (Statement KBContext Proof TV)))
(= (structural-prefilter-goal $statement)
   (assemble-runtime-fact
      $statement
      (brand KBContext (structuralPrefilterKb MAIN Nil))
      (brand Proof probe)
      (STV 1.0 1.0)))

;; The stored conclusion (Pair $x $x) can produce the first shape but not the
;; second. An outer-head-only index treated both as potentially concludable.
!(test
   (prefilter-head-concludable?
      (structural-prefilter-goal (Pair one one)))
   true)
!(test
   (prefilter-head-concludable?
      (structural-prefilter-goal (Pair one two)))
   false)
