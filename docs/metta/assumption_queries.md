# Queries under assumptions

Status: built, October 2026.

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
  over the rules' predicate heads, as dormant rules compute their support;
  the assumed facts' heads are recorded when the context is opened, so this
  reads the query's facts, not the knowledge base).
  A premise of an affected predicate is read in C; any other premise is read
  in the main context. So beliefs the assumptions cannot change are read where
  they are, with the answers, rows and caches the main context already has,
  and no work on them is repeated or thrown away.
- **Reading C.** A premise read in C sees C's facts and the main context's
  stored facts of the same statement (not forward copies of derived values):
  an assumption adds to what is known, it does not hide it. What follows from
  them is derived in C.
- **The goal** is read in C.
- **Folds.** A fold premise whose member pattern the assumptions affect is
  scoped to C: its arguments name C instead of the KB, and its member node
  lies in C (members cached per scope).
- **The world's rules.** A goal in C is also concluded by the rules compiled
  for the main context (connective adapters among them, for `And` and `Not`
  goals), with C as the conclusion's context (`sk-world-rule-match`), and no
  rule is skipped as dormant there: dormancy is judged in the main context,
  and C's assumptions can support what the main context lacks.
- **No variables.** C names no query variables, unlike an implication
  query's contexts (which name the hypothetical individual's), so its keys
  are ground.

## Cleanup

Whatever lies in C is recorded under C when it is created
(`&sk_ctx_items`): its nodes (`sk-add-child!`), keys (`sk-register-key!`)
and fold members (`sk-fold-member`). So is each link between C and the rest
of the store: a wait, answer, child or use edge from a node or key in C to
one outside it. The query's root lies in the main context and waits on C's
goal, the only thing outside C that reads it; it is recorded under C as
well.

After the query's results are externalized (`run-query-execution-plan`),
`sk-clear-contexts!` removes every recorded node and key from all the stores
keyed by its hash. A key's rows leave the reader lists of the keys they read,
which may lie in the main context, together with their per-row marks. A fold
node in C takes its fold's key along. The answer queue loses deliveries into
C. The context's marks go (`context-forget!`). So no later query reads,
updates or walks anything a past decision assumed, and a sequence of
decisions leaves the stores as one does (`test_assuming_query.metta`).

What stays: the link digests (`&sk_link`, one integer per link, since a
join's digest names the partial join it extended), and the work done in the
main context, which is ordinary knowledge any query may reuse.

Implication queries' contexts stay: they hold the derivation of a
main-context belief, the implication itself.

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
