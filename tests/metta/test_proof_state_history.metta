!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd historyKb (: left-a (HistoryLeft a) (STV 1.0 0.8)))
!(compileadd historyKb (: left-b (HistoryLeft b) (STV 1.0 0.8)))
!(compileadd historyKb (: right-a (HistoryRight a) (STV 1.0 0.7)))
!(compileadd historyKb
   (: (no_inverse left-rule)
      (Implication (HistoryLeft $x) (HistoryOutput $x))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd historyKb
   (: (no_inverse right-rule)
      (Implication (HistoryRight $x) (HistoryOutput $x))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; Output a has two active raw candidates and a merged representative. Output
;; b has one raw representative. All three raw proofs remain durable history.
!(test
   (collapse (query 50 historyKb (: $proof (HistoryOutput $x) $tv)))
   ((: (merge/revision
          (by (no_inverse left-rule) left-a)
          (by (no_inverse right-rule) right-a))
       (HistoryOutput a) (STV 1.0 0.8636363636363636))
    (: (by (no_inverse left-rule) left-b)
       (HistoryOutput b) (STV 1.0 0.8))))

;; A zero-budget read restricts each output's value to the proofs matching the
;; pattern: a's left-rule derivation answers although its merged value does not.
!(test
   (collapse
      (query 0 historyKb
         (: (by (no_inverse left-rule) $source) (HistoryOutput $x) $tv)))
   ((: (by (no_inverse left-rule) left-a)
       (HistoryOutput a) (STV 1.0 0.8))
    (: (by (no_inverse left-rule) left-b)
       (HistoryOutput b) (STV 1.0 0.8))))

;; With no compatible published group, the historical fallback can still
;; retrieve a raw proof which previously lost the representative role.
!(test
   (collapse
      (query 0 historyKb
         (: (by (no_inverse left-rule) left-a) (HistoryOutput $x) $tv)))
   ((: (by (no_inverse left-rule) left-a)
       (HistoryOutput a) (STV 1.0 0.8))))

;; A TV constraint likewise selects the proofs with that truth value: a's
;; left-rule derivation, never its merged value.
!(test
   (collapse
      (query 0 historyKb
         (: $proof (HistoryOutput $x) (STV 1.0 0.8))))
   ((: (by (no_inverse left-rule) left-a)
       (HistoryOutput a) (STV 1.0 0.8))
    (: (by (no_inverse left-rule) left-b)
       (HistoryOutput b) (STV 1.0 0.8))))

;; Warm the grounded goal key used below; the earlier queries used a variable
;; statement pattern with its own durable search index.
!(test
   (collapse (query 50 historyKb (: $proof (HistoryOutput a) $tv)))
   ((: (merge/revision
          (by (no_inverse left-rule) left-a)
          (by (no_inverse right-rule) right-a))
       (HistoryOutput a) (STV 1.0 0.8636363636363636))))

;; Constraint variants share durable history, but each root independently
;; selects its compatible published group or falls back to its raw incumbent.
!(test
   (collapse
      (query-many 0 historyKb
         ((: (by (no_inverse left-rule) left-a) (HistoryOutput a) $tv)
          (: $proof (HistoryOutput a) $tv))))
   ((query-result 0
       (: (by (no_inverse left-rule) left-a)
          (HistoryOutput a) (STV 1.0 0.8)))
    (query-result 1
       (: (merge/revision
             (by (no_inverse left-rule) left-a)
             (by (no_inverse right-rule) right-a))
          (HistoryOutput a) (STV 1.0 0.8636363636363636)))))

!(test
   (collapse
      (query-many 0 historyKb
         ((: $proof (HistoryOutput a) (STV 1.0 0.8))
          (: $proof (HistoryOutput a) (STV 1.0 0.8636363636363636)))))
   ((query-result 0 (: (by (no_inverse left-rule) left-a) (HistoryOutput a) (STV 1.0 0.8))) (query-result 1 (: (merge/revision (by (no_inverse left-rule) left-a) (by (no_inverse right-rule) right-a)) (HistoryOutput a) (STV 1.0 0.8636363636363636)))))
