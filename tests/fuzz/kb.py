"""Small knowledge bases with one meaning in PeTTaChainer and in ProbLog.

A ``KB`` is the abstract form both translations are written from: unary
predicates over a few individuals, root predicates with a prior, and one CTV
rule per derived predicate. ``metta`` and ``problog`` write it out; the shared
semantics, and what is left out because the two readings differ, are in
docs/metta/fuzzing.md.
"""

from __future__ import annotations

import dataclasses
import json
from dataclasses import dataclass, field

BAYES_PRIOR_COUNT = 0.2  # PeTTaChainer's default a: a population prior is (s n + a/2) / (n + a)


def uniform_prior(k: float) -> str:
    """A learned rule's stated truth: two pseudo-observations at 0.5 per
    branch (confidence 2 / (2 + k)), so revising it with n instances is
    Laplace's rule (s + 1) / (n + 2), the oracle's estimate."""
    c = 2 / (2 + k)
    return f"(CTV (STV 0.5 {c:.10g}) (STV 0.5 {c:.10g}))"


@dataclass(frozen=True)
class Literal:
    pred: str
    negated: bool = False


@dataclass(frozen=True)
class Antecedent:
    """A literal (``op`` "lit", one part), or an And / Or of literals."""

    op: str
    parts: tuple[Literal, ...]

    @property
    def preds(self) -> list[str]:
        return [part.pred for part in self.parts]

    def holds(self, world: dict[str, bool]) -> bool:
        values = [world[part.pred] != part.negated for part in self.parts]
        return any(values) if self.op == "or" else all(values)


@dataclass(frozen=True)
class Rule:
    """``ant -> head`` with P(head | ant) = p and P(head | not ant) = q. A
    learned rule states the weak prior to PeTTaChainer, which refines it from
    the history; the oracle uses Laplace's rule over the same history."""

    name: str
    head: str
    ant: Antecedent
    p: float
    q: float
    learned: bool = False


@dataclass(frozen=True)
class Fact:
    """An observation of ``(pred ind)``: hard (strength 0 or 1) or soft
    (strength in between, on a root predicate only), confidence 1."""

    pred: str
    ind: str
    strength: float

    @property
    def hard(self) -> bool:
        return self.strength in (0.0, 1.0)


