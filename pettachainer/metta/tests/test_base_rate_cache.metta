!(import! &self petta_chainer)

!(compileadd brKb (: r (Implication (Premises (P $x)) (Conclusions (Q $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd brKb (: qa (Q alice) (STV 0.9 0.8)))

!(compileadd brKb (: pb (P bob) (STV 0.7 0.8)))

; First query computes the base rates by folding over all instances and
; harvests them into the cache afterwards.
!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with (foldall-proof pb) (foldall-proof qa (r pb))) qa) (P alice) (STV 0.736162240263287 0.0003604307138536469)))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.6999999999999998 0.0009990009990009992))

; Second query answers from the cached base rates: the inverted proof keeps
; its modus ponens TV but the base-rate premises are cache hits (cpu tokens,
; no fold expansion).
!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.736162240263287 0.0003604307138536469)))

; User-provided base rates override the cache and feed inversion directly.
!(set-base-rate brKb (P $x) (STV 0.5 0.5))
!(set-base-rate brKb (Q $x) (STV 0.9 0.5))

!(test
   (query 200 brKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu cpu) qa) (P alice) (STV 0.5 0.569301064166628)))

; Adding a fact invalidates computed entries but keeps user-provided ones.
!(compileadd brKb (: pc (P carol) (STV 0.3 0.8)))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.5 0.5))

!(clear-base-rate brKb (P $x))
!(clear-base-rate brKb (Q $x))

!(test
   (let $cached (cached-base-rate brKb (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   no-cache-entry)

; Public inheritance priors are mirrored to the compiler's private evidence
; pattern, including when Inheritance is nested beside a shared variable.
!(set-base-rate inheritanceAliasKb
   (And (Inheritance $x madeOfPlastic) (Operation $x opLighter))
   (STV 0.25 0.9))

!(test
   (cached-base-rate inheritanceAliasKb
      (And (inheritance-evidence $x madeOfPlastic) (Operation $x opLighter)))
   ((STV 0.25 0.9)))

!(clear-base-rate inheritanceAliasKb
   (And (Inheritance $x madeOfPlastic) (Operation $x opLighter)))

!(test
   (cached-base-rate inheritanceAliasKb
      (And (inheritance-evidence $x madeOfPlastic) (Operation $x opLighter)))
   ())

; --- Refinement of computed cache entries ---

!(compileadd brKb2 (: r (Implication (Premises (P $x)) (Conclusions (Q $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd brKb2 (: qa (Q alice) (STV 0.9 0.8)))

!(compileadd brKb2 (: pb (P bob) (STV 0.7 0.8)))

; A weak computed entry gets refined: the refold has higher confidence, so the
; snapshot replaces the cached value, the conclusion uses the refined base
; rate, and the harvest writes the refined value back to the cache.
!(store-computed-base-rate! brKb2 (P $x) (STV 0.2 0.0001) base-rate)

!(test
   (query 200 brKb2 (: $prf (P alice) $tv))
   (: ((inverted r with (foldall-proof pb) (foldall-proof qa (r pb))) qa) (P alice) (STV 0.736162240263287 0.0003604307138536469)))

!(test
   (let $cached (cached-base-rate brKb2 (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.6999999999999998 0.0009990009990009992))

; A high-confidence computed entry is protected: the refold's confidence is
; lower, so the cached estimate survives refinement and feeds the conclusion.
!(compileadd brKb3 (: r (Implication (Premises (P $x)) (Conclusions (Q $x))) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd brKb3 (: qa (Q alice) (STV 0.9 0.8)))

!(compileadd brKb3 (: pb (P bob) (STV 0.7 0.8)))

!(store-computed-base-rate! brKb3 (P $x) (STV 0.5 0.9) base-rate)

!(test
   (query 200 brKb3 (: $prf (P alice) $tv))
   (: ((inverted r with cpu (foldall-proof qa (r pb))) qa) (P alice) (STV 0.5258301716166336 0.008091509912253481)))

!(test
   (let $cached (cached-base-rate brKb3 (P $x))
      (if (== $cached ()) no-cache-entry (car-atom $cached)))
   (STV 0.5 0.9))
