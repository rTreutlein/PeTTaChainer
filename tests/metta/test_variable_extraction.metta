!(import! &self ../../pettachainer/metta/petta_chainer)

;; Goal sealing depends on source-variable identity and traversal order,
;; including repeated variables inside quoted, nested expressions.
!(test (collapse (extract-vars ())) (()))
!(test (collapse (extract-vars scalar)) (()))
!(test
   (collapse (extract-vars (quote (Outer (Inner value value) ()))))
   (()))
!(test
   (let (cons $found ()) (extract-vars $source)
      (== $found $source))
   true)
!(test
   (let ($first $second $third)
      (extract-vars (quote (Outer $x (Inner $x $y) ())))
      ((== $first $y) (== $second $x) (== $third $x)))
   (true true true))

;; Native closures are opaque source values. Their captured environment may
;; contain variables, but those are not source-expression variables to seal.
!(test
   (let $closure (|-> ($argument) (quote (Captured $capture $argument)))
      ((is-ground $closure) (extract-vars $closure)))
   (false ()))
!(test
   (let $closure (|-> ($argument) (quote (Captured $capture $argument)))
      (let (cons $found ())
         (extract-vars (quote (Outer $source $closure)))
         (== $found $source)))
   true)