@dataclass
class KB:
    individuals: list[str]  # the queried individuals
    roots: dict[str, float | None]  # root predicate -> stated prior, or None: estimated from the stored facts
    rules: list[Rule]
    facts: list[Fact]  # observations of the queried individuals
    history: list[Fact] = field(default_factory=list)  # fully observed past individuals
    complete: list[str] = field(default_factory=list)
    queries: list[tuple[str, str]] = field(default_factory=list)  # (pred, ind)
    features: list[str] = field(default_factory=list)

    # -- structure -------------------------------------------------------
    @property
    def preds(self) -> list[str]:
        return list(self.roots) + [rule.head for rule in self.rules]

    def rule_of(self, pred: str) -> Rule | None:
        return next((rule for rule in self.rules if rule.head == pred), None)

    def descendants(self, pred: str) -> set[str]:
        found, frontier = set(), [pred]
        while frontier:
            current = frontier.pop()
            for rule in self.rules:
                if current in rule.ant.preds and rule.head not in found:
                    found.add(rule.head)
                    frontier.append(rule.head)
        return found

    def history_individuals(self) -> list[str]:
        return list(dict.fromkeys(fact.ind for fact in self.history))

    @property
    def learned(self) -> bool:
        return any(rule.learned for rule in self.rules)

    # -- the oracle's parameters ------------------------------------------
    def prior(self, pred: str) -> float:
        """A root's prior: as stated, or PeTTaChainer's population prior over
        every stored fact of it, (s n + a/2) / (n + a)."""
        stated = self.roots[pred]
        if stated is not None:
            return stated
        values = [fact.strength for fact in self.history + self.facts if fact.pred == pred]
        return (sum(values) + BAYES_PRIOR_COUNT / 2) / (len(values) + BAYES_PRIOR_COUNT)

    def tally(self, rule: Rule) -> dict[bool, list[int]]:
        """Per branch (antecedent true / false): [consequent true, instances]
        over the history."""
        worlds: dict[str, dict[str, bool]] = {}
        for fact in self.history:
            worlds.setdefault(fact.ind, {})[fact.pred] = fact.strength == 1.0
        tally = {True: [0, 0], False: [0, 0]}
        for world in worlds.values():
            if rule.head in world and all(pred in world for pred in rule.ant.preds):
                branch = tally[rule.ant.holds(world)]
                branch[0] += world[rule.head]
                branch[1] += 1
        return tally

    def rates(self, rule: Rule) -> tuple[float, float]:
        """A rule's two branches: as stated, or Laplace counts over the history."""
        if not rule.learned:
            return rule.p, rule.q
        tally = self.tally(rule)
        return tuple((tally[b][0] + 1) / (tally[b][1] + 2) for b in (True, False))

    def model_prior(self, pred: str) -> float:
        """P(pred x) for an individual with no observations, by enumerating
        the roots and both coins of every rule (loops at their least
        fixpoint)."""
        import itertools

        roots, rules = list(self.roots), self.rules
        total = 0.0
        for bits in itertools.product((False, True), repeat=len(roots) + 2 * len(rules)):
            weight = 1.0
            world = {}
            for root, bit in zip(roots, bits):
                rate = self.prior(root)
                world[root] = bit
                weight *= rate if bit else 1 - rate
            coins = {}
            for index, rule in enumerate(rules):
                p, q = self.rates(rule)
                pos, neg = bits[len(roots) + 2 * index], bits[len(roots) + 2 * index + 1]
                weight *= (p if pos else 1 - p) * (q if neg else 1 - q)
                coins[rule.head] = (pos, neg)
            if weight == 0:
                continue
            world |= {rule.head: False for rule in rules}
            changed = True
            while changed:
                changed = False
                for rule in rules:
                    value = coins[rule.head][0] if rule.ant.holds(world) else coins[rule.head][1]
                    if value != world[rule.head]:
                        world[rule.head], changed = value, True
            total += weight * world[pred]
        return total

    def ancestors(self, pred: str) -> set[str]:
        found, frontier = set(), [pred]
        while frontier:
            rule = self.rule_of(frontier.pop())
            for parent in rule.ant.preds if rule else ():
                if parent not in found:
                    found.add(parent)
                    frontier.append(parent)
        return found

    def unobserved_below(self, pred: str, ind: str) -> bool:
        """Neither ``(pred ind)`` nor anything derived from it is observed."""
        observed = {fact.pred for fact in self.facts if fact.ind == ind}
        return pred not in observed and not (self.descendants(pred) & observed)

    def latent_premise(self, pred: str, ind: str) -> bool:
        """Whether ``(pred ind)`` is derived from a root atom that is neither
        observed nor below an observation: the chainer gives such an atom no
        value as a premise (a population prior answers roots only)."""
        return any(root in self.roots and self.unobserved_below(root, ind) for root in self.ancestors(pred))

    # -- validity ----------------------------------------------------------
    def problems(self) -> list[str]:
        """Why the KB is outside the shared semantics (empty when it is not)."""
        issues = []
        heads = [rule.head for rule in self.rules]
        if len(set(heads)) != len(heads):
            issues.append("a predicate with two rules")
        for rule in self.rules:
            if rule.head in self.roots:
                issues.append(f"root {rule.head} has a rule")
            for pred in rule.ant.preds:
                if pred not in self.preds:
                    issues.append(f"{rule.name} reads undefined {pred}")
            if rule.learned and (rule.ant.op == "or" or any(part.negated for part in rule.ant.parts)):
                issues.append(f"learned {rule.name} has a shape the instance fold does not sample")
            if rule.learned and not all(count for _, count in self.tally(rule).values()):
                issues.append(f"learned {rule.name} has a branch without instances")
            if rule.head in self.complete:
                if rule.q != 0 or rule.learned:
                    issues.append(f"complete {rule.head} with a negative branch")
                if any(part.negated and part.pred in self.complete for part in rule.ant.parts):
                    issues.append(f"negation inside the complete predicates at {rule.name}")
        for rule in self.rules:
            if rule.head not in self.complete and rule.head in self.descendants(rule.head):
                issues.append(f"cycle through open {rule.head}")
            if any(part.negated and rule.head in self.descendants(part.pred) for part in rule.ant.parts):
                issues.append(f"negation in a cycle at {rule.name}")
        observed = {(fact.pred, fact.ind) for fact in self.facts}
        if len(observed) != len(self.facts):
            issues.append("an atom observed twice")
        for fact in self.facts:
            if fact.ind not in self.individuals or fact.pred not in self.preds:
                issues.append(f"fact on unknown atom {fact}")
            if not fact.hard:
                if fact.pred not in self.roots:
                    issues.append(f"soft observation of derived {fact.pred}")
                below = self.descendants(fact.pred)
                if any(other.ind == fact.ind and other.pred in below for other in self.facts):
                    issues.append(f"evidence below soft {fact.pred} {fact.ind}")
        for pred, ind in self.queries:
            if (pred, ind) in observed or ind not in self.individuals or pred not in self.preds:
                issues.append(f"bad query {pred} {ind}")
        if self.learned and not self.history:
            issues.append("learned rules without history")
        if any(rate is None for rate in self.roots.values()) and not self.history:
            issues.append("estimated priors without history")
        return issues

    # -- serialisation -----------------------------------------------------
    def to_json(self) -> dict:
        return dataclasses.asdict(self)

    @staticmethod
    def from_json(data: dict) -> "KB":
        rules = [
            Rule(r["name"], r["head"], Antecedent(r["ant"]["op"], tuple(Literal(**l) for l in r["ant"]["parts"])), r["p"], r["q"], r["learned"])
            for r in data["rules"]
        ]
        return KB(
            individuals=list(data["individuals"]),
            roots=dict(data["roots"]),
            rules=rules,
            facts=[Fact(**f) for f in data["facts"]],
            history=[Fact(**f) for f in data["history"]],
            complete=list(data["complete"]),
            queries=[tuple(q) for q in data["queries"]],
            features=list(data["features"]),
        )

    def copy(self) -> "KB":
        return KB.from_json(json.loads(json.dumps(self.to_json())))


