!(import! &self ../../pettachainer/metta/petta_chainer)

;; Certain rules carry no statistical evidence. Retirement must nevertheless
;; remove their existing views, their cached merges and downstream views.
!(compileadd retireKb (: old (Implication (A $t) (B $t)) (STV 1 1)))
!(compileadd retireKb (: downstream (Implication (B $t) (D $t)) (STV 1 1)))
!(compileadd retireKb (: alternative (Implication (C $t) (B $t)) (STV 0.2 1)))
!(compileadd retireKb (: a (A warm) (STV 1 1)))
!(compileadd retireKb (: c (C warm) (STV 1 1)))
!(query 40 retireKb (: $p (D warm) $tv))
!(withdraw-named-rules! old)
!(test (let (: $proof $_statement (STV $strength $_confidence))
               (query 40 retireKb (: $p (B warm) $tv))
            (data $proof $strength))
   ((by alternative c) 0.2))
!(test (let (: $proof $_statement (STV $strength $_confidence))
               (query 40 retireKb (: $p (D warm) $tv))
            (data $proof $strength))
   ((by downstream (by alternative c)) 0.2))
;; The old open waiter must never build a row for a new ground time point.
!(compileadd retireKb (: a-fresh (A fresh) (STV 1 1)))
!(compileadd retireKb (: c-fresh (C fresh) (STV 1 1)))
!(test (let (: $proof $_statement (STV $strength $_confidence))
               (query 40 retireKb (: $p (B fresh) $tv))
            (data $proof $strength))
   ((by alternative c-fresh) 0.2))

;; Reusing a source name creates new rule identities, without resurrecting
;; the views of the earlier rule bearing that name.
!(compileadd reuseKb (: reusable (Implication (Input $t) (Output $t)) (STV 1 1)))
!(compileadd reuseKb (: input (Input warm) (STV 1 1)))
!(query 40 reuseKb (: $p (Output warm) $tv))
!(withdraw-named-rules! reusable)
!(compileadd reuseKb (: reusable (Implication (Input $t) (Output $t)) (STV 0.2 1)))
!(test (let (: $proof $_statement (STV $strength $_confidence))
               (query 40 reuseKb (: $p (Output warm) $tv))
            (data $proof $strength))
   ((by reusable input) 0.2))


;; Cached fold proofs carry their members' rule identities too.
!(compileadd foldRetireKb (: fold-old (Implication (A $t) (B $t)) (CTV (STV 0.8 1) (STV 0 1))))
!(compileadd foldRetireKb (: fold-live (Implication (C $t) (B $t)) (CTV (STV 0.2 1) (STV 0 1))))
!(compileadd foldRetireKb (: fold-a (A warm) (STV 1 1)))
!(compileadd foldRetireKb (: fold-c (C warm) (STV 1 1)))
!(query 40 foldRetireKb (: $p (FoldAllTruth (B $t) (STV $s $_c) $s 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total) $tv))
!(withdraw-named-rules! fold-old)
!(test (let (: $_proof (FoldAllTruth $_pattern $_tv-pattern $_extractor $_init $_fun -> $total) $_tv)
               (query 40 foldRetireKb (: $p (FoldAllTruth (B $t) (STV $s $_c) $s 0 (|-> ($acc $elem) (+ $acc $elem)) -> $result) $tv))
            $total)
   0.2)

;; Compression retains retirement provenance after the old rows are gone.
!(set-forgetting 1 1.0)
!(compileadd summaryRetireKb (: summary-old (Implication (A $t) (B $t)) (CTV (STV 0.8 1) (STV 0 1))))
!(compileadd summaryRetireKb (: summary-a (A warm) (STV 1 1)))
!(query 40 summaryRetireKb (: $p (B warm) $tv))
!(advance-epoch)
!(advance-epoch)
!(withdraw-named-rules! summary-old)
!(test (collapse (query 40 summaryRetireKb (: $p (B warm) $tv))) ())
!(set-forgetting 0 1.0)
