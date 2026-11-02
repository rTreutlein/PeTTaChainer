;; Signatures of the support natives (lib/*.pl).
(: declare-natives! (-[det]-> Atom Atom Bool))

;; SWI heap values are opaque Prolog terms. The parameter tracks their payload
;; type, while heap_pop adapts get_from_heap/4 to PeTTa's single output.
!(use-module! heaps)
!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))
!(assertzPredicate (Predicate (arity empty_heap 1)))
!(assertzPredicate (Predicate (arity add_to_heap 4)))
!(assertzPredicate (Predicate (arity get_from_heap 4)))
!(assertzPredicate (Predicate (arity heap_size 2)))
(: Heap (Foreign 1))
(: empty_heap (-[det]-> (Heap $item)))
(: add_to_heap (-[det]-> (Heap $item) Number $item (Heap $item)))

;; Builtin result types PeTTa leaves open.
(: sort-atom (-[det]-> (List $item) (List $item)))
(: current-time (-[det]-> Number))

!(declare-natives! -[det]-> (
   (heap-empty? (Heap $item) Bool)
   (hash-set (List Number) (List Number))
   (hash-union (List Number) (List Number) (List Number))
   (hash-subset? (List Number) (List Number) Bool)
   (hash-intersection (List Number) (List Number) (List Number))
   (alpha_unique_keys (List $item) (List $item))
   ;; KL divergence of Beta(a1, b1) from Beta(a2, b2).
   (beta_kl Number Number Number Number Number)))

!(declare-natives! -[semidet]-> (
   (heap_pop (Heap $item) (Number $item (Heap $item)))
   (finally (-[nondet]-> Atom $result) (-[nondet]-> Atom Atom) $result)))
