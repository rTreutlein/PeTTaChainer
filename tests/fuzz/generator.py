"""Seeded random knowledge bases over switchable features.

``generate(seed, features)`` is deterministic per seed. Every KB it returns
passes ``KB.problems()``: its PeTTaChainer and ProbLog readings agree by the
choices in docs/metta/fuzzing.md.
"""

from __future__ import annotations

import random

from .kb import KB, Antecedent, Fact, Literal, Rule

FEATURES = {
    "chain": "rule antecedents may read derived predicates",
    "shared": "a predicate may feed several rules (common causes)",
    "and": "And antecedents",
    "or": "Or antecedents",
    "not": "negated antecedent literals",
    "cycle": "a positive loop over complete predicates",
    "soft": "soft observations of roots (strength strictly between 0 and 1)",
    "evidence": "hard observations of derived statements",
    "observe": "hard observations of roots",
    "latent": "root atoms of the queried individuals may stay unobserved (otherwise each is observed)",
    "derived_rates": "pin each derived predicate's base rate to its prior under the model (no history only)",
    "learned": "rules refined from a fully observed history (Laplace oracle)",
    "history_rates": "root priors estimated from a fully observed history",
}
DEFAULT = ["chain", "shared", "and", "or", "not", "evidence", "observe", "latent", "derived_rates"]

PREDS = ["A", "B", "C", "D", "E", "F", "G", "H"]
INDIVIDUALS = ["a", "b"]


def _rate(rng: random.Random, low: float = 0.05, high: float = 0.95) -> float:
    return round(rng.uniform(low, high), 2)


def sample_world(kb: KB, rng: random.Random) -> dict[str, bool]:
    """One individual drawn from the KB's true model: roots by their prior,
    each rule's two branches by a coin each, loops at their least fixpoint."""
    world = {pred: rng.random() < kb.prior(pred) for pred in kb.roots}
    coins = {rule.head: (rng.random() < rule.p, rng.random() < rule.q) for rule in kb.rules}
    world |= {rule.head: False for rule in kb.rules}
    changed = True
    while changed:  # rules are in topological order apart from the loop's back edge
        changed = False
        for rule in kb.rules:
            value = coins[rule.head][0] if rule.ant.holds(world) else coins[rule.head][1]
            if value != world[rule.head]:
                world[rule.head], changed = value, True
    return world


def _antecedent(rng: random.Random, candidates: list[str], features: set[str]) -> Antecedent:
    forms = ["lit"] + [op for op in ("and", "or") if op in features and len(candidates) >= 2]
    op = rng.choice(forms)
    preds = rng.sample(candidates, 1 if op == "lit" else min(len(candidates), rng.choice([2, 2, 3])))
    return Antecedent(op, tuple(Literal(pred, "not" in features and rng.random() < 0.3) for pred in preds))


def generate(seed: int, features: list[str], max_statements: int = 15) -> KB:
    rng = random.Random(seed)
    on = set(features) | ({"chain"} if "cycle" in features else set())  # a loop closes a chain
    for _ in range(100):
        kb = _attempt(rng, on, max_statements)
        if kb is not None and not kb.problems():
            kb.features = sorted(on)
            return kb
    raise RuntimeError(f"no valid KB for seed {seed} and features {sorted(on)}")


