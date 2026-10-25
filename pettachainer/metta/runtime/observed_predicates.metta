;; Observed predicates (docs/metta/observed_predicates.md).
;;
;; A predicate declared observed has a place in time (set-predicate-time) and
;; its statements are observed: once a time point's observations are in, what
;; was not observed did not happen. They are in once a true link fact reaches
;; the time point (set-time-link, (link earlier later)): the client states a
;; time point's observations before the link into it. Then each ground
;; statement of an observed predicate at that time point that a rule concludes
;; (what the
;; knowledge base predicts) and that has no stored fact is stored false, as an
;; ordinary fact named unobserved-<hash>: a rule that predicted it has a
;; negative sample, as an agent that anticipates an event and sees it not come
;; has negative evidence (ONA's anticipation). A fact stated for the time point
;; after the link is not reconciled with the false one: the link closes it.

;; kb -> its observed predicates.
(: &observed (SpaceOf (KB Atom)))
!(bind! &observed (new-space))

(: set-observed-predicate (-[det]-> KB Atom Bool))
(= (set-observed-predicate $kb $head)
   (let* (($_declared (declared-head! $head))
          ($_old (remove-data-rows! &observed (quote ($kb $head))))
          ($_row (add-atom &observed ($kb $head))))
      true))

;; The false facts an added statement closes: for a true link fact, the
;; unobserved statements of the time point it reaches; () otherwise.
(: observed-gaps (-[det]-> KB AnnotatedStatement (List AnnotatedStatement)))
(= (observed-gaps $kb $stmt)
   (case $stmt (
      ((: $_prf ($link $_earlier $later) (STV $s $_c))
         (if (> $s 0.5)
            (if (space-row-present? &hm_link ($kb $link))
               (collapse (let* ((($head $position)
                                   (match &observed ($kb $head)
                                      (match &hm_time ($head $kb $position $_layer) ($head $position))))
                                ($gaps (closed-world-gaps $kb $head $position $later)))
                            (superpose $gaps)))
               ())
            ()))
      ($_other ()))))
