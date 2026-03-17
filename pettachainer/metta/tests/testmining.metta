!(import! &self petta_chainer)

!(compileadd kb (: d1 (Dog fido) (STV 1.0 0.5)))

!(compileadd kb (: t1 (HasTail fido) (STV 1.0 0.5)))

!(test
   (match &mining_stats (ind-impl-stats kb (Dog (V 1)) (HasTail (V 1)) $a $b)
      (ind-impl-stats kb (Dog (V 1)) (HasTail (V 1)) $a $b))
   (ind-impl-stats kb (Dog (V 1)) (HasTail (V 1)) 0.5 0.0))

!(test
   (match &mining_stats (ind-impl-stats kb (HasTail (V 1)) (Dog (V 1)) $a $b)
      (ind-impl-stats kb (HasTail (V 1)) (Dog (V 1)) $a $b))
   (ind-impl-stats kb (HasTail (V 1)) (Dog (V 1)) 0.5 0.0))

!(compileadd kb (: d2 (Dog spot) (STV 1.0 0.5)))

!(compileadd kb (: t2 (HasTail spot) (STV 0.0 0.5)))

!(test
   (match &mining_stats (ind-impl-stats kb (Dog (V 1)) (HasTail (V 1)) $a $b)
      (ind-impl-stats kb (Dog (V 1)) (HasTail (V 1)) $a $b))
   (ind-impl-stats kb (Dog (V 1)) (HasTail (V 1)) 0.5 0.5))

!(test
   (match &mining_stats (ind-impl-stats kb (HasTail (V 1)) (Dog (V 1)) $a $b)
      (ind-impl-stats kb (HasTail (V 1)) (Dog (V 1)) $a $b))
   (ind-impl-stats kb (HasTail (V 1)) (Dog (V 1)) 0.5 0.0))

!(compileadd kb (: o1 (Owns alice dog) (STV 1.0 1.0)))

!(compileadd kb (: o2 (Owns alice cat) (STV 1.0 1.0)))

!(test
   (match &mining_stats (ind-impl-stats kb (Owns (V 1) dog) (Owns (V 1) cat) $a $b)
      (ind-impl-stats kb (Owns (V 1) dog) (Owns (V 1) cat) $a $b))
   (ind-impl-stats kb (Owns (V 1) dog) (Owns (V 1) cat) 1.0 0.0))

!(test
   (match &mining_stats (ind-impl-stats kb (Owns (V 1) cat) (Owns (V 1) dog) $a $b)
      (ind-impl-stats kb (Owns (V 1) cat) (Owns (V 1) dog) $a $b))
   (ind-impl-stats kb (Owns (V 1) cat) (Owns (V 1) dog) 1.0 0.0))

!(test
   (match rules
      ($id
         (: (kb MAIN ())
            ((mined_implication (Owns (V 1) dog) (Owns (V 1) cat)) $p)
            (Owns $a cat)
            $tv)
         $args)
      ok)
   ok)

!(compileadd kb (: o3 (Owns bob dog) (STV 1.0 1.0)))

!(test
   (match rules
      ($id
         (: (kb MAIN ())
            ((mined_implication (Owns (V 1) dog) (Owns (V 1) cat)) $p)
            (Owns $x cat)
            $tv)
         $args)
      (if (is-member (: (kb MAIN ()) $prf (Owns $x dog) $tvin) $args) ok fail))
   ok)

!(compileadd kb2 (: o1 (Owns alice dog) (STV 1.0 1.0)))

!(compileadd kb2 (: o2 (Owns alice cat) (STV 1.0 1.0)))

!(test
   (collapse
      (match &kb
         (rules
            ($args |-
               (: (kb2 MAIN ())
                  ((inverted (mined_implication (Owns (V 1) dog) (Owns (V 1) cat))
                        with
                        $x1
                        $x2
                        $x3
                        $x4)
                     $p)
                  (Owns $a dog)
                  $tv)))
         found))
   ())

!(test
   (pretty
      (: (mined_implication (Owns (V 1) dog) (Owns (V 1) cat))
         (Owns bob cat)
         (STV 1.0 0.5)))
   (: (Implication (Premises (Owns (V 1) dog)) (Conclusions (Owns (V 1) cat)))
      (Owns bob cat)
      (STV 1.0 0.5)))

!(test
   (pretty
      (rules
         (((: (kb MAIN ()) p1 (Owns bob dog) (STV 1.0 1.0))
               (CPU MpFormula ((STV 1.0 1.0) (STV 1.0 0.5)) (STV 1.0 0.5)))
            |-
            (: (kb MAIN ())
               ((mined_implication (Owns (V 1) dog) (Owns (V 1) cat)) p1)
               (Owns bob cat)
               (STV 1.0 0.5)))))
   (: mined_implication
      ((Implication (Premises (Owns (V 1) dog)) (Conclusions (Owns (V 1) cat))) p1)
      (Owns bob cat)
      (STV 1.0 0.5)))

!(test
   (pretty
      (rules
         (((: (kb MAIN ()) p1 (Owns bob dog) (STV 1.0 1.0))
               (CPU MpFormula ((STV 1.0 1.0) (STV 1.0 0.5)) $tvout))
            |-
            (: (kb MAIN ())
               ((mined_implication (Owns (V 1) dog) (Owns (V 1) cat)) p1)
               (Owns bob cat)
               $tvout))))
   (: mined_implication
      ((Implication (Premises (Owns (V 1) dog)) (Conclusions (Owns (V 1) cat))) p1)
      (Owns bob cat)
      (STV 1.0 1.0)))
