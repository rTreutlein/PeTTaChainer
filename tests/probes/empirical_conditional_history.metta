!(import! &self ../../pettachainer/metta/petta_chainer)

;; #68(c): the instance tally becomes current within the first evaluation,
;; but its root reader keeps the earlier view. More budget does not fix it.
!(compileadd ev68HistoryKb (: a1 (A x) (STV 1 0.9)))
!(compileadd ev68HistoryKb (: b1 (B x) (STV 0.7 0.9)))
!(compileadd ev68HistoryKb (: c1 (C x) (STV 1 0.9)))
!(compileadd ev68HistoryKb (: (no_inverse r1) (Implication (C $v) (B $v)) (STV 0.8 0.9)))
!(println! (cold (collapse (query 5000 ev68HistoryKb (: $p (Implication (A x) (B x)) $tv)))))
!(println! (repeat (collapse (query 5000 ev68HistoryKb (: $p (Implication (A x) (B x)) $tv)))))
