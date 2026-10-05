# Answers by index

Status: built, October 2026.

## Problem

A node's answers are the keys its own search finds:
- facts read at expansion or when a join waits on a ground premise;
- the conclusions of rows its own rules complete (`sk-complete-row!` →
  `sk-add-answer!`).

A key registered by another node's search does not reach it. The node gets
the key only if its own rules derive it again, which costs search budget.
So what a node sees depends on search order, not on what the chainer knows.

Two cases were traced on StationOps (replayed, 8 seeds, 10 modules, 20
shifts). Both differ between head and dormant rules only because dormancy
changes the search order.

**Fold membership.** A fold's members are the answers of its member node,
the open pattern's compiled goal. Seed 1, shift 2: the key
`SealLeak new ore-feed-pump shift-01-M10` exists under both, but only head's
member node has it. It got there through the inversion of
`patchGoal-new-ore-feed-pump`, a rule whose row derives nothing
(self-support) and is dormant under dormancy. The base rate counts four
instances under dormancy and five under head.

**A ground node's own key.** Seed 5, shift 3, module M05: the root
`SealLeak old ore-feed-pump shift-03-M05` has a row of rule 86, the alarm
inversion with the instance's temporal prior `LeakPredicted`, under head
(belief 1.0) and none under dormancy (belief 0.37).
- Under dormancy, rule 86's join waits on the ground node
  `(LeakPredicted old ore-feed-pump shift-03-M05) ctx $p $tv`. The node is
  expanded but has no answer.
- The key exists with a value, as the answer of another node: the same
  statement with the proof pattern `(by persist-…)`.
- The node's own rules did not derive the key again before the search
  budget ran out.

The base-rate difference turned out not to matter for quality (membership
alone left Brier unchanged), but it showed the shape of the defect. The
ground-node case is what moved beliefs.

## Rule

- A **ground node** reading any proof and value has exactly one possible
  answer, its own key. It is answered by the key as soon as the key exists,
  whichever search registered it.
- A **fold's member node** is answered by every registered ground key
  unifying with it, whichever search registered the key. A fold over a
  pattern counts the pattern's known instances.
- **Any other open node** is answered by its own search, as before. Feeding
  it every matching key lets a root's join (roots always proceed) recurse
  through its own conclusions without a budget. The first, unrestricted
  version did exactly this: the recursive `timeAndRule` test and
  `flyingraven` overflowed the stack.
- A node with a proof or value pattern, such as `(by persist-…)`, is a
  filter over proofs. A key says nothing about which proof produced it, so
  such a node is answered by its own search, as before.

## Mechanism

- **`&sk_node_prefix (prefix type kbctx node-hash node)`.** It holds ground
  nodes and fold member nodes that read any proof and value. Each sits under
  the hash of its statement's longest ground prefix, or of the head when the
  statement has none, as `kb-facts` and `&sk_key_prefix` index facts and
  keys. The lookup columns are copies, so a match leaves the node open.
- **A node is indexed when it joins the skeleton** (`sk-add-child!`), and a
  root when its query starts (`sk-root-score-step`). A fold's member node
  qualifies once its `&sk_member_of` row exists, which `sk-expand!` writes
  before linking the child. Indexing takes the registered ground keys that
  unify with the node (`sk-unifying-key-hashes`) as answers.
- **A new ground key** (`sk-register-key!`) looks itself up under the hash
  of each prefix of its statement and of its head, and answers every node it
  unifies with through `sk-add-answer!`. That is the same path a key found
  by the node's own search takes: the answer row, fold membership
  (`sk-member-step`), and a delivery queued for the node's waiters, drained
  and parked as any other.

The cost per new key is one indexed lookup per prefix of its statement. It
is bounded by the statement's arity and the nodes sharing a prefix, not by
the size of the KB.

## What does not change

- Search, budgets and joins are unchanged.
- Self-support exclusion is unchanged; a fold's take still reads members
  without values derived through it.
- Forgetting is unchanged: a buried key leaves the answers of open nodes
  and `&sk_keys`.

## Correctness

A ground node asks for the value of one statement. When the chainer holds a
key for that statement, the key is the answer, however it was found. A fold
over a pattern counts the pattern's known instances. Both answers become
properties of what the chainer knows, not of the order its search ran in.
Open nodes stay bounded by search, which is what keeps recursive rules
finite.

## Evaluation

- **Unit tests** (`tests/metta/test_answers_by_index.metta`):
  - a key registered later answers a fold's member node;
  - a member node set up later takes a key registered before it;
  - a root's join over a ground premise completes from the premise's key
    registered by another search, with one search step that expands only
    the root. On the old code no row is made.
- **The traced incident** (seed 5, shift 3, M05) under dormancy: rule 86's
  row now exists, and the belief is 1.0 as under head.
- **Replayed grid** for head and dormancy, judged by the quality-vs-compute
  frontier: see Result.

## Result

Replayed StationOps, 8 seeds, 10 modules, 20 shifts. Each cell is Brier,
then compute per seed (forward + query):

| | head | head + index | dormancy | dormancy + index |
|---|---|---|---|---|
| f 2, q 300 | 0.0591 (20.3 s) | 0.0591 (24.7 s) | 0.0600 (18.5 s) | 0.0600 (29.1 s) |
| f 0.5, q 300 | 0.0607 (24.1 s) | 0.0597 (19.4 s) | 0.0655 (14.5 s) | 0.0603 (18.1 s) |
| f 0.5, q 200 | 0.0615 (13.6 s) | 0.0600 (16.3 s) | 0.0728 (11.9 s) | 0.0610 (15.3 s) |

- **Dormancy gap closed at low forward:** f 0.5 cells drop from 0.073 to
  0.061 and from 0.066 to 0.060.
- **Head improves too:** f 0.5, q 300 goes from 0.0607 to 0.0597.
- **Cost rises in some cells:** dormancy at f 2, q 300 goes from 18.5 s to
  29.1 s. Nodes now receive answers they did not search for, and their
  joins proceed.

The rest of the grid has not run yet. The run stopped when the machine
crashed.
