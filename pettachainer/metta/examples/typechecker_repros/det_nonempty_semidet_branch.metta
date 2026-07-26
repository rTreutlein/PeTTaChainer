; A branch that excludes the empty list should make the semidet head accessor
; deterministic within that branch.
;
; Passes:
;   run.sh det_nonempty_semidet_branch.metta --strict
; Fails on PeTTa typecheck-v2 6222d50:
;   run.sh det_nonempty_semidet_branch.metta --strict --strict-det
;   Determinism check failed for 'first-or-zero': call('first-number')

(: first-number (-[semidet]-> (List Number) Number))
(= (first-number (cons $head $_tail)) $head)

(: first-or-zero (-> (List Number) Number))
(= (first-or-zero $values)
   (if (== $values ())
      0
      (first-number $values)))

!(test (first-or-zero (4 5)) 4)
!(test (first-or-zero ()) 0)
