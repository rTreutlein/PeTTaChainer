;; Runtime goal identities, truth-value normalization, and expected values.
(: tv-confidence (-[det]-> $truth-value Number))
(= (tv-confidence $tv)
   (if (is-var $tv) 1.0
      (case $tv
         (((STV $_s $c) (if (is-var $c) 1.0 $c))
          ((CTV $pos $neg) (min (tv-confidence $pos) (tv-confidence $neg)))
          ($_other 1.0)))))

(: goal-has-type-vars?
   (-[det]-> (| Goal
          (Statement KBContext Proof TV))
       Bool))
(= (goal-has-type-vars? $goal)
   (case $goal
      (((CPU $fun $args $res)
          (if
             (== (extract-vars (CPU $fun $args $res)) ())
             false true))
       (($type ($_kbid $_ctx $vars) $_prf $_tv)
          (if (== (extract-vars $type) ())
             (if (== $vars Nil) false true)
             true)))))

(: goal-key
   (-[det]-> (| Goal
          (Statement KBContext Proof TV))
       Expression))
(= (goal-key $goal)
   (case $goal
      (((CPU $fun $args $res)
          (sealed
             (extract-vars (CPU $fun $args $res))
             (CPU $fun $args $res)))
       (($type ($kbid $ctx $vars) $_prf $_tv)
          (let $sealed-goal
             (sealed
                (extract-vars (quote ($type $vars)))
                (quote ($type $vars)))
             (quote ($sealed-goal ($kbid $ctx))))))))

(: normalize-expected-stv (-[det]-> $truth-value STVType))
(= (normalize-expected-stv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (case $tv
         (((STV $s $c)
             (STV
                (if (is-var $s) 1.0 $s)
                (if (is-var $c) 1.0 $c)))
          ($other (the STVType $other))))))

;; Re-establish a TV read from untyped storage without first attaching one
;; broad union guard to an open constructor. Dispatching on the runtime tag
;; lets CTV fields receive their precise STV constraints immediately.
(: checked-stored-tv (-[det]-> Atom TV))
(= (checked-stored-tv $tv)
   (if (is-var $tv)
      (the TV $tv)
      (case $tv
         (((STV $s $c)
             (STV $s $c))
          ((CTV $pos $neg)
             (CTV
                $pos
                $neg))
          (no-evidence no-evidence)))))

(: normalize-expected-tv (-[det]-> $truth-value TV))
(= (normalize-expected-tv $tv)
   (if (is-var $tv) (STV 1.0 1.0)
      (case $tv
         (((STV $s $c) (STV (if (is-var $s) 1.0 $s) (if (is-var $c) 1.0 $c)))
          ((CTV $pos $neg)
             (CTV
                (normalize-expected-stv $pos)
                (normalize-expected-stv $neg)))
          (no-evidence no-evidence)
          ($other (the TV $other))))))

(: normalize-expected-ctv
   (-[semidet]-> $truth-value CTVType))
(= (normalize-expected-ctv
      (CTV $pos $neg))
   (CTV
      (normalize-expected-stv $pos)
      (normalize-expected-stv $neg)))

(: normalize-expected-evidence-tv
   (-[semidet]-> $truth-value (| STVType CTVType)))
(= (normalize-expected-evidence-tv $tv)
   (if (is-var $tv)
      (STV 1.0 1.0)
      (case $tv
         (((STV $s $c)
             (STV
                (if (is-var $s) 1.0 $s)
                (if (is-var $c) 1.0 $c)))
          ((CTV $pos $neg)
             (CTV
                (normalize-expected-stv $pos)
                (normalize-expected-stv $neg)))
          ($_other (empty))))))

;; CPU arguments are formula-dependent and enter through a generic execution
;; record. Normalize known TV constructors without reflective checks; retain
;; an explicit checked fallback for invalid or user-extended TV values.
(: expected-tv (-[det]-> $candidate TV))
(= (expected-tv $value) (normalize-expected-tv $value))

;; Expected TVs dispatch directly on the known formula set instead of going
;; through reduce: reduce's runtime dispatch (fun/1 + current_predicate +
;; current_op per call) dominated backward-search profiles. Failure modes are
;; preserved -- a formula clause that does not match (or yields empty) makes
;; this function fail exactly like the reduce-based call did.
(: cpu-expected-tv
   (-[nondet]-> $formula $arguments  (| TV (List Atom))))
(= (cpu-expected-tv $fun ($a))
   (if (== $fun NotFormula)
      (if (is-var $a)
         (STV 1.0 1.0)
         (NotFormula (normalize-expected-stv $a)))
      ()))

(= (cpu-expected-tv $fun ($a $b))
   (case $fun
      ((CTVModusPonensFormula
         (CTVModusPonensFormula
            (normalize-expected-evidence-tv $a)
            (normalize-expected-ctv $b)))
       (CTVFormula
         (CTVFormula
            (normalize-expected-evidence-tv $a)
            (normalize-expected-ctv $b)))
       (AndFormula
         (AndFormula
            (normalize-expected-stv $a)
            (normalize-expected-stv $b)))
       (OrFormula
         (OrFormula
            (normalize-expected-stv $a)
            (normalize-expected-stv $b)))
       (LikelierThanFormula
         (LikelierThanFormula
            (normalize-expected-stv $a)
            (normalize-expected-stv $b)))
       (()
         (cons ()
            (cons (expected-tv $a)
               (cons (expected-tv $b) ()))))
       ($_other ()))))

(= (cpu-expected-tv $fun ($a $b $ctv))
   (if (== $fun CTVInversionFormula)
      (let*
         (($na (expected-tv $a))
          ($nb (expected-tv $b))
          ($nctv (expected-tv $ctv))
          ($confidence
             (* (min-atom
                  ((tv-confidence $na)
                   (tv-confidence $nb)
                   (tv-confidence $nctv)))
                0.9)))
         (if (or (is-var $a) (is-var $b))
            (CTV (STV 1.0 $confidence) (STV 1.0 $confidence))
            (CTVInversionFormula $na $nb $nctv)))
      ()))

(: first-cpu-expected-tv
   (-[det]-> $formula $arguments (| TV (List Atom))))
(= (first-cpu-expected-tv $fun $args)
   (let $res (let $hits (collapse (cpu-expected-tv $fun $args)) (if (== $hits ()) () (car-atom $hits)))
      $res))

(: cpu-expected-confidence (-[det]-> $formula $arguments Number))
(= (cpu-expected-confidence $fun $args)
   (let $res (first-cpu-expected-tv $fun $args)
      (if (== $res ()) 1.0 (tv-confidence $res))))
