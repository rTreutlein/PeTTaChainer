!(import! &self petta_chainer)

!(compileadd openQueryKb (: d1 (Dog max) (STV 1.0 1.0)))

!(compileadd openQueryKb (: d2 (Dog ann) (STV 1.0 1.0)))

!(compileadd openQueryKb
   (: (no_inverse dog_to_animal)
      (Implication (Premises (Dog $x)) (Conclusions (Animal $x)))
      (STV 1.0 1.0)))

!(test (collapse (query 20 openQueryKb (: $prf (Animal $a) $tv)))
   ((: (rule-proof (no_inverse dog_to_animal) d2) (Animal ann) (STV 1.0 0.9))
      (: (rule-proof (no_inverse dog_to_animal) d1) (Animal max) (STV 1.0 0.9))))
