!(import! &self petta_chainer)

; Raven induction with inheritance represented through ordinary implication
; machinery. There is no set-base-rate and no inheritanceInduction rule here.
;
; Direct inheritance observations register rv1 and rv2 as KB subjects. When
; inversion needs the singleton priors for (Inheritance $x rv1) or
; (Inheritance $x rv2), the runtime now supplies a KB-global concept-node
; prior, 1/N over currently registered inheritance endpoint nodes.
; This example mirrors the source libPLN setup, so it intentionally gives that
; synthetic prior high confidence instead of using the open-ended default.
;
; The compiler derives implication views from the direct inheritance
; observations. When modus ponens or inversion needs a full CTV, the compiled
; rule estimates the negative branch from current base rates at calculation time.

!(set-concept-prior-confidence ravenDerivedKb 0.9)

!(compileadd ravenDerivedKb (: rv1RavenObserved (Inheritance rv1 raven) (STV 0.9 0.9)))
!(compileadd ravenDerivedKb (: rv2RavenObserved (Inheritance rv2 raven) (STV 0.9 0.9)))
!(compileadd ravenDerivedKb (: rv1BlackObserved (Inheritance rv1 (IntSet black)) (STV 0.8 0.9)))
!(compileadd ravenDerivedKb (: rv2BlackObserved (Inheritance rv2 (IntSet black)) (STV 0.0 0.9)))

(= (raven-result-tv (: $_proof $_type $tv)) $tv)

!(test
   (let $results
      (collapse
         (query 300 ravenDerivedKb
            (: $prf (Inheritance raven (IntSet black)) $tv)))
      ((length $results) (map-flat raven-result-tv $results)))
   (1 ((STV 0.338977056690164 0.7053110921718064))))
