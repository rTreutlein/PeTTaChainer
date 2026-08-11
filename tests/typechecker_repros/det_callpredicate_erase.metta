; erase/1 is the cleanup half of the assertz/2 clause-reference API.  Given a
; valid reference it is deterministic, but the generic callPredicate verdict
; currently prevents a deterministic wrapper.
;
; Fails on PeTTa typecheck-v2 418a0c5 in both modes:
;   run.sh det_callpredicate_erase.metta --strict
;   run.sh det_callpredicate_erase.metta --strict --strict-det
;   Determinism check failed for 'erase-one': call(callPredicate)

(: ClauseRef (Newtype Expression))

(: erase-one (-[det]-> ClauseRef Bool))
(= (erase-one $reference)
   (let $_erased
      (callPredicate
         (Predicate (erase $reference)))
      true))