# -- PeTTaChainer --------------------------------------------------------------


def _num(value: float) -> str:
    return f"{value:.6g}"


def _metta_literal(literal: Literal, var: str = "$x") -> str:
    atom = f"({literal.pred} {var})"
    return f"(Not {atom})" if literal.negated else atom


def metta_antecedent(ant: Antecedent) -> str:
    parts = [_metta_literal(part) for part in ant.parts]
    return parts[0] if ant.op == "lit" else f"({'And' if ant.op == 'and' else 'Or'} {' '.join(parts)})"


def metta_rule(rule: Rule, k: float) -> str:
    tv = uniform_prior(k) if rule.learned else f"(CTV (STV {_num(rule.p)} 1) (STV {_num(rule.q)} 1))"
    return f"(: {rule.name} (Implication {metta_antecedent(rule.ant)} ({rule.head} $x)) {tv})"


def metta_fact(fact: Fact, prefix: str = "obs") -> str:
    return f"(: {prefix}-{fact.pred}-{fact.ind} ({fact.pred} {fact.ind}) (STV {_num(fact.strength)} 1))"


@dataclass
class MettaProgram:
    """What the chainer is given: settings, statements, base-rate pins, queries."""

    complete: list[str]
    refinement: bool
    statements: list[str]
    base_rates: list[tuple[str, str]]  # (pattern, tv) for set-base-rate
    queries: list[str]


