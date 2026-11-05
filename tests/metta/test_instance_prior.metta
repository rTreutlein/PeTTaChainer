!(import! &self ../../pettachainer/metta/petta_chainer)

;; A rule declared (WithPrior p (Implication a b)) is also inverted per
;; instance: an observation of b updates the instance's own prior p by Bayes'
;; rule, with P(b) from p and the rule by total probability. The sensor has
;; P(alarm | leak) = 0.9 and P(alarm | no leak) = 0.2.

!(compileadd priorKb (: sensor (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Alarm $u))) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd priorKb (: pm (LeakPredicted m) (STV 0.1 1.0)))
!(compileadd priorKb (: am (Alarm m) (STV 1.0 1.0)))
!(compileadd priorKb (: pn (LeakPredicted n) (STV 0.1 1.0)))
!(compileadd priorKb (: an (Alarm n) (STV 0.0 1.0)))
!(compileadd priorKb (: pr (LeakPredicted r) (STV 0.6 1.0)))
!(compileadd priorKb (: ar (Alarm r) (STV 1.0 1.0)))
!(compileadd priorKb (: h1 (SealLeak h1) (STV 1.0 1.0)))
!(compileadd priorKb (: ah1 (Alarm h1) (STV 1.0 1.0)))
!(compileadd priorKb (: h2 (SealLeak h2) (STV 0.0 1.0)))
!(compileadd priorKb (: ah2 (Alarm h2) (STV 0.0 1.0)))
!(compileadd priorKb (: az (Alarm z) (STV 1.0 1.0)))

;; 0.9 * 0.1 / (0.9 * 0.1 + 0.2 * 0.9)
!(test
   (query 400 priorKb (: $p (SealLeak m) $tv))
   (: ((inverted sensor with pm (prior (STV 0.1 1.0))) am) (SealLeak m) (STV 0.33333333333333337 0.9999)))
;; 0.1 * 0.1 / (0.1 * 0.1 + 0.8 * 0.9)
!(test
   (query 400 priorKb (: $p (SealLeak n) $tv))
   (: ((inverted sensor with pn (prior (STV 0.1 1.0))) an) (SealLeak n) (STV 0.013698630136986297 0.9999)))
;; 0.9 * 0.6 / (0.9 * 0.6 + 0.2 * 0.4)
!(test
   (query 400 priorKb (: $p (SealLeak r) $tv))
   (: ((inverted sensor with pr (prior (STV 0.6 1.0))) ar) (SealLeak r) (STV 0.8709677419354838 0.9999)))
;; A sure prior stays sure whatever is observed, and its posterior stays
;; confident: P(alarm) is not a separate uncertain input to Bayes' rule.
!(compileadd surePriorKb (: sensor (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Alarm $u))) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd surePriorKb (: pc (LeakPredicted c) (STV 1.0 0.99)))
!(compileadd surePriorKb (: ac (Alarm c) (STV 0.0 1.0)))
!(test
   (query 400 surePriorKb (: $p (SealLeak c) $tv))
   (: ((inverted sensor with pc (prior (STV 0.9999987373769259 0.99))) ac) (SealLeak c) (STV 0.9999898991046826 0.92522875330068)))
;; Without a prior for z, the leak base rate stands in as the prior.
!(test
   (query 400 priorKb (: $p (SealLeak z) $tv))
   (: ((inverted sensor with cpu (prior (STV 0.44576917411650074 0.006211180124223602))) az) (SealLeak z) (STV 0.7835198289038907 0.009581610628009274)))

;; An assumed observation updates the instance's prior as a stored one does:
;; the population inversion's evidence lies within the instance inversion's,
;; which stands alone, rather than applying the alarm's likelihood twice
;; (0.9 * 0.1 / (0.9 * 0.1 + 0.2 * 0.9), as for m).
!(compileadd priorKb (: pq (LeakPredicted q) (STV 0.1 1.0)))
!(test
   (query 400 priorKb (: $p (Assuming (Alarm q) (SealLeak q)) $tv))
   (: (assuming ((inverted sensor with pq (prior (STV 0.1 1.0))) (ctx proof 0)))
      (Assuming (Alarm q) (SealLeak q)) (STV 0.33333333333333337 0.9999)))

;; --- A filter over time --------------------------------------------------------
;; A leak persists and a sound seal starts leaking with hazard 0.05. Shift 1's
;; posterior predicts shift 2, whose alarm updates the prediction.

!(compileadd chainKb (: sensor (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Alarm $u))) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd chainKb (: persist (Implication (And (Next $p $u) (SealLeak $p)) (LeakPredicted $u)) (CTV (STV 1.0 1.0) (STV 0.05 1.0))))
!(compileadd chainKb (: p1 (LeakPredicted m1) (STV 0.1 1.0)))
!(compileadd chainKb (: a1 (Alarm m1) (STV 1.0 1.0)))
!(compileadd chainKb (: n12 (Next m1 m2) (STV 1.0 1.0)))
!(compileadd chainKb (: a2 (Alarm m2) (STV 1.0 1.0)))

;; 1/3 + (2/3) * 0.05, then 0.9 * 0.3667 / (0.9 * 0.3667 + 0.2 * 0.6333)
!(test
   (query 400 chainKb (: $p (LeakPredicted m2) $tv))
   (: (by persist (conjunction n12 ((inverted sensor with p1 (prior (STV 0.1 1.0))) a1))) (LeakPredicted m2) (STV 0.3666666666666667 0.9999)))
!(test
   (query 400 chainKb (: $p (SealLeak m2) $tv))
   (: ((inverted sensor with (by persist (conjunction n12 ((inverted sensor with p1 (prior (STV 0.1 1.0))) a1))) (prior (STV 0.3666666666666667 1.0))) a2) (SealLeak m2) (STV 0.7226277372262774 0.9999)))
