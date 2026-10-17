!(import! &self ../../pettachainer/metta/petta_chainer)

;; #84: a durable implication premise must subscribe even before MAIN has
;; its independent co-premise. Repeating the existential cannot need a
;; separate ground judgment to wake that private context.
(: late84-values (-[nondet]-> KB (List TV)))
(= (late84-values $kb)
   (collapse (let (: $_proof $_statement $tv)
      (query 300 $kb (: $p (Exists ($e) (And (Member $e StockSplit)
         (Implication (Implemented $e) (Not (Dilutes $e))))) $value)) $tv)))

!(compileadd late84Warm (: event (Member Split1 StockSplit) (STV 1 0.9)))
!(compileadd late84Warm (: bridge (Implication (And (StockSplit $e) (Implemented $e)) (Not (Dilutes $e))) (STV 1 0.9)))
!(test (late84-values late84Warm) ())
!(test (late84-values late84Warm) ())
!(compileadd late84Warm (: split (StockSplit Split1) (STV 1 0.9)))

!(compileadd late84Fresh (: event (Member Split1 StockSplit) (STV 1 0.9)))
!(compileadd late84Fresh (: bridge (Implication (And (StockSplit $e) (Implemented $e)) (Not (Dilutes $e))) (STV 1 0.9)))
!(compileadd late84Fresh (: split (StockSplit Split1) (STV 1 0.9)))
!(test (late84-values late84Fresh) ((STV 1.0 0.7498915583532259)))
!(test (late84-values late84Warm) (late84-values late84Fresh))
!(test (late84-values late84Warm) (late84-values late84Fresh))
!(test (collapse (query 300 late84Warm (: $p (Implemented Split1) $tv))) ())
!(test (collapse (query 300 late84Warm (: $p (Not (Dilutes Split1)) $tv))) ())

;; A second observation of an already borrowed premise must refresh the
;; same durable rows, rather than preserving their old confidence forever.
!(compileadd late84Warm (: second (StockSplit Split1) (STV 1 0.5)))
!(compileadd late84Fresh (: second (StockSplit Split1) (STV 1 0.5)))
!(test (late84-values late84Warm) (late84-values late84Fresh))
!(test (late84-values late84Warm) (late84-values late84Fresh))

;; Indexed subscriptions preserve the unbound reader and shared variables,
;; reject another KB/binding, and leave with an unindexed key.
!(sk-leaf-facts (Late84Pair $x $x) (late84Index 987 Nil) sk-any-filter)
!(test (=alpha (sk-world-readers (Late84Pair a a) late84Index)
   ((sk-key (Late84Pair $x $x) (late84Index 987 Nil)))) true)
!(test (sk-world-readers (Late84Pair a b) late84Index) ())
!(test (sk-world-readers (Late84Pair a a) late84Other) ())
!(test (sk-world-readers (Late84Other a a) late84Index) ())
!(sk-unindex-key! (Late84Pair $x $x) (late84Index 987 Nil)
   (index-hash (sk-key (Late84Pair $x $x) (late84Index 987 Nil))))
!(test (sk-world-readers (Late84Pair a a) late84Index) ())

;; A row may already be stale for another reason when the world fact lands.
;; Its released current-reader link must not hide the borrowing subscription.
!(foreach-flat sk-stale-key! (sk-world-readers (StockSplit Split1) late84Warm))
!(compileadd late84Warm (: third (StockSplit Split1) (STV 1 0.4)))
!(compileadd late84Fresh (: third (StockSplit Split1) (STV 1 0.4)))
!(test (late84-values late84Warm) (late84-values late84Fresh))
!(test (late84-values late84Warm) (late84-values late84Fresh))