def _attempt(rng: random.Random, on: set[str], max_statements: int) -> KB | None:
    n_preds = rng.randint(3, 6)
    n_roots = rng.randint(1, min(3, n_preds - 1))
    names = PREDS[:n_preds]
    roots = {pred: _rate(rng, 0.1, 0.9) for pred in names[:n_roots]}
    rules: list[Rule] = []
    used: set[str] = set()
    for head in names[n_roots:]:
        pool = list(roots) + ([rule.head for rule in rules] if "chain" in on else [])
        if "shared" not in on:
            pool = [pred for pred in pool if pred not in used]
        if not pool:
            break
        ant = _antecedent(rng, pool, on)
        used.update(ant.preds)
        rules.append(Rule(f"r{head}", head, ant, _rate(rng), _rate(rng), "learned" in on and rng.random() < 0.7))
    if not rules:
        return None
    complete: list[str] = []
    if "cycle" in on:
        rules, complete = _close_loop(rng, rules)
        if not complete:
            return None
    kb = KB(individuals=INDIVIDUALS[: rng.randint(1, 2)], roots=roots, rules=rules, facts=[], complete=complete)
    if "learned" in on or "history_rates" in on:
        kb.history = [
            Fact(pred, f"h{i}", 1.0 if value else 0.0)
            for i in range(rng.randint(8, 30))
            for pred, value in sample_world(kb, rng).items()
        ]
    kb.facts = _observations(kb, rng, on, max_statements - len(rules))  # drawn with the true rates
    if "history_rates" in on:
        kb.roots = {pred: None for pred in roots}
    observed = {(fact.pred, fact.ind) for fact in kb.facts}
    kb.queries = [(pred, ind) for ind in kb.individuals for pred in kb.preds if (pred, ind) not in observed]
    rng.shuffle(kb.queries)
    kb.queries = sorted(kb.queries[:8], key=lambda atom: (atom[1], kb.preds.index(atom[0])))
    return kb if kb.queries else None


def _close_loop(rng: random.Random, rules: list[Rule]) -> tuple[list[Rule], list[str]]:
    """Turn a chain X -> ... -> Y of derived predicates into a loop by adding Y
    as a disjunct of X's antecedent. The loop's predicates are complete, their
    rules have no negative branch and no negation (ProbLog's least fixpoint is
    then the chainer's well-founded reading)."""
    heads = [rule.head for rule in rules]
    reads = {rule.head: set(rule.ant.preds) for rule in rules}
    pairs = []
    for i, x in enumerate(heads):
        for y in heads[i:]:
            path = _path(reads, x, y)
            if path:
                pairs.append(path)
    if not pairs:
        return rules, []
    loop = rng.choice(pairs)  # [x, ..., y], each read by the next
    x, y = loop[0], loop[-1]
    out = []
    for rule in rules:
        if rule.head not in loop:
            out.append(rule)
            continue
        parts = tuple(Literal(part.pred) for part in rule.ant.parts)
        op = rule.ant.op
        if rule.head == x:
            parts = parts + (Literal(y),)
            op = "or"
        elif op == "or" and len(parts) > 1:
            op = "and" if rng.random() < 0.5 else "or"
        out.append(Rule(rule.name, rule.head, Antecedent(op if len(parts) > 1 else "lit", parts), rule.p if rng.random() < 0.5 else 1.0, 0.0))
    return out, loop


def _path(reads: dict[str, set[str]], x: str, y: str) -> list[str] | None:
    """Derived predicates [x, ..., y], each reading the one before it."""
    if x == y:
        return [x] if x in reads.get(x, set()) else None
    frontier = [[x]]
    while frontier:
        path = frontier.pop()
        for head, preds in reads.items():
            if path[-1] in preds and head not in path:
                if head == y:
                    return path + [y]
                frontier.append(path + [head])
    return None


def _observations(kb: KB, rng: random.Random, on: set[str], room: int) -> list[Fact]:
    """Observations of the queried individuals drawn from one sampled world
    each, so the evidence is possible. Without ``latent`` every root atom is
    observed first; the rest is a random subset of what the features allow."""
    required, optional = [], []
    for ind in kb.individuals:
        world = sample_world(kb, rng)
        for pred in kb.preds:
            kinds = [k for k in ("observe", "soft") if k in on] if pred in kb.roots else ["evidence"] if "evidence" in on else []
            if kinds:
                entry = (pred, ind, rng.choice(kinds), world[pred])
                (required if pred in kb.roots and "latent" not in on else optional).append(entry)
    rng.shuffle(optional)
    chosen = required + optional[: rng.randint(0, len(optional))]
    facts: list[Fact] = []
    for pred, ind, kind, value in chosen[: max(0, room)]:
        fact = Fact(pred, ind, _rate(rng, 0.1, 0.9) if kind == "soft" else (1.0 if value else 0.0))
        trial = KB(kb.individuals, kb.roots, kb.rules, facts + [fact], kb.history, kb.complete)
        if not trial.problems():
            facts.append(fact)
    return facts
