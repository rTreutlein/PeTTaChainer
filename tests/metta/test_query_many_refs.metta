!(import! &self ../../pettachainer/metta/petta_chainer)

;; query-many-refs answers as query-many does, with each proof left as a
;; reference into the proof store; expand-proof prints it as query-many does.
!(compileadd refsKb (: a (A x) (STV 0.9 0.9)))
!(compileadd refsKb (: ab (Implication (A $v) (B $v)) (STV 0.8 0.9)))
!(compileadd refsKb (: bc (Implication (B $v) (C $v)) (STV 0.7 0.9)))

!(test (case (collapse (query-many-refs 10 refsKb ((: $p (C x) $t) (: $p (A x) $t)))) (
          (((query-result 0 (: (proof-ref $pid) (C x) (STV 0.6539999999999999 0.018637821320546876)))
            (query-result 1 (: a (A x) (STV 0.9 0.9))))
             (expand-proof (proof-ref $pid)))))
       (by bc (by ab a)))
!(test (collapse (query-many 10 refsKb ((: $p (C x) $t))))
       ((query-result 0 (: (by bc (by ab a)) (C x) (STV 0.6539999999999999 0.018637821320546876)))))
