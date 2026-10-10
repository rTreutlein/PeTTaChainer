"""Shrink a flagged KB to a minimal one that still fails the same way.

A failure is a category on one query atom. Every candidate reduction keeps
the KB inside the shared semantics (``KB.problems()``) and is kept when both
sides still disagree on that atom in that category. Reductions, tried until
none applies: keep only the failing query, drop an individual, an
observation, a rule (its head becomes a root with its prior under the model),
an antecedent part, a negation, a loop declaration, half the history, and
unused root predicates.
"""

from __future__ import annotations

import dataclasses
from typing import Callable, Iterator

from .kb import KB, Antecedent, Literal, Rule
from .run import Settings, Verdict, chainer, judge, oracle


def fails(kb: KB, category: str, atom: tuple[str, str], settings: Settings) -> Verdict | None:
    if kb.problems() or atom not in kb.queries:
        return None
    (exact,) = oracle([kb])
    if "error" in exact:
        return None
    verdict = judge(kb, exact, chainer(kb, settings), settings)
    index = kb.queries.index(atom)
    return verdict if (category, index) in verdict.flags or (category == "crash" and verdict.error) else None


def _with(kb: KB, **changes) -> KB:
    out = kb.copy()
    for key, value in changes.items():
        setattr(out, key, value)
    return out


def _drop_rule(kb: KB, rule: Rule) -> KB:
    """The rule's head becomes a root at its prior under the model, so the
    predicates reading it keep their meaning."""
    roots = dict(kb.roots)
    roots[rule.head] = None if kb.roots and all(r is None for r in kb.roots.values()) and kb.history else round(kb.model_prior(rule.head), 10)
    return _with(
        kb,
        roots=roots,
        rules=[r for r in kb.rules if r is not rule],
        complete=[p for p in kb.complete if p != rule.head],
    )


def _set_ant(kb: KB, rule: Rule, ant: Antecedent) -> KB:
    return _with(kb, rules=[dataclasses.replace(r, ant=ant) if r is rule else r for r in kb.rules])


def candidates(kb: KB, atom: tuple[str, str]) -> Iterator[KB]:
    if len(kb.queries) > 1:
        yield _with(kb, queries=[atom])
    for ind in kb.individuals:
        if ind != atom[1]:
            yield _with(kb, individuals=[i for i in kb.individuals if i != ind], facts=[f for f in kb.facts if f.ind != ind], queries=[q for q in kb.queries if q[1] != ind])
    for fact in kb.facts:
        yield _with(kb, facts=[f for f in kb.facts if f is not fact])
    for rule in reversed(kb.rules):
        yield _drop_rule(kb, rule)
    for rule in kb.rules:
        parts = rule.ant.parts
        if len(parts) > 1:
            for part in parts:
                rest = tuple(p for p in parts if p is not part)
                yield _set_ant(kb, rule, Antecedent(rule.ant.op if len(rest) > 1 else "lit", rest))
        for part in parts:
            if part.negated:
                yield _set_ant(kb, rule, Antecedent(rule.ant.op, tuple(Literal(p.pred) if p is part else p for p in parts)))
    for pred in kb.complete:
        yield _with(kb, complete=[p for p in kb.complete if p != pred])
    people = kb.history_individuals()
    if len(people) > 2:
        keep = set(people[: len(people) // 2])
        yield _with(kb, history=[f for f in kb.history if f.ind in keep])
    if kb.history and not kb.learned and all(rate is not None for rate in kb.roots.values()):
        yield _with(kb, history=[])
    read = {pred for rule in kb.rules for pred in rule.ant.preds} | {f.pred for f in kb.facts} | {q[0] for q in kb.queries}
    unused = [pred for pred in kb.roots if pred not in read]
    if unused:
        yield _with(kb, roots={p: r for p, r in kb.roots.items() if p not in unused}, history=[f for f in kb.history if f.pred not in unused])


def size(kb: KB) -> int:
    return len(kb.roots) + len(kb.rules) + len(kb.facts) + sum(len(r.ant.parts) for r in kb.rules) + len(kb.individuals) + len(kb.queries) + len(kb.history_individuals())


def shrink(kb: KB, category: str, atom: tuple[str, str], settings: Settings, log: Callable[[str], None] = lambda _: None, limit: int = 200) -> tuple[KB, Verdict | None, int]:
    """The smallest failing KB found and its verdict, with the runs it took."""
    verdict = fails(kb, category, atom, settings)
    runs = 1
    if verdict is None:
        return kb, None, runs
    progress = True
    while progress and runs < limit:
        progress = False
        for candidate in candidates(kb, atom):
            if size(candidate) >= size(kb) and candidate.queries == kb.queries:
                continue
            runs += 1
            found = fails(candidate, category, atom, settings)
            if found is not None:
                kb, verdict, progress = candidate, found, True
                log(f"  shrunk to size {size(kb)} ({len(kb.rules)} rules, {len(kb.facts)} facts)")
                break
            if runs >= limit:
                break
    return kb, verdict, runs
