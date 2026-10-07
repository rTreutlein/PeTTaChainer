# Queries under assumptions

Status: design, October 2026.

## Problem

A client often asks a question that holds only together with some facts: a
StationOps decision step reads the current leak beliefs together with the
step's candidates, costs and eligibility. Stored as facts, those facts and
the skeleton nodes built over them stay after the question is answered.
StationOps' decision steps left about 10,000 nodes after 20 shifts, and
action query time per shift rose 1.4 s → 5.7 s at a fixed budget
(`client_practices.md`).

An implication query, `(Implication A B)`, does not serve: it estimates the
implication's truth. It assumes A in a positive and a refuting context, and a
rule premise is read in that context only when it mentions the query's free
variables; other premises are read in the main context, where A does not
hold. Its contexts also stay after the query (two per query, with their
nodes, rows and answers).

## Query form

    (: $prf (Assuming (And <fact> ...) <goal>) $tv)

answers `<goal>` as if the facts were stored, together with everything the
knowledge base holds. The answers are the goal's, with the facts' proofs as
`(assumed n)`. Nothing of the query stays afterwards.

## Context

The query opens a fresh context C (`(kb C Nil)`) holding the assumed facts.

- **What reads C.** A predicate is *affected* when it is an assumed fact's
  predicate, or concluded by a rule with an affected premise (a fixed point
  over the rules' predicate heads, as dormant rules compute their support).
  A premise of an affected predicate is read in C; any other premise is read
  in the main context. So beliefs the assumptions cannot change are read where
  they are, with the answers, rows and caches the main context already has,
  and no work on them is repeated or thrown away.
- **Reading C.** A premise read in C sees C's facts and keys, and the main
  context's facts and keys of the same statement: an assumption adds to what
  is known, it does not hide it.
- **The goal** is read in C.

## Cleanup

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
