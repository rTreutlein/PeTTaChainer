!(import! &self ../../pettachainer/metta/petta_chainer)

;; #42: the stored target is the instance prior for the diagnostic update.
;; Disable likelihood shrinkage here to leave a hand-computable Jeffrey update:
;; P(E)=.9*.3+.2*.7=.41;
;; q=.4*(.27/.41)+.6*(.03/.59)=.2939231087226126.
;; Its update variance is below the population prior's, so the max(0, ...)
;; term is zero. V_logit=1/(3201*.3*.7). At q this implies
;; n=3201*.3*.7/(q*(1-q))-1, c=n/(n+800)=.8018851534917931.
!(set-bayes-prior-count 0)
!(compileadd storedKb (: diagnostic (Implication (Cause $t) (Effect $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd storedKb (: (no_inverse prediction) (Implication (Action $t) (Effect $t)) (CTV (STV 0.4 1) (STV 0.4 1))))
!(compileadd storedKb (: cause-prior (Cause now) (STV 0.3 0.8)))
!(set-base-rate storedKb (Cause $t) (STV 0.3 0.9))

(= (stored-update? (: $proof $_statement (STV $s $c)))
   (and (== (case $proof (((assuming $inner) (car-atom $inner)) ($_plain (car-atom $proof)))) factored-revision)
      (and (< (abs-math (- $s 0.2939231087226126)) 0.000001)
           (< (abs-math (- $c 0.8018851534917931)) 0.000001))))

;; Exercise the overlay first, then MAIN: no context-local value may leak.
!(test (stored-update? (query 2000 storedKb (: $p (Assuming (Action now) (Cause now)) $tv))) true)
!(test (query 2000 storedKb (: $p (Cause now) $tv)) (: cause-prior (Cause now) (STV 0.3 0.8)))
!(compileadd storedKb (: action (Action now) (STV 1 1)))
!(test (stored-update? (query 2000 storedKb (: $p (Cause now) $tv))) true)

;; An antecedent completion is the same kind of update.
!(compileadd completionKb (: diagnostic (Implication (And (Enabled $t) (Cause $t)) (Effect $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd completionKb (: (no_inverse prediction) (Implication (Action $t) (Effect $t)) (CTV (STV 0.4 1) (STV 0.4 1))))
!(compileadd completionKb (: cause-prior (Cause now) (STV 0.3 0.8)))
!(compileadd completionKb (: enabled (Enabled now) (STV 1 1)))
!(compileadd completionKb (: action (Action now) (STV 1 1)))
!(set-base-rate completionKb (Cause $t) (STV 0.3 0.9))
!(test (stored-update? (query 2000 completionKb (: $p (Cause now) $tv))) true)
!(set-bayes-prior-count 0.2)
