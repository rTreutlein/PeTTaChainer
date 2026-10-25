;; A recursive rule that builds ever larger terms, ONA reasoningbench's
;; (Num $x) → (Num (succ $x)) (ChainerGame benchmarks/ona/nal_pln/
;; reasoningbench_num.metta). The rule's base rates read its members through
;; the open nodes (Num $x) and (Num (succ $x)); the inverted rule asks
;; (Num (succ (succ $x))) of the second, and so on. Such an instance of an
;; open node whose rules were started reads that node's answers instead
;; (docs/metta/runtime_design_assumptions.md, "Queries read what their roots
;; reach"), so the open nodes stay a fixed few however long the queries go
;; on, and rows cost more the larger their statement, so a step costs the same
;; however deep the chain of members grows.

!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd numKb (: r9 (Implication (Num $x) (Num (succ $x))) (STV 1.0 0.9)))
!(compileadd numKb (: f10 (Num 1) (STV 1.0 0.9)))

!(test (query 100 numKb (: $p (Num (succ 1)) $tv))
   (: (by r9 f10) (Num (succ 1)) (STV 1.0 0.8709625388003415)))
!(test (query 100 numKb (: $p (Num (succ (succ 1))) $tv))
   (: (by r9 (by r9 f10)) (Num (succ (succ 1))) (STV 1.0 0.8616947709793574)))
!(test (query 100 numKb (: $p (Num (succ (succ (succ 1)))) $tv))
   (: (by r9 (by r9 (by r9 f10))) (Num (succ (succ (succ 1)))) (STV 1.0 0.8586491273564638)))
!(test (query 100 numKb (: $p (Num (succ (succ (succ (succ 1))))) $tv))
   (: (by r9 (by r9 (by r9 (by r9 f10)))) (Num (succ (succ (succ (succ 1))))) (STV 1.0 0.8576386846041206)))

;; Rules were started on (Num $x) and (Num (succ $x)) only; every deeper open
;; node reads one of them.
!(test (match-count &sk_open_node ($_prefix $_hash $_node)) 2)
!(test (> (match-count &sk_subsumed ($_ghash $_general $_specific)) 0) true)
