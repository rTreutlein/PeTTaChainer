# Backward Chainer Flow

This describes the current backward chainer in terms of:

- control flow
- state transitions
- how goals, frontiers, and proofs feed each other

## Control Flow

```mermaid
flowchart TD
    A["query(steps, kb, stmt)"] --> B["mm2compileQuery(kb, stmt)"]
    B --> C["internalize-proof-structure"]
    C --> D["split into goal(query) + adds"]
    D --> E["inject-compiled-adds(adds) -> &kb"]
    D --> F["chainer(steps, query)"]

    F --> G["clear-backward-state + reset ids + clear agenda"]
    G --> H["ensure-goal(query) -> root gid"]
    H --> I["schedule-goal(1.0, root gid)"]
    I --> J["search-goals(steps + 1)"]

    J --> K["pop qitem(score, gid) from heap"]
    K --> L{"stale or expanded?"}
    L -- "yes" --> J
    L -- "no" --> M["expand-goal(steps, gid)"]

    M --> N["expand-direct-goal"]
    M --> O["expand-rule-goal"]

    N --> P["direct-goal-results(steps, goal)"]
    P --> Q["commit-proof-candidate(gid, classify, leaf candidate)"]
    Q --> R["store accepted proof + wake waiters"]

    O --> U["lookup rule + build bundle + spawn-frontier"]

    U --> X["ensure-goal(next premise) -> child gid"]
    X --> Y{"cycle to ancestor?"}
    Y -- "yes" --> J
    Y -- "no" --> Z["store frontier + goal_waiter(child gid, fid)"]
    Z --> AA["attach-existing-goal-proofs(fid, child gid)"]
    Z --> AB["schedule-goal(score, child gid)"]

    R --> AC["prune dominated goal links"]
    AC --> AD["add goal_proof"]
    AD --> AE["advance all waiting frontiers for this gid"]
    AE --> AF["advance-frontier(fid, pid)"]
    AF --> AG{"evidence overlap?"}
    AG -- "yes" --> J
    AG -- "no" --> AH["advance-frontier-bundle(bundle, pid)"]
    AH --> AI{"premise matched?"}
    AI -- "no" --> J
    AI -- "yes, bundle empty" --> W["build-parent-proof(aid, bundle, score, evidence, pid-list)"]
    W --> R
    AI -- "yes, bundle non-empty" --> AJ["spawn-frontier(updated bundle, min score, merged evidence, pid path)"]
    AJ --> U

    J --> AK["goal-results(root gid)"]
    AK --> AL["merge-goal-proof-list"]
    AL --> AM["materialize-proof-atom"]
    AM --> AN["externalize-proof-structure"]
    AN --> AO["pretty"]
```

## State Flow

```mermaid
flowchart LR
    subgraph GoalState
        G1["&goal_lookup\n goal term -> gid"]
        G2["&goal_by_id\n gid -> goal term"]
        G3["&goal_expanded\n gid -> true"]
        G4["&goal_pending_score\n gid -> best queued score"]
        G5["heap agenda\n qitem(score, gid)"]
    end

    subgraph RuleState
        R1["&and_node\n aid -> parent gid, rule id, bound, bundle"]
        R2["&frontier\n fid -> parent gid, aid, bundle, score, seen, rev-pids"]
        R3["&goal_waiter\n child gid -> fid"]
    end

    subgraph ProofState
        P1["&proof_goal\n pid -> gid"]
        P2["&proof_kind\n pid -> (leaf result) | (rule aid)"]
        P3["&proof_tv\n pid -> tv"]
        P4["&proof_stats\n pid -> score, evidence set"]
        P6["&proof_children\n pid -> child pids"]
        P7["&goal_proof\n gid -> pid"]
    end

    G1 --> G2
    G2 --> G5
    G5 --> G3
    G5 --> G4

    G2 --> R1
    R1 --> R2
    R2 --> R3
    R3 --> G2

    G2 --> P1
    P1 --> P2
    P1 --> P3
    P1 --> P4
    P1 --> P6
    P1 --> P7
    P7 --> R2
```

## Information Flow Summary

- `gid` is the scheduling unit.
- `aid` is one rule application for one parent goal.
- `fid` is one partially satisfied path through an `aid`.
- `pid` is one proof alternative for one goal.

The main loop is:

1. A `gid` is popped from the heap.
2. The goal is expanded into direct proofs and rule options.
3. Rule options create `aid`s and `fid`s.
4. Child goals accumulate `pid`s.
5. New `pid`s wake any waiting `fid`s.
6. Completed `fid`s emit parent `pid`s.
7. Root `gid` proofs are merged and materialized at the end.

## Where Pruning Happens

- Queue staleness: `goal_pending_score`
- No re-expansion: `goal_expanded`
- Cycle blocking: `goal-has-ancestor?`
- Proof dominance: `proof-overlap-dominates?` inside `register-proof`
- Frontier reuse blocking: evidence overlap check inside `advance-frontier`

## Boundary

- External interface:
  - `(: kb prf type tv)`
- Internal runtime:
  - `(type kb prf tv)`
- Conversion happens only around `compileadd/query`.
