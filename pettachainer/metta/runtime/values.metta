;; Runtime goal identities, truth-value normalization, and expected values.
(: tv-confidence (-[det]-> $truth-value Number))
(= (tv-confidence $tv)
   (if (is-var $tv) 1.0
      (case $tv
         (((STV $_s $c) (if (is-var $c) 1.0 $c))
          ((CTV $pos $neg) (min (tv-confidence $pos) (tv-confidence $neg)))
          ($_other 1.0)))))

;; A lookup column is hashed with every variable replaced by one marker
;; (imported Prolog helper index-hash): the integer lets SWI build a JIT hash
;; index on the space, while the complete key stored beside it lets =alpha
;; reject collisions and distinguish variable-sharing patterns.
;; The hashes of a statement's prefixes, its head with its first one, two, ...
;; arguments, up to the first argument that is not ground, longest first
;; (imported Prolog helper statement-prefix-hashes; see &kb_prefix).
(: statement-prefix-hashes (-[det]-> $statement (List Number)))
;; The hash a statement with variables is stored under, and the hashes a
;; pattern with a ground prefix reads such statements by besides its longest
;; prefix (imported Prolog helpers; see &kb_open).
(: statement-open-hash (-[det]-> $statement Number))
(: statement-open-probes (-[det]-> $statement (List Number)))

;; Fact lookup extends these prefixes through an implication antecedent's
;; nested heads, keeping source templates selective without changing node keys.
(: kb-fact-prefix-hashes (-[det]-> $statement (List Number)))
(: kb-fact-open-hash (-[det]-> $statement Number))
(: kb-fact-open-probes (-[det]-> $statement (List Number)))

(: append-flat (-[det]-> (List $a) (List $a) (List $a)))
(= (append-flat () $right) $right)
(= (append-flat (cons $head $tail) $right) (cons $head (append-flat $tail $right)))

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
          ((CTV $pos $neg)
             (CTV
                (normalize-expected-stv $pos)
                (normalize-expected-stv $neg)))
          (no-evidence no-evidence)
          ($other (the TV $other))))))

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
       (ImplicationModusPonensFormula
         (ImplicationModusPonensFormula
            (normalize-expected-evidence-tv $a)
            (normalize-expected-ctv $b)))
       (CTVFormula
         (CTVFormula
            (normalize-expected-evidence-tv $a)
            (normalize-expected-ctv $b)))
       ;; An open prior read as certain would leave P(A|not B) undefined, so
       ;; the inversion is expected at its rule's confidence, discounted as
       ;; CTVInversionFormula's is.
       (CTVBayesFormula
         (if (is-var $a)
            (let $confidence (* 0.9 (tv-confidence (expected-tv $b)))
               (CTV (STV 1.0 $confidence) (STV 1.0 $confidence)))
            (CTVBayesFormula
               (normalize-expected-evidence-tv $a)
               (normalize-expected-ctv $b))))
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
   (let $hits (collapse (cpu-expected-tv $fun $args))
      (if (== $hits ()) () (car-atom $hits))))

(: cpu-expected-confidence (-[det]-> $formula $arguments Number))
(= (cpu-expected-confidence $fun $args)
   (let $res (first-cpu-expected-tv $fun $args)
      (if (== $res ()) 1.0 (tv-confidence $res))))
