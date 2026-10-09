# Evidence sets

Every value the chainer computes carries the evidence behind it: the facts,
and the rules with estimated truth, that its proofs use. Merging and premise
selection read it to decide whether two values are independent
(`runtime_design_assumptions.md`, "Truth values are views").

## Representation

A value holds its evidence as one interned set, `(ev-set Id)`, with
`(ev-set 0)` the empty set. The sets live in Prolog (`runtime_helpers.pl`):

- An **entry** (`fact-ev`, `not-fact-ev`, `rule-ev`, `rule-excluded`,
  `not-ev`, or a proof name read off a proof term) is interned once as an
  integer (`ev_entry(Id, Hash, Entry)`, found by its id or its hash).
- A **set** is the list of its entry ids in the order the entries were first
  added (`ev_set(Id, Hash, Ordered, Sorted, Excluded)`), interned by that list, so
  equal evidence has one id and `sk-same-view?` compares ids. `Sorted` holds
  the same ids in order for the set tests; `Excluded` holds the ids of the
  `rule-ev` entries that the set's `rule-excluded` entries name.
- Both id sequences are packed in strings, one character per id. A clause
  stores such a string in about a fifth of the space of an integer list
  (1.2 KB against 5.8 KB for 230 ids), and `string_codes/2` unpacks it in C.
  A character holds at most 1,114,111, so that many entries can be interned;
  one more raises a type error.
- Sets never change. A union is memoized by its operands
  (`ev_union_memo/2`).

The order is kept because two readers depend on it: conditioning picks the
first shared statement in the row's evidence (`sk-clash-on`), and the lifting
merge multiplies the shared facts in the order its intersections leave them.
A union is the first set followed by the second's entries the first lacks,
exactly what `list_to_set(append(A, B))` gave over the former flat lists.

| operation | cost |
|---|---|
| union, memoized | O(1); first time O(\|A\| + \|B\|) over integers |
| overlap, subset | O(\|A\| + \|B\|) merge of sorted integer lists |
| shared facts (`premise-evidence-overlap?`, `sk-clash-on`) | the merge, then one lookup per shared entry |
| excluded rules | O(1) when the set excludes nothing |
| equality | id comparison |

Entries are materialized as terms only where a reader needs them: the shared
facts of a clash or a lifting merge, and the fact leaves the lifting merge
re-evaluates.

## Collection

Replaced views leave sets nothing refers to. `stored-refs-gc!` collects them
together with stored proofs: it walks every `&` space once, marks the proof
references and evidence sets it finds, follows live stored proofs to the
proofs and evidence they hold, and erases the unmarked proofs, sets and
memoized unions. It runs when a dependency collection is due (`query.metta`).
Entries are kept; there is one per fact or rule a proof used.
