# Facts that arrive after the search

Status: built, October 2026. Branch `value-scheduling`.

## Problem

SupplyNet stage "scale" (ChainerGame `docs/supply_network.md`) asks, every
round, for the fronts, storms and blocks of the new period and again for the
fronts and storms of the oldest unresolved one. A period's late shipments
arrive one to three rounds after it, three inversions below its storm
(`Storm → Blocked → Delayed → Late`). At size m, seed 1, one step per query
(master 0b2f637c), 117 of 135 re-asked fronts and storms came back unchanged,
and more budget did not help until 16 steps per query.

Instrumented per round (expansions by predicate and by the age of the period
they belong to):

- **No expansion ever returns to a past period.** At 1, 2 and 4 steps per
  query every expansion of rounds 2 to 10 is in the new period: its 51 roots,
  then its `Delayed` nodes (9 of 108 at 1 step, 81 at 2, all at 4), then its
  `Alarm` nodes and, at 4 and 8 steps, its `Late` nodes. A past `Delayed` node
  scores as its current sibling did, one level deeper below a past root, so it
  never wins.
- **A fact reached only expanded nodes.** Activation read a new fact into the
  nodes of `&sk_node_terms`, the expanded ones. A join waiting on an
  unexpanded ground premise read the premise's facts once, when it started
  waiting. So a `Delayed` node expanded in its own round, before its
  shipments arrived, waited on `(Late s t)` forever: at 4 steps per query all
  108 `Delayed` nodes of every period were expanded and the past storms were
  still 0.07 off (master's `Storm_past` error, m seed 1). 8 and 16 steps
  improved only because they expanded the current period's `Late` nodes,
  which have no fact yet, and that expansion registered them for later
  activation. That work (the inverted `late` row of each shipment, built and
  evaluated against its own parent) is what made 16 steps cost 10–20 times
  1 step and 5–10 GB.
- **Deliveries waited for a walk.** Activation ran before the walk and its
  deliveries were parked with their node until a walk passed it, so even a
  fact that reached a waiting join was read only if a later query walked
  there.

So the answer to "is the new evidence reachable within the budget" was no at
any budget below 16 steps; the 3-inversion depth mattered only because
nothing but expansion could bring a fact in.

## Rule

Stored facts cost no expansion, however late they arrive. A fact stored
after the search is read before the next query's walk by

1. every node that reads its key: the expanded nodes it matches, as before,
   and the ground premises joins wait on, expanded or not; and
2. through each rule it is a premise of, each node the skeleton holds,
   unexpanded, for that rule's conclusion: that rule alone is started there,
   as expanding the node would start it (`sk-absorb-step`). The node stays
   unexpanded; a later expansion starts its other rules, and the join already
   built is found again by its row identity.

A missing ground fact is pending input, not an impossible premise. Even
when no rule concludes it, expansion retains the ordinary join waiting on
it. Pruning that join before registration left an And-consequent node
expanded without its statement rule or its input waiter: later facts could
not reach the projections reading that node (tracker #44). Only ground
computations that cannot succeed are prefiltered; missing facts use the
same indexed delivery path as other premises, without re-expansion.
A population fold over a mixed connective, such as metadata conjoined with
an implication, also keeps its exact compilation shape. Treating the whole
connective as a user predicate can abstract a child into a variable, bind
it to `CPU` during compilation, and fail the query after marking the fold
expanded. Its temporary sample waiter then has no rule definition when a
later fact tries to extend it, interrupting delivery to the projections.

The rules a ground key is a premise of are found by hashing the key's
statement prefixes (`&prem_prefix`, one row per premise under its longest
ground prefix, within its KB), so the lookup costs a few hashes per fact,
not a walk over every premise with the fact's head. Premises with a variable
head are not indexed there; their facts arrive through expansion.

Before a query's walk, new facts are activated against the nodes that were
there before (a root new to the skeleton still starts from its population
prior, as `test_anytime_roots` expects), then the query's roots are
registered and new rules activated, since a query's own rules build its
roots' rows (`test_foldall_query_goal`). The answers are delivered at once
from an allowance of their own, ten rows per new fact and per step of the
query (`execute-backward`). Reading new evidence is the deferred cost of
storing it, so it must not take the rows the query's own search needs:
giving it the query's allowance starved the search at the round where a
period resolves (159 labels at once, m): 81 joins of the new roots were
deferred and the current fronts fell to their priors. Ten rows per fact
alone was too little where one fact refolds an implication instance fold
(`test_implication_instance_fold`); the per-step share covers that, and the
allowance still bounds what new facts set off through recursive rules. What
it does not cover is delivered from the query's allowance.

A row never computed is not forced by an outside change (`sk-force!`): its
first view changes its key whatever caused it. Forcing such rows only
multiplied per-cause records (73,483 in one round at m, 4 steps per query,
against 8,334 without).

## What was tried and dropped

- **A certain statement expanded without a step.** Expansion applies no
  rule to it, so it only reads facts its readers already read. It freed the
  36 `Alarm` steps per round at m and helped there before absorption, but
  with absorption it made no difference at m, was worse at s (0.050 against
  0.028 at 1 step per query) and changed StationOps replay seed 3 (budget 50:
  Brier 0.0663 → 0.0694, one module's leak belief losing a certain proof from
  shift 16 on), through the order the freed steps took.
- **Priority for nodes with unread evidence.** Absorption reads the evidence
  without any step, so a priority would only matter for evidence below nodes
  the skeleton does not hold yet (at size l, `tiers` 3, the second level of
  depots). Not built.

## Results

SupplyNet scale grid (sizes s, m, l: seeds 1–2; xl: seed 1, at most 8 steps
per query), master d4f390d2 against this branch; error to the exact
posterior, ms per query, peak MB. Raw JSON:
`bench/results/supplynet_scale/grid_{d4f390d2,vs12}.json`.

| size | steps/query | error | ms/query | peak MB |
|---|---|---|---|---|
| s | 1 / 4 / 16 | 0.080 → 0.068 / 0.058 → 0.040 / 0.034 → 0.027 | 7 → 15 / 55 → 50 / 173 → 129 | 204 → 220 / 243 → 299 / 572 → 556 |
| m | 1 / 4 / 16 | 0.022 → 0.013 / 0.021 → 0.012 / 0.009 → 0.005 | 12 → 39 / 37 → 97 / 375 → 355 | 332 → 853 / 762 → 1785 / 4589 → 5583 |
| l | 1 / 4 / 16 | 0.069 → 0.066 / 0.062 → 0.048 / 0.027 → 0.015 | 13 → 18 / 32 → 76 / 305 → 313 | 641 → 889 / 1218 → 2434 / 5468 → 9318 |
| xl | 1 / 4 / 8 | 0.039 → 0.038 / 0.036 → 0.017 / 0.036 → 0.013 | 20 → 31 / 43 → 160 / 100 → 273 | 1164 → 1892 / 2333 → 8384 / 4850 → 12111 |

The past storms and fronts now follow their late evidence (m, seed 1, one
step per query: 102 of 135 re-asked answers unchanged before, 8 after; past
storm error 0.078 → 0.005). The curves no longer stay flat from 1 to 8 steps
per query. Per query, each step costs more, because absorbed evidence makes
more rows change and every view carries its evidence as a list: memory grows
with the evidence absorbed (views, latest views and merged values of 15–40 KB
each at m) and with the 8 KB mask of every interned dependency node.

Below one step per query, where some roots are never expanded, which roots
the budget reaches changes (absorbed rows make roots look started), and roots
whose population rate is 0 or 1 lose their only answer: s and l at 0.25 and
0.5 steps are slightly worse (l 0.5: 0.151 → 0.161).

StationOps replay (seeds 1–4, budgets 25 and 50): belief streams identical
except seed 3 budget 25 (14 beliefs, Brier 0.0657 → 0.0649) and seed 4
budget 25 (1 belief); time within 3%.
