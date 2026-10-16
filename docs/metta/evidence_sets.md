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

Replaced views leave sets nothing refers to. They are collected together
with stored proofs, in cycles spread over queries (`runtime_helpers.pl`). A
cycle marks what the stores reached when it started: it scans the columns of
the spaces that hold proof references or evidence sets (`refs_holder`; a fact
in `&kb` with a referenced proof is also held by `&sk_forward_stored` or
`&materialized_facts`), follows each marked proof to the proofs and evidence
it holds, and then erases the unmarked proofs, memoized unions and sets that
existed when it started; unions go before sets, since a union kept while its
result is gone would hand the erased set to a later query. What was created since is kept. While it marks, a
holder row that is removed is scanned as it goes (`prolog_listen`), and until
it ends, an interned set found again by its entries or a memoized union is
marked, so nothing reachable at the start is lost. A stored proof is found
only through references, so one nothing reached cannot be reached again.

Every query ends with one slice (`stored-refs-gc-step!`). A cycle starts
when either new proof count or new proof words exceeds what the previous
cycle kept plus the holder rows it scanned (at least 4096). Large exact-fold
proofs therefore pay for collection before thousands of them accumulate.
Proof size is charged once when the proof is stored and measured for the
proofs the marker already follows; no store scan is added to the due check.
A slice allows 512 units plus 8 per new proof, retired rule, and 32 new proof
words since the preceding slice. Units remain holder rows scanned, marked
proofs followed, and stored records swept. Kept-size accounting includes
proofs born during the cycle, preserving the existing birth and removal
barriers. `stored-refs-gc!` collects everything nothing reaches at once.
Evidence entries are kept; there is one per fact or rule a proof used.

Where the memory of a run goes, stores against Prolog stacks, and the second
round of representation changes after this one:
[memory_census_2026-10-09.md](memory_census_2026-10-09.md).
