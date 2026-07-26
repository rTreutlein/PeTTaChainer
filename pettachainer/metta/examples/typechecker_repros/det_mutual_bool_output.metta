; Bound-Bool output certification is currently derived in one source-order
; pass.  Two mutually recursive det Bool functions therefore fail to certify:
; the first sees the second uncertified, and the second sees the first already
; poisoned.  Their calls cannot then feed a Boolean builtin.
;
; Fails on PeTTa typecheck-v2 9ba8764 in both modes:
;   run.sh det_mutual_bool_output.metta --strict
;   run.sh det_mutual_bool_output.metta --strict --strict-det
;   Determinism check failed for 'both-even?': call(and)

(: even-number? (-[det]-> Number Bool))
(: odd-number? (-[det]-> Number Bool))

(= (even-number? $number)
   (if (<= $number 0)
      true
      (odd-number? (- $number 1))))

(= (odd-number? $number)
   (if (<= $number 0)
      false
      (even-number? (- $number 1))))

(: both-even? (-[det]-> Number Number Bool))
(= (both-even? $left $right)
   (and (even-number? $left)
        (even-number? $right)))

!(test (both-even? 2 4) true)
!(test (both-even? 2 3) false)
