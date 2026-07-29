; min-atom is deterministic for a manifest nonempty list.  This is recognized
; for literal values, but not when every element is a deterministic Number
; expression.
;
; Passes:
;   run.sh det_min_computed_nonempty.metta --strict
; Fails on PeTTa typecheck-v2 6222d50:
;   run.sh det_min_computed_nonempty.metta --strict --strict-det
;   Determinism check failed for 'min-computed-three': call('min-atom')

(: identity-number (-[det]-> Number Number))
(= (identity-number $value) $value)

(: min-computed-three
   (-[det]-> Number Number Number Number))
(= (min-computed-three $a $b $c)
   (min-atom
      ((identity-number $a)
       (identity-number $b)
       (identity-number $c))))

!(test (min-computed-three 3 1 2) 1)
