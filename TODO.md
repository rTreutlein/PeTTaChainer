# TODO

- Add an additive merge mode for complementary evidence sets. In cases like `Dog -> Animal` and `Not Dog -> Animal`, the two proofs are split parts of one conditional formula, not independent estimates. If one proof uses `(fact-ev ... d (Dog))` and the other uses `(not-fact-ev ... d (Dog))`, combine the MP-produced strengths additively instead of using `merge/revision` averaging. Also decide how zero-confidence branches should be scheduled once this merge mode exists.

- Decide whether to enable the merge absorption shortcut in `merge-proof-atoms`. The original code had `(if $proof-a (and (= $prfa (merge/revision ...)) (proof-tree-contains $prfa $prfb)) ...)` with condition and value swapped, so the "if one proof's merge/revision tree already contains the other, return it unchanged" shortcut never fired (PeTTa's `if` sends non-boolean conditions to the else branch). The dead branches and the orphaned `proof-tree-contains` helpers were removed; enabling the shortcut properly would change merge results and needs its own evaluation.

- Fix bare single-variable premises in implication queries. `lower-source-premise` unwraps a single-var-element premise `($x)` to the bare var `$x`, which breaks the assumed-premise pipeline: `(query ... (Implication (Premises ($x)) (Conclusions (B))) ...)` returns nothing. Named patterns like `(Feature $x)` work fine. Either support the bare form or reject it explicitly.

- Decide whether merged forward facts should re-trigger rules. `forward-fact-upsert` pushes a fact onto the forward agenda only when it is new; when an existing fact is revision-merged to a different TV the update never propagates to rules within that run, making forward chaining sensitive to evidence arrival order.
