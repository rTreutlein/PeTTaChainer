!(import! &self ../../pettachainer/metta/petta_chainer)

;; A rule ingestion rejects after compiling it leaves nothing behind: its
;; antecedent's producers are not withheld from later readers of the key, and
;; queries add no permanent rules for the compounds they read (#142).
!(set-functional-predicate rejectedKb Size 2 (1))
!(compileadd rejectedKb (: pa (P a) (STV 0.8 0.9)))
!(compileadd rejectedKb (: qa (Q a) (STV 0.7 0.9)))
!(test (case (catch (compileadd rejectedKb (: bad (Implication (And (P $x) (Q $x)) (Size $x big)) (STV 0.9 0.9)))) (
   ((Error $_call $_error) rejected)
   ($_other accepted)))
   rejected)
!(test (query 100 rejectedKb (: $p (And (P $y) (Q $y)) $tv)) (: (conjunction pa qa) (And (P a) (Q a)) (STV 0.5599999999999999 0.9124421574418279)))
!(test (query 100 rejectedKb (: $p (And (P a) (Q a)) $tv)) (: (conjunction pa qa) (And (P a) (Q a)) (STV 0.5599999999999999 0.9124421574418279)))
!(test (let* (($before (length (collapse (match rules (runtime-rule-row $i ($t (rejectedKb $c $v) $p $tv) $a) $i))))
              ($_answers (collapse (query 100 rejectedKb (: $q (And (Q a) (P a)) $qtv))))
              ($after (length (collapse (match rules (runtime-rule-row $j ($t2 (rejectedKb $c2 $v2) $p2 $tv2) $a2) $j)))))
         (== $before $after))
   true)
