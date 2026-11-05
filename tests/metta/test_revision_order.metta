!(import! &self ../../pettachainer/metta/petta_chainer)

;; Revision adds evidence counts, so the views of one statement merge to the
;; mean of their strengths weighted by their counts, whatever the order the
;; search finds them in. A view through a rule and a fact both stated with
;; confidence 1 is a point, which has no finite count: points weigh alike, so
;; 0.9, 0.7, 0.5 and 0.3 give their mean 0.6 in every order (pairwise
;; averaging gave 0.475 or 0.725 depending on the order).

(= (near? $x $y) (< (max (- $x $y) (- $y $x)) 0.000000001))
(= (answer-strength $kb $goal)
   (let (: $_p $_type (STV $s $_c)) (query 100 $kb (: $p $goal $tv)) $s))

;; A merged confidence converts back to the count it came from.
!(test (near? (/ (confidence-to-count (count-confidence 16000000.0)) 16000000.0) 1.0) true)

;; Four point views merge to their mean in every order.
(= (rule-view! $kb $rule $antecedent $fact $s $c)
   (progn
      (compileadd $kb (: $rule (Implication ($antecedent $x) (C $x)) (CTV (STV $s $c) (STV 0.1 $c))))
      (compileadd $kb (: $fact ($antecedent x) (STV 1 1)))))
!(rule-view! up r1 A1 a1 0.9 1)
!(rule-view! up r2 A2 a2 0.7 1)
!(rule-view! up r3 A3 a3 0.5 1)
!(rule-view! up r4 A4 a4 0.3 1)
!(rule-view! down r4 A4 a4 0.3 1)
!(rule-view! down r3 A3 a3 0.5 1)
!(rule-view! down r2 A2 a2 0.7 1)
!(rule-view! down r1 A1 a1 0.9 1)
!(rule-view! mixed r3 A3 a3 0.5 1)
!(rule-view! mixed r1 A1 a1 0.9 1)
!(rule-view! mixed r4 A4 a4 0.3 1)
!(rule-view! mixed r2 A2 a2 0.7 1)
!(test
   (let $up (answer-strength up (C x))
      (data (< (max (- $up 0.6) (- 0.6 $up)) 0.000001)
            (near? (answer-strength down (C x)) $up)
            (near? (answer-strength mixed (C x)) $up)))
   (true true true))

;; Two and three views. Two points merge to their mean, 0.55; a finite view
;; (the rule stated with confidence 0.6) does not move them, in either order.
!(rule-view! two-ab r1 A1 a1 0.9 1)
!(rule-view! two-ab r3 A3 a3 0.2 1)
!(rule-view! two-ba r3 A3 a3 0.2 1)
!(rule-view! two-ba r1 A1 a1 0.9 1)
!(rule-view! three-abc r1 A1 a1 0.9 1)
!(rule-view! three-abc r2 A2 a2 0.6 0.6)
!(rule-view! three-abc r3 A3 a3 0.2 1)
!(rule-view! three-cba r3 A3 a3 0.2 1)
!(rule-view! three-cba r2 A2 a2 0.6 0.6)
!(rule-view! three-cba r1 A1 a1 0.9 1)
!(test
   (data (near? (answer-strength two-ab (C x)) 0.55)
         (near? (answer-strength two-ba (C x)) 0.55)
         (near? (answer-strength three-abc (C x)) 0.55)
         (near? (answer-strength three-cba (C x)) 0.55))
   (true true true true))
