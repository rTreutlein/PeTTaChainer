;; Runtime goal identities, truth-value normalization, and expected values.
(: tv-confidence (-[det]-> $truth-value Number))
(= (tv-confidence $tv)
   (if (is-var $tv) 1.0
      (case $tv
         (((STV $_s $c) (if (is-var $c) 1.0 $c))
          ((CTV $pos $neg) (min (tv-confidence $pos) (tv-confidence $neg)))
          ($_other 1.0)))))

(: normalize-expected-stv (-[det]-> $truth-value STVType))
(= (normalize-expected-stv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (case $tv
         (((STV $s $c) (STV (if (is-var $s) 1.0 $s) (if (is-var $c) 1.0 $c)))
          ($other (the STVType $other))))))

;; Re-establish a TV read from untyped storage without first attaching one
;; broad union guard to an open constructor. Dispatching on the runtime tag
;; lets CTV fields receive their precise STV constraints immediately.
(: checked-stored-tv (-[det]-> Atom TV))
(= (checked-stored-tv $tv)
   (if (is-var $tv)
      (the TV $tv)
      (case $tv
         (((STV $s $c) (STV $s $c))
          ((CTV $pos $neg) (CTV $pos $neg))
          ((likelihood-read $_raw $read $_support) (expected-tv $read))
          (no-evidence no-evidence)
          ($other (the TV $other))))))

(: normalize-expected-ctv (-[semidet]-> $truth-value CTVType))
(= (normalize-expected-ctv (CTV $pos $neg))
   (CTV (normalize-expected-stv $pos) (normalize-expected-stv $neg)))

(: normalize-expected-evidence-tv (-[semidet]-> $truth-value (| STVType CTVType)))
(= (normalize-expected-evidence-tv $tv)
   (if (is-var $tv)
      (STV 1.0 1.0)
      (case $tv
         (((STV $_s $_c) (normalize-expected-stv $tv))
          ((CTV $_pos $_neg) (normalize-expected-ctv $tv))
          ($_other (empty))))))

;; CPU arguments are formula-dependent and enter through a generic execution
;; record. Normalize known TV constructors without reflective checks; retain
;; an explicit checked fallback for invalid or user-extended TV values.
(: expected-tv (-[det]-> $candidate TV))
(= (expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (case $tv
         (((STV $_s $_c) (normalize-expected-stv $tv))
          ((CTV $pos $neg) (CTV (normalize-expected-stv $pos) (normalize-expected-stv $neg)))
          ((likelihood-read $_raw $read $_support) (expected-tv $read))
          (no-evidence no-evidence)
          ($other (the TV $other))))))

;; Expected TVs dispatch directly on the known formula set, which is faster
;; than reduce; a formula clause that does not match makes this fail.
(: normalize-expected-likelihoods (-[semidet]-> $candidate LikelihoodRead))
(= (normalize-expected-likelihoods $candidate)
   (if (is-var $candidate)
      (likelihood-read (CTV (STV 1 1) (STV 1 1)) (CTV (STV 1 1) (STV 1 1)) unknown-support)
      (case $candidate (
         ((likelihood-read $raw $read $support)
            (likelihood-read (normalize-expected-ctv $raw) (normalize-expected-ctv $read) $support))))))
