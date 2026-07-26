; A det function whose implementation always produces a bound Bool should be
; usable as an operand of and/or/not.  The checker recognizes bound Bool
; parameters and det builtin Bool results, but does not propagate the same
; guarantee through a user function call.
;
; Fails on PeTTa typecheck-v2 19c4671 in both modes:
;   run.sh det_bool_call_operand.metta --strict
;   run.sh det_bool_call_operand.metta --strict --strict-det
;   Determinism check failed for 'both-empty': call(and)

(: is-empty (-[det]-> (List Number) Bool))
(= (is-empty $values)
   (== $values ()))

(: both-empty (-[det]-> (List Number) (List Number) Bool))
(= (both-empty $left $right)
   (and (is-empty $left)
        (is-empty $right)))

!(test (both-empty () ()) true)
!(test (both-empty () (1)) false)
