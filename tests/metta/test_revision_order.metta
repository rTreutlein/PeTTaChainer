!(import! &self ../../pettachainer/metta/petta_chainer)

;; Revision adds evidence counts, so the views of one statement merge to the
;; mean of their strengths weighted by their counts, whatever the order the
;; search finds them in. Views near certainty keep their counts: a view through
;; a rule and a fact both stated with confidence 1 is derived, not stated, and
;; has the most confident derived count (confidence 0.9999). When confidences
;; of 0.9999 and above were all read as that count, a merged view weighed as
;; much as each further view: 0.9, 0.7, 0.5 and 0.3 gave 0.475 or 0.725
;; depending on the order instead of their mean 0.6.

(= (near? $x $y) (< (max (- $x $y) (- $y $x)) 0.000000001))
(= (answer-strength $kb $goal)
   (let (: $_p $_type (STV $s $_c)) (query 100 $kb (: $p $goal $tv)) $s))

;; A merged confidence converts back to the count it came from.
!(test (near? (/ (confidence-to-count (count-confidence 16000000.0)) 16000000.0) 1.0) true)

;; Four views at confidence 0.9999 merge to their mean in every order.
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
;; The views' counts differ by 10^-5 of themselves (the strength of a certain
;; fact is clipped off 1, which leaves it a variance of 10^-13), so the mean is
;; 0.6 to within 10^-6, and the same in every order.
!(let $up (answer-strength up (C x))
   (progn
      (test (< (max (- $up 0.6) (- 0.6 $up)) 0.000001) true)
      (test (near? (answer-strength down (C x)) $up) true)
      (test (near? (answer-strength mixed (C x)) $up) true)))

;; Two and three views: the weighted mean of the views, each read alone.
;; The view through the rule stated with confidence 0.6 weighs less.
!(rule-view! g1 r1 A1 a1 0.9 1)
!(rule-view! g2 r2 A2 a2 0.6 0.6)
!(rule-view! g3 r3 A3 a3 0.2 1)
(= (view $kb)
   (let (: $_p $_type (STV $s $c)) (query 100 $kb (: $p (C x) $tv))
      ($s (confidence-to-count $c))))
(= (weighted-mean (($s1 $n1) ($s2 $n2)))
   (/ (+ (* $s1 $n1) (* $s2 $n2)) (+ $n1 $n2)))
(= (weighted-mean (($s1 $n1) ($s2 $n2) ($s3 $n3)))
   (/ (+ (* $s1 $n1) (+ (* $s2 $n2) (* $s3 $n3))) (+ $n1 (+ $n2 $n3))))
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
!(let* (($v1 (view g1)) ($v2 (view g2)) ($v3 (view g3)))
   (progn
      (test (near? (answer-strength two-ab (C x)) (weighted-mean ($v1 $v3))) true)
      (test (near? (answer-strength two-ba (C x)) (weighted-mean ($v1 $v3))) true)
      (test (near? (answer-strength three-abc (C x)) (weighted-mean ($v1 $v2 $v3))) true)
      (test (near? (answer-strength three-cba (C x)) (weighted-mean ($v1 $v2 $v3))) true)))
