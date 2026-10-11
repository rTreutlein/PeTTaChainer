# Materializing Composed Rules

## Core idea

The distinction that matters is not facts versus rules, or deductive versus
inductive reasoning. It is **closed proofs versus open proofs**.

- A materialized fact is a proof DAG with no open inputs.
- A materialized rule is the same proof DAG cut at selected boundary nodes,
  with those nodes replaced by input holes.

The unified primitive should therefore be:

```text
materialize-proof(root, boundaries)

boundaries empty   -> fact
boundaries present -> compiled rule
```

This is proof residualization: preserve the computation between the boundary
and the root, while turning the boundary proofs into rule premises.

## Example

Given:

```text
r1: A -> B
r2: B -> C
```

a composed rule should not be stored as an unrelated new implication. It should
be the residual form of applying `r1` followed by `r2`:

```metta
(rules
   ((: $kb $a-proof (A $x) $a-tv)
    (CPU CTVModusPonensFormula
       ($a-tv $r1-ctv) $b-tv)
    (CPU CTVModusPonensFormula
       ($b-tv $r2-ctv) $c-tv)
    |-
    (: $kb
       (by r2 (by r1 $a-proof))
       (C $x)
       $c-tv)))
```

This is equivalent to executing the original rules because:

- the input proof and TV remain rule inputs;
- every internal TV computation remains in the rule body;
- the conclusion retains the original composed proof expression;
- no independent evidence or alternative semantics are introduced.

Aggregate, statistical, and other inductive computations require no separate
representation. Their proof DAGs contain different internal operations, but
residualization treats those operations in exactly the same way.

## The real difficulty: boundaries and generalization

Producing the residual rule is mechanical once its boundaries are known. The
hard problem is deciding which proof nodes should become inputs and when a
ground proof may be generalized.

A proof of `C(bob)` does not justify replacing `bob` with `$x`. A reusable rule
can come from either:

1. an already-open proof, such as proving `C($x)` under an assumed `A($x)`; or
2. jointly anti-unifying several compatible proof instances.

Anti-unification must cover the complete residual proof, including:

- boundary premises;
- the conclusion;
- shared variables;
- constants;
- CPU arguments and results;
- internal proof structure.

Generalizing only the visible premise and conclusion can produce a rule whose
internal computation is no longer valid.

## Required invariants

- Applying a materialized rule must produce the same proof and TV as applying
  its component proof DAG.
- A materialized rule must not acquire new independent evidence merely because
  it was given a reusable runtime entry.
- Variable sharing and constants must survive residualization exactly.
- Cycles and shared-evidence constraints remain those of the original proof.
- Materialized facts remain the zero-boundary case of the same operation.
