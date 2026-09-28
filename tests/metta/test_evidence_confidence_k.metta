!(import! &self ../../pettachainer/metta/petta_chainer)

; --- PLN's evidence parameter k is a user setting --------------------------

; The default k is 800: 800 pieces of evidence give confidence 0.5.
!(test (count-confidence 800.0) 0.5)

!(test (set-evidence-confidence-k 1.0) true)

; Every conversion between counts and confidences reads the current k.
!(test (count-confidence 1.0) 0.5)
!(test (confidence-to-count 0.5) 1.0)
!(test (merge-stv-fields 1.0 0.5 0.0 0.5) (STV 0.5 0.6666666666666666))

; A member fold counts each individual once, so two observed members of
; Normal give confidence 2/(2+k).
!(compileadd kKb (: n-1 (Member h1 Normal) (STV 1 1)))
!(compileadd kKb (: l-1 (Member h1 Leak) (STV 1 1)))
!(compileadd kKb (: n-2 (Member h2 Normal) (STV 1 1)))
!(compileadd kKb (: l-2 (Member h2 Leak) (STV 0 1)))

!(test
   (collapse (let (: $_prf $_type $tv)
      (query 100 kKb (: $prf (Inheritance Normal Leak) $tv))
      $tv))
   ((STV 0.5 0.6666666666666666)))
