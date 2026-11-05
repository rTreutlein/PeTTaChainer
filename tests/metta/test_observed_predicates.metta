!(import! &self ../../pettachainer/metta/petta_chainer)

;; Observed predicates (docs/metta/observed_predicates.md): once a link fact
;; reaches a time point, the statements of an observed predicate at it that a
;; rule concludes and that were not observed are stored false, so a rule
;; whose prediction did not come gets a negative sample.

!(set-evidence-confidence-k 1)
!(set-rule-refinement anticipateKb true)
!(set-positive-only-predicate anticipateKb Did)
!(set-positive-only-predicate anticipateKb NextPeriod)
!(set-predicate-time anticipateKb Ball 2 0)
!(set-time-link anticipateKb NextPeriod)
!(set-observed-predicate anticipateKb Ball)
!(compileadd anticipateKb (: w (Implication (And (NextPeriod $t $u) (Ball right $t) (Did right $t)) (Ball equal $u)) (STV 0.5 0.01)))
;; d2 shows the predicted equal; d3 and d4 show right: equal did not come.
;; Each time point's observations come before the link into it.
!(compileadd anticipateKb (: b1 (Ball right d1) (STV 1 1)))
!(compileadd anticipateKb (: o1 (Did right d1) (STV 1 1)))
!(compileadd anticipateKb (: b2 (Ball equal d2) (STV 1 1)))
!(compileadd anticipateKb (: b2r (Ball right d2) (STV 1 1)))
!(compileadd anticipateKb (: n1 (NextPeriod d1 d2) (STV 1 1)))
!(compileadd anticipateKb (: o2 (Did right d2) (STV 1 1)))
!(compileadd anticipateKb (: b3 (Ball right d3) (STV 1 1)))
!(compileadd anticipateKb (: n2 (NextPeriod d2 d3) (STV 1 1)))
!(compileadd anticipateKb (: o3 (Did right d3) (STV 1 1)))
!(compileadd anticipateKb (: b4 (Ball right d4) (STV 1 1)))
;; d3 was reached without equal; d4's observations are not in yet: its
;; equal is still open (and d1, which no link reaches, is never closed).
!(test (collapse (match &kb ((Ball equal $d) (anticipateKb $_c $_v) $_p (STV 0.0 1.0)) $d)) (d3))
!(compileadd anticipateKb (: n3 (NextPeriod d3 d4) (STV 1 1)))
!(test (collapse (match &kb ((Ball equal $d) (anticipateKb $_c $_v) $_p (STV 0.0 1.0)) $d)) (d3 d4))
;; One sample observed, two anticipated and missed: 1 in 3, confidence 3/4,
;; as with the false facts stated by hand.
!(test (let (: $prf $t $tv) (query 200 anticipateKb (: $prf (RuleTruth (Implication (And (NextPeriod $t $u) (Ball right $t) (Did right $t)) (Ball equal $u))) $tv)) $tv)
   (STV 0.3337930287176089 0.750611069596577))
;; An observed statement keeps its fact: d2's equal was seen, and nothing
;; else is stated for it.
!(test (collapse (match &kb ((Ball equal d2) (anticipateKb $_c $_v) $_p $tv) $tv)) ((STV 1 1)))

;; Undeclared, nothing is closed.
!(set-predicate-time openKb Ball 2 0)
!(set-time-link openKb NextPeriod)
!(compileadd openKb (: w (Implication (And (NextPeriod $t $u) (Ball right $t)) (Ball equal $u)) (STV 0.5 0.01)))
!(compileadd openKb (: b1 (Ball right d1) (STV 1 1)))
!(compileadd openKb (: n1 (NextPeriod d1 d2) (STV 1 1)))
!(compileadd openKb (: n2 (NextPeriod d2 d3) (STV 1 1)))
!(test (collapse (match &kb ((Ball $x $d) (openKb $_c $_v) $_p (STV 0.0 1.0)) $d)) ())
