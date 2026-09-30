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
   (: ((inverted sensor with pm derived) am) (SealLeak m) (STV 0.33333333333333337 0.9996618426374195)))
;; 0.1 * 0.1 / (0.1 * 0.1 + 0.8 * 0.9)
!(test
   (query 400 priorKb (: $p (SealLeak n) $tv))
   (: ((inverted sensor with pn derived) an) (SealLeak n) (STV 0.013698630136986297 0.9999000064925436)))
;; 0.9 * 0.6 / (0.9 * 0.6 + 0.2 * 0.4)
!(test
   (query 400 priorKb (: $p (SealLeak r) $tv))
   (: ((inverted sensor with pr derived) ar) (SealLeak r) (STV 0.8709677419354838 0.9999000002456949)))
;; A sure prior stays sure whatever is observed, and its posterior stays
;; confident: P(alarm) is not a separate uncertain input to Bayes' rule.
!(compileadd surePriorKb (: sensor (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Alarm $u))) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd surePriorKb (: pc (LeakPredicted c) (STV 1.0 0.99)))
!(compileadd surePriorKb (: ac (Alarm c) (STV 0.0 1.0)))
!(test
   (query 400 surePriorKb (: $p (SealLeak c) $tv))
   (: ((inverted sensor with pc derived) ac) (SealLeak c) (STV 1.0 0.6071721767418005)))
;; Without a prior for z, the leak base rate stands in as the prior.
!(test
   (query 400 priorKb (: $p (SealLeak z) $tv))
   (: ((inverted sensor with cpu derived) az) (SealLeak z) (STV 0.7824772645698216 0.009553281112175816)))

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
   (: (by persist (conjunction n12 ((inverted sensor with p1 derived) a1))) (LeakPredicted m2) (STV 0.3666666666666667 0.9996988559387328)))
!(test
   (query 400 chainKb (: $p (SealLeak m2) $tv))
   (: ((inverted sensor with (by persist (conjunction n12 ((inverted sensor with p1 derived) a1))) derived) a2) (SealLeak m2) (STV 0.7226277372262774 0.9996577117394115)))
