# Fold membership by index

Status: design, October 2026.

## Problem

A fold over a pattern has one member node: the pattern's compiled goal, an
open node (`sk-fold-member`, `sk-expand!`). The fold's members are that
node's answers. A key becomes an answer of the member node only when:

- a stored fact matches it at expansion, or
- one of the node's own rules completes a row concluding it
  (`sk-complete-row!` → `sk-add-answer!`).

A key that a different node's search derived does not reach the member node.
That includes another query's ground node for the same instance. It reaches
the node only if the member node's own joins happen to enumerate it as well.
Those joins are paid from the row budget, their deliveries are parked when
the budget runs out, and parked deliveries resume only when a later walk
reaches the node.

So what a fold counts depends on which rules the member node runs and how
the search spent its budget, not on what the chainer knows.

Traced on StationOps (seed 1, shift 2, replayed):
- The key `SealLeak new ore-feed-pump shift-01-M10` exists under head and
  under dormant rules.
- Under head the member node `(SealLeak new ore-feed-pump $u)` has it as an
  answer. It got there through rule 15, the inversion of
  `patchGoal-new-ore-feed-pump`, whose join over `PatchPaysOff` instances
  enumerated it. That rule's row yields nothing: its premise depends on the
  conclusion, so self-support excludes it. It is dormant under dormant rules.
- With rule 15 dormant, the member node's remaining rule (the alarm
  inversion, rule 87) has not enumerated shift-01 by the end of shift 2. The
  base rate `SealLeak new ore-feed-pump` therefore counts h-0000..0003 under
  dormancy and h-0000..0003 plus shift-01 under head: (0.389, 0.444)
  against (0.350, 0.500).

A rule that derives nothing was doing the enumeration. Refreshing member
values cannot fix this (`base_rate_refresh.md`): the member is not missing
a value, it is missing from the fold.

## Rule

A fold's members are the registered keys that unify with its member
pattern, whichever search registered them. Membership is a property of the
key, found through an index: one bookkeeping step per key, independent of
search budget. What the search budget buys is values, never membership.

## Mechanism

- **Index of member nodes.** When `sk-expand!` sets up a fold's member node
  (the `&sk_member_of` row), it also records the node's term in
  `&sk_member_terms (prefix type kbctx node-hash node)`.
  - `prefix` is the hash of the pattern's longest ground prefix, as
    `kb-facts` and `&sk_key_prefix` use, or 0 for a pattern with none.
  - The lookup columns are copies, as in `&sk_reader_terms`, so a match
    leaves the stored node open.
- **New key.** `sk-register-key!` already runs once per new key. For a
  ground key it looks up `&sk_member_terms` under each of the key's prefix
  hashes (`statement-prefix-hashes`) and under 0. For each node the key
  unifies with, it calls `sk-add-answer!` on that node, which records the
  answer, joins the key to every fold over the node (`sk-member-step`) and
  queues the delivery to the node's waiters. That is the same path a key
  found by the node's own search takes, so nothing downstream changes.
- **New member node.** A member node set up after keys exist takes the
  registered keys that unify with it (`sk-unifying-key-hashes`, the existing
  prefix index) as answers, the same way.

The cost per new key is one indexed lookup per prefix of its statement. It
is bounded by the statement's arity and the number of fold patterns sharing
a prefix, not by the size of the KB or of the population.

A key joining a fold before it has a value is harmless:
- a base rate takes it when it has one (`sk-rate-take-step` leaves out a
  key without a value);
- a computed fold reads its members' views.

When the key's value arrives or changes, the existing `&sk_use` edge marks
the fold dirty as it does today.

## What does not change

- Search, budgets and joins are unchanged. A delivery to the member node's
  waiters is drained, parked and resumed as any other.
- Self-support exclusion is unchanged. A member whose value depends on the
  rate is filtered at the take (`sk-rate-take-step`), as today.
- Forgetting is unchanged. A buried key leaves its `&sk_keys` registration
  and the open nodes' answers (`sk-bury!`). It joins again only if a search
  registers it again.

## Correctness

A fold over a pattern means the fold over the pattern's instances. A
registered key that unifies with the pattern is such an instance, whatever
derived it. Counting it is what the fold means. Not counting it is the
budget-dependent omission described above.

Membership still depends on which keys exist: the chainer only knows the
instances some search or fact created. That is laziness, which is wanted.
Membership no longer depends on which node created them, which is not
wanted.

## Evaluation

- **Unit test:** a key derived only by a ground query joins a base rate over
  its pattern that was read before. The rate reflects it at the next query
  without the member node's search reaching it. A member node created
  later takes existing keys.
- **Rate agreement:** dump the base-rate cache per shift (seed 1, 8 shifts)
  under head and under dormancy, both with membership by index. The rates
  should agree far more closely than today's differences of up to 0.07.
  They need not agree exactly, since the two still register different keys.
- **Replayed grid:** the same settings as grid48/49 for head and dormancy
  with membership by index, judged by the quality-vs-compute frontier.
  Success:
  - dormancy's plateau reaches head's;
  - the f 0.5, q ≥ 200 cells recover;
  - the bookkeeping does not cost visible compute.
