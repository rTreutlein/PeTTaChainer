!(import! &self ../../pettachainer/metta/petta_chainer)

;; #71: the instance tally and its root reader become current in one cold
;; evaluation. The Python regression also checks a fresh KB at 300 steps.
!(compileadd ev68HistoryKb (: a1 (A x) (STV 1 0.9)))
!(compileadd ev68HistoryKb (: b1 (B x) (STV 0.7 0.9)))
!(compileadd ev68HistoryKb (: c1 (C x) (STV 1 0.9)))
!(compileadd ev68HistoryKb (: (no_inverse r1) (Implication (C $v) (B $v)) (STV 0.8 0.9)))
!(test (collapse (query 5000 ev68HistoryKb (: $p (Implication (A x) (B x)) $tv)))
   ((: (implication-instance-fold cpu) (Implication (A x) (B x))
      (STV 0.9032258064516129 0.0010152758040650398))))
!(test (collapse (query 5000 ev68HistoryKb (: $p (Implication (A x) (B x)) $tv)))
   ((: (implication-instance-fold cpu) (Implication (A x) (B x))
      (STV 0.9032258064516129 0.0010152758040650398))))