def metta(kb: KB, k: float) -> MettaProgram:
    statements = [metta_rule(rule, k) for rule in kb.rules]
    statements += [metta_fact(fact, "hist") for fact in kb.history]
    statements += [metta_fact(fact) for fact in kb.facts]
    return MettaProgram(
        complete=list(kb.complete),
        refinement=kb.learned,
        statements=statements,
        base_rates=[(f"({pred} $x)", f"(STV {_num(rate)} 1.0)") for pred, rate in kb.roots.items() if rate is not None]
        + [(f"({rule.head} $x)", f"(STV {kb.model_prior(rule.head):.10g} 1.0)") for rule in kb.rules if "derived_rates" in kb.features],
        queries=[f"(: $prf ({pred} {ind}) $tv)" for pred, ind in kb.queries],
    )


def metta_file(kb: KB, budget: int, k: float, repo: str) -> str:
    """A standalone .metta repro (run it with .venv/bin/petta)."""
    program = metta(kb, k)
    lines = [f"!(import! &self {repo}/pettachainer/metta/petta_chainer)", f"!(set-evidence-confidence-k {_num(k)})"]
    lines += [f"!(set-complete-predicate kb {head})" for head in program.complete]
    if program.refinement:
        lines.append("!(set-rule-refinement kb true)")
    lines += [f"!(compileadd kb {statement})" for statement in program.statements]
    lines += [f"!(set-base-rate kb {pattern} {tv})" for pattern, tv in program.base_rates]
    lines += [f"!(query {budget} kb {query})" for query in program.queries]
    return "\n".join(lines) + "\n"


# -- ProbLog -------------------------------------------------------------------


def _pl(name: str) -> str:
    return name.lower()


def _pl_prob(p: float) -> str:
    return "" if p == 1 else f"{p:.10g}::"


def problog(kb: KB, evidence: bool = True) -> str:
    """The exact program. A CTV rule is two exclusive clauses over its
    antecedent predicate (no noisy-OR: every head has one rule); a root's
    prior is one probabilistic fact per individual, a soft observation's
    strength in its place; hard observations are evidence. With ``evidence``
    False the observations are left out (the prior marginals)."""
    lines = [f"ind({ind})." for ind in kb.individuals]
    soft = {(fact.pred, fact.ind): fact.strength for fact in kb.facts if not fact.hard}
    for pred in kb.roots:
        prior = kb.prior(pred)
        for ind in kb.individuals:
            p = soft.get((pred, ind), prior) if evidence else prior
            if p > 0:
                lines.append(f"{_pl_prob(p)}{_pl(pred)}({ind}).")
    for index, rule in enumerate(kb.rules):
        ant = f"ant_{index}(X)"
        for part in rule.ant.parts if rule.ant.op == "or" else [None]:
            literals = [part] if part else list(rule.ant.parts)
            body = ", ".join(("\\+" if lit.negated else "") + f"{_pl(lit.pred)}(X)" for lit in literals)
            lines.append(f"{ant} :- ind(X), {body}.")
        p, q = kb.rates(rule)
        if p > 0:
            lines.append(f"{_pl_prob(p)}{_pl(rule.head)}(X) :- ind(X), {ant}.")
        if q > 0:
            lines.append(f"{_pl_prob(q)}{_pl(rule.head)}(X) :- ind(X), \\+{ant}.")
    for pred in kb.preds:  # a predicate with no clause left fails rather than errs
        lines.append(f"{_pl(pred)}(X) :- fail.")
    if evidence:
        lines += [f"evidence({_pl(f.pred)}({f.ind}), {'true' if f.strength == 1 else 'false'})." for f in kb.facts if f.hard]
    lines += [f"query({_pl(pred)}({ind}))." for pred, ind in kb.queries]
    return "\n".join(lines) + "\n"
