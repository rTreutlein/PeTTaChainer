# Queries under assumptions

Status: built except cleanup, October 2026. The context is not yet removed at
the query's end (see Cleanup).

## Problem

A client often asks a question that holds only together with some facts: a
StationOps decision step reads the current leak beliefs together with the
step's candidates, costs and eligibility. Stored as facts, those facts and
the skeleton nodes built over them stay after the question is answered.
StationOps' decision steps left about 10,000 nodes after 20 shifts, and
action query time per shift rose 1.4 s → 5.7 s at a fixed budget
(`client_practices.md`).

An implication query, `(Implication A B)`, does not serve: it judges how
strongly A implies B, from the assumption alone. Its contexts see nothing of
the main context, and a premise is read in them only when it mentions the
query's variables (the hypothetical individual); world facts about the
statements it relates would make it hold trivially. A decision wants the
opposite: the world as it is, plus the decision's facts. Placing premises in
an implication query by what the assumptions affect, or letting its contexts
see the world, broke the implication tests (patches kept outside the
repository); the two questions need two query forms.

## Query form

    (: $prf (Assuming (And <fact> ...) <goal>) $tv)

answers `<goal>` as if the facts were stored, together with everything the
knowledge base holds, with proof `(assuming <proof in the context>)`, one
answer per binding of the goal's variables. A fact may be an implication: it
is then a rule within the query, which lets a client link stored statements
to the ones its question reads without adding rules to the knowledge base.

## Context

The query opens a fresh context C holding the assumed facts, marked as a
context that sees the world (`context-world!`).

- **What reads C.** A predicate is *affected* when it is an assumed fact's
  predicate, or concluded by a rule with an affected premise (a fixed point
  over the rules' predicate heads, as dormant rules compute their support).
  A premise of an affected predicate is read in C; any other premise is read
  in the main context. So beliefs the assumptions cannot change are read where
  they are, with the answers, rows and caches the main context already has,
  and no work on them is repeated or thrown away.
- **Reading C.** A premise read in C sees C's facts and the main context's
  stored facts of the same statement (not forward copies of derived values):
  an assumption adds to what is known, it does not hide it. What follows from
  them is derived in C.
- **The goal** is read in C.

## Cleanup (not built)

Every node, key, row, view, answer, wait and deferred item whose context is
C is recorded under C when created (`&sk_context_items`). When the query
ends, its contexts' items are removed, as its query-local rules are
(`sk-clear-temp!`). Main-context keys that read C's keys do not exist: a
main-context premise never reads C.

## Budget

The query's budget is spent as any query's: on the expansions under its
goal. Main-context premises are expanded in the main context and stay
expanded for later queries, as any query's work does.

## Evaluation

1. Unit tests:
   - an assumed fact combines with a main-context belief;
   - the main context is unchanged after the query: no new facts, nodes or
     rows outside it, and none in C;
   - an unaffected premise is read in the main context, and its existing
     answer is reused without expansion.
2. Full suite.
3. StationOps: decision steps as `Assuming` queries over the step's facts.
   Proposals equal the reference oracle. Over a 60-shift live game, action
   query time per shift stays flat without forgetting, and memory grows as in
   a replay without actions (about 5 MB per shift).
