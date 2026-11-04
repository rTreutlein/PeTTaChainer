"""Shrink a flagged KB to a minimal one that still fails the same way.

A failure is a category on one query atom. Every candidate reduction keeps
the KB inside the shared semantics (``KB.problems()``) and is kept when both
sides still disagree on that atom in that category. Reductions, tried until
none applies: keep only the failing query, drop an individual, an
observation, a rule (its head becomes a root with its prior under the model),
an antecedent part, a negation, a loop declaration, half the history (down to 8 individuals), and
unused root predicates.
"""

from __future__ import annotations

import dataclasses
import json
from typing import Callable, Iterator

from .kb import KB, Antecedent, Literal, Rule
from .run import Settings, Verdict, chainer, judge, oracle


MIN_HISTORY = 8  # the generator's smallest history: a smaller one only amplifies sampling noise


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
    if len(people) >= 2 * MIN_HISTORY:
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


def shrink_event(kb, flag, settings, execute, limit=24):
    """Delete to a fixed point while retaining this query and invariant.

    Paired mutations are rebuilt after every reduction. A trial is accepted
    only with the same semantic failure, never a crash in place of a wrong
    answer. The status explicitly records a limit rather than claiming a
    globally minimal counterexample.
    """
    from .run import event_evaluate
    from .kb import formula_text
    kb = kb.copy()
    query = formula_text(kb.queries[flag['query']])
    invariant = flag['invariant']
    checked = flag.get('variant', invariant)
    kb.checks = [checked] if checked in kb.checks else []
    # Marginal/joint consistency needs all three queries.
    if invariant not in ('frechet',):
        kb.queries = [kb.queries[flag['query']]]
    attempts, detail = 0, flag
    seen = set()
    while True:
        candidates = []
        # A producer family is a useful chunk: deleting interleaved sources
        # one at a time otherwise spends most trials on irrelevant siblings.
        for head in dict.fromkeys(r[2] for r in kb.rules):
            family = [r for r in kb.rules if r[2] == head]
            for keep in ([], family[:1], family[-1:]):
                if len(keep) == len(family):
                    continue
                c = kb.copy()
                c.rules = [r for r in kb.rules if r[2] != head] + keep
                candidates.append(c)
        for field in ('raw', 'reports', 'rules'):
            values = getattr(kb, field)
            if len(values) > 2:
                for part in (values[:len(values)//2], values[len(values)//2:]):
                    c = kb.copy()
                    setattr(c, field, part)
                    candidates.append(c)
            for i in range(len(values)):
                c = kb.copy()
                del getattr(c, field)[i]
                candidates.append(c)
        # Roots used by a remaining rule/query cannot simply disappear from
        # the model. Remove an unused atom together with its source instead.
        for atom in kb.roots:
            c = kb.copy()
            del c.roots[atom]
            candidates.append(c)
        for atom in kb.bases:
            c = kb.copy()
            del c.bases[atom]
            candidates.append(c)
        if kb.probe and kb.probe[0] > 4:
            c = kb.copy()
            c.probe = [n//2 for n in kb.probe]
            candidates.append(c)
        progress = False
        for c in candidates:
            # Keep transformations defined after removing required structure.
            if checked in ('flip', 'false') and not c.reports:
                continue
            if checked == 'neutral' and not c.roots:
                continue
            if checked == 'inactive' and not c.rules:
                continue
            if c.reference and not c.rules and not any(not isinstance(f, str) for f, _, _ in c.reports):
                continue
            if c.reference or invariant == 'flip':
                atoms = set(c.roots) | {r[2] for r in c.rules}
                def reads(form):
                    return {form} if isinstance(form, str) else set().union(*(reads(x) for x in form[1:]))
                required = set().union(*(reads(r[1]) for r in c.rules), *(reads(f) for f, _, _ in c.reports), *(reads(q) for q in c.queries))
                if not required <= atoms:
                    continue
                if c.reference and not c.raw:
                    c.roots = {a: tv for a, tv in c.roots.items() if a in required}
                    c.bases = {a: tv for a, tv in c.bases.items() if a in atoms and a in required}
            key = json.dumps(c.to_json(), sort_keys=True)
            if key in seen:
                continue
            if attempts >= limit:
                return kb, detail, attempts, False
            seen.add(key)
            attempts += 1
            found = event_evaluate(c, settings, execute)
            matches = [f for f in found['flags'] if f['invariant'] == invariant and
                       f['severity'] == flag['severity'] and f.get('variant') == flag.get('variant') and
                       formula_text(c.queries[f['query']]) == query]
            if matches:
                kb, detail, progress = c, matches[0], True
                break
        if not progress:
            return kb, detail, attempts, True
